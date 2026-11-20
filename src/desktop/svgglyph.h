#pragma once
#include <QColor>
#include <QQuickPaintedItem>

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
