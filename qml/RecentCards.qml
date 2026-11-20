import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// "Visitado recientemente" on Inicio: one card per page, newest first, as on Notion's Home.
ColumnLayout {
    id: recent
    property var rows: []               // pages with "at"
    property var covers: ({})
    property var describe: function(at) { return "" }
    signal chosen(string id)
    spacing: 10
    RowLayout {
        spacing: 7
        Glyph { name: "recent"; font.pixelSize: 13 }
        Label { text: "Visitado recientemente"; color: Theme.muted; font.pixelSize: 13; font.weight: Font.DemiBold }
    }
    ListView {
        id: strip
        Layout.fillWidth: true; Layout.preferredHeight: 136
        orientation: ListView.Horizontal; spacing: 12; clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: recent.rows
        ScrollBar.horizontal: ScrollBar { policy: strip.contentWidth > strip.width ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
        delegate: AbstractButton {
            id: card
            required property var modelData
            required property int index
            readonly property string cover: modelData.cover || ""
            readonly property var colors: recent.covers[cover.slice(9)] || null
            objectName: "recentCard-" + index
            width: 150; height: 128; hoverEnabled: true
            Accessible.name: "Abrir " + modelData.title
            onClicked: recent.chosen(modelData.id)
            background: Rectangle {
                radius: Theme.radiusPanel; color: card.hovered ? Theme.raised : Theme.surface
                border.color: card.visualFocus ? Theme.focus : card.hovered ? Theme.line : Theme.hover
            }
            contentItem: Item {
                // The page cover in miniature; a plain band when the page has none.
                Rectangle {
                    x: 6; y: 6; width: parent.width-12; height: 40; radius: 6
                    color: Theme.hover; visible: !card.cover.startsWith("photo:")
                    gradient: card.colors ? coverGradient : null
                    Gradient {
                        id: coverGradient
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: card.colors ? card.colors[0] : Theme.hover }
                        GradientStop { position: 1; color: card.colors ? card.colors[1] : Theme.hover }
                    }
                }
                Item {
                    x: 6; y: 6; width: parent.width-12; height: 40; clip: true
                    visible: card.cover.startsWith("photo:")
                    Image {
                        anchors.fill: parent; asynchronous: true; fillMode: Image.PreserveAspectCrop
                        source: parent.visible ? backend.photoUrl(card.cover.slice(6)) : ""
                        sourceSize.width: 300
                    }
                }
                PageIcon { x: 12; y: 30; icon: card.modelData.icon || ""; size: 22 }
                Text {
                    x: 14; y: 64; width: parent.width-28
                    text: card.modelData.title; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                }
                Text {
                    x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                    text: recent.describe(card.modelData.at); color: Theme.muted; font.pixelSize: 11
                }
            }
        }
    }
}
