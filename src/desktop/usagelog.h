#pragma once
#include <QJsonObject>
#include <QObject>
#include <QVariantList>

// Tokens spent by each "Crear con IA" / "Editar con IA" request, kept on this computer
// (one JSON line per request) for the Uso tab.
class UsageLog : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList recent READ recent NOTIFY changed)
    Q_PROPERTY(QVariantMap last READ last NOTIFY changed)
    Q_PROPERTY(int count READ count NOTIFY changed)
public:
    explicit UsageLog(QString file = {}, QObject *parent = nullptr);
    static QString defaultFile();
    void add(QJsonObject record);
    QVariantList recent() const;
    QVariantMap last() const;
    int count() const { return int(items.size()); }
    Q_INVOKABLE QVariantMap totals(int days) const;
    Q_INVOKABLE QVariantList daily(int days) const;
    Q_INVOKABLE void clear();
signals:
    void changed();
private:
    static QVariantMap view(const QJsonObject &record);
    QString path;
    QList<QJsonObject> items;
};
