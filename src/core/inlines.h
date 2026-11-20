#pragma once
#include <QJsonArray>
#include <QJsonObject>

namespace notes {
/// Styles of a span of text (`spans[].style`), combined as bits.
enum InlineStyle { Bold=1, Italic=2, Underline=4, Strike=8, Code=16, Highlight=32, Superscript=64 };
/// An http(s) address a span may link to.
bool webLink(const QString &url);
/// A link to another page of the library (lunqio://page/ID).
bool pageLink(const QString &url);
/// Checks that spans fit the text and use known styles, links and colours.
void validateSpans(const QString &text,const QJsonArray &spans);
/// Moves spans after `removed` characters at `start` were replaced by `added` ones.
QJsonArray replaceSpans(const QJsonArray &spans,int start,int removed,int added);
/// The block's text with its spans as HTML, for exports.
QString inlineHtml(const QJsonObject &block);
/// The printed colour of a palette name (gray, brown… red) for text or for a background.
QString paletteTone(const QString &name, bool background);
}
