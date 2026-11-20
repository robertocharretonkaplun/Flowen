#pragma once
#include "mcplink.h"
#include "connectors.h"
#include "usagelog.h"
#include "planlimits.h"
#include <QElapsedTimer>
#include <QJsonArray>
#include <QTemporaryDir>
#include <QUrl>
#include <QVariantList>
#include <functional>
#include <memory>

/// "Editar con IA" rewrites a selection and "Crear con IA" writes new blocks. Both run
/// through Claude Code or Codex and apply the result through the library's MCP session.
class WritingAssistant : public QObject {
    Q_OBJECT
    Q_PROPERTY(McpLink* link READ link CONSTANT)
    Q_PROPERTY(Connectors* connectors READ connectors CONSTANT)
    Q_PROPERTY(UsageLog* usage READ usage CONSTANT)
    Q_PROPERTY(PlanLimits* limits READ limits CONSTANT)
    Q_PROPERTY(QString phase READ phase NOTIFY changed)
    Q_PROPERTY(QString mode READ mode NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QString problem READ problem NOTIFY changed)
    Q_PROPERTY(QString proposal READ proposal NOTIFY changed)
    Q_PROPERTY(QVariantList blocks READ blocks NOTIFY changed)
    Q_PROPERTY(QString executable READ executable NOTIFY executableChanged)
    Q_PROPERTY(QString engine READ engine WRITE setEngine NOTIFY engineChanged)
    Q_PROPERTY(QString engineName READ engineName NOTIFY engineChanged)
    Q_PROPERTY(bool engineReady READ engineReady NOTIFY engineChanged)
    Q_PROPERTY(QString claudeAccount READ claudeAccount NOTIFY engineChanged)
    /// "Preguntar a Lunqio": questions answered from the notes sent with them, this session only.
    Q_PROPERTY(QVariantList conversation READ conversation NOTIFY changed)
public:
    explicit WritingAssistant(const QString &db, QString executable = {}, const QString &claude = {});
    ~WritingAssistant() override;
    McpLink *link() { return &connection; }
    Connectors *connectors() { return &hub; }
    UsageLog *usage() { return &spending; }
    PlanLimits *limits() { return &plans; }
    QString phase() const { return stage; }
    QString mode() const { return kind; }
    QString error() const { return issue; }
    QString problem() const { return hint; }
    QString proposal() const { return replacement; }
    QVariantList blocks() const { return written.toVariantList(); }
    QString executable() const { return cli; }
    QString engine() const { return engineKey; }
    void setEngine(const QString &key);
    QString engineName() const { return engineKey == "claude" ? "Claude" : "Codex"; }
    bool engineReady() const;
    QString claudeAccount() const { return account; }
    Q_INVOKABLE void setExecutable(const QUrl &file);
    Q_INVOKABLE void generate(QVariantMap selection, QString instruction);
    Q_INVOKABLE void compose(QVariantMap place, QString instruction);
    Q_INVOKABLE void apply();
    Q_INVOKABLE void ask(QString question, QVariantList notes);
    Q_INVOKABLE void clearConversation();
    QVariantList conversation() const { return asked.toVariantList(); }
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void checkClaude();
    Q_INVOKABLE void signInClaude();
signals:
    void changed();
    void executableChanged();
    void engineChanged();
    void applied(QString pageId);
private:
    using Accept = std::function<bool(const QJsonObject &)>;
    void launch(const QString &prompt, const QByteArray &schema, Accept accept);
    void finish(int code, QProcess::ExitStatus exit, const QString &output, const Accept &accept);
    void fail(QString text, QString kind = {});
    void stopModel();
    QString claude() const;
    void record(const QJsonObject &claudeReply, bool succeeded);
    McpLink connection;
    Connectors hub;
    UsageLog spending;
    PlanLimits plans;
    QElapsedTimer clock;
    QString cli, engineKey, account = "unknown", stage = "idle", kind = "edit", issue, hint, replacement;
    QJsonObject target;
    QJsonArray written, asked;
    QProcess *model = nullptr;
    QProcess *probe = nullptr;
    QTimer deadline;
    QByteArray diagnostics, transcript;
    int generation = 0;
    std::unique_ptr<QTemporaryDir> work;
};
