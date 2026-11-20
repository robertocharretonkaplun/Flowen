import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// A small emoji picker for page icons and callouts.
Popup {
    id: picker
    property var done: null
    property bool removable: false
    readonly property var emojis: [
        "💡","📌","📝","📚","📖","✅","⚠️","❗","❓","💬","🔥","⭐",
        "🎮","🕹️","👾","🎲","🎯","🏆","🎨","🎬","🎵","📷","🎧","🧩",
        "🚀","💻","🛠️","⚙️","🔧","🧪","📈","📊","🗂️","📁","🗓️","⏰",
        "🌱","🌍","☀️","🌙","⚡","🌈","🍀","🍎","☕","🍕","🐱","🐶",
        "❤️","😀","😎","🤔","🙌","👍","👀","🧠","✨","🎉","🔒","🔑"]
    function pick(anchor, callback, canRemove) {
        done = callback; removable = !!canRemove
        parent = anchor
        x = 0; y = anchor.height+6
        open()
    }
    width: 336; padding: 10
    background: Rectangle { radius: Theme.radiusPanel; color: Theme.surface; border.color: Theme.line }
    contentItem: ColumnLayout {
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            Label { text: "Elige un icono"; color: Theme.muted; font.pixelSize: 12; Layout.fillWidth: true }
            UiButton {
                visible: picker.removable; text: "Quitar"; quiet: true
                onClicked: { const callback = picker.done; picker.close(); if (callback) callback("") }
            }
        }
        Grid {
            columns: 8; spacing: 2
            Repeater {
                model: picker.emojis
                delegate: AbstractButton {
                    required property string modelData
                    width: 38; height: 38; hoverEnabled: true; focusPolicy: Qt.NoFocus
                    Accessible.name: modelData
                    onClicked: { const callback = picker.done; picker.close(); if (callback) callback(modelData) }
                    background: Rectangle { radius: Theme.radiusButton; color: parent.hovered ? Theme.hover : "transparent" }
                    contentItem: Text {
                        text: parent.modelData; font.family: "Segoe UI Emoji"; font.pixelSize: 22
                        renderType: Text.NativeRendering; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
