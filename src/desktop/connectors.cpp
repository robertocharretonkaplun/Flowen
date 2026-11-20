#include "connectors.h"
#include "appsettings.h"
#include "mcplink.h"
#include "store.h"
#include <QClipboard>
#include <QCryptographicHash>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <algorithm>
#include <utility>
#include <QTimeZone>
#ifdef Q_OS_WIN
#include <windows.h>
#include <appmodel.h>
#include <tlhelp32.h>
#include <iterator>
#include <vector>
#endif

using Obj = QJsonObject;
namespace {
QString native(const QString &path) { return QDir::toNativeSeparators(path); }
QList<QFileInfo> folders(const QString &parent, const QString &pattern) {
    if (parent.isEmpty()) return {};
    return QDir(parent).entryInfoList({pattern},QDir::Dirs | QDir::NoDotAndDotDot);
}
QString firstLine(const QByteArray &text) {
    return QString::fromLocal8Bit(text).trimmed().section('\n',0,0).trimmed().left(220);
}
// Start time of the oldest running Claude Desktop process (the app, not the Claude Code CLI it bundles).
QDateTime claudeDesktopStarted() {
    QDateTime earliest;
#ifdef Q_OS_WIN
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
    if (snapshot == INVALID_HANDLE_VALUE) return earliest;
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    for (BOOL more = Process32FirstW(snapshot,&entry); more; more = Process32NextW(snapshot,&entry)) {
        if (_wcsicmp(entry.szExeFile,L"claude.exe") != 0) continue;
        HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,entry.th32ProcessID);
        if (!process) continue;
        wchar_t image[1024];
        DWORD size = DWORD(std::size(image));
        FILETIME created, exited, kernel, user;
        if (QueryFullProcessImageNameW(process,0,image,&size) && GetProcessTimes(process,&created,&exited,&kernel,&user)) {
            const QString path = QString::fromWCharArray(image,int(size)).toCaseFolded();
            if (path.contains("\\windowsapps\\claude_") || path.contains("\\anthropicclaude\\")) {
                ULARGE_INTEGER ticks;
                ticks.LowPart = created.dwLowDateTime;
                ticks.HighPart = created.dwHighDateTime;
                const auto when = QDateTime::fromMSecsSinceEpoch(qint64(ticks.QuadPart/10000)-11644473600000LL,QTimeZone::UTC);
                if (!earliest.isValid() || when < earliest) earliest = when;
            }
        }
        CloseHandle(process);
    }
    CloseHandle(snapshot);
#endif
    return earliest;
}
}

// ---- Shared behaviour ------------------------------------------------------

