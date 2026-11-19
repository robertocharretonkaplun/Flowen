import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Which assistant writes for "Editar con IA" and "Crear con IA": Claude or Codex.
Rectangle {
    id: control
    required property var assistant
    readonly property bool locked: assistant.phase === "generating" || assistant.phase === "applying"
    implicitWidth: options.implicitWidth+4; implicitHeight: 28; radius: 7
    color: "#1c1c1e"; border.color: "#3a3a3d"
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
                background: Rectangle { radius: 5; color: option.current ? "#35373c" : option.hovered ? "#29292c" : "transparent" }
                contentItem: Text {
                    id: label; text: option.modelData.label; font.pixelSize: 12
                    font.weight: option.current ? Font.DemiBold : Font.Normal
                    color: option.current ? "#eef0f3" : "#a9a6ae"; opacity: option.enabled ? 1 : 0.5
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
