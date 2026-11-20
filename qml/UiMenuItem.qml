import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// A row of a Flowen menu: symbol, label, shortcut (or a check), and an arrow for submenus.
// Labels written "Deshacer    Ctrl+Z" show the part after the four spaces as the shortcut.
// Hidden rows take no room, so menus can change with what was clicked.
MenuItem {
    id: item
    property string glyph: subMenu && subMenu.glyph !== undefined ? subMenu.glyph : ""
    property string keys: ""
    property bool danger: false
    // A check for one choice among several (paper, view) without making the row checkable.
    property bool marked: false
    readonly property var parts: text.split("    ")
    readonly property string label: parts[0].replace("&","")
    readonly property string hint: keys || (parts.length > 1 ? parts[parts.length-1].trim() : action && typeof action.shortcut === "string" ? action.shortcut : "")
    implicitWidth: Math.max(236,row.implicitWidth+leftPadding+rightPadding)
    implicitHeight: visible ? 34 : 0
    height: visible ? implicitHeight : 0
    leftPadding: 12; rightPadding: 12
    indicator: Item {}
    arrow: Item {}
    contentItem: RowLayout {
        id: row
        spacing: 10
        opacity: item.enabled ? 1 : 0.42
        Item {
            implicitWidth: 18; implicitHeight: 18
            Glyph {
                anchors.centerIn: parent; visible: !!item.glyph; name: item.glyph; font.pixelSize: 14
                color: item.danger ? Theme.danger : Theme.glyph
            }
        }
        Text {
            text: item.label; Layout.fillWidth: true; elide: Text.ElideRight
            color: item.danger ? Theme.danger : Theme.text; font.pixelSize: 14; font.family: Theme.family
        }
        Text { visible: !!item.hint && !item.subMenu; text: item.hint; color: Theme.muted; font.pixelSize: 12; font.family: Theme.family }
        Glyph { visible: (item.checkable && item.checked) || item.marked; name: "check"; font.pixelSize: 12; color: Theme.accent }
        Glyph { visible: !!item.subMenu; name: "right"; font.pixelSize: 11; color: Theme.muted }
    }
    background: Rectangle {
        x: 2; width: parent.width-4; radius: 6
        color: item.highlighted && item.enabled ? (item.danger ? Theme.dangerSoft : Theme.hover) : "transparent"
    }
}
