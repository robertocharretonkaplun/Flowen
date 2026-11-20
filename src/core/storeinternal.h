#pragma once
/// Helpers shared by the files of the library (store.cpp, library.cpp); not part of its interface.
#include "contract.h"
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>

namespace notes {
using Obj = QJsonObject;
using Arr = QJsonArray;
inline QString now() { return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs); }
inline QByteArray json(const Obj &o) { return QJsonDocument(o).toJson(QJsonDocument::Compact); }
inline Obj parse(const QByteArray &bytes) { return QJsonDocument::fromJson(bytes).object(); }
inline void invalid(QString message) { throw Error("invalid_argument",message); }
/// Search and sorting ignore case and accents: "arbol" finds "Árbol" and "Álgebra" sorts with the a's.
inline QString fold(const QString &text) {
    QString out = text.toCaseFolded().normalized(QString::NormalizationForm_D);
    out.removeIf([](QChar c) { return c.category() == QChar::Mark_NonSpacing; });
    return out;
}
inline void databaseError(const QSqlError &e) {
    bool busy = (e.nativeErrorCode().toInt() & 255) == 5 || (e.nativeErrorCode().toInt() & 255) == 6;
    throw Error(busy ? "database_busy" : "storage_error", busy ? "La biblioteca está ocupada. Vuelve a intentar." :
                "SQLite no pudo completar la operación. Comprueba la ruta, los permisos y el espacio disponible.");
}
class Transaction {
    QSqlDatabase &db;
    bool done = false;
public:
    Transaction(QSqlDatabase &db, bool writing) : db(db) {
        QSqlQuery q(db);
        if (!q.exec(writing ? "BEGIN IMMEDIATE" : "BEGIN")) databaseError(q.lastError());
    }
    void commit() { if (!db.commit()) databaseError(db.lastError()); done = true; }
    ~Transaction() { if (!done) db.rollback(); }
};
}
