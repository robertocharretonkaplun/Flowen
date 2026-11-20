import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// "Preguntar a Flowen": questions about your notes, answered by Claude or Codex from the pages that
// match them best (the open page always goes too). Each answer names its pages; open them, copy the
// answer or keep it as a page. The conversation lasts until Flowen closes.
Item {
    id: page
    required property var assistant
    required property var workspace             // the window: call(), selectPage(), currentId
    readonly property bool busy: assistant.mode === "ask" && assistant.phase === "generating"
    readonly property bool failed: assistant.mode === "ask" && assistant.phase === "error"
    property string asking: ""
    function send(text) {
        const question = (text || "").trim()
        if (!question || busy) return
        const found = workspace.call("ask_notes",{question: question, id: workspace.currentId || ""})
        asking = question
        field.text = ""
        assistant.ask(question,found ? found.notes : [])
    }
    // A page with the question as title, the answer as paragraphs and links to the pages it used.
    function keep(turn) {
        const blocks = []
        for (const line of turn.answer.split("\n")) {
            if (!line.trim()) continue
            const bullet = /^\s*-\s+/.test(line)
            blocks.push({type: bullet ? "list" : "paragraph", text: line.replace(/^\s*-\s+/,"").trim()})
        }
        const sources = turn.sources.filter(s => s.id !== "tareas-sin-terminar")
        if (sources.length) blocks.push({type: "heading", level: 3, text: "Fuentes"})
        for (const s of sources) blocks.push({type: "list", text: s.title, spans: [{start: 0, end: s.title.length, style: 0, link: "lunqio://page/" + s.id}]})
        const made = workspace.call("create_page",{title: turn.question.slice(0,200), icon: "💬", blocks: blocks.slice(0,128)})
        if (made) { workspace.refreshNavigation(); workspace.selectPage(made.id) }
    }
    onBusyChanged: if (!busy) Qt.callLater(function() { list.positionViewAtEnd() })

    ColumnLayout {
        anchors.fill: parent; anchors.topMargin: 24; anchors.bottomMargin: 18
        width: parent.width; spacing: 12
        RowLayout {
            Layout.fillWidth: true; Layout.maximumWidth: 820; Layout.alignment: Qt.AlignHCenter
            Layout.leftMargin: 24; Layout.rightMargin: 24; spacing: 10
            Glyph { name: "sparkles"; font.pixelSize: 22 }
            Label { text: "Preguntar a Flowen"; font.pixelSize: 26; font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true }
            UiButton { visible: page.assistant.conversation.length > 0; text: "Nueva conversación"; quiet: true; onClicked: page.assistant.clearConversation() }
            EngineSwitch { assistant: page.assistant }
        }
        ListView {
            id: list
            objectName: "askList"
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 18
            model: page.assistant.conversation
            ScrollBar.vertical: ScrollBar {}
            header: Item { width: list.width; height: 4 }
            footer: Item {
                width: list.width; height: page.busy || page.failed ? 76 : 8
                ColumnLayout {
                    visible: page.busy || page.failed
                    x: Math.max(24,(list.width-820)/2); width: Math.min(820,list.width-48); spacing: 6
                    Label { text: page.asking; color: Theme.text; font.pixelSize: 15; font.weight: Font.DemiBold; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 14
                        text: page.busy ? page.assistant.engineName + " está leyendo tus notas…" : page.assistant.error
                        color: page.failed ? Theme.danger : Theme.muted
                    }
                }
            }
            delegate: Item {
                id: turn
                required property var modelData
                required property int index
                width: list.width; height: body.implicitHeight
                ColumnLayout {
                    id: body
                    x: Math.max(24,(list.width-820)/2); width: Math.min(820,list.width-48); spacing: 8
                    Label { text: turn.modelData.question; color: Theme.text; font.pixelSize: 15; font.weight: Font.DemiBold; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    TextEdit {
                        objectName: "askAnswer-" + turn.index
                        Layout.fillWidth: true; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                        text: turn.modelData.answer; color: Theme.textSoft; font.pixelSize: 15; font.family: Theme.family
                        selectionColor: Theme.selection; selectedTextColor: Theme.text
                    }
                    Flow {
                        Layout.fillWidth: true; spacing: 6
                        visible: turn.modelData.sources.length > 0
                        Repeater {
                            model: turn.modelData.sources
                            delegate: AbstractButton {
                                id: source
                                required property var modelData
                                enabled: modelData.id !== "tareas-sin-terminar"
                                implicitHeight: 28; leftPadding: 8; rightPadding: 10; hoverEnabled: true
                                Accessible.name: "Abrir " + modelData.title
                                onClicked: page.workspace.selectPage(modelData.id)
                                background: Rectangle { radius: 6; color: source.hovered ? Theme.hover : Theme.raised; border.color: Theme.line }
                                contentItem: RowLayout {
                                    spacing: 6
                                    Glyph { name: "page"; font.pixelSize: 12 }
                                    Text { text: source.modelData.title; color: Theme.textSoft; font.pixelSize: 13 }
                                }
                            }
                        }
                    }
                    RowLayout {
                        spacing: 4
                        UiButton { text: "Copiar"; symbol: "copy"; quiet: true; onClicked: { copyHelper.text = turn.modelData.answer; copyHelper.selectAll(); copyHelper.copy() } }
                        UiButton { objectName: "askKeep-" + turn.index; text: "Guardar como página"; symbol: "newPage"; quiet: true; onClicked: page.keep(turn.modelData) }
                        Label { text: turn.modelData.engine === "claude" ? "Claude" : "Codex"; color: Theme.faint; font.pixelSize: 12; Layout.leftMargin: 6 }
                    }
                }
            }
            // Before the first question: what it does and a few to try.
            ColumnLayout {
                visible: !list.count && !page.busy && !page.failed
                x: Math.max(24,(list.width-820)/2); y: 30; width: Math.min(820,list.width-48); spacing: 12
                Label {
                    Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.secondary; font.pixelSize: 15
                    text: "Pregunta sobre lo que tienes escrito. " + page.assistant.engineName + " lee las páginas que mejor coinciden con tu pregunta (y la que tienes abierta) y te dice de cuáles sacó la respuesta."
                }
                Repeater {
                    model: ["¿Qué tareas tengo pendientes?", "Resume lo que escribí sobre las reuniones", "¿Qué ideas tengo para el próximo proyecto?"]
                    delegate: UiButton { required property string modelData; text: modelData; symbol: "help"; alignLeft: true; onClicked: page.send(modelData) }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; Layout.maximumWidth: 820; Layout.alignment: Qt.AlignHCenter
            Layout.leftMargin: 24; Layout.rightMargin: 24; spacing: 8
            TextField {
                id: field; objectName: "askField"
                Layout.fillWidth: true; implicitHeight: 44
                placeholderText: page.busy ? "Esperando la respuesta…" : "Pregunta sobre tus notas…"
                enabled: !page.busy; selectByMouse: true; maximumLength: 2000; font.pixelSize: 15; leftPadding: 14
                color: Theme.text; placeholderTextColor: Theme.faint
                background: Rectangle { radius: Theme.radiusPanel; color: Theme.surface; border.color: field.activeFocus ? Theme.focus : Theme.line }
                onAccepted: page.send(text)
            }
            UiButton {
                objectName: "askSend"; implicitHeight: 44; implicitWidth: 44; primary: !page.busy
                symbol: page.busy ? "stop" : "send"; hint: page.busy ? "Detener" : "Preguntar (Intro)"
                enabled: page.busy || !!field.text.trim()
                onClicked: page.busy ? page.assistant.cancel() : page.send(field.text)
            }
        }
    }
    TextEdit { id: copyHelper; visible: false }
}
