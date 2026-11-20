#include "editor.h"
#include "pagefile.h"
#include <QClipboard>
#include <QFileInfo>
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
static QSettings preferences() { return QSettings(QSettings::defaultFormat(),QSettings::UserScope,"Lunqio","Editor"); }
Editor::Editor(notes::Store &store, const QString &codex, const QString &claude) : store(store), writing(store.path(),codex,claude) {
    connect(QGuiApplication::clipboard(),&QClipboard::dataChanged,this,&Editor::clipboardChanged);
}
bool Editor::clipboardPhoto() const { return pagefile::clipboardHasPhoto(QGuiApplication::clipboard()->mimeData()); }
// Lunqio oscuro/claro, the usual Claro ("white") and Oscuro ("black"), or Claro/Oscuro as Windows is.
static bool knownTheme(const QString &value) {
    return value == "dark" || value == "light" || value == "white" || value == "black" || value == "system";
}
QString Editor::theme() const {
    const QString forced = qEnvironmentVariable("LUNQIO_THEME");
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
Obj Editor::dispatch(const QString &action, const Obj &a) {
    const auto id = a["id"].toString();
    const int expected = a["expected_revision"].toInt();
    if (action == "page") return store.page(id);
    if (action == "navigation") return {{"pages",store.navigation()},{"favorites",store.favorites()},{"recent",store.recent(8)}};
    if (action == "favorite") {
        store.setFavorite(id,a["on"].toBool(),a.contains("index") ? a["index"].toInt() : -1);
        return {{"favorites",store.favorites()}};
    }
    if (action == "visit") { store.visit(id); return {{"recent",store.recent(8)}}; }
    if (action == "generation") return {{"value",store.generation()}};
    if (action == "history") return {{"rows",store.history(id)}};
    if (action == "backlinks") return {{"pages",store.backlinks(id)}};
    if (action == "save") return store.saveDraft(id,expected,a["title"].toString(),a["blocks"].toArray());
    if (action == "restore_revision") return store.restoreRevision(id,expected,a["target"].toInt());
    if (action == "insert_photo") return pagefile::insertPhoto(store,id,expected,QUrl(a["url"].toString()).toLocalFile());
    if (action == "clipboard_photo") return {{"photos",pagefile::storeClipboardPhotos(store,QGuiApplication::clipboard()->mimeData())}};
    if (action == "cover_photo") {
        const QString asset = pagefile::storePhoto(store,QUrl(a["url"].toString()).toLocalFile());
        return store.call("update_page",{{"id",id},{"expected_revision",expected},{"cover","photo:"+asset}},"manual");
    }
    if (action == "backup" || action == "export" || action == "draft") {
        auto path = QUrl(a["url"].toString()).toLocalFile();
        if (path.isEmpty()) throw notes::Error("invalid_argument","Elige un archivo local.");
        if (action == "backup") store.backup(path);
        else pagefile::save(store,action == "draft" ? a : store.page(id),path);
        return {};
    }
    return store.call(action,a,"manual");
}
QVariantMap Editor::run(const QString &action, const QVariantMap &arguments) {
    try {
        return {{"ok",true},{"data",dispatch(action,Obj::fromVariantMap(arguments)).toVariantMap()}};
    } catch (const notes::Error &e) {
        return {{"ok",false},{"code",e.code},{"message",QString::fromUtf8(e.what())}};
    }
}
