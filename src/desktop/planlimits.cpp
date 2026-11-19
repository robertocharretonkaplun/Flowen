#include "planlimits.h"
#include <QDateTime>
#include <QDir>
#include <QJsonDocument>
#include <QSettings>
#include <cmath>
#include <utility>

namespace {
QSettings preferences() { return QSettings(QSettings::defaultFormat(),QSettings::UserScope,"Lunqio","Editor"); }
qint64 nowMs() { return QDateTime::currentMSecsSinceEpoch(); }
// Reset times arrive in seconds; keep milliseconds for QML dates.
qint64 toMs(qint64 value) { return value > 0 && value < 100000000000LL ? value*1000 : value; }
QJsonObject window(int used, qint64 resetsAt, qint64 minutes = 0) {
    QJsonObject w{{"used",qBound(0,used,100)}};
    if (resetsAt > 0) w["resetsAt"] = toMs(resetsAt);
    if (minutes > 0) w["minutes"] = minutes;
    return w;
}
}

PlanLimits::PlanLimits(QObject *parent) : QObject(parent) {
    claudeState = QJsonDocument::fromJson(preferences().value("planLimits/claude").toByteArray()).object();
    codexState = QJsonDocument::fromJson(preferences().value("planLimits/codex").toByteArray()).object();
    timeout.setSingleShot(true);
    connect(&timeout,&QTimer::timeout,this,[this] { codexState["error"] = "Codex tardó demasiado en responder."; stop(); emit changed(); });
}
PlanLimits::~PlanLimits() { stop(); }
void PlanLimits::save() {
    preferences().setValue("planLimits/claude",QJsonDocument(claudeState).toJson(QJsonDocument::Compact));
    preferences().setValue("planLimits/codex",QJsonDocument(codexState).toJson(QJsonDocument::Compact));
}
void PlanLimits::stop() {
    timeout.stop();
    if (auto *old = std::exchange(process,nullptr)) {
        old->disconnect(this);
        old->closeWriteChannel();
        if (old->state() != QProcess::NotRunning && !old->waitForFinished(300)) old->kill();
        old->deleteLater();
    }
    buffer.clear();
}
void PlanLimits::refreshIfStale(int seconds) {
    if (nowMs()-codexState["updatedAt"].toInteger() > qint64(seconds)*1000) refreshCodex();
}
// account/rateLimits/read over the app-server's JSON-RPC, then the process is closed.
void PlanLimits::refreshCodex() {
    if (program.isEmpty() || process) return;
    process = new QProcess(this);
    process->setWorkingDirectory(QDir::tempPath());
    auto send = [this](const QJsonObject &packet) {
        if (process) process->write(QJsonDocument(packet).toJson(QJsonDocument::Compact)+"\n");
    };
    connect(process,&QProcess::readyReadStandardOutput,this,[this,send] {
        buffer += process->readAllStandardOutput();
        qsizetype end;
        while (process && (end = buffer.indexOf('\n')) >= 0) {
            const auto message = QJsonDocument::fromJson(buffer.left(end)).object();
            buffer.remove(0,end+1);
            const int id = message["id"].toInt(-1);
            if (id == 1) {
                send({{"method","initialized"},{"params",QJsonObject()}});
                send({{"id",2},{"method","account/rateLimits/read"},{"params",QJsonValue::Null}});
            } else if (id == 2) {
                finishCodex(message);
                return;
            }
        }
    });
    connect(process,&QProcess::errorOccurred,this,[this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) return;
        codexState["error"] = "No se pudo abrir Codex.";
        stop(); emit changed();
    });
    connect(process,&QProcess::finished,this,[this](int,QProcess::ExitStatus) {
        if (!process) return;
        codexState["error"] = "Codex no informó sus límites.";
        stop(); emit changed();
    });
    process->start(program,{"app-server"});
    send({{"id",1},{"method","initialize"},{"params",QJsonObject{{"clientInfo",QJsonObject{{"name","lunqio"},{"version","1"}}}}}});
    timeout.start(25000);
    emit changed();
}
void PlanLimits::finishCodex(const QJsonObject &reply) {
    const auto limits = reply["result"].toObject()["rateLimits"].toObject();
    if (limits.isEmpty()) {
        codexState["error"] = reply["error"].toObject()["message"].toString("Codex no informó sus límites.");
    } else {
        QJsonObject state{{"updatedAt",nowMs()}};
        if (!limits["planType"].toString().isEmpty()) state["plan"] = limits["planType"].toString();
        for (const auto &[key,name] : {std::pair{"primary","fiveHour"},std::pair{"secondary","weekly"}}) {
            const auto w = limits[key].toObject();
            if (w.isEmpty()) continue;
            // The primary window is normally 5 hours and the secondary one week; trust the reported length.
            const qint64 minutes = w["windowDurationMins"].toInteger();
            const QString slot = minutes >= 1440 ? "weekly" : minutes > 0 ? "fiveHour" : name;
            state[slot] = window(w["usedPercent"].toInt(),w["resetsAt"].toInteger(),minutes);
        }
        const auto credits = limits["credits"].toObject();
        if (!credits.isEmpty())
            state["credits"] = QJsonObject{{"has",credits["hasCredits"].toBool()},{"unlimited",credits["unlimited"].toBool()},
                                           {"balance",credits["balance"].toString()}};
        codexState = state;
        save();
    }
    stop();
    emit changed();
}
// Claude Code's rate_limit_info: utilization is a fraction (0.08 = 8 %), resetsAt is in seconds.
void PlanLimits::takeClaude(const QJsonObject &info) {
    QJsonObject state = claudeState;
    bool any = false;
    const auto unified = info["unifiedWindows"].toObject();
    auto take = [&](const QJsonObject &w, const QString &slot) {
        if (!w.contains("utilization")) return;
        state[slot] = window(int(std::lround(w["utilization"].toDouble()*100)),w["resetsAt"].toInteger(),slot == "weekly" ? 10080 : 300);
        any = true;
    };
    take(unified["five_hour"].toObject(),"fiveHour");
    take(unified["seven_day"].toObject(),"weekly");
    if (!any && info.contains("utilization")) {
        const QString type = info["rateLimitType"].toString();
        if (type == "five_hour") take(info,"fiveHour");
        else if (type == "seven_day") take(info,"weekly");
    }
    if (!any) return;
    state["updatedAt"] = nowMs();
    state.remove("error");
    claudeState = state;
    save();
    emit changed();
}
