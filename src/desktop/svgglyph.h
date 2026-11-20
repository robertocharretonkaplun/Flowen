#pragma once
#include <QColor>
#include <QImage>
#include <QQuickPaintedItem>
#include <QUrl>

// One symbol of Lunqio's icon set (assets/glyphs, from design/identidad). The SVGs are drawn in two
// inks: the outline (#2C1312 in the files) takes `color` and the detail (#C83918) takes `accent`.
class SvgGlyph : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY changed)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY changed)
    Q_PROPERTY(QColor accent READ accent WRITE setAccent NOTIFY changed)
    Q_PROPERTY(bool available READ available NOTIFY changed)
public:
    explicit SvgGlyph(QQuickItem *parent = nullptr);
    static void registerType();
    QString name() const { return glyph; }
    QColor color() const { return ink; }
    QColor accent() const { return detail; }
    bool available() const;
    void setName(const QString &value);
    void setColor(const QColor &value);
    void setAccent(const QColor &value);
    void paint(QPainter *painter) override;
signals:
    void changed();
private:
    QString glyph;
    QColor ink{"#FBF1E0"}, detail{"#FF7959"};
};

// A photo of the page, drawn smoothly and clipped to rounded corners (radius 0 keeps them square).
// status follows Image: 1 shown, 3 unreadable, 0 without a source.
class PhotoView : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(qreal radius READ radius WRITE setRadius NOTIFY radiusChanged)
    Q_PROPERTY(int status READ status NOTIFY sourceChanged)
public:
    explicit PhotoView(QQuickItem *parent = nullptr);
    QUrl source() const { return url; }
    void setSource(const QUrl &value);
    qreal radius() const { return corner; }
    void setRadius(qreal value);
    int status() const { return state; }
    void paint(QPainter *painter) override;
signals:
    void sourceChanged();
    void radiusChanged();
private:
    QUrl url;
    QImage picture;
    qreal corner = 0;
    int state = 0;
};
