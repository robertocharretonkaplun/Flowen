import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// "Crear con IA", modelled on Notion's AI prompt: it opens under the current line,
// writes new blocks, shows them, and inserts them only when you accept.
Rectangle {
    id: composer
    required property var assistant
    property Item anchorItem: null     // block the content goes after, or replaces when it is an empty line
    property Item viewport: null
    property real scrollOffset: 0
    property var place: ({})
    property string lastInstruction: ""
    property bool active: false
    property int highlighted: 0
    signal openConnectors()
    readonly property bool mine: assistant.mode === "create"
    readonly property bool busy: mine && assistant.phase === "generating"
    readonly property bool previewing: mine && assistant.phase === "preview"
    readonly property bool applying: mine && assistant.phase === "applying"
    readonly property bool failed: mine && assistant.phase === "error"
    readonly property bool needsSignIn: assistant.engine === "claude" && assistant.claudeAccount === "out" && !failed
    readonly property bool showSuggestions: active && !busy && !previewing && !applying && !prompt.text
    readonly property var suggestions: {
        const list = []
        if (place.before) list.push({glyph: "edit", text: "Continuar escribiendo", prompt: "Continúa el texto de la página de forma natural.", run: true})
        if (place.before) list.push({glyph: "page", text: "Resumir lo anterior", prompt: "Resume en pocas frases el contenido de la página.", run: true})
        list.push({glyph: "list", text: "Lista de puntos sobre…", prompt: "Escribe una lista de puntos sobre "})
        list.push({glyph: "bulb", text: "Lluvia de ideas sobre…", prompt: "Haz una lluvia de ideas sobre "})
        list.push({glyph: "heading", text: "Esquema sobre…", prompt: "Escribe un esquema con encabezados y puntos sobre "})
        list.push({glyph: "task", text: "Lista de tareas para…", prompt: "Crea una lista de tareas para "})
        list.push({glyph: "help", text: "Explicar…", prompt: "Explica de forma sencilla qué es "})
        return list
    }

    function show(where, item) {
        if (assistant.phase !== "applying") assistant.cancel()
        place = where; anchorItem = item; lastInstruction = ""; highlighted = 0
        prompt.text = ""
        active = true
        if (assistant.engine === "claude" && assistant.claudeAccount !== "in") assistant.checkClaude()
        prompt.forceActiveFocus()
    }
    function close() {
        if (mine && (busy || previewing || failed)) assistant.cancel()
        active = false
        const item = anchorItem
        anchorItem = null
        if (item && item.focusEditor) item.focusEditor()
    }
    function run(instruction) {
        instruction = instruction.trim()
        if (!instruction) return
        lastInstruction = instruction
        prompt.text = ""
        assistant.compose(place,instruction)
    }
    function pick(suggestion) {
        if (suggestion.run) { run(suggestion.prompt); return }
        prompt.text = suggestion.prompt
        prompt.cursorPosition = prompt.length
        prompt.forceActiveFocus()
    }
    function submit() {
        const text = prompt.text.trim()
        if (busy || applying) return
        if (previewing && !text) { assistant.apply(); return }
        if (previewing) {
            run(lastInstruction + "\n\nAjusta la versión anterior según esto: " + text + "\n\nVersión anterior:\n" + assistant.proposal)
            return
        }
        if (!text) { if (suggestions[highlighted]) pick(suggestions[highlighted]); return }
        run(text)
    }
    function retry() { if (lastInstruction) assistant.compose(place,lastInstruction) }
    // The field is disabled while the assistant writes; give the keyboard back when it finishes.
    onBusyChanged: if (!busy && active) prompt.forceActiveFocus()

    // Under the line it writes after; above it when the bottom of the window is too close.
    readonly property var placement: {
        scrollOffset; height; suggestionList.height; showSuggestions
        if (!active || !parent) return {x: 0, y: 0}
        const area = parent
        if (viewport) { viewport.width; viewport.height }
        const reference = anchorItem || viewport
        const origin = reference ? reference.mapToItem(area,0,0) : Qt.point(24,area.height/2)
        const total = height + (showSuggestions ? suggestionList.height + 6 : 0)
        // An empty line is taken over by the prompt; otherwise it opens just below the line.
        let y = !anchorItem ? origin.y + 40 : place.empty ? origin.y - 8 : origin.y + anchorItem.height + 4
        if (y + total > area.height - 10) y = anchorItem ? origin.y - height - 6 : area.height - total - 10
        return {x: Math.round(Math.max(8,origin.x - 6)), y: Math.round(Math.max(8,y))}
    }
    x: placement.x; y: placement.y; z: 25
    width: Math.max(420,Math.min(740,(anchorItem ? anchorItem.width : 700) + 12))
    height: body.implicitHeight + 16
    visible: active
    radius: Theme.radiusPanel; color: Theme.surface; border.color: busy ? Theme.accentLine : Theme.pressed
    Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 2; anchors.bottomMargin: -5; radius: Theme.radiusPanel+1; color: Theme.shadow }
    Rectangle { z: -2; anchors.fill: parent; anchors.margins: -5; anchors.bottomMargin: -14; radius: Theme.radiusPanel+4; color: Theme.shadowSoft }
    MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons; onWheel: function(wheel) { wheel.accepted = false } }

    // Each proposed block as it will look in the page: markers, quote bar, note and code panels, divider.
    component BlockPreview: Item {
        id: line
        required property var modelData
        required property int index
        property var all: []
        readonly property string type: modelData.type
        readonly property bool boxed: type === "callout" || type === "code"
        readonly property int number: {
            const all = line.all
            let n = 0
            for (let i = index; i >= 0 && all[i] && all[i].type === "numbered"; --i) ++n
            return n
        }
        readonly property string marker: type === "list" ? "•" : type === "task" ? "☐" : type === "toggle" ? "▸"
                                         : type === "numbered" ? number + "." : type === "callout" ? (modelData.icon || "💡") : ""
        Layout.fillWidth: true
        implicitHeight: type === "divider" ? 17 : content.implicitHeight+(boxed ? 16 : 0)+(type === "heading" ? 6 : 0)
        Rectangle {
            visible: line.boxed; anchors.fill: parent
            radius: Theme.radiusButton; color: line.type === "code" ? Theme.base : Theme.raised; border.color: Theme.hover
        }
        Rectangle { visible: line.type === "divider"; anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: Theme.line }
        RowLayout {
            id: content
            visible: line.type !== "divider"
            x: line.boxed ? 10 : 0; y: line.boxed ? 8 : line.type === "heading" ? 6 : 0
            width: parent.width-(line.boxed ? 20 : 0); spacing: 8
            Rectangle { visible: line.type === "quote"; Layout.preferredWidth: 3; Layout.fillHeight: true; radius: 1.5; color: Theme.accent }
            Label {
                visible: !!line.marker; text: line.marker
                font.family: line.type === "callout" ? "Segoe UI Emoji" : Theme.family
                font.pixelSize: line.type === "list" ? 17 : 15; color: line.type === "list" ? Theme.accent : Theme.secondary
                Layout.alignment: Qt.AlignTop; Layout.topMargin: line.type === "list" ? -1 : 0
                font.features: {"tnum": 1}
            }
            Label {
                Layout.fillWidth: true; wrapMode: Text.Wrap; text: line.modelData.text; color: Theme.text
                font.family: line.type === "code" ? Theme.mono : Theme.family
                font.pixelSize: line.type === "heading" ? [19,21,18,16][line.modelData.level || 2] : line.type === "code" ? 13 : 15
                font.weight: line.type === "heading" ? Font.DemiBold : Font.Normal
            }
        }
    }

    ColumnLayout {
        id: body
        x: 8; y: 8; width: parent.width-16
        spacing: 8
        ScrollView {
            id: preview
            visible: composer.previewing || composer.applying
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(320,result.implicitHeight+20)
            clip: true; contentWidth: availableWidth
            background: Rectangle { radius: Theme.radiusButton; color: Theme.base; border.color: Theme.hover }
            ColumnLayout {
                id: result
                x: 12; y: 10; width: preview.availableWidth-24
                spacing: 6
                Repeater { model: composer.previewing || composer.applying ? composer.assistant.blocks : []; delegate: BlockPreview { all: composer.assistant.blocks } }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Glyph {
                name: "sparkles"; font.pixelSize: 16; Layout.leftMargin: 6
                // Breathes while the assistant writes; always settles back to full opacity.
                SequentialAnimation on opacity {
                    running: composer.busy; loops: Animation.Infinite; alwaysRunToEnd: true
                    NumberAnimation { from: 1; to: 0.35; duration: 520; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.35; to: 1; duration: 520; easing.type: Easing.InOutSine }
                }
            }
            TextField {
                id: prompt; objectName: "aiPrompt"
                Layout.fillWidth: true; maximumLength: 2000; selectByMouse: true
                enabled: !composer.busy && !composer.applying
                font.pixelSize: 15; color: Theme.text; leftPadding: 2
                placeholderTextColor: Theme.muted
                placeholderText: composer.busy ? composer.assistant.engineName + " está escribiendo…"
                                 : composer.applying ? "Insertando…"
                                 : composer.previewing ? "Pide un cambio o pulsa Intro para insertar…"
                                 : "Pide a la IA que escriba algo…"
                Accessible.name: "Instrucción para Crear con IA"
                background: Item {}
                onAccepted: composer.submit()
                onTextChanged: composer.highlighted = 0
                Keys.onEscapePressed: function(event) {
                    event.accepted = true
                    if (composer.busy) composer.assistant.cancel(); else composer.close()
                }
                Keys.onDownPressed: function(event) {
                    if (!composer.showSuggestions) return
                    event.accepted = true; composer.highlighted = (composer.highlighted+1) % composer.suggestions.length
                }
                Keys.onUpPressed: function(event) {
                    if (!composer.showSuggestions) return
                    event.accepted = true; composer.highlighted = (composer.highlighted+composer.suggestions.length-1) % composer.suggestions.length
                }
            }
            EngineSwitch { assistant: composer.assistant; visible: !composer.previewing && !composer.applying }
            AbstractButton {
                id: send; objectName: "aiSend"
                implicitWidth: 30; implicitHeight: 30
                focusPolicy: Qt.NoFocus; hoverEnabled: true
                enabled: composer.busy || (!composer.applying && (!!prompt.text.trim() || composer.previewing))
                Accessible.name: composer.busy ? "Detener" : composer.previewing && !prompt.text.trim() ? "Insertar" : "Enviar"
                ToolTip.visible: hovered; ToolTip.delay: 450; ToolTip.text: Accessible.name
                onClicked: composer.busy ? composer.assistant.cancel() : composer.submit()
                background: Rectangle {
                    radius: 15
                    color: !send.enabled ? Theme.raised : send.down ? Theme.accentPressed : Theme.accent
                }
                contentItem: Glyph { name: composer.busy ? "stop" : "send"; font.pixelSize: 13; color: send.enabled ? Theme.accentInk : Theme.faint }
            }
        }
        AiProblem {
            Layout.fillWidth: true; Layout.leftMargin: 6
            assistant: composer.assistant; mode: "create"
            onRetry: composer.retry()
            onOpenConnectors: { composer.close(); composer.openConnectors() }
        }
        RowLayout {
            visible: composer.needsSignIn
            Layout.fillWidth: true; Layout.leftMargin: 6; spacing: 10
            Label { text: "Claude Code necesita que inicies sesión una vez para escribir aquí."; color: Theme.warning; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
            UiButton { text: "Iniciar sesión"; onClicked: composer.assistant.signInClaude() }
            UiButton { text: "Comprobar"; quiet: true; onClicked: composer.assistant.checkClaude() }
        }
        RowLayout {
            visible: composer.previewing || composer.applying
            Layout.fillWidth: true; spacing: 8
            UiButton { objectName: "aiInsert"; primary: true; text: "Insertar"; enabled: composer.previewing; onClicked: composer.assistant.apply() }
            UiButton { text: "Reintentar"; enabled: composer.previewing; onClicked: composer.retry() }
            Item { Layout.fillWidth: true }
            Label {
                objectName: "aiSpent"; color: Theme.muted; font.pixelSize: 12
                readonly property var spent: composer.assistant.usage.last
                text: composer.assistant.blocks.length + (composer.assistant.blocks.length === 1 ? " bloque" : " bloques")
                      + " · " + composer.assistant.engineName
                      + (spent.total ? " · " + (spent.total >= 1000 ? (spent.total/1000).toLocaleString(Qt.locale(),'f',1) + " k" : spent.total) + " tokens" : "")
            }
            UiButton { text: "Descartar"; quiet: true; enabled: composer.previewing; onClicked: composer.close() }
        }
    }

    Rectangle {
        id: suggestionList
        visible: composer.showSuggestions
        y: parent.height + 6; width: 300
        height: options.implicitHeight + 12
        radius: Theme.radiusPanel; color: Theme.surface; border.color: Theme.line
        Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 2; anchors.bottomMargin: -5; radius: Theme.radiusPanel+1; color: Theme.shadow }
        ColumnLayout {
            id: options
            x: 6; y: 6; width: parent.width-12; spacing: 0
            Text { text: "Escribir con IA"; color: Theme.muted; font.pixelSize: 12; Layout.leftMargin: 8; Layout.topMargin: 2; Layout.bottomMargin: 4 }
            Repeater {
                model: composer.suggestions
                delegate: AbstractButton {
                    id: suggestion
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true; implicitHeight: 30; leftPadding: 8; rightPadding: 8
                    focusPolicy: Qt.NoFocus; hoverEnabled: true
                    Accessible.name: modelData.text
                    onHoveredChanged: if (hovered) composer.highlighted = index
                    onClicked: composer.pick(modelData)
                    background: Rectangle { radius: Theme.radiusButton; color: composer.highlighted === suggestion.index ? Theme.raised : "transparent" }
                    contentItem: RowLayout {
                        spacing: 10
                        Glyph { name: suggestion.modelData.glyph; color: Theme.accent; Layout.preferredWidth: 18 }
                        Text { text: suggestion.modelData.text; color: Theme.text; font.pixelSize: 14; Layout.fillWidth: true }
                    }
                }
            }
        }
    }
}
