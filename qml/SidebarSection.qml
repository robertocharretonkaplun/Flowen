import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Favoritos or Recientes in the sidebar: a header that folds the list, then one row per page.
// Favorites can be dragged into a new order, as in Notion.
ColumnLayout {
    id: section
    property string title
    property var rows: []               // [{id, title, icon, detail}]
    property string currentId: ""
    property bool open: true
    property bool favorites: false      // rows show a filled star that removes them
    signal chosen(string id)
    signal unfavorite(string id)
    signal moved(string id, int index)
    signal menuRequested(string id, Item anchor)
    spacing: 2

    UiButton {
        objectName: section.objectName + "Header"
        text: section.title; quiet: true; alignLeft: true; Layout.topMargin: 8
        symbol: section.open ? "down" : "right"; hint: "Mostrar u ocultar " + section.title.toLowerCase()
        onClicked: section.open = !section.open
    }
    Item {
        id: list
        visible: section.open
        Layout.fillWidth: true; implicitHeight: column.implicitHeight
        property int dragFrom: -1
        property int dropAt: -1
        readonly property int step: 34
        Column {
            id: column
            width: parent.width; spacing: 2
            Repeater {
                model: section.rows
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: column.width; height: 32; radius: 5
                    opacity: list.dragFrom === index ? 0.45 : 1
                    color: modelData.id === section.currentId ? Theme.hover : entry.hovered || star.hovered ? Theme.raised : "transparent"
                    AbstractButton {
                        id: entry
                        objectName: section.objectName + "-" + row.index
                        anchors.fill: parent; hoverEnabled: true; padding: 3; leftPadding: 11; rightPadding: section.favorites ? 32 : 8
                        Accessible.name: row.modelData.title
                        onClicked: section.chosen(row.modelData.id)
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: section.menuRequested(row.modelData.id,row) }
                        DragHandler {
                            enabled: section.favorites && section.rows.length > 1
                            target: null; xAxis.enabled: false
                            onActiveChanged: {
                                if (active) { list.dragFrom = row.index; list.dropAt = row.index; return }
                                const from = list.dragFrom, to = list.dropAt
                                list.dragFrom = -1; list.dropAt = -1
                                // Dropping on its own slot, or just below it, keeps the order.
                                if (from >= 0 && to >= 0 && to !== from && to !== from+1) section.moved(row.modelData.id,to > from ? to-1 : to)
                            }
                            onCentroidChanged: if (active) {
                                const y = entry.mapToItem(list,centroid.position.x,centroid.position.y).y
                                list.dropAt = Math.max(0,Math.min(section.rows.length,Math.round(y/list.step)))
                            }
                        }
                        background: Rectangle { color: "transparent"; radius: 4; border.width: entry.visualFocus ? 1 : 0; border.color: Theme.focus }
                        contentItem: RowLayout {
                            spacing: 9
                            PageIcon { icon: row.modelData.icon || ""; size: 15 }
                            Label {
                                text: row.modelData.title; elide: Text.ElideRight; Layout.fillWidth: true
                                color: row.modelData.id === section.currentId ? Theme.text : Theme.secondary
                            }
                            Label { visible: !!row.modelData.detail; text: row.modelData.detail || ""; color: Theme.muted; font.pixelSize: 11 }
                        }
                    }
                    UiButton {
                        id: star
                        visible: section.favorites && (entry.hovered || hovered)
                        anchors.right: parent.right; anchors.rightMargin: 3; anchors.verticalCenter: parent.verticalCenter
                        width: 26; height: 26; quiet: true
                        symbol: "starFilled"; symbolColor: Theme.favorite; hint: "Quitar de favoritos"
                        onClicked: section.unfavorite(row.modelData.id)
                    }
                }
            }
        }
        Rectangle {
            visible: list.dragFrom >= 0
            x: 6; width: parent.width-12; height: 2; radius: 1; color: Theme.accent
            y: Math.max(0,list.dropAt*list.step-2)
        }
    }
}
