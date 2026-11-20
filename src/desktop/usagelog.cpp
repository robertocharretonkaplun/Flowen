#include "usagelog.h"
#include "store.h"
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QLocale>
#include <QSaveFile>
#include <QStandardPaths>
#include <utility>

namespace {
constexpr int Kept = 5000;
qint64 tokens(const QJsonObject &r) {
    return r["input"].toInteger()+r["cacheRead"].toInteger()+r["cacheWrite"].toInteger()+r["output"].toInteger();
}
QDate localDay(const QJsonObject &r) { return QDateTime::fromString(r["at"].toString(),Qt::ISODate).toLocalTime().date(); }
}

UsageLog::UsageLog(QString file, QObject *parent) : QObject(parent), path(file.isEmpty() ? defaultFile() : std::move(file)) {
    QFile in(path);
    if (!in.open(QIODevice::ReadOnly)) return;
    while (!in.atEnd()) {
        const auto record = QJsonDocument::fromJson(in.readLine()).object();
        if (!record.isEmpty() && record.contains("at")) items.append(record);
    }
    if (items.size() > Kept) items = items.mid(items.size()-Kept);
}
QString UsageLog::defaultFile() {
    const QString forced = notes::environment("USAGE_FILE");
    if (!forced.isEmpty()) return forced;
    return QDir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)).filePath("Flowen/usage.jsonl");
}
void UsageLog::add(QJsonObject record) {
    record["total"] = tokens(record);
    items.append(record);
    QDir().mkpath(QFileInfo(path).absolutePath());
    if (items.size() > Kept+500) {
        items = items.mid(items.size()-Kept);
        QSaveFile out(path);
        if (out.open(QIODevice::WriteOnly)) {
            for (const auto &r : items) out.write(QJsonDocument(r).toJson(QJsonDocument::Compact)+"\n");
            out.commit();
        }
    } else {
        QFile out(path);
        if (out.open(QIODevice::Append)) out.write(QJsonDocument(record).toJson(QJsonDocument::Compact)+"\n");
    }
    emit changed();
}
QVariantMap UsageLog::view(const QJsonObject &record) {
    auto map = record.toVariantMap();
    map["total"] = tokens(record);
    return map;
}
QVariantList UsageLog::recent() const {
    QVariantList out;
    for (qsizetype i = items.size()-1; i >= 0 && out.size() < 50; --i) out << view(items[i]);
    return out;
}
QVariantMap UsageLog::last() const { return items.isEmpty() ? QVariantMap() : view(items.last()); }
// days < 0: everything; 1: today; 7: today and the six days before.
QVariantMap UsageLog::totals(int days) const {
    const QDate first = QDate::currentDate().addDays(-(days-1));
    qint64 input = 0, cacheRead = 0, cacheWrite = 0, output = 0;
    double cost = 0;
    int requests = 0, priced = 0;
    for (const auto &r : items) {
        if (days >= 0 && localDay(r) < first) continue;
        ++requests;
        input += r["input"].toInteger(); cacheRead += r["cacheRead"].toInteger();
        cacheWrite += r["cacheWrite"].toInteger(); output += r["output"].toInteger();
        if (r["cost"].toDouble(-1) >= 0) { cost += r["cost"].toDouble(); ++priced; }
    }
    return {{"requests",requests},{"input",input},{"cacheRead",cacheRead},{"cacheWrite",cacheWrite},{"output",output},
            {"total",input+cacheRead+cacheWrite+output},{"cost",cost},{"priced",priced}};
}
// Oldest to newest, one entry per calendar day, split by assistant.
QVariantList UsageLog::daily(int days) const {
    QVariantList out;
    const QDate today = QDate::currentDate();
    for (int i = days-1; i >= 0; --i) {
        const QDate day = today.addDays(-i);
        qint64 claude = 0, codex = 0;
        int requests = 0;
        for (const auto &r : items) {
            if (localDay(r) != day) continue;
            ++requests;
            (r["engine"].toString() == "claude" ? claude : codex) += tokens(r);
        }
        out << QVariantMap{{"day",day.toString(Qt::ISODate)},{"label",QLocale().toString(day,"d MMM")},{"claude",claude},{"codex",codex},
                           {"requests",requests},{"today",i == 0}};
    }
    return out;
}
void UsageLog::clear() {
    items.clear();
    QFile::remove(path);
    emit changed();
}
