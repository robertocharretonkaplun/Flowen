import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The page's outline at its right edge, as in Notion: a short line per heading (longer for bigger
// ones). Hovering opens the list of headings; a click takes you there.
Item {
    id: outline
    property var headings: []                   // [{index, level, text}]
    signal chosen(int index)
    readonly property bool open: hover.hovered
    width: open ? 248 : 30
    height: list.implicitHeight+16
    Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    HoverHandler { id: hover }
    Rectangle {
        anchors.fill: parent; radius: Theme.radiusPanel
        color: outline.open ? Theme.surface : "transparent"; border.color: outline.open ? Theme.line : "transparent"
        Rectangle { visible: outline.open; z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 3; anchors.bottomMargin: -7; radius: Theme.radiusPanel+2; color: Theme.shadow }
    }
    Column {
        id: list
        x: 8; y: 8; width: parent.width-16; spacing: outline.open ? 2 : 7
        Repeater {
            model: outline.headings
            delegate: Item {
                id: entry
                required property var modelData
                width: list.width; height: outline.open ? 26 : 3
                Rectangle {
                    visible: !outline.open; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: [0,14,10,7][entry.modelData.level] || 7; height: 2; radius: 1; color: Theme.faint
                }
                AbstractButton {
                    objectName: "outline-" + entry.modelData.index
                    visible: outline.open; anchors.fill: parent; hoverEnabled: true; focusPolicy: Qt.NoFocus
                    leftPadding: 8+(entry.modelData.level-1)*12; rightPadding: 8
                    Accessible.name: "Ir a " + entry.modelData.text
                    onClicked: outline.chosen(entry.modelData.index)
                    background: Rectangle { radius: 6; color: parent.hovered ? Theme.hover : "transparent" }
                    contentItem: Text {
                        text: entry.modelData.text; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                        color: entry.modelData.level === 1 ? Theme.text : Theme.secondary; font.pixelSize: 13
                        font.weight: entry.modelData.level === 1 ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }
    }
}
