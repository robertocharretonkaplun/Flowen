#pragma once
#include <QDir>
#include <QJsonObject>
#include <QLockFile>
#include <QProcess>
#include <QTimer>
#include <QUrl>
#include <functional>
#include <memory>

/// One AI client (Claude Desktop, Claude Code or Codex) that can start notas-mcp for
/// this library. Turning it on registers the server in the client's own configuration.
class Connector : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString key READ key CONSTANT)
    Q_PROPERTY(QString title READ title CONSTANT)
    Q_PROPERTY(QString summary READ summary CONSTANT)
    Q_PROPERTY(QString icon READ icon CONSTANT)
    Q_PROPERTY(bool usesProgram READ usesProgram CONSTANT)
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString detail READ detail NOTIFY changed)
    Q_PROPERTY(QString serverName READ serverName NOTIFY changed)
    Q_PROPERTY(QString location READ location NOTIFY changed)
    Q_PROPERTY(QString program READ program NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(bool enabled READ enabled NOTIFY changed)
    Q_PROPERTY(bool registered READ registered NOTIFY changed)
public:
    Connector(QString key, QString title, QString summary, QString icon, const QString &database, QObject *parent);
    ~Connector() override;
    QString key() const { return id; }
    QString title() const { return heading; }
    QString summary() const { return about; }
    QString icon() const { return glyph; }
    virtual bool usesProgram() const { return false; }
    QString state() const { return status; }
    QString detail() const { return message; }
    QString serverName() const { return name; }
    QString location() const { return QDir::toNativeSeparators(where); }
    QString program() const { return exe; }
    bool busy() const { return status == "checking" || status == "applying"; }
    virtual bool ready() const { return status != "missing"; }
    bool enabled() const { return status == "applying" ? wanted : active; }
    bool registered() const { return present || stale; }
    void setProgram(const QString &path);
    Q_INVOKABLE void inspect();
    Q_INVOKABLE void setEnabled(bool on);
    Q_INVOKABLE void remove();
    Q_INVOKABLE void reveal() const;
    Q_INVOKABLE bool chooseProgram(const QUrl &file);
signals:
    void changed();
protected:
    enum class Match { None, Ours, Stale };
    struct Entry { QString name; Match match = Match::None; bool enabled = true; };
    using Done = std::function<void(int,const QByteArray &,const QByteArray &)>;
    virtual void check() = 0;              // inspect and report a final state
    virtual void apply(bool on) = 0;       // runs while the state is "applying"
    virtual void unregister() = 0;
    virtual QString settingsKey() const { return {}; }
    Match classify(const QString &command, QStringList args, const QJsonObject &env) const;
    QList<Entry> scanJson(const QJsonObject &servers) const;
    QString freeName(const QStringList &taken) const;
    void adopt(const QList<Entry> &found);
    void settle(const QString &on, const QString &paused, const QString &off);
    void report(const QString &state, const QString &detail);
    void fail(const QString &detail) { report("error",detail); }
    void run(const QStringList &args, Done done);
    void sequence(QList<QStringList> commands, const QString &failure, std::function<void()> finish);
    QString serverCommand() const;
    QStringList serverArgs() const;
    QString database, exe, where, name, status = "idle", message;
    QList<Entry> entries;
    bool present = false, active = false, stale = false, wanted = false;
private:
    QString id, heading, about, glyph;
    QProcess process;
    QTimer timeout;
    Done pending;
    std::unique_ptr<QLockFile> guard;
};

class ClaudeDesktopConnector : public Connector {
    Q_OBJECT
public:
    ClaudeDesktopConnector(const QString &database, QString config = {}, QObject *parent = nullptr);
    static QString findConfig();
protected:
    void check() override;
    void apply(bool on) override;
    void unregister() override { apply(false); }
private:
    bool read(QJsonObject &config);
    bool write(const QJsonObject &config);
    bool watching() const;
    void flagRestart();
    bool fixed;
};

class ClaudeCodeConnector : public Connector {
    Q_OBJECT
public:
    explicit ClaudeCodeConnector(const QString &database, QObject *parent = nullptr);
    static QString findProgram();
    static QString configFile();
    bool usesProgram() const override { return true; }
    bool ready() const override { return !exe.isEmpty() && !busy(); }
protected:
    void check() override;
    void apply(bool on) override;
    void unregister() override { apply(false); }
    QString settingsKey() const override { return "claudeExecutable"; }
private:
    bool servers(QJsonObject &out);
};

class CodexConnector : public Connector {
    Q_OBJECT
public:
    explicit CodexConnector(const QString &database, QObject *parent = nullptr);
    static QString findProgram();
    static QString configFile();
    bool usesProgram() const override { return true; }
    bool ready() const override { return !exe.isEmpty() && !busy(); }
protected:
    void check() override;
    void apply(bool on) override;
    void unregister() override;
private:
    void list(std::function<void(QStringList)> next);
    bool toggle(const QString &server, bool on);
};

/// The clients shown in the Connectors tab.
class Connectors : public QObject {
    Q_OBJECT
    Q_PROPERTY(QList<QObject *> clients READ clients CONSTANT)
    Q_PROPERTY(Connector *claudeDesktop READ claudeDesktop CONSTANT)
    Q_PROPERTY(Connector *claudeCode READ claudeCode CONSTANT)
    Q_PROPERTY(Connector *codex READ codex CONSTANT)
public:
    Connectors(const QString &database, QObject *parent = nullptr);
    QList<QObject *> clients() const { return {desktop,code,openai}; }
    Connector *claudeDesktop() const { return desktop; }
    Connector *claudeCode() const { return code; }
    Connector *codex() const { return openai; }
    Q_INVOKABLE void inspectAll();
    Q_INVOKABLE void copyConfiguration() const;
private:
    QString database;
    ClaudeDesktopConnector *desktop;
    ClaudeCodeConnector *code;
    CodexConnector *openai;
};
