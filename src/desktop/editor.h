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
    notes::Store &store;
    WritingAssistant writing;
    QTemporaryDir photoCache;
public:
    explicit Editor(notes::Store &store, const QString &codex = {}, const QString &claude = {})
        : store(store), writing(store.path(),codex,claude) {}
    WritingAssistant *assistant() { return &writing; }
    // The name shown on comments: chosen in Lunqio, else the Windows account's full name.
    QString author() const;
    void setAuthor(const QString &name);
    Q_INVOKABLE QUrl photoUrl(const QString &asset);
    Q_INVOKABLE QUrl suggestedFile(const QUrl &folder,QString title) const;
    Q_INVOKABLE QVariantMap run(const QString &action, const QVariantMap &arguments = {});
signals:
    void authorChanged();
private:
    QJsonObject dispatch(const QString &action, const QJsonObject &args);
};
