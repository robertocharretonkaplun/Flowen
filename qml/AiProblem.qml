import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The assistant's last error with the one action that usually fixes it.
ColumnLayout {
    id: notice
    required property var assistant
    property string mode: "edit"
    signal openConnectors()
    signal retry()
    readonly property bool claude: assistant.engine === "claude"
    readonly property string other: claude ? "Codex" : "Claude"
    visible: assistant.phase === "error" && assistant.mode === mode
    spacing: 8
    Label { text: notice.assistant.error; color: Theme.danger; wrapMode: Text.Wrap; font.pixelSize: 13; Layout.fillWidth: true }
    Flow {
        Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height; spacing: 8
        UiButton {
            objectName: "signInClaude"; visible: notice.assistant.problem === "signin" && notice.claude
            text: "Iniciar sesión en Claude"; primary: true; onClicked: notice.assistant.signInClaude()
        }
        UiButton {
            visible: notice.assistant.problem === "signin" && notice.claude
            text: "Ya inicié sesión"; onClicked: { notice.assistant.checkClaude(); notice.retry() }
        }
        UiButton {
            objectName: "switchEngine"; visible: notice.assistant.problem === "limit"
            text: "Usar " + notice.other; primary: true
            onClicked: { notice.assistant.engine = notice.claude ? "codex" : "claude"; notice.retry() }
        }
        UiButton {
            visible: notice.assistant.problem === "setup" || (notice.assistant.problem === "signin" && !notice.claude)
            text: "Abrir conectores"; onClicked: notice.openConnectors()
        }
    }
}
