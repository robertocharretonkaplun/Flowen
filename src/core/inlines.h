#pragma once
#include <QJsonArray>
#include <QJsonObject>

namespace notes {
enum InlineStyle { Bold=1, Italic=2, Underline=4, Strike=8, Code=16, Highlight=32, Superscript=64 };
bool webLink(const QString &url);
bool pageLink(const QString &url);
void validateSpans(const QString &text,const QJsonArray &spans);
QJsonArray replaceSpans(const QJsonArray &spans,int start,int removed,int added);
QString inlineHtml(const QJsonObject &block);
QString paletteTone(const QString &name, bool background);
}
