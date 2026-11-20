#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <stdexcept>

namespace notes {
/// A refused request: `code` is stable for programs (invalid_argument, not_found, revision_conflict…),
/// the message is for people.
struct Error : std::runtime_error {
    QString code;
    Error(QString code, const QString &message)
        : std::runtime_error(message.toStdString()), code(std::move(code)) {}
};
/// The MCP tools with their JSON schemas (only the read tools when `readOnly`).
QJsonArray tools(bool readOnly);
/// Whether a tool only reads the library.
bool isReadTool(const QString &name);
/// Checks a tool's arguments against its schema; throws Error when they do not fit.
void validateCall(const QString &name, const QJsonObject &args);
/// A new random id for a page or block.
QString newId();
}
