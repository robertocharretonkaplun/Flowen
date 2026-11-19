#pragma once
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <functional>

// One private stdio session for the open desktop library.
class McpLink : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString detail READ detail NOTIFY changed)
    Q_PROPERTY(QStringList tools READ tools NOTIFY changed)
    Q_PROPERTY(QString databasePath READ databasePath CONSTANT)
    Q_PROPERTY(bool autoConnect READ autoConnect WRITE setAutoConnect NOTIFY autoConnectChanged)
public:
    using Reply = std::function<void(QJsonObject,QString)>;
    explicit McpLink(QString database, QObject *parent = nullptr);
    ~McpLink() override;
    QString state() const { return status; }
    QString detail() const { return message; }
    QStringList tools() const { return toolNames; }
    QString databasePath() const { return database; }
    static QString serverPath();
    bool autoConnect() const { return automatic; }
    void setAutoConnect(bool enable);
    Q_INVOKABLE void open();
    Q_INVOKABLE void close();
    void tool(const QString &name, const QJsonObject &args, Reply reply);
signals:
    void changed();
    void autoConnectChanged();
private:
    void rpc(const QString &method, const QJsonObject &params, Reply reply);
    void send(const QJsonObject &packet);
    void stop(const QString &reason);
    void consume();
    QString database, status = "offline", message;
    QStringList toolNames;
    bool automatic;
    QProcess *process = nullptr;
    QTimer timeout;
    Reply pending;
    int sequence = 0;
};
