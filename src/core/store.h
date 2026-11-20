#pragma once
#include "contract.h"
#include <QSqlDatabase>
#include <QSqlQuery>

namespace notes {
class Store {
public:
    static QString defaultPath();
    QString path() const { return db.databaseName(); }
    Store(const QString &path, bool readOnly = false);
    ~Store();
    Store(const Store &) = delete;
    Store &operator=(const Store &) = delete;
    QJsonObject call(const QString &name, const QJsonObject &args, const QString &actor);
    QJsonObject page(const QString &id);
    QJsonArray navigation();
    QJsonArray history(const QString &id);
    QJsonArray backlinks(const QString &id);
    QJsonArray favorites();
    QJsonArray recent(int limit);
    void setFavorite(const QString &id, bool on, int index = -1);
    void visit(const QString &id);
    qint64 generation();
    QJsonObject saveDraft(const QString &id, int expected, const QString &title, QJsonArray blocks);
    QJsonObject restoreRevision(const QString &id, int expected, int target);
    QJsonObject insertPhoto(const QString &id, int expected, const QString &caption,
                            const QString &mime, const QByteArray &bytes);
    QString addPhoto(const QString &mime, const QByteArray &bytes);
    QByteArray photo(const QString &asset, QString &mime);
    void backup(const QString &destination);
private:
    QSqlDatabase db;
    bool readOnly;
    QSqlQuery sql(const QString &statement, const QVariantList &values = {});
    QJsonObject load(const QString &id);
    QJsonObject checked(const QString &id, int expected, bool deleted = false);
    QJsonObject record(QJsonObject page, const QString &actor, bool rewriteBlocks = false);
    QJsonObject mutate(const QString &name, const QJsonObject &args, const QString &actor);
    QJsonObject read(const QString &name, const QJsonObject &args);
    void checkParent(const QString &id, const QJsonValue &parent);
    void assignParent(QJsonObject &page, const QJsonValue &parent);
};
}
