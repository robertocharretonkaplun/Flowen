import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The ✦ next to the star: AI over the whole open page, as Gemini in Google Docs. Summaries, key points,
// pending tasks, suggestions or any question about the page appear here, newest first, and stay while
// Flowen is open. The page does not change unless you press «Insertar al final».
Rectangle {
    id: panel
    required property var assistant
    required property var workspace          // the window: currentId, locked, reviewPage(), insertInsight()
    signal closeRequested()
    readonly property bool busy: assistant.mode === "review" && assistant.phase === "generating"
    readonly property bool failed: assistant.mode === "review" && assistant.phase === "error"
    readonly property bool otherBusy: assistant.mode !== "review" && (assistant.phase === "generating" || assistant.phase === "applying")
    property string asking: ""
    // What this page has, newest first, with each entry's index in the assistant's list (to remove it).
    readonly property var results: {
        const out = []
        const all = assistant.insights
        for (let i = all.length-1; i >= 0; --i)
            if (all[i].page === workspace.currentId) out.push(Object.assign({index: i}, all[i]))
        return out
    }
    readonly property var actions: [
        {key: "summary", label: "Resumir", glyph: "text",
         request: "Resume esta página: primero una o dos frases y después de 3 a 5 puntos con lo esencial."},
        {key: "points", label: "Puntos clave", glyph: "list",
         request: "Enumera las ideas clave de esta página, una por línea, en el orden en que aparecen."},
        {key: "tasks", label: "Pendientes", glyph: "task",
         request: "Enumera las tareas, decisiones pendientes y siguientes pasos que se desprenden de esta página. Si no hay, dilo."},
        {key: "improve", label: "Sugerencias", glyph: "improve",
         request: "Sugiere mejoras concretas de claridad, estructura y redacción para esta página, citando el fragmento de cada una. Señala también las faltas de ortografía. No la reescribas entera."},
        {key: "questions", label: "Preguntas", glyph: "help",
         request: "Escribe 5 preguntas que un lector podría hacerse sobre esta página, cada una con su respuesta breve según el texto."}]
    function run(label, request) {
        if (busy || otherBusy || !request.trim()) return
        asking = label
        workspace.reviewPage(label,request)
    }
    function send() {
        const text = field.text.trim()
        if (!text) return
        field.text = ""
        run(text.length > 60 ? text.slice(0,57) + "…" : text, text)
    }

    width: 384
    implicitHeight: column.implicitHeight+28
    radius: Theme.radiusPanel
    color: Theme.surface
    border.color: Theme.line
    Accessible.role: Accessible.Pane
    Accessible.name: "IA de la página"
    Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 4; anchors.bottomMargin: -10; radius: Theme.radiusPanel+2; color: Theme.shadow }
    // Clicks and the wheel stay in the panel.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: function(wheel) { wheel.accepted = true } }

    // Fills the panel: when the window limits the panel's height, the answers below scroll inside it.
    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.topMargin: 14; anchors.bottomMargin: 14
        spacing: 12
        clip: true
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Glyph { name: "sparkles"; font.pixelSize: 16 }
            Label { text: "IA de la página"; color: Theme.text; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
            EngineSwitch { assistant: panel.assistant }
            UiButton { objectName: "pageAssistClose"; symbol: "close"; quiet: true; implicitWidth: 28; implicitHeight: 28; hint: "Cerrar"; onClicked: panel.closeRequested() }
        }
        Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: 12
            text: "Trabaja con toda la página. Las respuestas se quedan aquí; la página no cambia."
        }
        Flow {
            Layout.fillWidth: true; spacing: 6
            Repeater {
                model: panel.actions
                delegate: UiButton {
                    required property var modelData
                    objectName: "assist-" + modelData.key
                    text: modelData.label; symbol: modelData.glyph; implicitHeight: 30
                    font.pixelSize: 13; font.weight: Font.Normal
                    enabled: !panel.busy && !panel.otherBusy
                    onClicked: panel.run(modelData.label,modelData.request)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            TextField {
                id: field; objectName: "pageAssistField"
                Layout.fillWidth: true; implicitHeight: 36
                placeholderText: "Pide algo sobre esta página…"
                enabled: !panel.busy; selectByMouse: true; maximumLength: 2000; font.pixelSize: 13; leftPadding: 10
                color: Theme.text; placeholderTextColor: Theme.faint
                background: Rectangle { radius: Theme.radiusButton; color: Theme.base; border.color: field.activeFocus ? Theme.focus : Theme.line }
                onAccepted: panel.send()
            }
            UiButton {
                objectName: "pageAssistSend"; implicitWidth: 36; implicitHeight: 36; primary: !panel.busy
                symbol: panel.busy ? "stop" : "send"; hint: panel.busy ? "Detener" : "Enviar (Intro)"
                enabled: panel.busy || (!!field.text.trim() && !panel.otherBusy)
                onClicked: panel.busy ? panel.assistant.cancel() : panel.send()
            }
        }
        // Working, or why it could not.
        Label {
            objectName: "pageAssistStatus"
            visible: panel.busy || panel.failed || panel.otherBusy
            Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 13
            color: panel.failed ? Theme.danger : Theme.muted
            text: panel.busy ? panel.assistant.engineName + " está leyendo la página: " + panel.asking + "…"
                  : panel.failed ? panel.assistant.error
                  : panel.assistant.engineName + " está ocupado con otra tarea."
        }
        Rectangle { visible: panel.results.length > 0; Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hover }
        ScrollView {
            id: scroller; objectName: "pageAssistScroll"
            visible: panel.results.length > 0
            // As tall as the answers, but only what is left of the panel: the rest scrolls.
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.preferredHeight: answers.implicitHeight
            Layout.maximumHeight: answers.implicitHeight
            Layout.minimumHeight: Math.min(answers.implicitHeight,120)
            clip: true; contentWidth: availableWidth; contentHeight: answers.implicitHeight
            ScrollBar.vertical.policy: answers.implicitHeight > height+1 ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
            ColumnLayout {
                id: answers
                width: scroller.availableWidth-10; spacing: 14   // room for the scroll bar
                Repeater {
                    model: panel.results
                    delegate: ColumnLayout {
                        id: entry
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true; spacing: 6
                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Label { text: entry.modelData.label; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                            Label { text: (entry.modelData.engine === "claude" ? "Claude" : "Codex") + " · " + new Date(entry.modelData.at).toLocaleTimeString(Qt.locale(),"h:mm a")
                                    color: Theme.faint; font.pixelSize: 11 }
                        }
                        TextEdit {
                            objectName: "pageInsight-" + entry.index
                            Layout.fillWidth: true; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                            text: entry.modelData.answer; color: Theme.textSoft; font.pixelSize: 13; font.family: Theme.family
                            selectionColor: Theme.selection; selectedTextColor: Theme.text
                        }
                        RowLayout {
                            spacing: 2
                            UiButton { text: "Copiar"; symbol: "copy"; quiet: true; implicitHeight: 28; font.pixelSize: 12
                                onClicked: { copyHelper.text = entry.modelData.answer; copyHelper.selectAll(); copyHelper.copy() } }
                            UiButton { objectName: "pageInsightInsert-" + entry.index; text: "Insertar al final"; symbol: "add"; quiet: true
                                implicitHeight: 28; font.pixelSize: 12; enabled: !panel.workspace.locked
                                hint: panel.workspace.locked ? "En Modo lectura la página no cambia" : "Añade esta respuesta al final de la página"
                                onClicked: panel.workspace.insertInsight(entry.modelData) }
                            UiButton { symbol: "close"; quiet: true; implicitWidth: 28; implicitHeight: 28; hint: "Quitar"
                                onClicked: panel.assistant.forgetInsight(entry.modelData.index) }
                        }
                    }
                }
            }
        }
        Label {
            visible: !panel.results.length && !panel.busy && !panel.failed
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.faint; font.pixelSize: 12
            text: "Elige una acción o escribe, por ejemplo: «¿Qué datos de esta página necesitan una fuente?»"
        }
    }
    TextEdit { id: copyHelper; visible: false }
}
