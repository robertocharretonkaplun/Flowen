import QtQuick
import Flowen

// A symbol from Flowen's icon set (design/identidad/iconografia): a 24-unit drawing with a 1.8 stroke.
// In the default ink the outline is ivory and the detail coral, as the identity shows; any other
// color (a state, a muted control, text on the accent) draws the whole symbol in that color.
Item {
    id: glyph
    required property string name
    property color color: Theme.glyph
    property color accent: Qt.colorEqual(color,Theme.glyph) ? Theme.glyphAccent : color
    // Kept from the font-based glyphs: font.pixelSize sets the size.
    property font font: Qt.font({family: Theme.family, pixelSize: 15})
    readonly property int box: Math.round(font.pixelSize*1.2)
    implicitWidth: box; implicitHeight: box
    Accessible.ignored: true
    SvgGlyph {
        anchors.centerIn: parent
        width: glyph.box; height: glyph.box
        name: glyph.name; color: glyph.color; accent: glyph.accent
    }
}
