#include "svgglyph.h"
#include <QFile>
#include <QHash>
#include <QPainter>
#include <QSvgRenderer>
#include <QtQml>
#include <memory>

namespace {
QByteArray source(const QString &name) {
    static QHash<QString,QByteArray> files;
    auto found = files.find(name);
    if (found == files.end()) {
        QFile file(":/glyphs/"+name+".svg");
        found = files.insert(name,file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray());
    }
    return found.value();
}
QByteArray hex(const QColor &c) { return c.name(QColor::HexRgb).toUtf8(); }
// Renderers are shared by every symbol drawn with the same name and inks.
QSvgRenderer *renderer(const QString &name, const QColor &ink, const QColor &detail) {
    static QHash<QString,std::shared_ptr<QSvgRenderer>> cache;
    const QString key = name+'/'+ink.name(QColor::HexArgb)+'/'+detail.name(QColor::HexArgb);
    auto found = cache.find(key);
    if (found != cache.end()) return found->get();
    QByteArray svg = source(name);
    if (svg.isEmpty()) return nullptr;
    svg.replace("#2C1312",hex(ink)).replace("#C83918",hex(detail));
    // Ink with transparency (a disabled or faded symbol) applies to the whole drawing.
    auto r = std::make_shared<QSvgRenderer>(svg);
    if (!r->isValid()) return nullptr;
    if (cache.size() > 600) cache.clear();
    return cache.insert(key,r)->get();
}
}

SvgGlyph::SvgGlyph(QQuickItem *parent) : QQuickPaintedItem(parent) {
    setAntialiasing(true);
    setMipmap(true);
    setFlag(ItemHasContents,true);
    connect(this,&SvgGlyph::changed,this,[this] { update(); });
}
void SvgGlyph::registerType() { qmlRegisterType<SvgGlyph>("Lunqio",1,0,"SvgGlyph"); }
bool SvgGlyph::available() const { return !glyph.isEmpty() && !source(glyph).isEmpty(); }
void SvgGlyph::setName(const QString &value) { if (value != glyph) { glyph = value; emit changed(); } }
void SvgGlyph::setColor(const QColor &value) { if (value != ink) { ink = value; emit changed(); } }
void SvgGlyph::setAccent(const QColor &value) { if (value != detail) { detail = value; emit changed(); } }
void SvgGlyph::paint(QPainter *painter) {
    if (glyph.isEmpty() || width() <= 0 || height() <= 0) return;
    QColor solidInk = ink, solidDetail = detail;
    const qreal alpha = ink.alphaF();
    solidInk.setAlphaF(1);
    solidDetail.setAlphaF(1);
    auto *r = renderer(glyph,solidInk,solidDetail);
    if (!r) return;
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setOpacity(alpha);
    const qreal side = qMin(width(),height());
    r->render(painter,QRectF((width()-side)/2,(height()-side)/2,side,side));
}
