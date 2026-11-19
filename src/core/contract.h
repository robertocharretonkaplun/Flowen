#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <stdexcept>

namespace notes {
struct Error : std::runtime_error {
    QString code;
    Error(QString code, const QString &message)
        : std::runtime_error(message.toStdString()), code(std::move(code)) {}
};
QJsonArray tools(bool readOnly);
bool isReadTool(const QString &name);
void validateCall(const QString &name, const QJsonObject &args);
QString newId();
}