Connector::Connector(QString key, QString title, QString summary, QString icon, const QString &db, QObject *parent)
    : QObject(parent), database(QFileInfo(db).absoluteFilePath()), id(std::move(key)), heading(std::move(title)),
      about(std::move(summary)), glyph(std::move(icon)) {
    process.setWorkingDirectory(QDir::tempPath());
    timeout.setSingleShot(true);
    connect(&process,&QProcess::finished,this,[this](int code,QProcess::ExitStatus exit) {
        timeout.stop();
        const QByteArray out = process.readAllStandardOutput(), err = process.readAllStandardError();
        auto done = std::exchange(pending,Done());
        if (!done) return;
        // Continue outside the signal so the next step can reuse the process.
        QMetaObject::invokeMethod(this,[this,done,code,exit,out,err] {
            if (exit != QProcess::NormalExit) fail(heading + " se cerró antes de terminar.");
            else done(code,out,err);
        },Qt::QueuedConnection);
    });
    connect(&process,&QProcess::errorOccurred,this,[this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart || !pending) return;
        timeout.stop();
        pending = {};
        fail(QString("No se pudo abrir %1. Revisa el ejecutable elegido.").arg(heading));
    });
    connect(&timeout,&QTimer::timeout,this,[this] {
        pending = {};
        process.kill();
        fail(QString("%1 tardó demasiado en responder. Vuelve a comprobarlo.").arg(heading));
    });
}
Connector::~Connector() {
    process.disconnect(this);
    if (process.state() != QProcess::NotRunning) { process.kill(); process.waitForFinished(1000); }
}
void Connector::report(const QString &state, const QString &detail) {
    status = state;
    message = detail;
    if (!busy()) guard.reset();
    emit changed();
}
void Connector::setProgram(const QString &path) {
    if (exe == path) return;
    exe = path;
    emit changed();
}
void Connector::inspect() {
    if (busy()) return;
    report("checking","Comprobando…");
    check();
}
void Connector::setEnabled(bool on) {
    if (busy() || !ready()) return;
    guard = std::make_unique<QLockFile>(QDir::temp().filePath("flowen-connector-"+id+".lock"));
    if (!guard->tryLock(1500)) {
        guard.reset();
        fail("Otra ventana de Flowen está cambiando este conector. Inténtalo de nuevo en unos segundos.");
        return;
    }
    wanted = on;
    report("applying",on ? "Activando…" : "Desactivando…");
    apply(on);
}
void Connector::remove() {
    if (busy() || !ready() || !registered()) return;
    guard = std::make_unique<QLockFile>(QDir::temp().filePath("flowen-connector-"+id+".lock"));
    if (!guard->tryLock(1500)) {
        guard.reset();
        fail("Otra ventana de Flowen está cambiando este conector. Inténtalo de nuevo en unos segundos.");
        return;
    }
    wanted = false;
    report("applying","Quitando el registro…");
    unregister();
}
void Connector::reveal() const {
    if (where.isEmpty()) return;
    const QFileInfo info(where);
#ifdef Q_OS_WIN
    if (info.isFile()) { QProcess::startDetached("explorer.exe",{"/select,",native(where)}); return; }
#endif
    QDesktopServices::openUrl(QUrl::fromLocalFile(info.absolutePath()));
}
bool Connector::chooseProgram(const QUrl &file) {
    const QFileInfo info(file.toLocalFile());
    const QString suffix = info.suffix().toLower();
    if (busy() || !info.isFile() || (suffix != "exe" && suffix != "cmd" && suffix != "bat")) return false;
    setProgram(info.absoluteFilePath());
    if (!settingsKey().isEmpty()) appSettings().setValue(settingsKey(),exe);
    inspect();
    return true;
}
QString Connector::serverCommand() const { return native(McpLink::serverPath()); }
QStringList Connector::serverArgs() const { return {"--db",native(database)}; }

