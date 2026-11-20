import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Which assistant writes for "Editar con IA" and "Crear con IA": Claude or Codex.
Rectangle {
    id: control
    required property var assistant
    readonly property bool locked: assistant.phase === "generating" || assistant.phase === "applying"
    implicitWidth: options.implicitWidth+4; implicitHeight: 28; radius: 7
    color: Theme.base; border.color: Theme.pressed
    Accessible.role: Accessible.PageTabList
    Accessible.name: "Asistente de IA"
    RowLayout {
        id: options
        anchors.centerIn: parent; spacing: 2
        Repeater {
            model: [{key: "claude", label: "Claude"},{key: "codex", label: "Codex"}]
            delegate: AbstractButton {
                id: option
                required property var modelData
                readonly property bool current: control.assistant.engine === modelData.key
                objectName: "engine-" + modelData.key
                implicitWidth: label.implicitWidth+22; implicitHeight: 24
                enabled: !control.locked; focusPolicy: Qt.NoFocus; hoverEnabled: true
                Accessible.name: "Usar " + modelData.label
                Accessible.checkable: true
                Accessible.checked: current
                onClicked: control.assistant.engine = modelData.key
                background: Rectangle { radius: 5; color: option.current ? Theme.pressed : option.hovered ? Theme.raised : "transparent" }
                contentItem: Text {
                    id: label; text: option.modelData.label; font.pixelSize: 12
                    font.weight: option.current ? Font.DemiBold : Font.Normal
                    color: option.current ? Theme.text : Theme.muted; opacity: option.enabled ? 1 : 0.5
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
