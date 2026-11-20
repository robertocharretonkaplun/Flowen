#include "store.h"
#include "storeinternal.h"
#include "inlines.h"
#include <QCryptographicHash>
#include <algorithm>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QHash>
#include <QLockFile>
#include <QRegularExpression>
#include <QSet>
#include <QSqlError>
#include <QSqlRecord>
#include <QStandardPaths>
#include <QTemporaryFile>

namespace notes {
QSqlQuery Store::sql(const QString &statement, const QVariantList &values) {
    QSqlQuery q(db);
    if (!q.prepare(statement)) databaseError(q.lastError());
    for (const auto &v : values) q.addBindValue(v);
    if (!q.exec()) databaseError(q.lastError());
    return q;
}
QString Store::defaultPath() {
    QString custom = qEnvironmentVariable("LUNQIO_DB");
    if (!custom.isEmpty()) return custom;
    return QDir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)).filePath("Lunqio/notas.sqlite3");
}
Store::Store(const QString &path, bool ro) : db(QSqlDatabase::addDatabase("QSQLITE",newId())), readOnly(ro) {
    QFileInfo file(path);
    if (!file.isAbsolute()) invalid("Indica una ruta absoluta para la biblioteca.");
    if (!ro && !file.absoluteDir().mkpath(".")) throw Error("storage_error","No se pudo crear la carpeta de datos.");
    db.setDatabaseName(file.absoluteFilePath());
    db.setConnectOptions(ro ? "QSQLITE_OPEN_READONLY;QSQLITE_BUSY_TIMEOUT=2500" : "QSQLITE_BUSY_TIMEOUT=2500");
    if (!db.open()) databaseError(db.lastError());
    sql("PRAGMA foreign_keys=ON");
    auto oldLibrary = [this] {
        auto q = sql("SELECT user_version,application_id FROM pragma_user_version,pragma_application_id");
        return q.next() && q.value(0).toInt() == 1 && q.value(1).toInt() == 1280196913;
    };
    QLockFile migrationLock(path+".migration.lock");
    if (!ro && oldLibrary()) {
        if (!migrationLock.tryLock(2500)) throw Error("database_busy","Otra ventana está actualizando la biblioteca. Vuelve a abrirla.");
        if (oldLibrary()) {
            QTemporaryFile previous(path+".v1-XXXXXX.sqlite3");
            if (!previous.open()) throw Error("storage_error","No se pudo crear la copia anterior a la actualización.");
            const QString copyPath = previous.fileName();
            previous.close();
            sql("VACUUM INTO ?",{copyPath});
            previous.setAutoRemove(false);
        }
    }
    Transaction tx(db,!ro);
    auto version = sql("PRAGMA user_version");
    version.next();
    int v = version.value(0).toInt();
    version.finish();
    if (v == 0 && !ro) {
        auto tables = sql("SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
        tables.next();
        if (tables.value(0).toInt()) throw Error("schema_error","La base de datos pertenece a otra aplicación.");
        tables.finish();
        sql("CREATE TABLE pages(id TEXT PRIMARY KEY, parent_id TEXT REFERENCES pages(id), title TEXT NOT NULL, title_fold TEXT NOT NULL, position INTEGER NOT NULL, revision INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, trash_batch TEXT)");
        sql("CREATE INDEX by_parent ON pages(parent_id, position, id)");
        sql("CREATE TABLE blocks(id TEXT PRIMARY KEY, page_id TEXT NOT NULL REFERENCES pages(id), position INTEGER NOT NULL, content_json TEXT NOT NULL, text_fold TEXT NOT NULL, UNIQUE(page_id,position))");
        sql("CREATE TABLE revisions(seq INTEGER PRIMARY KEY AUTOINCREMENT, page_id TEXT NOT NULL REFERENCES pages(id), revision INTEGER NOT NULL, snapshot_json TEXT NOT NULL, actor TEXT NOT NULL, at TEXT NOT NULL, UNIQUE(page_id,revision))");
        sql("CREATE TABLE operations(key TEXT PRIMARY KEY, fingerprint BLOB NOT NULL, result_json TEXT NOT NULL)");
        sql("PRAGMA application_id=1280196913");
    } else {
        auto app = sql("PRAGMA application_id");
        app.next();
        if ((v != 1 && v != 2) || app.value(0).toInt() != 1280196913)
            throw Error("schema_error","La versión o el formato de la biblioteca es incompatible.");
    }
    if (!ro && v < 2) {
        sql("CREATE TABLE photos(id TEXT PRIMARY KEY, mime TEXT NOT NULL, bytes BLOB NOT NULL)");
        sql("PRAGMA user_version=2");
    }
    // Page icon and cover. Optional columns keep version 2, so older notas-mcp copies still open the library.
    if (!ro) {
        QStringList columns;
        auto info = sql("PRAGMA table_info(pages)");
        while (info.next()) columns << info.value(1).toString();
        info.finish();
        if (!columns.contains("icon")) sql("ALTER TABLE pages ADD COLUMN icon TEXT");
        if (!columns.contains("cover")) sql("ALTER TABLE pages ADD COLUMN cover TEXT");
        // Page typography (font, smaller text, full width): optional columns as well.
        if (!columns.contains("font")) sql("ALTER TABLE pages ADD COLUMN font TEXT");
        if (!columns.contains("small_text")) sql("ALTER TABLE pages ADD COLUMN small_text INTEGER");
        if (!columns.contains("full_width")) sql("ALTER TABLE pages ADD COLUMN full_width INTEGER");
        // Favorites and recent visits: desktop-only, outside page revisions.
        sql("CREATE TABLE IF NOT EXISTS favorites(page_id TEXT PRIMARY KEY, position INTEGER NOT NULL)");
        sql("CREATE TABLE IF NOT EXISTS visits(page_id TEXT PRIMARY KEY, at TEXT NOT NULL)");
        // Your page templates: a copy of a page's look and blocks, without comments.
        sql("CREATE TABLE IF NOT EXISTS templates(id TEXT PRIMARY KEY, name TEXT NOT NULL, icon TEXT, page_json TEXT NOT NULL, created_at TEXT NOT NULL)");
        refold();
    }
    tx.commit();
    if (!ro) sql("PRAGMA journal_mode=WAL");
}
Store::~Store() {
    auto connection = db.connectionName();
    db.close();
    db = QSqlDatabase();
    QSqlDatabase::removeDatabase(connection);
}
static Obj metadata(const QSqlQuery &q) {
    Obj o;
    for (const auto key : {"id","title","parent_id","revision","position","created_at","updated_at","deleted_at"})
        o[key] = q.isNull(key) ? QJsonValue(QJsonValue::Null) : QJsonValue::fromVariant(q.value(key));
    for (const auto key : {"icon","cover"})
        o[key] = q.record().indexOf(key) < 0 || q.isNull(key) ? QJsonValue(QJsonValue::Null) : QJsonValue::fromVariant(q.value(key));
    const bool styled = q.record().indexOf("font") >= 0;
    o["font"] = styled && !q.isNull("font") ? q.value("font").toString() : QStringLiteral("sans");
    o["small_text"] = styled && q.value("small_text").toInt() != 0;
    o["full_width"] = styled && q.value("full_width").toInt() != 0;
    return o;
}
Obj Store::load(const QString &id) {
    auto q = sql("SELECT * FROM pages WHERE id=?",{id});
    if (!q.next()) throw Error("not_found","La página no existe.");
    auto p = metadata(q);
    Arr blocks;
    auto b = sql("SELECT content_json FROM blocks WHERE page_id=? ORDER BY position",{id});
    while (b.next()) blocks.append(parse(b.value(0).toByteArray()));
    p["blocks"] = blocks;
    return p;
}
Obj Store::page(const QString &id) {
    Transaction tx(db,false);
    auto p = load(id);
    tx.commit();
    return p;
}
Obj Store::checked(const QString &id, int expected, bool deleted) {
    auto p = load(id);
    if (p["revision"].toInt() != expected) throw Error("revision_conflict","La página cambió desde que la abriste.");
    if (p["deleted_at"].isNull() == deleted) throw Error("invalid_state","La página está en otra ubicación (biblioteca o papelera).");
    return p;
}
void Store::checkParent(const QString &id, const QJsonValue &parent) {
    if (parent.isNull() || parent.isUndefined()) return;
    auto q = sql("WITH RECURSIVE chain(id,parent_id,deleted_at) AS (SELECT id,parent_id,deleted_at FROM pages WHERE id=? UNION ALL SELECT p.id,p.parent_id,p.deleted_at FROM pages p JOIN chain c ON p.id=c.parent_id) SELECT id,deleted_at FROM chain",{parent.toString()});
    if (!q.next()) invalid("La página de destino no existe.");
    do {
        if (q.value(0).toString() == id) invalid("El destino crearía un ciclo.");
        if (!q.value(1).isNull()) invalid("El destino está en la papelera.");
    } while (q.next());
}
void Store::assignParent(Obj &p, const QJsonValue &parent) {
    checkParent(p["id"].toString(),parent);
    p["parent_id"] = parent.isString() ? parent : QJsonValue(QJsonValue::Null);
    auto pos = sql("SELECT coalesce(max(position),-1)+1 FROM pages WHERE parent_id IS ?",{p["parent_id"].toVariant()});
    pos.next();
    p["position"] = pos.value(0).toInt();
}
static void checkTitle(const QString &title) {
    if (title.trimmed().isEmpty() || title.toUcs4().size() > 240 || title.contains(QChar::Null)) invalid("Escribe un título de entre 1 y 240 caracteres.");
}
static Obj completeBlock(Obj block, QString id) {
    auto data = block;
    data.remove("id");
    // Desktop drafts and MCP writes share the same content schema.
    validateCall("create_page",{{"title","x"},{"blocks",Arr{data}}});
    // value(), not operator[]: reading a missing key through operator[] would add it as null.
    validateSpans(block.value("text").toString(),block.value("spans").toArray());
    const QString type = block["type"].toString();
    if (type != "task" && block.contains("checked")) invalid("Solo las tareas admiten una casilla.");
    if (type != "heading" && block.contains("level")) invalid("Solo los encabezados tienen nivel.");
    if (type != "callout" && block.contains("icon")) invalid("Solo las notas destacadas tienen icono.");
    if (type == "divider" && (block.contains("align") || block.contains("color") || block.contains("background")))
        invalid("Un separador no tiene alineación ni color.");
    if (type != "toggle" && block.contains("collapsed")) invalid("Solo los desplegables se pliegan.");
    if (type == "divider" && (!block["text"].toString().isEmpty() || !block["spans"].toArray().isEmpty()))
        invalid("Un separador no lleva texto.");
    if (type == "task" && !block.contains("checked")) block["checked"] = false;
    if (block["indent"].toInt() == 0) block.remove("indent");
    block["id"] = id;
    return block;
}
static void checkIcon(const QJsonValue &icon) {
    if (icon.isString() && (icon.toString().trimmed().isEmpty() || icon.toString().contains('\n'))) invalid("Elige un emoji como icono.");
}
Obj Store::record(Obj p, const QString &actor, bool rewriteBlocks) {
    const auto id = p["id"].toString(), stamp = now();
    int revision = p["revision"].toInt()+1;
    p["revision"] = revision;
    p["updated_at"] = stamp;
    auto title = p["title"].toString();
    checkTitle(title);
    // Blocks never keep "spans": null (older saves wrote it, and the schema refuses it on the way back).
    Arr blocks;
    for (const auto &value : p["blocks"].toArray()) {
        Obj block = value.toObject();
        if (block.contains("spans") && block.value("spans").isNull()) block.remove("spans");
        blocks.append(block);
    }
    p["blocks"] = blocks;
    if (blocks.size() > 512 || QJsonDocument(blocks).toJson(QJsonDocument::Compact).size() > 1024*1024) invalid("La página supera 512 bloques o 1 MiB de contenido.");
    // Covers made from a photo must point to one stored in this library.
    const QString cover = p["cover"].toString();
    if (cover.startsWith("photo:") && !sql("SELECT 1 FROM photos WHERE id=?",{cover.mid(6)}).next()) invalid("La foto de portada no existe en esta biblioteca.");
    QString before;
    {
        auto old = sql("SELECT title FROM pages WHERE id=?",{id});
        if (old.next()) before = old.value(0).toString();
    }
    const QString font = p["font"].toString();
    sql("UPDATE pages SET parent_id=?,title=?,title_fold=?,position=?,revision=?,updated_at=?,deleted_at=?,icon=?,cover=?,font=?,small_text=?,full_width=? WHERE id=?",
        {p["parent_id"].toVariant(),title,fold(title),p["position"].toInt(),revision,stamp,p["deleted_at"].toVariant(),
         p["icon"].isString() ? QVariant(p["icon"].toString()) : QVariant(),cover.isEmpty() ? QVariant() : QVariant(cover),
         font.isEmpty() || font == "sans" ? QVariant() : QVariant(font),p["small_text"].toBool() ? 1 : 0,p["full_width"].toBool() ? 1 : 0,id});
    if (rewriteBlocks) {
        sql("DELETE FROM blocks WHERE page_id=?",{id});
        int pos = 0;
        for (const auto &value : blocks) {
            auto b = value.toObject();
            if (b["type"] == "image" && !sql("SELECT 1 FROM photos WHERE id=?",{b["asset"].toString()}).next())
                invalid("La foto no existe en esta biblioteca.");
            sql("INSERT INTO blocks VALUES(?,?,?,?,?)",{b["id"].toString(),id,pos++,QString::fromUtf8(json(b)),fold(b["text"].toString())});
        }
    }
    sql("INSERT INTO revisions(page_id,revision,snapshot_json,actor,at) VALUES(?,?,?,?,?)",
        {id,revision,QString::fromUtf8(json(p)),actor,stamp});
    if (!before.isEmpty() && before != title) renameMentions(id,before,title,actor);
    return {{"id",id},{"revision",revision}};
}
// Libraries written before accents were folded (or by an older notas-mcp) get their search keys updated.
void Store::refold() {
    QList<QPair<QString,QString>> titles, texts;
    auto p = sql("SELECT id,title,title_fold FROM pages");
    while (p.next()) {
        const QString f = fold(p.value(1).toString());
        if (f != p.value(2).toString()) titles.append({p.value(0).toString(),f});
    }
    p.finish();
    for (const auto &[id,f] : titles) sql("UPDATE pages SET title_fold=? WHERE id=?",{f,id});
    QList<QPair<QString,QString>> repaired;
    auto b = sql("SELECT id,content_json,text_fold FROM blocks");
    while (b.next()) {
        Obj block = parse(b.value(1).toByteArray());
        const QString f = fold(block.value("text").toString());
        if (f != b.value(2).toString()) texts.append({b.value(0).toString(),f});
        // Blocks saved with "spans": null by older versions lose that key.
        if (block.contains("spans") && block.value("spans").isNull()) {
            block.remove("spans");
            repaired.append({b.value(0).toString(),QString::fromUtf8(json(block))});
        }
    }
    b.finish();
    for (const auto &[id,f] : texts) sql("UPDATE blocks SET text_fold=? WHERE id=?",{f,id});
    for (const auto &[id,content] : repaired) sql("UPDATE blocks SET content_json=? WHERE id=?",{content,id});
}
// A page's new title reaches the mentions of it that still read the old one, in every other page
// (each changed page gets a revision). Mentions whose text was edited by hand keep it.
void Store::renameMentions(const QString &id, const QString &before, const QString &after, const QString &actor) {
    const QString target = "lunqio://page/"+id;
    QStringList pages;
    auto q = sql("SELECT DISTINCT page_id FROM blocks WHERE page_id<>? AND instr(content_json,?)>0",{id,target});
    while (q.next()) pages << q.value(0).toString();
    q.finish();
    for (const QString &pageId : pages) {
        Obj page = load(pageId);
        Arr blocks = page["blocks"].toArray();
        bool changed = false;
        for (qsizetype i = 0; i < blocks.size(); ++i) {
            Obj block = blocks[i].toObject();
            QString text = block["text"].toString();
            Arr spans;
            int shift = 0;
            for (const auto &value : block["spans"].toArray()) {
                Obj s = value.toObject();
                int start = s["start"].toInt()+shift, end = s["end"].toInt()+shift;
                if (s["link"].toString() == target && text.mid(start,end-start) == before) {
                    text.replace(start,end-start,after);
                    const int delta = int(after.size())-int(before.size());
                    end += delta; shift += delta;
                }
                s["start"] = start; s["end"] = end;
                spans.append(s);
            }
            if (shift || text != block["text"].toString()) {
                block["text"] = text; block["spans"] = spans;
                blocks[i] = block; changed = true;
            }
        }
        if (!changed) continue;
        page["blocks"] = blocks;
        record(page,actor,true);
    }
}
qint64 Store::generation() {
    auto q = sql("SELECT coalesce(max(seq),0) FROM revisions");
    q.next();
    return q.value(0).toLongLong();
}
Arr Store::navigation() {
    Arr rows;
    auto q = sql("SELECT * FROM pages WHERE deleted_at IS NULL ORDER BY position,id");
    while (q.next()) rows.append(metadata(q));
    return rows;
}
Arr Store::history(const QString &id) {
    Arr rows;
    auto q = sql("SELECT revision,actor,at FROM revisions WHERE page_id=? ORDER BY revision DESC",{id});
    while (q.next()) rows.append(Obj{{"revision",q.value(0).toInt()},{"actor",q.value(1).toString()},{"at",q.value(2).toString()}});
    return rows;
}
Obj Store::read(const QString &name, const Obj &args) {
    int limit = args["limit"].toInt(20), cursor = args["cursor"].toInt();
    Arr items;
    Obj output;
    QString field = "pages";
    if (name == "get_page") {
        output = load(args["id"].toString());
        auto blocks = output.take("blocks").toArray();
        field = "blocks";
        for (qsizetype i = cursor; i < blocks.size() && items.size() <= limit; ++i) items.append(blocks[i]);
    } else {
        QSqlQuery q(db);
        if (name == "search_notes") {
            QString needle = fold(args["query"].toString().trimmed());
            if (needle.isEmpty()) invalid("Escribe algo para buscar.");
            // Best first: the title itself, a title that starts with it, one that contains it, then the
            // text; the most recently edited first within each.
            q = sql("SELECT p.*, (SELECT b.content_json FROM blocks b WHERE b.page_id=p.id AND instr(b.text_fold,?)>0 ORDER BY b.position LIMIT 1) AS hit "
                    "FROM pages p WHERE p.deleted_at IS NULL AND (instr(p.title_fold,?)>0 OR EXISTS(SELECT 1 FROM blocks b WHERE b.page_id=p.id AND instr(b.text_fold,?)>0)) "
                    "ORDER BY p.title_fold=? DESC,instr(p.title_fold,?)=1 DESC,instr(p.title_fold,?)>0 DESC,p.updated_at DESC,p.id LIMIT ? OFFSET ?",
                    {needle,needle,needle,needle,needle,needle,limit+1,cursor});
        } else if (args["trashed"].toBool() && !args["parent_id"].isString()) {
            q = sql("SELECT p.* FROM pages p LEFT JOIN pages a ON a.id=p.parent_id WHERE p.deleted_at IS NOT NULL AND p.trash_batch IS NOT a.trash_batch ORDER BY p.deleted_at DESC,p.id LIMIT ? OFFSET ?",{limit+1,cursor});
        } else {
            q = sql("SELECT * FROM pages WHERE parent_id IS ? AND (deleted_at IS NOT NULL)=? ORDER BY position,id LIMIT ? OFFSET ?",
                    {args["parent_id"].toVariant(),args["trashed"].toBool(),limit+1,cursor});
        }
        while (q.next()) {
            Obj row = metadata(q);
            if (name == "search_notes") {
                QString text = parse(q.value("hit").toByteArray())["text"].toString(row["title"].toString());
                qsizetype start = qMax<qsizetype>(0,fold(text).indexOf(fold(args["query"].toString().trimmed()))-36);
                row["snippet"] = text.mid(start,160);
            }
            items.append(row);
        }
    }
    bool more = items.size() > limit;
    if (more) items.removeLast();
    output[field] = items;
    output["next_cursor"] = more ? QJsonValue(qint64(cursor)+limit) : QJsonValue(QJsonValue::Null);
    return output;
}
Obj Store::mutate(const QString &name, const Obj &args, const QString &actor) {
    if (name == "create_page") {
        QString id = newId(), stamp = now();
        Obj p{{"id",id},{"title",args["title"]},{"created_at",stamp},{"deleted_at",QJsonValue::Null},
              {"icon",args.value("icon").isString() ? args["icon"] : QJsonValue(QJsonValue::Null)},
              {"cover",args.value("cover").isString() ? args["cover"] : QJsonValue(QJsonValue::Null)},
              {"font",args.value("font").toString("sans")},{"small_text",args["small_text"].toBool()},{"full_width",args["full_width"].toBool()}};
        checkIcon(p["icon"]);
        assignParent(p,args["parent_id"]);
        Arr blocks;
        for (const auto &b : args["blocks"].toArray()) blocks.append(completeBlock(b.toObject(),newId()));
        p["blocks"] = blocks;
        sql("INSERT INTO pages(id,title,title_fold,position,revision,created_at,updated_at) VALUES(?,'','',0,0,?,?)",{id,stamp,stamp});
        return record(p,actor,true);
    }
    QString id = args["id"].toString();
    bool restore = name == "restore_page";
    auto p = checked(id,args["expected_revision"].toInt(),restore);
    if (name == "update_page") {
        static const QStringList fields{"title","parent_id","icon","cover","font","small_text","full_width"};
        if (std::none_of(fields.begin(),fields.end(),[&](const QString &f) { return args.contains(f); }))
            invalid("Indica un título, un destino, un icono, una portada o el aspecto del texto.");
        for (const auto key : {"font","small_text","full_width"}) if (args.contains(key)) p[key] = args[key];
        if (args.contains("title")) p["title"] = args["title"];
        if (args.contains("icon")) { checkIcon(args["icon"]); p["icon"] = args["icon"]; }
        if (args.contains("cover")) p["cover"] = args["cover"];
        if (args.contains("parent_id") && args["parent_id"] != p["parent_id"]) assignParent(p,args["parent_id"]);
        return record(p,actor);
    }
    if (name == "apply_block_changes") {
        auto blocks = p["blocks"].toArray();
        for (const auto &entry : args["changes"].toArray()) {
            auto op = entry.toObject();
            QString kind = op["op"].toString(), blockId = op["block_id"].toString();
            int index = op["index"].toInt(int(blocks.size()));
            if (kind == "insert") {
                if (index > blocks.size()) invalid("Posición de inserción fuera de rango.");
                blocks.insert(index,completeBlock(op["block"].toObject(),newId()));
                continue;
            }
            qsizetype old = 0;
            while (old < blocks.size() && blocks[old].toObject()["id"] != blockId) ++old;
            if (old == blocks.size()) invalid("El bloque no pertenece a la página.");
            if (kind == "remove") blocks.removeAt(old);
            else if (kind == "update") blocks[old] = completeBlock(op["block"].toObject(),blockId);
            else if (kind == "replace_text") {
                auto block = blocks[old].toObject();
                QString text = block["text"].toString(), original = op["original"].toString();
                int start = op["start"].toInt();
                if (text.mid(start,original.size()) != original)
                    throw Error("selection_conflict","La selección cambió. Selecciona el fragmento de nuevo.");
                const auto replacement = op["replacement"].toString();
                if (block.contains("spans")) block["spans"] = replaceSpans(block["spans"].toArray(),start,int(original.size()),int(replacement.size()));
                text.replace(start,original.size(),replacement);
                block["text"] = text;
                blocks[old] = completeBlock(block,blockId);
            }
            else {
                if (index >= blocks.size()) invalid("Posición de destino fuera de rango.");
                auto b = blocks.takeAt(old);
                blocks.insert(index,b);
            }
        }
        p["blocks"] = blocks;
        return record(p,actor,true);
    }
    auto group = sql("SELECT trash_batch FROM pages WHERE id=?",{id});
    group.next();
    QVariant batch = group.value(0);
    group.finish();
    auto tree = sql("WITH RECURSIVE tree(id) AS (SELECT ? UNION ALL SELECT p.id FROM pages p JOIN tree t ON p.parent_id=t.id WHERE p.trash_batch IS ?) SELECT id FROM tree",{id,batch});
    QStringList ids;
    while (tree.next()) ids.append(tree.value(0).toString());
    tree.finish();
    if (restore && p["parent_id"].isString()) {
        auto parent = sql("SELECT deleted_at FROM pages WHERE id=?",{p["parent_id"].toString()});
        if (!parent.next() || !parent.value(0).isNull()) assignParent(p,QJsonValue::Null);
    }
    QString stamp = now(), newBatch = newId();
    Obj result;
    for (const auto &child : ids) {
        auto item = child == id ? p : load(child);
        item["deleted_at"] = restore ? QJsonValue(QJsonValue::Null) : QJsonValue(stamp);
        sql("UPDATE pages SET trash_batch=? WHERE id=?",{restore ? QVariant() : QVariant(newBatch),child});
        auto saved = record(item,actor);
        if (child == id) result = saved;
    }
    result["affected"] = ids.size();
    return result;
}
Obj Store::call(const QString &name, const Obj &args, const QString &actor) {
    validateCall(name,args);
    bool writing = !isReadTool(name);
    if (writing && readOnly) throw Error("read_only","Biblioteca abierta en modo de solo lectura.");
    Transaction tx(db,writing);
    auto key = args["operation_key"].toString();
    QByteArray fingerprint;
    if (!key.isEmpty()) {
        fingerprint = QCryptographicHash::hash(name.toUtf8()+'\0'+json(args),QCryptographicHash::Sha256);
        auto cached = sql("SELECT fingerprint,result_json FROM operations WHERE key=?",{key});
        if (cached.next()) {
            if (cached.value(0).toByteArray() != fingerprint) throw Error("operation_conflict","La clave ya pertenece a otra operación.");
            auto result = parse(cached.value(1).toByteArray());
            cached.finish();
            tx.commit();
            return result;
        }
    }
    Obj result = writing ? mutate(name,args,actor) : read(name,args);
    if (!key.isEmpty()) sql("INSERT INTO operations VALUES(?,?,?)",{key,fingerprint,QString::fromUtf8(json(result))});
    tx.commit();
    return result;
}
Obj Store::saveDraft(const QString &id, int expected, const QString &title, Arr blocks) {
    Transaction tx(db,true);
    auto p = checked(id,expected);
    QSet<QString> existing, seen;
    for (const auto &b : p["blocks"].toArray()) existing.insert(b.toObject()["id"].toString());
    Arr normalized;
    for (const auto &value : blocks) {
        auto b = value.toObject();
        QString blockId = b["id"].toString();
        if (blockId.isEmpty()) blockId = newId();
        else if (!existing.contains(blockId) || seen.contains(blockId)) invalid("Identificador de bloque inválido.");
        seen.insert(blockId);
        normalized.append(completeBlock(b,blockId));
    }
    p["title"] = title;
    p["blocks"] = normalized;
    record(p,"manual",true);
    auto result = load(id);
    tx.commit();
    return result;
}
Obj Store::restoreRevision(const QString &id, int expected, int target) {
    Transaction tx(db,true);
    auto p = checked(id,expected);
    auto q = sql("SELECT snapshot_json FROM revisions WHERE page_id=? AND revision=?",{id,target});
    if (!q.next()) invalid("La revisión no existe.");
    auto snapshot = parse(q.value(0).toByteArray());
    q.finish();
    p["title"] = snapshot["title"];
    p["blocks"] = snapshot["blocks"];
    p["icon"] = snapshot.value("icon").isString() ? snapshot["icon"] : QJsonValue(QJsonValue::Null);
    p["cover"] = snapshot.value("cover").isString() ? snapshot["cover"] : QJsonValue(QJsonValue::Null);
    p["font"] = snapshot.value("font").toString("sans");
    p["small_text"] = snapshot["small_text"].toBool();
    p["full_width"] = snapshot["full_width"].toBool();
    if (p["cover"].toString().startsWith("photo:") && !sql("SELECT 1 FROM photos WHERE id=?",{p["cover"].toString().mid(6)}).next())
        p["cover"] = QJsonValue(QJsonValue::Null);
    auto parent = snapshot["parent_id"];
    if (parent != p["parent_id"]) {
        try { assignParent(p,parent); }
        catch (const Error &e) { if (e.code != "invalid_argument") throw; assignParent(p,QJsonValue::Null); }
    }
    auto result = record(p,"manual",true);
    tx.commit();
    return result;
}
Obj Store::insertPhoto(const QString &id, int expected, const QString &caption,
                       const QString &mime, const QByteArray &bytes) {
    if (readOnly) throw Error("read_only","Biblioteca de solo lectura.");
    Transaction tx(db,true);
    auto p = checked(id,expected);
    const QString asset = QString::fromLatin1(QCryptographicHash::hash(bytes,QCryptographicHash::Sha256).toHex());
    sql("INSERT OR IGNORE INTO photos(id,mime,bytes) VALUES(?,?,?)",{asset,mime,bytes});
    auto blocks = p["blocks"].toArray();
    blocks.append(completeBlock({{"type","image"},{"asset",asset},{"text",caption},{"width_percent",100}},newId()));
    p["blocks"] = blocks;
    auto result = record(p,"manual",true);
    tx.commit();
    return result;
}
// Keeps a photo in the library without adding a block (used for page covers).
QString Store::addPhoto(const QString &mime, const QByteArray &bytes) {
    if (readOnly) throw Error("read_only","Biblioteca de solo lectura.");
    const QString asset = QString::fromLatin1(QCryptographicHash::hash(bytes,QCryptographicHash::Sha256).toHex());
    sql("INSERT OR IGNORE INTO photos(id,mime,bytes) VALUES(?,?,?)",{asset,mime,bytes});
    return asset;
}
QByteArray Store::photo(const QString &asset, QString &mime) {
    auto q = sql("SELECT mime,bytes FROM photos WHERE id=?",{asset});
    if (!q.next()) throw Error("not_found","La biblioteca no contiene la foto.");
    mime = q.value(0).toString();
    return q.value(1).toByteArray();
}
void Store::backup(const QString &destination) {
    if (destination.isEmpty() || QFileInfo::exists(destination)) invalid("Elige un archivo nuevo para la copia.");
    sql("VACUUM INTO ?",{destination});
}
}