// An entry belongs to this library when it starts notas-mcp for the same database file.
// If that notas-mcp no longer exists (the package moved), the entry is stale.
Connector::Match Connector::classify(const QString &command, QStringList args, const QJsonObject &env) const {
    lastLegacy = false;
    const QFileInfo server(command);
    if (server.completeBaseName().compare("notas-mcp",Qt::CaseInsensitive) != 0) return Match::None;
    args.removeAll(QStringLiteral("--read-only"));
    QString db;
    if (args.isEmpty()) db = env.value("FLOWEN_DB").toString(env.value("LUNQIO_DB").toString(notes::Store::defaultPath()));
    else if (args.size() == 2 && args[0] == "--db") db = args[1];
    else return Match::None;
    // Registered by Lunqio for the library Flowen has copied: it has to point at Flowen's from now on.
    if (notes::samePath(db,notes::Store::legacyPath()) && notes::samePath(database,notes::Store::defaultPath())
        && !notes::samePath(database,db)) {
        lastLegacy = true;
        return Match::Stale;
    }
    if (QFileInfo(db) != QFileInfo(database)) return Match::None;
    return server.isFile() ? Match::Ours : Match::Stale;
}
QList<Connector::Entry> Connector::scanJson(const QJsonObject &servers) const {
    QList<Entry> out;
    for (auto it = servers.begin(); it != servers.end(); ++it) {
        const auto server = it.value().toObject();
        QStringList args;
        for (const auto &a : server["args"].toArray()) args << a.toString();
        const auto match = classify(server["command"].toString(),args,server["env"].toObject());
        if (match != Match::None) out.append({it.key(),match,!server["disabled"].toBool(false),lastLegacy});
    }
    return out;
}
// Keep "flowen" for the first library; other libraries get a stable suffix.
QString Connector::freeName(const QStringList &taken) const {
    if (!taken.contains("flowen")) return "flowen";
    const auto key = QDir::cleanPath(database).toCaseFolded().toUtf8();
    const QString base = "flowen-"+QString::fromLatin1(QCryptographicHash::hash(key,QCryptographicHash::Sha256).toHex().left(10));
    QString candidate = base;
    for (int i = 2; taken.contains(candidate); ++i) candidate = base+"-"+QString::number(i);
    return candidate;
}
void Connector::adopt(const QList<Entry> &found) {
    entries = found;
    const Entry *best = nullptr;
    for (const auto &e : entries)
        if (e.match == Match::Ours && (!best || (e.enabled && !best->enabled))) best = &e;
    present = best != nullptr;
    active = present && best->enabled;
    stale = !present && !entries.isEmpty();
    migrating = !present && std::any_of(entries.begin(),entries.end(),[](const Entry &e) { return e.legacy && e.enabled; });
    name = best ? best->name : stale ? entries.first().name : QString();
}
void Connector::settle(const QString &on, const QString &paused, const QString &off) {
    if (active) report("on",on.arg(name));
    else if (present) report("paused",paused.arg(name));
    else if (stale) report("outdated",QString("«%1» apunta a una copia anterior de Flowen o de Lunqio. Actívalo para actualizar la ruta.").arg(name));
    else report("off",off);
    // A connector Lunqio left on moves to Flowen's library by itself, once: it was on, and the notes it
    // pointed at were copied to Flowen. Otherwise the assistant would keep writing in the old copy.
    if (migrating && !migrated && ready()) {
        migrated = true;
        QMetaObject::invokeMethod(this,[this] { setEnabled(true); },Qt::QueuedConnection);
    }
}
void Connector::run(const QStringList &args, Done done) {
    if (process.state() != QProcess::NotRunning) { fail(heading+" sigue ocupado. Vuelve a intentarlo."); return; }
    pending = std::move(done);
    const QString suffix = QFileInfo(exe).suffix().toLower();
#ifdef Q_OS_WIN
    if (suffix == "cmd" || suffix == "bat") {
        // npm installs a batch shim that has to go through cmd.exe.
        QStringList parts{"\""+native(exe)+"\""};
        for (const auto &a : args) parts << "\""+a+"\"";
        process.setProgram(qEnvironmentVariable("ComSpec","cmd.exe"));
        process.setArguments({});
        process.setNativeArguments("/d /s /c \""+parts.join(' ')+"\"");
    } else {
        process.setNativeArguments({});
        process.setProgram(exe);
        process.setArguments(args);
    }
#else
    process.setProgram(exe);
    process.setArguments(args);
#endif
    timeout.start(20000);
    process.start();
}
void Connector::sequence(QList<QStringList> commands, const QString &failure, std::function<void()> finish) {
    if (commands.isEmpty()) { finish(); return; }
    const QStringList next = commands.takeFirst();
    run(next,[this,commands,failure,finish](int code,const QByteArray &,const QByteArray &err) {
        if (code != 0) {
            const QString reason = firstLine(err);
            fail(reason.isEmpty() ? failure : failure+" "+reason);
            return;
        }
        sequence(commands,failure,finish);
    });
}

// ---- Claude Desktop: claude_desktop_config.json -----------------------------

