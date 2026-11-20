#include "store.h"
#include <QCoreApplication>
#include <QCommandLineParser>
#include <QJsonDocument>
#include <cmath>
#include <iostream>
#ifdef Q_OS_WIN
#include <fcntl.h>
#include <io.h>
#endif

using Obj = QJsonObject;
using Arr = QJsonArray;
static void send(const QJsonValue &id, const char *key, const Obj &body) {
    Obj packet{{"jsonrpc","2.0"},{"id",id},{key,body}};
    std::cout << QJsonDocument(packet).toJson(QJsonDocument::Compact).toStdString() << '\n' << std::flush;
}
static void fail(const QJsonValue &id, int code, QString message) {
    send(id,"error",{{"code",code},{"message",message}});
}
static Obj toolResult(const Obj &data, bool error = false) {
    return {{"content",Arr{Obj{{"type","text"},{"text",QString::fromUtf8(QJsonDocument(data).toJson(QJsonDocument::Compact))}}}},
            {"isError",error}};
}
class Session {
    notes::Store &store;
    bool readOnly;
    enum { Fresh, Negotiated, Ready } state = Fresh;
public:
    Session(notes::Store &store, bool readOnly) : store(store), readOnly(readOnly) {}
    void receive(const QByteArray &line) {
        QJsonParseError error;
        auto doc = QJsonDocument::fromJson(line,&error);
        if (error.error != QJsonParseError::NoError) return fail(QJsonValue::Null,-32700,"Invalid JSON");
        // Const access: operator[] on a mutable QJsonObject would insert "params": null when it is missing.
        const Obj req = doc.object(), params = req.value("params").toObject();
        auto id = req.value("id");
        QString method = req["method"].toString();
        if (!doc.isObject() || req["jsonrpc"] != "2.0" || method.isEmpty() ||
            !(id.isUndefined() || id.isString() || (id.isDouble() && std::floor(id.toDouble()) == id.toDouble())))
            return fail(QJsonValue::Null,-32600,"Invalid request");
        if (id.isUndefined()) {
            if (method == "notifications/initialized" && state == Negotiated) state = Ready;
            return;
        }
        // Clients built on the TypeScript SDK (Claude Desktop, Claude Code) omit params on tools/list and ping.
        const auto given = req.value("params");
        if (!given.isUndefined() && !given.isNull() && !given.isObject()) return fail(id,-32602,"Invalid params");
        if (method == "ping") return send(id,"result",{});
        if (method == "initialize") {
            if (state != Fresh || !params["protocolVersion"].isString() || !params["capabilities"].isObject() ||
                !params["clientInfo"].toObject()["name"].isString() || !params["clientInfo"].toObject()["version"].isString())
                return fail(id,-32602,"Invalid initialization");
            QString version = params["protocolVersion"].toString();
            if (version != "2025-06-18" && version != "2025-03-26") version = "2025-11-25";
            state = Negotiated;
            return send(id,"result",{{"protocolVersion",version},{"serverInfo",Obj{{"name","lunqio"},{"version",LUNQIO_VERSION}}},
                                     {"capabilities",Obj{{"tools",Obj{}}}}});
        }
        if (state != Ready) return fail(id,-32002,"Initialize the session first");
        if (method == "tools/list") {
            if (params.contains("cursor")) return fail(id,-32602,"Unknown cursor");
            return send(id,"result",{{"tools",notes::tools(readOnly)}});
        }
        if (method != "tools/call") return fail(id,-32601,"Method not found");
        if (!params["name"].isString() || (params.contains("arguments") && !params["arguments"].isObject()))
            return fail(id,-32602,"Invalid tool call");
        try {
            send(id,"result",toolResult(store.call(params["name"].toString(),params["arguments"].toObject(),"mcp")));
        } catch (const notes::Error &e) {
            if (e.code == "unknown_tool") return fail(id,-32602,"Unknown tool");
            send(id,"result",toolResult({{"code",e.code},{"message",QString::fromUtf8(e.what())}},true));
        }
    }
};
int main(int argc, char **argv) {
    QCoreApplication app(argc,argv);
    QCoreApplication::setApplicationName("notas-mcp");
    QCommandLineParser cli;
    cli.addHelpOption();
    cli.addOption({"db","Ruta absoluta de SQLite.","archivo",notes::Store::defaultPath()});
    cli.addOption({"read-only","Abrir una biblioteca existente en modo de solo lectura."});
    cli.process(app);
#ifdef Q_OS_WIN
    _setmode(_fileno(stdin),_O_BINARY);
    _setmode(_fileno(stdout),_O_BINARY);
#endif
    try {
        bool ro = cli.isSet("read-only");
        notes::Store store(cli.value("db"),ro);
        Session session(store,ro);
        QByteArray line;
        bool overflow = false;
        char ch;
        while (std::cin.get(ch)) {
            if (ch == '\n') {
                if (overflow) fail(QJsonValue::Null,-32600,"Request exceeds 2 MiB");
                else session.receive(line);
                overflow = false;
                line.clear();
            } else if (line.size() < 2*1024*1024) line.append(ch);
            else overflow = true;
        }
    } catch (const std::exception &e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
    return 0;
}
