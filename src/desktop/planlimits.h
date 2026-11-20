#pragma once
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>

/// The plan's usage limits (5-hour and weekly windows) of each assistant, as the
/// provider reports them. Codex answers on request through `codex app-server`;
/// Claude Code reports them alongside each request (`rate_limit_event`).
class PlanLimits : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap claude READ claude NOTIFY changed)
    Q_PROPERTY(QVariantMap codex READ codex NOTIFY changed)
    Q_PROPERTY(bool checking READ checking NOTIFY changed)
public:
    explicit PlanLimits(QObject *parent = nullptr);
    ~PlanLimits() override;
    QVariantMap claude() const { return claudeState.toVariantMap(); }
    QVariantMap codex() const { return codexState.toVariantMap(); }
    bool checking() const { return process != nullptr; }
    void setCodexProgram(const QString &path) { program = path; }
    Q_INVOKABLE void refreshCodex();
    Q_INVOKABLE void refreshIfStale(int seconds = 90);
    void takeClaude(const QJsonObject &info);
signals:
    void changed();
private:
    void finishCodex(const QJsonObject &reply);
    void stop();
    void save();
    QJsonObject claudeState, codexState;
    QString program;
    QProcess *process = nullptr;
    QTimer timeout;
    QByteArray buffer;
};