ClaudeDesktopConnector::ClaudeDesktopConnector(const QString &db, QString config, QObject *parent)
    : Connector("claude-desktop","Claude Desktop","Aplicación de escritorio de Claude","desktop",db,parent),
      fixed(!config.isEmpty()) {
    where = fixed ? config : findConfig();
}
QString ClaudeDesktopConnector::findConfig() {
    const QString forced = notes::environment("CLAUDE_DESKTOP_CONFIG");
    if (!forced.isEmpty()) return forced;
    const QString local = qEnvironmentVariable("LOCALAPPDATA"), roaming = qEnvironmentVariable("APPDATA");
    QStringList candidates;
    // Store installs keep their data outside the package; older ones use the virtualised AppData.
    for (const auto &dir : folders(local+"/Claude-Data","claude_*"))
        candidates << QDir(dir.absoluteFilePath()).filePath("claude_desktop_config.json");
    for (const auto &dir : folders(local+"/Packages","Claude_*"))
        candidates << QDir(dir.absoluteFilePath()).filePath("LocalCache/Roaming/Claude/claude_desktop_config.json");
    if (!roaming.isEmpty()) candidates << QDir(roaming).filePath("Claude/claude_desktop_config.json");
#ifdef Q_OS_MACOS
    candidates << QDir::home().filePath("Library/Application Support/Claude/claude_desktop_config.json");
#endif
    for (const auto &c : candidates) if (QFileInfo(c).isFile()) return QDir::cleanPath(c);
    for (const auto &c : candidates) if (QFileInfo(c).absoluteDir().exists()) return QDir::cleanPath(c);
    return {};
}
bool ClaudeDesktopConnector::read(QJsonObject &config) {
    config = {};
    QFile file(where);
    if (!file.exists()) return true;
    if (!file.open(QIODevice::ReadOnly)) { fail("No se pudo leer la configuración de Claude Desktop."); return false; }
    QByteArray bytes = file.readAll();
    if (bytes.startsWith("\xEF\xBB\xBF")) bytes.remove(0,3);
    if (bytes.trimmed().isEmpty()) return true;
    QJsonParseError error;
    const auto doc = QJsonDocument::fromJson(bytes,&error);
    if (error.error != QJsonParseError::NoError || !doc.isObject() ||
        (doc.object().contains("mcpServers") && !doc.object()["mcpServers"].isObject())) {
        fail("La configuración de Claude Desktop no es JSON válido. Corrígela antes de cambiar el conector.");
        return false;
    }
    config = doc.object();
    return true;
}
bool ClaudeDesktopConnector::write(const QJsonObject &config) {
    QDir().mkpath(QFileInfo(where).absolutePath());
    if (QFileInfo::exists(where)) {
        const QString backup = where+".flowen-backup";
        QFile::remove(backup);
        QFile::copy(where,backup);
    }
    QSaveFile file(where);
    if (!file.open(QIODevice::WriteOnly) || file.write(QJsonDocument(config).toJson(QJsonDocument::Indented)) < 0 || !file.commit()) {
        fail("No se pudo guardar la configuración de Claude Desktop. Revisa los permisos de la carpeta.");
        return false;
    }
    if (watching()) appSettings().setValue("claudeDesktopWrittenAt",QDateTime::currentDateTimeUtc());
    return true;
}
// Only the real configuration belongs to the running Claude Desktop.
bool ClaudeDesktopConnector::watching() const {
    return !fixed && notes::environment("CLAUDE_DESKTOP_CONFIG").isEmpty();
}
// Claude Desktop reads its configuration once, at start. Until it restarts, the change is not live.
void ClaudeDesktopConnector::flagRestart() {
    if (!watching() || (status != "on" && status != "off")) return;
    // Claude also rewrites this file while it runs, so only Flowen's own writes count:
    // the recorded time, or when the backup made before each write was created.
    QDateTime written = appSettings().value("claudeDesktopWrittenAt").toDateTime();
    const QDateTime backup = QFileInfo(where+".flowen-backup").birthTime();
    if (backup.isValid() && (!written.isValid() || backup > written)) written = backup;
    const QDateTime started = claudeDesktopStarted();
    if (!written.isValid() || !started.isValid() || started > written) return;
    report("restart",active
        ? QString("«%1» ya está en la configuración, pero Claude Desktop sigue abierto desde antes del cambio. Ciérralo por completo, también desde la bandeja del sistema, y vuelve a abrirlo.").arg(name)
        : "Claude Desktop sigue usando la configuración anterior. Ciérralo por completo y vuelve a abrirlo para dejar de compartir la biblioteca.");
}
void ClaudeDesktopConnector::check() {
    if (!fixed) where = findConfig();
    if (where.isEmpty()) { adopt({}); report("missing","No se encontró Claude Desktop en este equipo."); return; }
    QJsonObject config;
    if (!read(config)) return;
    adopt(scanJson(config["mcpServers"].toObject()));
    settle("Activo como «%1». Abre un chat nuevo en Claude Desktop para usarlo.","Activo como «%1».",
           "Actívalo para usar esta biblioteca desde los chats de Claude Desktop.");
    flagRestart();
}
void ClaudeDesktopConnector::apply(bool on) {
    if (where.isEmpty()) { fail("No se encontró Claude Desktop en este equipo."); return; }
    QJsonObject config;
    if (!read(config)) return;
    const auto before = config["mcpServers"].toObject();
    auto servers = before;
    const auto mine = scanJson(servers);
    const bool ours = std::any_of(mine.begin(),mine.end(),[](const Entry &e) { return e.match == Match::Ours; });
    QString reuse;
    for (const auto &e : mine) {
        if (!on || e.match == Match::Stale) {
            servers.remove(e.name);
            if (e.match == Match::Stale && !e.legacy && reuse.isEmpty()) reuse = e.name;
        } else if (!e.enabled) {
            auto server = servers[e.name].toObject();
            server.remove("disabled");
            servers[e.name] = server;
        }
    }
    if (on && !ours)
        servers[reuse.isEmpty() ? freeName(servers.keys()) : reuse] =
            Obj{{"command",serverCommand()},{"args",QJsonArray::fromStringList(serverArgs())}};
    const bool same = servers == before;
    if (!same) {
        config["mcpServers"] = servers;
        if (!write(config)) return;
    }
    adopt(scanJson(servers));
    settle("Activo como «%1». Reinicia Claude Desktop para cargar el cambio.","Activo como «%1».",
           same ? "Actívalo para usar esta biblioteca desde los chats de Claude Desktop."
                : "Desactivado. Reinicia Claude Desktop para aplicar el cambio.");
    flagRestart();
}

