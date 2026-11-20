import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Dialog {
    id: dialog
    required property var assistant
    property var selection: ({})
    property bool busy: assistant.phase === "generating" || assistant.phase === "applying"
    property bool suspended: false
    readonly property bool ready: assistant.engineReady && assistant.link.state === "connected"
    readonly property string proposal: assistant.mode === "edit" ? assistant.proposal : ""
    signal settingsRequested()
    title: "Editar con IA"; modal: true; anchors.centerIn: parent
    width: Math.min(560,parent.width-40)
    height: Math.min(560,parent.height-42)
    padding: 18
    background: Rectangle { color: Theme.surface; radius: Theme.radiusPanel; border.color: Theme.line }
    header: RowLayout {
        spacing: 10
        Glyph { name: "sparkles"; font.pixelSize: 17; Layout.leftMargin: 18; Layout.topMargin: 18 }
        Label {
            text: "Editar con IA"; Layout.topMargin: 18
            font.pixelSize: 19; font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true
        }
        EngineSwitch { assistant: dialog.assistant; Layout.rightMargin: 18; Layout.topMargin: 18 }
    }
    closePolicy: assistant.phase === "applying" ? Popup.NoAutoClose : Popup.CloseOnEscape
    // A preset instruction (from the selection menu) starts generating right away when the assistant is ready.
    function begin(value, preset) {
        assistant.cancel(); selection = value; instruction.text = preset || "Mejora la redacción conservando el significado."
        open(); Qt.callLater(function(){ instruction.forceActiveFocus(); instruction.selectAll() })
        if (assistant.engine === "claude" && assistant.claudeAccount !== "in") assistant.checkClaude()
        if (preset && ready) assistant.generate(selection,preset)
    }
    onClosed: if (!suspended) assistant.cancel()
    contentItem: ColumnLayout {
        spacing: 9
        Label { text: "Texto seleccionado"; color: Theme.muted; font.pixelSize: 12 }
        ScrollView {
            Layout.fillWidth: true; Layout.preferredHeight: 74; clip: true; contentWidth: availableWidth
            TextArea {
                readOnly: true; selectByMouse: true; textFormat: TextEdit.PlainText; wrapMode: TextEdit.Wrap
                text: dialog.selection.original || ""; color: Theme.textSoft; font.pixelSize: 15
                background: Rectangle { color: Theme.base; radius: 5 }
            }
        }
        Label { text: "Instrucción para " + dialog.assistant.engineName; font.pixelSize: 13 }
        TextField {
            id: instruction; maximumLength: 640; Layout.fillWidth: true; enabled: !dialog.busy
            placeholderText: "¿Qué quieres cambiar?"; Accessible.name: "Instrucción para " + dialog.assistant.engineName
            onAccepted: if (text.trim() && !dialog.busy && dialog.ready) dialog.assistant.generate(dialog.selection,text)
        }
        RowLayout {
            UiButton { text: "Mejorar redacción"; enabled: !dialog.busy; onClicked: instruction.text = "Mejora la redacción conservando el significado." }
            UiButton { text: "Corregir"; enabled: !dialog.busy; onClicked: instruction.text = "Corrige la ortografía y la gramática." }
            UiButton { text: "Acortar"; enabled: !dialog.busy; onClicked: instruction.text = "Acorta el texto conservando las ideas principales." }
        }
        Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.secondary; font.pixelSize: 13
            text: dialog.assistant.phase === "generating" ? dialog.assistant.engineName + " está preparando una propuesta…"
                  : dialog.proposal ? "Propuesta" + (dialog.assistant.usage.last.total
                      ? " · " + (dialog.assistant.usage.last.total >= 1000 ? (dialog.assistant.usage.last.total/1000).toLocaleString(Qt.locale(),'f',1) + " k" : dialog.assistant.usage.last.total) + " tokens" : "")
                  : dialog.assistant.engineName + " recibirá el fragmento y tu instrucción al generar la propuesta."
        }
        ScrollView {
            visible: !!dialog.proposal; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentWidth: availableWidth
            TextArea { text: dialog.proposal; textFormat: TextEdit.PlainText; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; font.pixelSize: 15 }
        }
        AiProblem {
            Layout.fillWidth: true; assistant: dialog.assistant; mode: "edit"
            onRetry: if (dialog.ready) dialog.assistant.generate(dialog.selection,instruction.text)
            onOpenConnectors: dialog.settingsRequested()
        }
        RowLayout {
            visible: dialog.assistant.phase !== "error" && (!dialog.ready || (dialog.assistant.engine === "claude" && dialog.assistant.claudeAccount === "out"))
            Layout.fillWidth: true; spacing: 10
            Label {
                Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.warning; font.pixelSize: 13
                text: dialog.assistant.link.state !== "connected" ? "Activa la conexión del editor en Conectores."
                      : !dialog.assistant.engineReady ? "No se encontró " + dialog.assistant.engineName + " en este equipo."
                      : "Claude Code necesita que inicies sesión una vez para escribir aquí."
            }
            UiButton {
                visible: dialog.assistant.engine === "claude" && dialog.assistant.claudeAccount === "out" && dialog.ready
                text: "Iniciar sesión"; onClicked: dialog.assistant.signInClaude()
            }
            UiButton { visible: !dialog.ready; text: "Abrir conectores"; onClicked: dialog.settingsRequested() }
        }
        Item { visible: !dialog.proposal; Layout.fillHeight: true }
        RowLayout {
            Layout.fillWidth: true
            UiButton { text: "Cancelar"; quiet: true; enabled: dialog.assistant.phase !== "applying"; onClicked: dialog.close() }
            Item { Layout.fillWidth: true }
            UiButton {
                text: dialog.proposal ? "Regenerar" : "Generar propuesta"
                primary: !dialog.proposal
                enabled: !dialog.busy && !!instruction.text.trim() && dialog.ready
                onClicked: dialog.assistant.generate(dialog.selection,instruction.text)
            }
            UiButton { visible: !!dialog.proposal; text: "Aplicar"; primary: true; enabled: dialog.assistant.phase === "preview"; onClicked: dialog.assistant.apply() }
        }
    }
}
