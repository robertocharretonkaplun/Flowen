#pragma once
#include "store.h"
#include "writingassistant.h"
#include <QObject>
#include <QTemporaryDir>
#include <QUrl>

class Editor : public QObject {
    Q_OBJECT
    Q_PROPERTY(WritingAssistant* assistant READ assistant CONSTANT)
    Q_PROPERTY(QString author READ author WRITE setAuthor NOTIFY authorChanged)
    /// True while the clipboard holds a photo, so Ctrl+V adds a photo block instead of its address.
    Q_PROPERTY(bool clipboardPhoto READ clipboardPhoto NOTIFY clipboardChanged)
    /// "dark"/"light" (Lunqio), "white"/"black" (the usual Claro/Oscuro) or "system".
    /// LUNQIO_THEME overrides it without saving.
    Q_PROPERTY(QString theme READ theme WRITE setTheme NOTIFY themeChanged)
    /// The version of this build (CMake's project version), for Acerca de.
    Q_PROPERTY(QString version READ version CONSTANT)
    notes::Store &store;
    WritingAssistant writing;
    QTemporaryDir photoCache;
public:
    explicit Editor(notes::Store &store, const QString &codex = {}, const QString &claude = {});
    WritingAssistant *assistant() { return &writing; }
    bool clipboardPhoto() const;
    QString version() const { return QStringLiteral(LUNQIO_VERSION); }
    QString theme() const;
    void setTheme(const QString &value);
    /// The name shown on comments: chosen in Lunqio, else the Windows account's full name.
    QString author() const;
    void setAuthor(const QString &name);
    Q_INVOKABLE QUrl photoUrl(const QString &asset);
    /// Small settings of the window kept between sessions (view mode, paper size…), under "ui/".
    Q_INVOKABLE QVariant preference(const QString &key, const QVariant &fallback = {}) const;
    Q_INVOKABLE void setPreference(const QString &key, const QVariant &value);
    Q_INVOKABLE QUrl suggestedFile(const QUrl &folder,QString title) const;
    Q_INVOKABLE QVariantMap run(const QString &action, const QVariantMap &arguments = {});
signals:
    void authorChanged();
    void clipboardChanged();
    void themeChanged();
private:
    QJsonObject dispatch(const QString &action, const QJsonObject &args);
};
