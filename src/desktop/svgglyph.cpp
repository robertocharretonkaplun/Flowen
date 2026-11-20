#include "svgglyph.h"
#include <QFile>
#include <QHash>
#include <QImageReader>
#include <QPainter>
#include <QPainterPath>
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
// Registers Flowen's painted items: the symbols and the photos.
void SvgGlyph::registerType() {
    qmlRegisterType<SvgGlyph>("Flowen",1,0,"SvgGlyph");
    qmlRegisterType<PhotoView>("Flowen",1,0,"PhotoView");
}
PhotoView::PhotoView(QQuickItem *parent) : QQuickPaintedItem(parent) {
    setAntialiasing(true);
    setFlag(ItemHasContents,true);
}
void PhotoView::setSource(const QUrl &value) {
    if (value == url) return;
    url = value;
    picture = {};
    state = 0;
    if (!url.isEmpty()) {
        // Photos are local files of the library's cache; a 1440 px copy is plenty for the page.
        QImageReader reader(url.toLocalFile());
        reader.setAutoTransform(true);
        const QSize size = reader.size();
        if (size.width() > 1440) reader.setScaledSize(QSize(1440,qMax(1,size.height()*1440/size.width())));
        picture = reader.read();
        state = picture.isNull() ? 3 : 1;
    }
    setImplicitSize(picture.isNull() ? 0 : picture.width(),picture.isNull() ? 0 : picture.height());
    emit sourceChanged();
    update();
}
void PhotoView::setRadius(qreal value) {
    if (qFuzzyCompare(value+1,corner+1)) return;
    corner = value;
    emit radiusChanged();
    update();
}
void PhotoView::paint(QPainter *painter) {
    if (picture.isNull() || width() <= 0 || height() <= 0) return;
    painter->setRenderHints(QPainter::Antialiasing | QPainter::SmoothPixmapTransform);
    const QRectF area(0,0,width(),height());
    if (corner > 0) {
        QPainterPath shape;
        shape.addRoundedRect(area,corner,corner);
        painter->setClipPath(shape);
    }
    painter->drawImage(area,picture);
}
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
