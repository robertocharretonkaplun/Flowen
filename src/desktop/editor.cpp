#include "editor.h"
#include "appsettings.h"
#include "pagefile.h"
#include <QBuffer>
#include <QClipboard>
#include <QFileInfo>
#include <QHash>
#include <QImage>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#ifdef Q_OS_WIN
#include <windows.h>
#include <lm.h>
#pragma comment(lib,"netapi32.lib")
#endif

using Obj = QJsonObject;
static QSettings preferences() { return appSettings(); }
Editor::Editor(notes::Store &store, const QString &codex, const QString &claude) : store(store), writing(store.path(),codex,claude) {
    connect(QGuiApplication::clipboard(),&QClipboard::dataChanged,this,&Editor::clipboardChanged);
}
bool Editor::clipboardPhoto() const { return pagefile::clipboardHasPhoto(QGuiApplication::clipboard()->mimeData()); }
QVariant Editor::preference(const QString &key, const QVariant &fallback) const {
    return preferences().value("ui/"+key,fallback);
}
void Editor::setPreference(const QString &key, const QVariant &value) {
    if (!key.isEmpty()) preferences().setValue("ui/"+key,value);
}
// Flowen oscuro/claro, the usual Claro ("white") and Oscuro ("black"), or Claro/Oscuro as Windows is.
static bool knownTheme(const QString &value) {
    return value == "dark" || value == "light" || value == "white" || value == "black" || value == "system";
}
QString Editor::theme() const {
    const QString forced = notes::environment("THEME");
    if (knownTheme(forced)) return forced;
    const QString saved = preferences().value("theme").toString();
    return knownTheme(saved) ? saved : QStringLiteral("dark");
}
void Editor::setTheme(const QString &value) {
    if (!knownTheme(value) || value == theme()) return;
    preferences().setValue("theme",value);
    emit themeChanged();
}
QString Editor::author() const {
    const QString chosen = preferences().value("commentAuthor").toString().simplified();
    if (!chosen.isEmpty()) return chosen.left(80);
    QString user = qEnvironmentVariable("USERNAME",qEnvironmentVariable("USER"));
#ifdef Q_OS_WIN
    LPBYTE buffer = nullptr;
    if (NetUserGetInfo(nullptr,reinterpret_cast<LPCWSTR>(user.utf16()),10,&buffer) == NERR_Success && buffer) {
        const QString full = QString::fromWCharArray(reinterpret_cast<USER_INFO_10 *>(buffer)->usri10_full_name).simplified();
        NetApiBufferFree(buffer);
        if (!full.isEmpty()) return full.left(80);
    }
#endif
    return user.isEmpty() ? QStringLiteral("Yo") : user.left(80);
}
void Editor::setAuthor(const QString &name) {
    const QString value = name.simplified().left(80);
    if (value == author()) return;
    preferences().setValue("commentAuthor",value);
    emit authorChanged();
}
QUrl Editor::suggestedFile(const QUrl &folder,QString title) const {
    static const QRegularExpression illegal(R"([\\/:*?"<>|.\x00-\x1f])");
    static const QRegularExpression reserved("^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$",QRegularExpression::CaseInsensitiveOption);
    title = title.replace(illegal," ").simplified().left(100).trimmed();
    if (title.isEmpty()) title = "Página";
    if (reserved.match(title).hasMatch()) title.prepend('_');
    QString path = folder.toLocalFile();
    if (path.isEmpty()) path = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    return QUrl::fromLocalFile(QDir(path).filePath(title));
}
QUrl Editor::photoUrl(const QString &asset) {
    static const QRegularExpression digest("^[a-f0-9]{64}$");
    if (!photoCache.isValid() || !digest.match(asset).hasMatch()) return {};
    QString path = photoCache.filePath(asset);
    if (!QFileInfo::exists(path)) {
        QString mime;
        try {
            auto bytes = store.photo(asset,mime);
            QSaveFile file(path);
            if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit()) return {};
        } catch (const notes::Error &) { return {}; }
    }
    return QUrl::fromLocalFile(path);
}
// A file the person chose in a dialog.
static QString chosenFile(const Obj &args) {
    const QString path = QUrl(args["url"].toString()).toLocalFile();
    if (path.isEmpty()) throw notes::Error("invalid_argument","Elige un archivo local.");
    return path;
}
namespace {
// One request from the window: its arguments, and the page and revision most actions are about.
struct Request { notes::Store &store; const Obj &args; QString id; int expected; };
using Handler = Obj (*)(const Request &);
QString localFile(const Obj &args) { return QUrl(args["url"].toString()).toLocalFile(); }
// What the window asks of the library, by name. Anything not listed is a library tool, the same ones
// MCP offers (create_page, update_page, trash_page, apply_block_changes…), run as a manual change.
const QHash<QString,Handler> &handlers() {
    static const QHash<QString,Handler> table{
        // Reading.
        {"page",[](const Request &r) -> Obj { return r.store.page(r.id); }},
        {"navigation",[](const Request &r) -> Obj {
            return {{"pages",r.store.navigation()},{"favorites",r.store.favorites()},{"recent",r.store.recent(8)}}; }},
        {"generation",[](const Request &r) -> Obj { return {{"value",r.store.generation()}}; }},
        {"history",[](const Request &r) -> Obj { return {{"rows",r.store.history(r.id)}}; }},
        {"backlinks",[](const Request &r) -> Obj { return {{"pages",r.store.backlinks(r.id)}}; }},
        {"ask_notes",[](const Request &r) -> Obj { return {{"notes",r.store.notesFor(r.args["question"].toString(),r.id)}}; }},
        // Favorites, recent pages and templates: desktop lists outside page revisions.
        {"favorite",[](const Request &r) -> Obj {
            r.store.setFavorite(r.id,r.args["on"].toBool(),r.args.contains("index") ? r.args["index"].toInt() : -1);
            return {{"favorites",r.store.favorites()}}; }},
        {"visit",[](const Request &r) -> Obj { r.store.visit(r.id); return {{"recent",r.store.recent(8)}}; }},
        {"templates",[](const Request &r) -> Obj { return {{"templates",r.store.templates()}}; }},
        {"save_template",[](const Request &r) -> Obj {
            r.store.saveTemplate(r.id,r.args["name"].toString()); return {{"templates",r.store.templates()}}; }},
        {"remove_template",[](const Request &r) -> Obj {
            r.store.removeTemplate(r.args["template"].toString()); return {{"templates",r.store.templates()}}; }},
        // Saving the page being edited.
        {"save",[](const Request &r) -> Obj {
            return r.store.saveDraft(r.id,r.expected,r.args["title"].toString(),r.args["blocks"].toArray()); }},
        {"restore_revision",[](const Request &r) -> Obj { return r.store.restoreRevision(r.id,r.expected,r.args["target"].toInt()); }},
        // Photos.
        {"insert_photo",[](const Request &r) -> Obj { return pagefile::insertPhoto(r.store,r.id,r.expected,localFile(r.args)); }},
        {"store_photo",[](const Request &r) -> Obj {
            const QString path = localFile(r.args);
            return {{"asset",pagefile::storePhoto(r.store,path)},{"caption",QFileInfo(path).completeBaseName()}}; }},
        {"clipboard_photo",[](const Request &r) -> Obj {
            return {{"photos",pagefile::storeClipboardPhotos(r.store,QGuiApplication::clipboard()->mimeData())}}; }},
        {"photo_save",[](const Request &r) -> Obj { return {{"path",pagefile::savePhoto(r.store,r.args["asset"].toString(),localFile(r.args))}}; }},
        {"photo_copy",[](const Request &r) -> Obj { pagefile::copyPhoto(r.store,r.args["asset"].toString()); return {}; }},
        {"cover_photo",[](const Request &r) -> Obj {
            const QString asset = pagefile::storePhoto(r.store,localFile(r.args));
            return r.store.call("update_page",{{"id",r.id},{"expected_revision",r.expected},{"cover","photo:"+asset}},"manual"); }},
        // Files: a backup of the library, a page or an unsaved draft exported.
        {"backup",[](const Request &r) -> Obj { r.store.backup(chosenFile(r.args)); return {}; }},
        {"export",[](const Request &r) -> Obj {
            Obj page = r.store.page(r.id);
            // A PDF follows the paper and margins of Diseño de página.
            for (const char *key : {"paper","margins"}) if (r.args.contains(key)) page.insert(key,r.args.value(key));
            pagefile::save(r.store,page,chosenFile(r.args)); return {}; }},
        {"draft",[](const Request &r) -> Obj { pagefile::save(r.store,r.args,chosenFile(r.args)); return {}; }},
    };
    return table;
}
}
Obj Editor::dispatch(const QString &action, const Obj &a) {
    const auto found = handlers().constFind(action);
    if (found == handlers().constEnd()) return store.call(action,a,"manual");
    return (*found)({store,a,a["id"].toString(),a["expected_revision"].toInt()});
}
QVariantMap Editor::run(const QString &action, const QVariantMap &arguments) {
    try {
        return {{"ok",true},{"data",dispatch(action,Obj::fromVariantMap(arguments)).toVariantMap()}};
    } catch (const notes::Error &e) {
        return {{"ok",false},{"code",e.code},{"message",QString::fromUtf8(e.what())}};
    }
}
