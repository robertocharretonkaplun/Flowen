#include "contract.h"
#include <QUuid>
#include <QRegularExpression>
#include <cmath>

namespace notes {
using Obj = QJsonObject;
using Arr = QJsonArray;
QString newId() { return QUuid::createUuid().toString(QUuid::WithoutBraces); }
static Obj string(int max, int min = 0) {
    return {{"type","string"},{"maxLength",max},{"minLength",min}};
}
static Obj number(int min, int max) {
    return {{"type","integer"},{"minimum",min},{"maximum",max}};
}
static Obj object(Obj properties, Arr required = {}) {
    return {{"type","object"},{"properties",properties},{"required",required},{"additionalProperties",false}};
}
static Obj array(Obj items, int max, int min = 0) {
    return {{"type","array"},{"items",items},{"maxItems",max},{"minItems",min}};
}
static const Obj &catalog() {
    static const Obj result = [] {
        Obj id = string(36,36);
        id["pattern"] = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$";
        Obj parent{{"anyOf",Arr{id,Obj{{"type","null"}}}}};
        Obj type{{"enum",Arr{"heading","paragraph","list","numbered","task","quote","callout","code","toggle","divider"}}};
        Obj flag{{"type","boolean"}};
        // A comment is `comment` (its first message) plus an optional thread with author, time, state and replies.
        Obj message = object({{"author",string(80)},{"at",string(40)},{"text",string(1024,1)}},{"author","at","text"});
        Obj thread = object({{"id",string(64,1)},{"author",string(80)},{"at",string(40)},{"resolved",Obj{{"type","boolean"}}},
            {"replies",array(message,50)}},{"id"});
        Obj span = object({{"start",number(0,16384)},{"end",number(1,16384)},{"style",number(0,127)},
            {"link",string(2048,1)},{"comment",string(1024,1)},{"thread",thread}},{"start","end","style"});
        // level: heading size 1-3. indent: nesting under the block above (toggles hide what they contain).
        // icon: a callout's emoji. collapsed: whether a toggle is closed.
        Obj textBlock = object({{"type",type},{"text",string(8192)},{"spans",array(span,8192)},{"checked",flag},
            {"level",number(1,3)},{"indent",number(0,6)},{"icon",string(16,1)},{"collapsed",flag}},{"type","text"});
        Obj asset = string(64,64);
        asset["pattern"] = "^[a-f0-9]{64}$";
        Obj photo = object({{"type",Obj{{"enum",Arr{"image"}}}},{"asset",asset},{"text",string(8192)},
            {"width_percent",number(10,100)},{"indent",number(0,6)}},{"type","asset","text","width_percent"});
        // Page look: an emoji icon and a cover ("gradient:<name>" or "photo:<asset>"); null removes them.
        Obj icon{{"anyOf",Arr{string(16,1),Obj{{"type","null"}}}}};
        Obj coverText = string(80,1);
        coverText["pattern"] = "^(gradient:[a-z]{2,20}|photo:[a-f0-9]{64})$";
        Obj cover{{"anyOf",Arr{coverText,Obj{{"type","null"}}}}};
        Obj block{{"anyOf",Arr{textBlock,photo}}};
        Obj offset = number(0,2147483646), rev = number(1,2147483647);
        Obj paging{{"cursor",offset},{"limit",number(1,50)}};
        Obj write{{"id",id},{"expected_revision",rev},{"operation_key",string(128,1)}};
        Obj list = paging, search = paging, get = paging;
        list["parent_id"] = parent;
        list["trashed"] = Obj{{"type","boolean"}};
        search["query"] = string(240,1);
        get["id"] = id;
        Obj update = write, changes = write;
        update["title"] = string(240,1);
        update["parent_id"] = parent;
        update["icon"] = icon;
        update["cover"] = cover;
        Obj index = number(0,511);
        auto operation = [&](QString kind, Obj fields, Arr required) {
            fields["op"] = Obj{{"enum",Arr{kind}}};
            required.append("op");
            return object(fields,required);
        };
        Obj op{{"anyOf",Arr{
            operation("insert",{{"index",index},{"block",block}},{"block"}),
            operation("update",{{"block_id",id},{"block",block}},{"block_id","block"}),
            operation("replace_text",{{"block_id",id},{"start",number(0,16384)},{"original",string(8192,1)},{"replacement",string(8192)}},{"block_id","start","original","replacement"}),
            operation("remove",{{"block_id",id}},{"block_id"}),
            operation("move",{{"block_id",id},{"index",index}},{"block_id","index"})}}};
        changes["changes"] = array(op,128,1);
        Obj specs;
        auto add = [&](QString name, QString description, Obj schema, bool read, bool destructive = false) {
            specs[name] = Obj{{"name",name},{"description",description},{"inputSchema",schema},
                {"annotations",Obj{{"readOnlyHint",read},{"destructiveHint",destructive},{"openWorldHint",false}}}};
        };
        add("list_pages","List immediate children (root by default). trashed=true lists trash roots.",object(list),true);
        add("search_notes","Search active titles and text. Results include a short matching excerpt.",object(search,{"query"}),true);
        add("get_page","Read page metadata and a slice of ordered blocks.",object(get,{"id"}),true);
        add("create_page","Create a page. Omit parent_id for root. Reuse operation_key on retries. Blocks: heading (level 1-3), "
            "paragraph, list, numbered, task (checked), quote, callout (icon emoji), code, toggle (collapsed), divider; indent nests a block under the one above.",
            object({{"title",string(240,1)},{"parent_id",parent},{"icon",icon},{"cover",cover},{"blocks",array(block,128)},
                    {"operation_key",string(128,1)}},{"title"}),false);
        Arr expected{"id","expected_revision"};
        add("update_page","Rename, move or restyle a page. Set parent_id to null to move to root; icon is an emoji, cover is "
            "gradient:<name> or photo:<asset>, null removes either.",object(update,expected),false,true);
        add("apply_block_changes","Apply ordered changes atomically. Indices start at zero. Insert appends by default. Update replaces a block while retaining its ID.",
            object(changes,{"id","expected_revision","changes"}),false,true);
        add("trash_page","Move a page and its active descendants to trash.",object(write,expected),false,true);
        add("restore_page","Restore a trashed page and descendants from the same deletion.",object(write,expected),false);
        return specs;
    }();
    return result;
}
bool isReadTool(const QString &name) {
    return catalog()[name].toObject()["annotations"].toObject()["readOnlyHint"].toBool();
}
QJsonArray tools(bool readOnly) {
    Arr result;
    for (auto it = catalog().begin(); it != catalog().end(); ++it)
        if (!readOnly || isReadTool(it.key())) result.append(it.value());
    return result;
}
static bool valid(const QJsonValue &value, const Obj &s) {
    if (s.contains("anyOf")) {
        for (const auto &choice : s["anyOf"].toArray()) if (valid(value,choice.toObject())) return true;
        return false;
    }
    if (s.contains("enum")) return s["enum"].toArray().contains(value);
    auto t = s["type"].toString();
    if (t == "boolean") return value.isBool();
    if (t == "null") return value.isNull();
    if (t == "integer") {
        double n = value.toDouble();
        return value.isDouble() && n == std::floor(n) && n >= s["minimum"].toInt() && n <= s["maximum"].toInt();
    }
    if (t == "string") {
        QString v = value.toString();
        auto length = v.toUcs4().size();
        return value.isString() && !v.contains(QChar::Null) && length >= s["minLength"].toInt() &&
            length <= s["maxLength"].toInt() && (!s.contains("pattern") || QRegularExpression(s["pattern"].toString()).match(v).hasMatch());
    }
    if (t == "array") {
        auto a = value.toArray();
        if (!value.isArray() || a.size() > s["maxItems"].toInt() || a.size() < s["minItems"].toInt()) return false;
        for (const auto &v : a) if (!valid(v,s["items"].toObject())) return false;
        return true;
    }
    auto props = s["properties"].toObject(), obj = value.toObject();
    if (!value.isObject()) return false;
    for (const auto &key : s["required"].toArray()) if (!obj.contains(key.toString())) return false;
    for (auto it = obj.begin(); it != obj.end(); ++it)
        if (!props.contains(it.key()) || !valid(it.value(),props[it.key()].toObject())) return false;
    return true;
}
void validateCall(const QString &name, const Obj &args) {
    if (!catalog().contains(name)) throw Error("unknown_tool","Herramienta desconocida.");
    if (!valid(args,catalog()[name].toObject()["inputSchema"].toObject()))
        throw Error("invalid_argument","Los argumentos no cumplen el esquema de la herramienta.");
}
}
