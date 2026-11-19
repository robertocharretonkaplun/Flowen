#include "mcplink.h"
#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonArray>
#include <QSettings>
#include <utility>

using Obj = QJsonObject;
static QSettings preferences() {
    return QSettings(QSettings::defaultFormat(),QSettings::UserScope,"Lunqio","Editor");
}
McpLink::McpLink(QString path, QObject *parent) : QObject(parent), database(std::move(path)) {
    automatic = preferences().value("mcpAutoConnect",true).toBool();
    timeout.setSingleShot(true);
    connect(&timeout,&QTimer::timeout,this,[this]{ stop("El servidor local tardó demasiado en responder."); });
}
QString McpLink::serverPath() {
#ifdef Q_OS_WIN
    return QCoreApplication::applicationDirPath()+"/notas-mcp.exe";
#else
    return QCoreApplication::applicationDirPath()+"/notas-mcp";
#endif
}
void McpLink::setAutoConnect(bool enable) {
    if (automatic == enable) return;
    automatic = enable;
    preferences().setValue("mcpAutoConnect",enable);
    emit autoConnectChanged();
}
McpLink::~McpLink() {
    pending = {};
    close();
}
void McpLink::close() { stop("Conexión cerrada."); }
void McpLink::stop(const QString &reason) {
    timeout.stop();
    auto callback = std::exchange(pending,{});
    auto *old = std::exchange(process,nullptr);
    if (old) {
        old->disconnect(this);
        old->closeWriteChannel();
        if (old->state() != QProcess::NotRunning && !old->waitForFinished(200)) old->kill();
        old->deleteLater();
    }
    status = "offline"; message = reason; toolNames.clear();
    emit changed();
    if (callback) callback({},reason);
}
void McpLink::send(const Obj &packet) {
    process->write(QJsonDocument(packet).toJson(QJsonDocument::Compact)+'\n');
}
void McpLink::rpc(const QString &method,const Obj &params,Reply reply) {
    if (!process || pending) { reply({},"La conexión MCP no está disponible."); return; }
    pending = std::move(reply);
    timeout.start(10000);
    send({{"jsonrpc","2.0"},{"id",++sequence},{"method",method},{"params",params}});
}
void McpLink::consume() {
    while (process && process->canReadLine()) {
        auto packet = QJsonDocument::fromJson(process->readLine()).object();
        if (!pending || packet["id"].toInt(-1) != sequence) continue;
        timeout.stop();
        auto reply = std::exchange(pending,{});
        reply(packet["result"].toObject(),packet["error"].toObject()["message"].toString());
    }
}
void McpLink::open() {
    if (process) return;
    status = "connecting"; message = "Negociando la conexión con notas-mcp…"; emit changed();
    process = new QProcess(this);
    process->setStandardErrorFile(QProcess::nullDevice());
    connect(process,&QProcess::readyReadStandardOutput,this,&McpLink::consume);
    connect(process,&QProcess::errorOccurred,this,[this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) stop("No se pudo iniciar notas-mcp. Comprueba que está junto a Lunqio.");
    });
    connect(process,&QProcess::finished,this,[this]{ stop("El proceso MCP local se cerró."); });
    connect(process,&QProcess::started,this,[this] {
        rpc("initialize",{{"protocolVersion","2025-11-25"},{"capabilities",Obj{}},
            {"clientInfo",Obj{{"name","lunqio-desktop"},{"version","0.4.0"}}}},[this](Obj result,QString error) {
            if (!process) return;
            if (!error.isEmpty() || result["protocolVersion"] != "2025-11-25" || !result["capabilities"].toObject().contains("tools")) {
                stop("El servidor no admite la conexión MCP de Lunqio."); return;
            }
            send({{"jsonrpc","2.0"},{"method","notifications/initialized"}});
            rpc("tools/list",{},[this](Obj list,QString why) {
                if (!process) return;
                bool read = false, write = false;
                for (const auto &entry : list["tools"].toArray()) {
                    auto t = entry.toObject();
                    const QString name = t["name"].toString();
                    if (!name.isEmpty()) toolNames.append(name);
                    read |= t["name"] == "get_page";
                    write |= t["name"] == "apply_block_changes" &&
                             QJsonDocument(t["inputSchema"].toObject()).toJson().contains("\"replace_text\"");
                }
                if (!why.isEmpty() || !read || !write) { stop("Actualiza notas-mcp a la misma versión que el editor."); return; }
                status = "connected"; message = "El editor está conectado a la biblioteca abierta mediante notas-mcp.";
                emit changed();
            });
        });
    });
    timeout.start(10000);
    process->start(serverPath(),{"--db",database});
}
void McpLink::tool(const QString &name,const Obj &args,Reply reply) {
    if (status != "connected") { reply({},"Conecta el servidor MCP de la biblioteca."); return; }
    rpc("tools/call",{{"name",name},{"arguments",args}},[reply=std::move(reply)](Obj r,QString error) {
        auto contents = r["content"].toArray();
        auto data = contents.isEmpty() ? Obj{} : QJsonDocument::fromJson(contents.first().toObject()["text"].toString().toUtf8()).object();
        if (error.isEmpty() && (r["isError"].toBool() || data.isEmpty()))
            error = data["message"].toString("Respuesta MCP no válida.");
        reply(data,error);
    });
}
