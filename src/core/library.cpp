#include "store.h"
#include "storeinternal.h"
#include <QHash>
#include <QRegularExpression>
#include <QSet>
#include <algorithm>

// The library's desktop side: favorites and recent visits, templates, backlinks and the notes sent with
// a question to "Preguntar a Lunqio". Favorites, visits and templates live in tables of their own and
// never create page revisions; MCP does not use any of this.
namespace notes {
// Favorites and visits never create revisions; pages in the trash are left out until restored.
Arr Store::favorites() {
    Arr ids;
    auto q = sql("SELECT f.page_id FROM favorites f JOIN pages p ON p.id=f.page_id WHERE p.deleted_at IS NULL ORDER BY f.position,f.page_id");
    while (q.next()) ids.append(q.value(0).toString());
    return ids;
}

Arr Store::recent(int limit) {
    Arr rows;
    auto q = sql("SELECT v.page_id,v.at FROM visits v JOIN pages p ON p.id=v.page_id WHERE p.deleted_at IS NULL ORDER BY v.at DESC,v.page_id LIMIT ?",{limit});
    while (q.next()) rows.append(Obj{{"id",q.value(0).toString()},{"at",q.value(1).toString()}});
    return rows;
}

void Store::setFavorite(const QString &id, bool on, int index) {
    if (readOnly) throw Error("read_only","Biblioteca de solo lectura.");
    Transaction tx(db,true);
    const auto p = load(id);
    if (on && !p["deleted_at"].isNull()) throw Error("invalid_state","La página está en la papelera.");
    // Rows of trashed pages keep their place, so a restored favorite comes back where it was.
    QStringList order, active;
    auto q = sql("SELECT f.page_id,p.deleted_at IS NULL FROM favorites f JOIN pages p ON p.id=f.page_id ORDER BY f.position,f.page_id");
    while (q.next()) if (q.value(0).toString() != id) {
        order << q.value(0).toString();
        if (q.value(1).toBool()) active << q.value(0).toString();
    }
    q.finish();
    if (on) {
        // The index counts visible favorites only.
        const int at = index >= 0 && index < active.size() ? int(order.indexOf(active[index])) : int(order.size());
        order.insert(at,id);
    }
    sql("DELETE FROM favorites");
    for (int i = 0; i < order.size(); ++i) sql("INSERT INTO favorites(page_id,position) VALUES(?,?)",{order[i],i});
    tx.commit();
}

void Store::visit(const QString &id) {
    if (readOnly) return;
    Transaction tx(db,true);
    sql("INSERT INTO visits(page_id,at) SELECT id,? FROM pages WHERE id=? AND deleted_at IS NULL "
        "ON CONFLICT(page_id) DO UPDATE SET at=excluded.at",{now(),id});
    sql("DELETE FROM visits WHERE page_id NOT IN (SELECT page_id FROM visits ORDER BY at DESC LIMIT 50)");
    tx.commit();
}

// The notes most related to a question, for "Preguntar a Lunqio": the open page first, then the pages
// whose title and text share most of the question's words (accents and case aside). A question about
// tasks also gets the unfinished tasks of the whole library. Each text is cut so the whole fits a prompt.
Arr Store::notesFor(const QString &question, const QString &current, int limit) {
    static const QSet<QString> filler{"para","como","cual","cuales","que","donde","cuando","sobre","esta","este","estos","estas",
        "tengo","tiene","tienen","hacer","entre","desde","hasta","porque","pero","todos","todas","algo","cosas","notas","nota",
        "pagina","paginas","dime","dame","resume","resumen","quiero","puedes","podrias","hay","mis","una","unos","unas","with",
        "what","which","about","have","from","that","this","there","their","the","and"};
    QStringList words;
    for (const QString &word : fold(question).split(QRegularExpression("[^\\p{L}\\p{N}]+"),Qt::SkipEmptyParts))
        if (word.size() >= 3 && !filler.contains(word) && !words.contains(word)) words << word;
    struct Candidate { QString id, title; QStringList lines; int score = 0; QDateTime at; };
    QList<Candidate> pages;
    QHash<QString,qsizetype> where;
    QStringList open;
    auto q = sql("SELECT p.id,p.title,p.title_fold,p.updated_at,b.content_json,b.text_fold FROM pages p LEFT JOIN blocks b ON b.page_id=p.id "
                 "WHERE p.deleted_at IS NULL ORDER BY p.id,b.position");
    while (q.next()) {
        const QString id = q.value(0).toString();
        if (!where.contains(id)) {
            Candidate c{id,q.value(1).toString(),{},0,QDateTime::fromString(q.value(3).toString(),Qt::ISODateWithMs)};
            for (const QString &w : words) if (q.value(2).toString().contains(w)) c.score += 5;
            where.insert(id,pages.size());
            pages.append(c);
        }
        Candidate &c = pages[where.value(id)];
        if (q.isNull(4)) continue;
        const Obj block = parse(q.value(4).toByteArray());
        const QString type = block["type"].toString(), text = block["text"].toString();
        if (text.isEmpty()) continue;
        for (const QString &w : words) c.score += int(q.value(5).toString().count(w));
        QString line = text;
        if (type == "task") {
            line = (block["checked"].toBool() ? "[x] " : "[ ] ")+text;
            if (!block["checked"].toBool()) open << "- "+text+" ("+c.title+")";
        } else if (type == "list" || type == "numbered") line = "- "+text;
        else if (type == "heading") line = "## "+text;
        else if (type == "quote") line = "> "+text;
        c.lines << line;
    }
    q.finish();
    std::stable_sort(pages.begin(),pages.end(),[&](const Candidate &a, const Candidate &b) {
        if ((a.id == current) != (b.id == current)) return a.id == current;
        return a.score != b.score ? a.score > b.score : a.at > b.at;
    });
    Arr notes;
    int budget = 16000;
    for (const Candidate &c : pages) {
        if (notes.size() >= limit || budget <= 0) break;
        if (c.id != current && (c.score == 0 && !words.isEmpty())) continue;
        const QString text = c.lines.join('\n').left(qMin(3500,budget));
        budget -= int(text.size());
        notes.append(Obj{{"id",c.id},{"title",c.title},{"text",text}});
    }
    static const QRegularExpression aboutTasks("tarea|pendiente|por hacer|to-?do|task");
    if (aboutTasks.match(fold(question)).hasMatch() && !open.isEmpty())
        notes.append(Obj{{"id","tareas-sin-terminar"},{"title","Tareas sin terminar en la biblioteca"},{"text",open.mid(0,80).join('\n')}});
    // With nothing found, the most recently edited pages give the assistant something to go on.
    if (notes.isEmpty()) for (const Candidate &c : pages) {
        if (notes.size() >= 3) break;
        notes.append(Obj{{"id",c.id},{"title",c.title},{"text",c.lines.join('\n').left(3000)}});
    }
    return notes;
}

// Templates: a page saved with its title, look and blocks. Comments stay with the original page.
Arr Store::templates() {
    Arr rows;
    auto q = sql("SELECT id,name,icon,page_json FROM templates ORDER BY created_at,id");
    while (q.next()) rows.append(Obj{{"id",q.value(0).toString()},{"name",q.value(1).toString()},
        {"icon",q.isNull(2) ? QJsonValue(QJsonValue::Null) : QJsonValue(q.value(2).toString())},{"page",parse(q.value(3).toByteArray())}});
    return rows;
}

void Store::saveTemplate(const QString &pageId, const QString &name) {
    if (readOnly) throw Error("read_only","Biblioteca de solo lectura.");
    const QString label = name.simplified().left(80);
    if (label.isEmpty()) invalid("Escribe un nombre para la plantilla.");
    Transaction tx(db,true);
    const Obj page = load(pageId);
    Obj copy;
    for (const auto key : {"title","icon","cover","font","small_text","full_width"}) copy[key] = page[key];
    Arr blocks;
    for (const auto &value : page["blocks"].toArray()) {
        Obj block = value.toObject();
        block.remove("id");
        Arr spans;
        for (const auto &s : block["spans"].toArray()) {
            Obj span = s.toObject();
            span.remove("comment"); span.remove("thread");
            if (span["style"].toInt() || span.contains("link") || span.contains("color") || span.contains("background")) spans.append(span);
        }
        if (spans.isEmpty()) block.remove("spans"); else block["spans"] = spans;
        blocks.append(block);
    }
    copy["blocks"] = blocks;
    sql("INSERT INTO templates(id,name,icon,page_json,created_at) VALUES(?,?,?,?,?)",
        {newId(),label,page["icon"].isString() ? QVariant(page["icon"].toString()) : QVariant(),QString::fromUtf8(json(copy)),now()});
    tx.commit();
}

void Store::removeTemplate(const QString &id) {
    if (readOnly) throw Error("read_only","Biblioteca de solo lectura.");
    sql("DELETE FROM templates WHERE id=?",{id});
}

// Active pages whose text mentions this page, with the first block that does.
Arr Store::backlinks(const QString &id) {
    Arr rows;
    QSet<QString> seen;
    auto q = sql("SELECT p.id,p.title,p.icon,b.content_json FROM blocks b JOIN pages p ON p.id=b.page_id "
                 "WHERE p.deleted_at IS NULL AND p.id<>? AND instr(b.content_json,?)>0 ORDER BY p.title_fold,p.id,b.position",
                 {id,"lunqio://page/"+id});
    while (q.next()) {
        const QString page = q.value(0).toString();
        if (seen.contains(page)) continue;
        seen.insert(page);
        rows.append(Obj{{"id",page},{"title",q.value(1).toString()},
                        {"icon",q.isNull(2) ? QJsonValue(QJsonValue::Null) : QJsonValue(q.value(2).toString())},
                        {"snippet",parse(q.value(3).toByteArray())["text"].toString().left(160)}});
    }
    return rows;
}
}
