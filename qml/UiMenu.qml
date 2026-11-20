import QtQuick
import QtQuick.Controls.Basic

// Flowen's menu: a rounded panel on the theme's surface with a soft shadow, a short fade, and rows
// drawn by UiMenuItem (also for submenus and actions). `glyph` is the symbol its entry shows in a
// parent menu.
Menu {
    id: menu
    property string glyph: ""
    // Wider for rows with a detail at the right (paper sizes, margins).
    property int minWidth: 236
    padding: 5
    topPadding: 6; bottomPadding: 6
    delegate: UiMenuItem {}
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 90; easing.type: Easing.OutCubic } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 70 } }
    background: Rectangle {
        implicitWidth: menu.minWidth
        radius: Theme.radiusPanel; color: Theme.surface; border.color: Theme.line
        Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 3; anchors.bottomMargin: -7; radius: Theme.radiusPanel+2; color: Theme.shadow }
    }
}