// ---- Claude Code: `claude mcp` with user scope ------------------------------

ClaudeCodeConnector::ClaudeCodeConnector(const QString &db, QObject *parent)
    : Connector("claude-code","Claude Code","Terminal, IDE y pestaña Code de Claude","terminal",db,parent) {
    exe = findProgram();
    where = configFile();
}
QString ClaudeCodeConnector::configFile() {
    const QString dir = qEnvironmentVariable("CLAUDE_CONFIG_DIR");
    return QDir(dir.isEmpty() ? QDir::homePath() : dir).filePath(".claude.json");
}
QString ClaudeCodeConnector::findProgram() {
    const QString saved = appSettings().value("claudeExecutable").toString();
    if (QFileInfo(saved).isFile()) return saved;
    const QString path = QStandardPaths::findExecutable("claude");
    if (!path.isEmpty()) return path;
    QStringList known{QDir::home().filePath(".local/bin/claude.exe")};
    const QString roaming = qEnvironmentVariable("APPDATA");
    if (!roaming.isEmpty()) known << QDir(roaming).filePath("npm/claude.cmd");
    for (const auto &c : known) if (QFileInfo(c).isFile()) return c;
    // The Claude desktop app ships its own copy of Claude Code; use the newest one.
    QFileInfo newest;
    for (const auto &app : folders(qEnvironmentVariable("LOCALAPPDATA")+"/Claude-Data","claude_*")) {
        QDirIterator it(app.absoluteFilePath()+"/claude-code",{"claude.exe"},QDir::Files,QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QFileInfo candidate(it.next());
            if (!newest.exists() || candidate.lastModified() > newest.lastModified()) newest = candidate;
        }
    }
    return newest.exists() ? newest.absoluteFilePath() : QString();
}
bool ClaudeCodeConnector::servers(QJsonObject &out) {
    out = {};
    where = configFile();
    QFile file(where);
    if (!file.exists()) return true;
    if (!file.open(QIODevice::ReadOnly)) { fail("No se pudo leer la configuración de Claude Code."); return false; }
    QJsonParseError error;
    const auto doc = QJsonDocument::fromJson(file.readAll(),&error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        fail("No se pudo leer la configuración de Claude Code. Vuelve a comprobarlo en unos segundos.");
        return false;
    }
    out = doc.object()["mcpServers"].toObject();
    return true;
}
void ClaudeCodeConnector::check() {
    if (!QFileInfo(exe).isFile()) exe = findProgram();
    QJsonObject list;
    if (!servers(list)) return;
    adopt(scanJson(list));
    if (exe.isEmpty() && !registered()) { report("missing","No se encontró Claude Code. Instálalo o elige claude.exe."); return; }
    settle("Activo como «%1» en todos tus proyectos. Abre una sesión nueva de Claude Code para usarlo.","Activo como «%1».",
           "Actívalo para usar esta biblioteca en todos tus proyectos de Claude Code.");
    if (exe.isEmpty()) report(status,message+" Elige claude.exe para poder cambiarlo.");
}
void ClaudeCodeConnector::apply(bool on) {
    QJsonObject list;
    if (!servers(list)) return;
    const auto mine = scanJson(list);
    const bool ours = std::any_of(mine.begin(),mine.end(),[](const Entry &e) { return e.match == Match::Ours; });
    QList<QStringList> steps;
    QStringList taken = list.keys();
    QString reuse;
    for (const auto &e : mine) {
        if (on && e.match == Match::Ours) continue;
        steps << QStringList{"mcp","remove","-s","user",e.name};
        taken.removeAll(e.name);
        if (e.match == Match::Stale && !e.legacy && reuse.isEmpty()) reuse = e.name;
    }
    if (on && !ours)
        steps << QStringList{"mcp","add","-s","user",reuse.isEmpty() ? freeName(taken) : reuse,"--",serverCommand()}+serverArgs();
    sequence(steps,"Claude Code no pudo guardar el cambio.",[this] { check(); });
}

