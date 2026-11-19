import QtQuick

// A page's emoji when it has one, else the generic glyph.
Item {
    property string icon: ""
    property string glyph: "page"
    property int size: 15
    implicitWidth: size+6; implicitHeight: size+6
    Glyph { anchors.centerIn: parent; visible: !parent.icon; name: parent.glyph; font.pixelSize: parent.size }
    Text {
        anchors.centerIn: parent; visible: !!parent.icon; text: parent.icon
        font.family: "Segoe UI Emoji"; font.pixelSize: parent.size; renderType: Text.NativeRendering
    }
}
