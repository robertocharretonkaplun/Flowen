#include "inlines.h"
#include "contract.h"
#include <QRegularExpression>
#include <QUrl>

namespace notes {
// A mention of another page of the library.
bool pageLink(const QString &url) {
    static const QRegularExpression page("^lunqio://page/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$");
    return page.match(url).hasMatch();
}
bool webLink(const QString &url) {
    QUrl parsed(url,QUrl::StrictMode);
    return parsed.isValid() && !parsed.host().isEmpty() && (parsed.scheme()=="http" || parsed.scheme()=="https");
}
void validateSpans(const QString &text,const QJsonArray &spans) {
    int previous = 0;
    for (const auto &value : spans) {
        const auto span = value.toObject();
        int start = span["start"].toInt(), end = span["end"].toInt();
        if (start < previous || end <= start || end > text.size() || text[start].isLowSurrogate() ||
            (end < text.size() && text[end].isLowSurrogate()) ||
            (span.contains("link") && !webLink(span["link"].toString()) && !pageLink(span["link"].toString())) ||
            (span.contains("thread") && !span.contains("comment")))
            throw Error("invalid_argument","El formato de la selección contiene un intervalo o enlace inválido.");
        previous = end;
    }
}
QJsonArray replaceSpans(const QJsonArray &spans,int start,int removed,int added) {
    QJsonArray result;
    const int cut = start+removed, shift = added-removed;
    for (auto value : spans) {
        auto s = value.toObject();
        int a = s["start"].toInt(), b = s["end"].toInt();
        if (a >= cut) { a += shift; b += shift; }
        else if (b > start) {
            const bool inherits = a <= start;
            a = inherits ? a : start+added;
            b = b >= cut ? b+shift : (inherits ? start+added : start);
        }
        if (a < b) { s["start"] = a; s["end"] = b; result.append(s); }
    }
    return result;
}
QString inlineHtml(const QJsonObject &block) {
    const QString text = block["text"].toString();
    auto escaped = [](QString s){ return s.toHtmlEscaped().replace("\n","<br>"); };
    QString html;
    int pos = 0;
    for (const auto &v : block["spans"].toArray()) {
        auto s = v.toObject();
        int a = s["start"].toInt(), b = s["end"].toInt(), flags = s["style"].toInt();
        html += escaped(text.mid(pos,a-pos));
        QString part = escaped(text.mid(a,b-a));
        auto tag = [&](int flag,const QString &name) { if (flags & flag) part="<"+name+">"+part+"</"+name+">"; };
        tag(Bold,"strong"); tag(Italic,"em"); tag(Underline,"u"); tag(Strike,"s"); tag(Code,"code"); tag(Superscript,"sup");
        if (flags & Highlight) part="<span style=\"background-color:#f3df9f;color:#202020\">"+part+"</span>";
        if (webLink(s["link"].toString())) part="<a href=\""+s["link"].toString().toHtmlEscaped()+"\">"+part+"</a>";
        if (s.contains("comment")) {
            const QString author = s["thread"].toObject()["author"].toString();
            const QString note = author.isEmpty() ? s["comment"].toString() : author+": "+s["comment"].toString();
            part="<span title=\""+note.toHtmlEscaped()+"\">"+part+"</span>";
        }
        html += part; pos = b;
    }
    return html+escaped(text.mid(pos));
}
}
