import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The page cover: a gradient or a photo across the top, changed or removed on hover.
Item {
    id: cover
    required property var page          // the window: pageCover, covers, setPageCover(), deleted
    signal uploadRequested()
    readonly property string value: page.pageCover
    readonly property bool photo: value.indexOf("photo:") === 0
    readonly property var colors: page.covers[value.slice(9)] || [Theme.hover,Theme.raised]
    visible: !!value
    clip: true
    Rectangle {
        anchors.fill: parent; visible: !cover.photo
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: cover.colors[0] }
            GradientStop { position: 1; color: cover.colors[1] }
        }
    }
    Image {
        anchors.fill: parent; visible: cover.photo; asynchronous: true
        source: cover.photo ? backend.photoUrl(cover.value.slice(6)) : ""
        fillMode: Image.PreserveAspectCrop
    }
    HoverHandler { id: hover }
    Row {
        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 12
        spacing: 6
        opacity: !cover.page.deleted && (hover.hovered || choices.opened) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        UiButton { id: change; objectName: "changeCover"; text: "Cambiar portada"; onClicked: choices.open() }
        UiButton { text: "Quitar"; onClicked: cover.page.setPageCover("") }
    }
    Popup {
        id: choices
        parent: change; x: change.width-width; y: change.height+6
        width: 360; padding: 12
        background: Rectangle { radius: Theme.radiusPanel; color: Theme.surface; border.color: Theme.line }
        contentItem: ColumnLayout {
            spacing: 10
            Label { text: "Degradados"; color: Theme.muted; font.pixelSize: 12 }
            Grid {
                columns: 4; spacing: 8
                Repeater {
                    model: Object.keys(cover.page.covers)
                    delegate: AbstractButton {
                        id: swatch
                        required property string modelData
                        width: 78; height: 46; hoverEnabled: true; focusPolicy: Qt.NoFocus
                        Accessible.name: "Portada " + modelData
                        onClicked: { choices.close(); cover.page.setPageCover("gradient:" + modelData) }
                        background: Rectangle {
                            radius: Theme.radiusButton; border.width: cover.value === "gradient:" + swatch.modelData ? 2 : 0; border.color: Theme.accent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: cover.page.covers[swatch.modelData][0] }
                                GradientStop { position: 1; color: cover.page.covers[swatch.modelData][1] }
                            }
                        }
                        contentItem: Item {}
                    }
                }
            }
            UiButton { text: "Subir una foto…"; symbol: "photo"; Layout.fillWidth: true; onClicked: { choices.close(); cover.uploadRequested() } }
        }
    }
}