// ---- Codex: `codex mcp` plus the enabled flag in config.toml ----------------

CodexConnector::CodexConnector(const QString &db, QObject *parent)
    : Connector("codex","Codex","App, terminal e IDE de OpenAI","code",db,parent) {
    exe = findProgram();
    where = configFile();
}
QString CodexConnector::configFile() {
    const QString home = qEnvironmentVariable("CODEX_HOME");
    return QDir(home.isEmpty() ? QDir::home().filePath(".codex") : home).filePath("config.toml");
}
QString CodexConnector::findProgram() {
    const QString saved = appSettings().value("codexExecutable").toString();
    if (QFileInfo(saved).isExecutable()) return saved;
    QString path = QStandardPaths::findExecutable("codex");
    if (!path.isEmpty()) return path;
#ifdef Q_OS_WIN
    // Explorer does not inherit the PATH used by the Codex desktop process.
    constexpr auto family = L"OpenAI.Codex_2p2nqsd0c76g0";
    UINT32 count = 0, length = 0;
    if (GetPackagesByPackageFamily(family,&count,nullptr,&length,nullptr) == ERROR_INSUFFICIENT_BUFFER) {
        std::vector<PWSTR> names(count);
        std::vector<wchar_t> buffer(length);
        if (GetPackagesByPackageFamily(family,&count,names.data(),&length,buffer.data()) == ERROR_SUCCESS) {
            for (auto package : names) {
                UINT32 size = 0;
                if (GetPackagePathByFullName(package,&size,nullptr) != ERROR_INSUFFICIENT_BUFFER) continue;
                std::vector<wchar_t> dir(size);
                if (GetPackagePathByFullName(package,&size,dir.data()) != ERROR_SUCCESS) continue;
                path = QDir(QString::fromWCharArray(dir.data())).filePath("app/resources/codex.exe");
                if (QFileInfo(path).isExecutable()) return path;
            }
        }
    }
#endif
    return {};
}
void CodexConnector::list(std::function<void(QStringList)> next) {
    run({"mcp","list","--json"},[this,next](int code,const QByteArray &out,const QByteArray &) {
        QJsonParseError error;
        const auto doc = QJsonDocument::fromJson(out,&error);
        if (code != 0 || error.error != QJsonParseError::NoError || !doc.isArray()) {
            fail("Codex no pudo leer su configuración de MCP. Comprueba la instalación.");
            return;
        }
        QList<Entry> found;
        QStringList names;
        for (const auto &value : doc.array()) {
            const auto server = value.toObject(), transport = server["transport"].toObject();
            names << server["name"].toString();
            if (transport["type"].toString() != "stdio") continue;
            QStringList args;
            for (const auto &a : transport["args"].toArray()) args << a.toString();
            const auto match = classify(transport["command"].toString(),args,transport["env"].toObject());
            if (match != Match::None) found.append({server["name"].toString(),match,server["enabled"].toBool(true),lastLegacy});
        }
        adopt(found);
        next(names);
    });
}
void CodexConnector::check() {
    where = configFile();
    if (exe.isEmpty()) { adopt({}); report("missing","No se encontró Codex. Instálalo o elige codex.exe."); return; }
    list([this](const QStringList &) {
        settle("Activo como «%1». Abre un chat nuevo de Codex para usarlo.",
               "«%1» está registrado, pero desactivado. Actívalo para usarlo en Codex.",
               "Actívalo para consultar y editar tus páginas desde Codex.");
    });
}
// Codex has no command to pause a server, so flip `enabled` in its own table.
bool CodexConnector::toggle(const QString &server, bool on) {
    where = configFile();
    QFile file(where);
    if (!file.open(QIODevice::ReadOnly)) { fail("No se pudo leer config.toml de Codex."); return false; }
    QStringList lines = QString::fromUtf8(file.readAll()).split('\n');
    file.close();
    const QRegularExpression header("^\\s*\\[\\s*mcp_servers\\s*\\.\\s*(\"?)"+QRegularExpression::escape(server)+"\\1\\s*\\]\\s*(#.*)?\\r?$");
    const QRegularExpression table("^\\s*\\[");
    const QRegularExpression key("^\\s*enabled\\s*=");
    qsizetype start = -1;
    for (qsizetype i = 0; i < lines.size() && start < 0; ++i) if (header.match(lines[i]).hasMatch()) start = i;
    if (start < 0) { fail(QString("No se encontró «%1» en config.toml de Codex.").arg(server)); return false; }
    const QString value = QString("enabled = %1").arg(on ? "true" : "false")+(lines[start].endsWith('\r') ? "\r" : "");
    qsizetype end = start+1;
    while (end < lines.size() && !table.match(lines[end]).hasMatch()) ++end;
    qsizetype found = -1;
    for (qsizetype i = start+1; i < end && found < 0; ++i) if (key.match(lines[i]).hasMatch()) found = i;
    if (found >= 0) lines[found] = value;
    else lines.insert(start+1,value);
    QSaveFile out(where);
    if (!out.open(QIODevice::WriteOnly) || out.write(lines.join('\n').toUtf8()) < 0 || !out.commit()) {
        fail("No se pudo guardar config.toml de Codex.");
        return false;
    }
    return true;
}
void CodexConnector::apply(bool on) {
    list([this,on](QStringList taken) {
        QList<QStringList> steps;
        QString reuse;
        for (const auto &e : entries) {
            if (e.match == Match::Stale) {
                if (!on) continue;
                steps << QStringList{"mcp","remove",e.name};
                taken.removeAll(e.name);
                if (!e.legacy && reuse.isEmpty()) reuse = e.name;
            } else if (e.enabled != on && !toggle(e.name,on)) return;
        }
        if (on && !present)
            steps << QStringList{"mcp","add",reuse.isEmpty() ? freeName(taken) : reuse,"--",serverCommand()}+serverArgs();
        sequence(steps,"Codex no pudo guardar el cambio.",[this] { check(); });
    });
}
void CodexConnector::unregister() {
    list([this](const QStringList &) {
        QList<QStringList> steps;
        for (const auto &e : entries) steps << QStringList{"mcp","remove",e.name};
        sequence(steps,"Codex no pudo quitar el registro.",[this] { check(); });
    });
}

// ---- The list shown in the Connectors tab -----------------------------------

Connectors::Connectors(const QString &db, QObject *parent)
    : QObject(parent), database(db), desktop(new ClaudeDesktopConnector(db,{},this)),
      code(new ClaudeCodeConnector(db,this)), openai(new CodexConnector(db,this)) {}
void Connectors::inspectAll() {
    desktop->inspect();
    code->inspect();
    openai->inspect();
}
void Connectors::copyConfiguration() const {
    const Obj server{{"command",native(McpLink::serverPath())},{"args",QJsonArray{"--db",native(database)}}};
    const Obj config{{"mcpServers",Obj{{"flowen",server}}}};
    QGuiApplication::clipboard()->setText(QString::fromUtf8(QJsonDocument(config).toJson(QJsonDocument::Indented)));
}
