import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQml.Models
import Lunqio

// One block of the page. Like Notion: Enter starts a new block, Backspace at the start joins
// it to the previous one, "/" opens the block menu, Tab nests it, and ⋮⋮ in the margin drags it.
Item {
    id: row
    required property string kind
    required property string body
    required property string spans
    required property bool done
    required property string asset
    required property int photoPercent
    required property int level
    required property int indent
    required property string icon
    required property bool collapsed
    // The block's look: align (left, center, right, justify), tint and fill (palette colours for its text
    // and background), frame (a photo's style). Empty is the default.
    required property string align
    required property string tint
    required property string fill
    required property string frame
    // The page's typography: "sans", "serif" or "mono", and smaller text.
    property string pageFont: "sans"
    property bool smallText: false
    readonly property string family: pageFont === "serif" ? "Georgia" : pageFont === "mono" ? Theme.mono : Theme.family
    required property int index
    required property int total
    required property bool editable
    property int number: 0
    property bool hasChildren: false
    property alias editor: input
    property alias formatter: fmt
    property bool toolsOpen: optionsMenu.visible
    property bool echoing: false
    property bool slashOpen: false
    property bool lifted: false
    property string tip: ""
    readonly property bool boxed: kind === "callout" || kind === "code"
    // Callouts and code sit on a panel; any text block with a background colour too, with less padding.
    readonly property bool panel: boxed || (!!fill && kind !== "image" && kind !== "divider")
    readonly property int padX: boxed ? 14 : panel ? 8 : 0
    readonly property int padY: boxed ? 10 : panel ? 3 : 0
    readonly property bool textual: kind !== "image" && kind !== "divider"
    signal editContent(string value, string styles)
    signal check(bool value)
    signal shift(int offset)
    signal removeRow()
    signal changeKind(string value)
    signal resizePhoto(int value)
    signal editing(var editor, int index)
    signal askAi()
    signal linkRequested()
    signal composeRequested()
    signal commentFocused(string id)
    signal splitRequested(int position)
    signal mergeRequested()
    signal navigate(int direction)
    signal slashTyped(int start)
    signal mentionTyped(int start, int marker)
    signal openPage(string id)
    signal slashKey(int key)
    signal addBelow()
    signal dragStarted()
    signal dragMoved(real sceneY)
    signal dragFinished()
    signal indentRequested(int step)
    signal collapseRequested()
    signal iconRequested(Item anchor)
    // A change to the look (role is align, tint, fill or frame) and the photo actions.
    signal lookRequested(string role, string value)
    signal photoAction(string name)
    // Set by the page: adds the clipboard's photo below this block; false when it holds no photo.
    property var pastePhoto: function() { return false }
    property var undoStructure: function() { return false }
    // Escape in the text: true when the page used it (closing the colour palette, say).
    property var escapeKey: function() { return false }
    property var redoStructure: function() { return false }
    implicitHeight: content.implicitHeight+2*padY+(kind === "heading" ? [0,14,8,4][level] : 0)
    opacity: lifted ? 0.4 : 1
    function focusEditor() { if (kind === "image") photoItem.item.focusCaption(); else if (textual) input.forceActiveFocus() }
    function focusAt(position) {
        if (!textual) { focusEditor(); return }
        input.forceActiveFocus()
        input.cursorPosition = position < 0 ? input.length : Math.min(position,input.length)
    }
    // Reload only when the model changed outside this editor (never while echoing our own edit).
    function syncEditor() {
        if (!echoing && (body !== fmt.text() || spans !== fmt.spans())) fmt.load(body,spans)
    }
    onBodyChanged: syncEditor()
    onSpansChanged: syncEditor()
    Component.onCompleted: fmt.load(body,spans)
    // Notion-style shortcuts. They only apply to a selection; Ctrl+K without one still opens search.
    function formatKey(event, run) {
        if (!editable || !textual || kind === "code" || !input.selectedText) return false
        const mods = event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier)
        const ctrl = Qt.ControlModifier, both = Qt.ControlModifier | Qt.ShiftModifier
        let style = 0
        if (mods === ctrl && event.key === Qt.Key_B) style = InlineEditor.Bold
        else if (mods === ctrl && event.key === Qt.Key_I) style = InlineEditor.Italic
        else if (mods === ctrl && event.key === Qt.Key_U) style = InlineEditor.Underline
        else if (mods === ctrl && event.key === Qt.Key_E) style = InlineEditor.Code
        else if (mods === both && event.key === Qt.Key_X) style = InlineEditor.Strike
        else if (mods === both && event.key === Qt.Key_H) style = InlineEditor.Highlight
        else if (mods === ctrl && event.key === Qt.Key_K) style = -1
        else return false
        if (run) { if (style < 0) linkRequested(); else fmt.toggle(style) }
        return true
    }
    // At the start of a paragraph, followed by a space (as in Notion): # ## ### headings, - * + bullets,
    // 1. numbers, [] task, " quote, > toggle, ``` code.
    readonly property var markers: ({"#": "heading1", "##": "heading2", "###": "heading3", "-": "list", "*": "list", "+": "list",
                                     "1.": "numbered", "[]": "task", "[ ]": "task", "\"": "quote", ">": "toggle", "```": "code"})
    function blockKey(event) {
        const plain = event.modifiers === Qt.NoModifier || event.modifiers === Qt.KeypadModifier
        const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        if (slashOpen && (event.key === Qt.Key_Up || event.key === Qt.Key_Down || enter || event.key === Qt.Key_Tab || event.key === Qt.Key_Escape)) {
            slashKey(event.key); return true
        }
        if (!editable) return false
        if (event.key === Qt.Key_Tab && plain) {
            if (kind === "code") input.insert(input.cursorPosition,"    "); else indentRequested(1)
            return true
        }
        if (event.key === Qt.Key_Backtab) { indentRequested(-1); return true }
        if (event.key === Qt.Key_Space && plain && kind === "paragraph") {
            if (input.length === 0) { composeRequested(); return true }
            const head = input.getText(0,input.cursorPosition)
            if (markers[head] && !input.selectedText) { input.remove(0,head.length); changeKind(markers[head]); return true }
        }
        // In code, Enter is a new line; Ctrl+Enter leaves the block.
        if (enter && kind === "code" && !(event.modifiers & Qt.ControlModifier)) return false
        if (enter && !(event.modifiers & (Qt.ShiftModifier | Qt.AltModifier))) {
            if (input.selectedText) input.remove(input.selectionStart,input.selectionEnd)
            splitRequested(input.cursorPosition)
            return true
        }
        if (event.key === Qt.Key_Backspace && plain && !input.selectedText && input.cursorPosition === 0) {
            if (kind !== "paragraph") changeKind("paragraph")
            else if (indent > 0) indentRequested(-1)
            else mergeRequested()
            return true
        }
        if (plain && !input.selectedText && event.key === Qt.Key_Up &&
            input.positionToRectangle(input.cursorPosition).y <= input.positionToRectangle(0).y + 1) { navigate(-1); return true }
        if (plain && !input.selectedText && event.key === Qt.Key_Down &&
            input.positionToRectangle(input.cursorPosition).y >= input.positionToRectangle(input.length).y - 1) { navigate(1); return true }
        return false
    }
    function updateTip(point) {
        const link = input.linkAt(point.x,point.y)
        tip = link.indexOf("lunqio://page/") === 0 ? "Clic para abrir la página" : link ? link + "\nCtrl+clic para abrir" : ""
    }
    InlineEditor {
        id: fmt
        scheme: Theme.scheme
        tones: Theme.tones
        document: input.textDocument
        selectionStart: input.selectionStart
        selectionEnd: input.selectionEnd
        onContentChanged: {
            const value = fmt.text(), styles = fmt.spans()
            if (value === row.body && styles === row.spans) return
            row.echoing = true
            row.editContent(value,styles)
            row.echoing = false
        }
    }
    // Hovering the block or its margin shows the + and ⋮⋮ controls.
    Item {
        x: content.x-56; width: parent.width-content.x+56; height: parent.height
        HoverHandler { id: hover }
    }
    Row {
        id: gutter
        x: content.x-52-row.padX; y: content.y+(row.kind === "heading" ? [0,10,6,3][row.level] : row.boxed ? 8 : 4)-(row.panel && !row.boxed ? 3 : 0)
        spacing: 2
        opacity: row.editable && (hover.hovered || row.toolsOpen || handleDrag.active) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 90 } }
        AbstractButton {
            objectName: "blockAdd"
            width: 22; height: 24; hoverEnabled: true; focusPolicy: Qt.NoFocus; enabled: row.editable
            Accessible.name: "Añadir un bloque debajo"
            ToolTip.visible: hovered; ToolTip.delay: 500; ToolTip.text: "Añadir debajo (escribe / para elegir)"
            onClicked: row.addBelow()
            background: Rectangle { radius: 4; color: parent.hovered ? Theme.hover : "transparent" }
            contentItem: Glyph { name: "add"; font.pixelSize: 13; color: Theme.muted }
        }
        Item {
            id: handle; objectName: "blockHandle"
            width: 18; height: 24
            Accessible.name: "Arrastrar o abrir el menú del bloque"
            Rectangle { anchors.fill: parent; radius: 4; color: handleHover.hovered || handleDrag.active ? Theme.hover : "transparent" }
            Glyph { anchors.centerIn: parent; name: "grip"; font.pixelSize: 14; color: Theme.muted }
            HoverHandler { id: handleHover; cursorShape: handleDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
            ToolTip.visible: handleHover.hovered && !handleDrag.active; ToolTip.delay: 500
            ToolTip.text: "Arrastra para mover · Clic para abrir el menú"
            TapHandler { enabled: row.editable; onTapped: (row.kind === "image" ? photoMenu : optionsMenu).popup(handle,0,handle.height) }
            DragHandler {
                id: handleDrag
                target: null; enabled: row.editable; xAxis.enabled: false
                onActiveChanged: active ? row.dragStarted() : row.dragFinished()
                onCentroidChanged: if (active) row.dragMoved(centroid.scenePosition.y)
            }
            Menu {
                id: optionsMenu
                Menu {
                    title: "Convertir en"
                    enabled: row.textual
                    MenuItem { text: "Texto"; onTriggered: row.changeKind("paragraph") }
                    MenuItem { text: "Encabezado 1"; onTriggered: row.changeKind("heading1") }
                    MenuItem { text: "Encabezado 2"; onTriggered: row.changeKind("heading2") }
                    MenuItem { text: "Encabezado 3"; onTriggered: row.changeKind("heading3") }
                    MenuItem { text: "Lista con viñetas"; onTriggered: row.changeKind("list") }
                    MenuItem { text: "Lista numerada"; onTriggered: row.changeKind("numbered") }
                    MenuItem { text: "Tarea"; onTriggered: row.changeKind("task") }
                    MenuItem { text: "Desplegable"; onTriggered: row.changeKind("toggle") }
                    MenuItem { text: "Cita"; onTriggered: row.changeKind("quote") }
                    MenuItem { text: "Nota destacada"; onTriggered: row.changeKind("callout") }
                    MenuItem { text: "Código"; onTriggered: row.changeKind("code") }
                }
                Menu {
                    id: tintMenu; title: "Color del texto"; enabled: row.textual
                    ToneItem { block: row; tone: ""; role: "tint" }
                    Instantiator {
                        model: Theme.toneNames
                        delegate: ToneItem { required property string modelData; block: row; tone: modelData; role: "tint" }
                        onObjectAdded: function(i, item) { tintMenu.insertItem(i+1,item) }
                        onObjectRemoved: function(i, item) { tintMenu.removeItem(item) }
                    }
                }
                Menu {
                    id: fillMenu; title: "Color de fondo"; enabled: row.textual
                    ToneItem { block: row; tone: ""; role: "fill" }
                    Instantiator {
                        model: Theme.toneNames
                        delegate: ToneItem { required property string modelData; block: row; tone: modelData; role: "fill" }
                        onObjectAdded: function(i, item) { fillMenu.insertItem(i+1,item) }
                        onObjectRemoved: function(i, item) { fillMenu.removeItem(item) }
                    }
                }
                Menu {
                    title: "Alinear"; enabled: row.textual
                    LookItem { block: row; text: "Izquierda"; role: "align"; value: "" }
                    LookItem { block: row; text: "Centro"; role: "align"; value: "center" }
                    LookItem { block: row; text: "Derecha"; role: "align"; value: "right" }
                    LookItem { block: row; text: "Justificado"; role: "align"; value: "justify" }
                }
                MenuSeparator {}
                MenuItem { text: "Aumentar sangría    Tab"; enabled: row.index > 0; onTriggered: row.indentRequested(1) }
                MenuItem { text: "Reducir sangría    Mayús+Tab"; enabled: row.indent > 0; onTriggered: row.indentRequested(-1) }
                MenuSeparator {}
                MenuItem { text: "Subir"; enabled: row.index > 0; onTriggered: row.shift(-1) }
                MenuItem { text: "Bajar"; enabled: row.index + 1 < row.total; onTriggered: row.shift(1) }
                MenuSeparator {}
                MenuItem { text: "Eliminar bloque"; onTriggered: row.removeRow() }
            }
            // Photos: where they sit, their style and size, and what to do with the picture.
            Menu {
                id: photoMenu
                Menu {
                    title: "Alinear"
                    LookItem { block: row; text: "Izquierda"; role: "align"; value: "" }
                    LookItem { block: row; text: "Centro"; role: "align"; value: "center" }
                    LookItem { block: row; text: "Derecha"; role: "align"; value: "right" }
                }
                Menu {
                    title: "Estilo"
                    LookItem { block: row; text: "Normal"; role: "frame"; value: "" }
                    LookItem { block: row; text: "Esquinas redondeadas"; role: "frame"; value: "rounded" }
                    LookItem { block: row; text: "Con borde"; role: "frame"; value: "border" }
                    LookItem { block: row; text: "Con sombra"; role: "frame"; value: "shadow" }
                }
                Menu {
                    title: "Ancho"
                    MenuItem { text: "Pequeña (25 %)"; checkable: true; checked: row.photoPercent === 25; onTriggered: row.resizePhoto(25) }
                    MenuItem { text: "Mediana (50 %)"; checkable: true; checked: row.photoPercent === 50; onTriggered: row.resizePhoto(50) }
                    MenuItem { text: "Grande (75 %)"; checkable: true; checked: row.photoPercent === 75; onTriggered: row.resizePhoto(75) }
                    MenuItem { text: "Columna completa"; checkable: true; checked: row.photoPercent === 100; onTriggered: row.resizePhoto(100) }
                }
                MenuSeparator {}
                MenuItem { text: "Ver a tamaño completo"; onTriggered: row.photoAction("view") }
                MenuItem { text: "Reemplazar foto…"; onTriggered: row.photoAction("replace") }
                MenuItem { text: "Guardar foto como…"; onTriggered: row.photoAction("save") }
                MenuItem { text: "Copiar imagen"; onTriggered: row.photoAction("copy") }
                MenuSeparator {}
                MenuItem { text: "Subir"; enabled: row.index > 0; onTriggered: row.shift(-1) }
                MenuItem { text: "Bajar"; enabled: row.index + 1 < row.total; onTriggered: row.shift(1) }
                MenuItem { text: "Eliminar foto"; onTriggered: row.removeRow() }
            }
        }
    }
    // A menu choice for one value of the look; checked while the block has it.
    component LookItem: MenuItem {
        required property Item block
        required property string role
        required property string value
        checkable: true; checked: block[role] === value
        onTriggered: block.lookRequested(role,value)
    }
    // A palette colour, shown as a coloured "A" (text) or a swatch (background).
    component ToneItem: MenuItem {
        required property Item block
        id: toneItem
        required property string tone
        required property string role
        text: tone ? Theme.toneLabels[tone] : (role === "tint" ? "Predeterminado" : "Sin fondo")
        checkable: true; checked: block[role] === tone
        onTriggered: block.lookRequested(role,tone)
        contentItem: RowLayout {
            spacing: 10
            Rectangle {
                implicitWidth: 20; implicitHeight: 20; radius: 4
                color: toneItem.role === "fill" && toneItem.tone ? Theme.tones[toneItem.tone][1] : "transparent"
                border.color: Theme.line
                Text {
                    anchors.centerIn: parent; visible: toneItem.role === "tint"; text: "A"; font.pixelSize: 13; font.weight: Font.DemiBold
                    color: toneItem.tone ? Theme.tones[toneItem.tone][0] : Theme.text
                }
            }
            Text { text: toneItem.text; color: Theme.text; font.pixelSize: 14; Layout.fillWidth: true }
            Glyph { visible: toneItem.checked; name: "check"; font.pixelSize: 12; color: Theme.accent }
        }
    }

    // Callouts and code sit on a soft panel; a background colour paints the block's own.
    Rectangle {
        visible: row.panel
        x: row.indent*26; width: parent.width-x; height: parent.height
        radius: row.boxed ? Theme.radiusButton : 4
        color: row.fill && Theme.tones[row.fill] ? Theme.tones[row.fill][1] : row.kind === "code" ? Theme.base : Theme.surface
        border.color: row.fill ? "transparent" : row.kind === "code" ? Theme.raised : Theme.hover
    }
    RowLayout {
        id: content
        x: row.indent*26+row.padX
        y: row.padY+(row.kind === "heading" ? [0,14,8,4][row.level] : 0)
        width: parent.width-x-row.padX
        spacing: 4
        CheckBox {
            id: taskCheck
            visible: row.kind === "task"; enabled: row.editable; checked: row.done
            Layout.alignment: Qt.AlignTop; Layout.preferredWidth: 22; Layout.preferredHeight: 31
            indicator: Rectangle {
                x: 1; y: Math.round((taskCheck.height-height)/2); width: 17; height: 17; radius: 3
                border.color: taskCheck.visualFocus ? Theme.focus : taskCheck.checked ? Theme.accent : Theme.faint
                color: taskCheck.checked ? Theme.accent : "transparent"
                Glyph { anchors.centerIn: parent; visible: taskCheck.checked; name: "check"; color: Theme.accentInk; font.pixelSize: 12 }
            }
            Accessible.name: "Tarea completada"
            onClicked: row.check(checked)
        }
        // Bullets change with depth, like Notion: • ◦ ▪
        Label {
            visible: row.kind === "list"; text: ["•","◦","▪"][row.indent % 3]
            font.pixelSize: 17; topPadding: 3; Layout.alignment: Qt.AlignTop; Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter
            color: Theme.accent
        }
        Label {
            objectName: "blockNumber"
            visible: row.kind === "numbered"; text: Math.max(1,row.number) + "."
            font.pixelSize: 16; topPadding: 3; Layout.alignment: Qt.AlignTop; Layout.minimumWidth: 22; color: Theme.text
            font.features: {"tnum": 1}
        }
        AbstractButton {
            objectName: "toggleArrow"
            visible: row.kind === "toggle"
            Layout.alignment: Qt.AlignTop; Layout.topMargin: 4; implicitWidth: 22; implicitHeight: 24
            hoverEnabled: true; focusPolicy: Qt.NoFocus
            Accessible.name: row.collapsed ? "Desplegar" : "Plegar"
            onClicked: row.collapseRequested()
            background: Rectangle { radius: 4; color: parent.hovered ? Theme.hover : "transparent" }
            contentItem: Glyph { name: row.collapsed ? "right" : "down"; font.pixelSize: 11; color: row.hasChildren ? Theme.textSoft : Theme.muted }
        }
        Rectangle {
            visible: row.kind === "quote"
            Layout.fillHeight: true; Layout.preferredWidth: 3; Layout.rightMargin: 10; radius: 1.5; color: Theme.accent
        }
        AbstractButton {
            objectName: "calloutIcon"
            visible: row.kind === "callout"
            Layout.alignment: Qt.AlignTop; implicitWidth: 30; implicitHeight: 30; Layout.rightMargin: 6
            hoverEnabled: true; focusPolicy: Qt.NoFocus; enabled: row.editable
            Accessible.name: "Cambiar el icono de la nota"
            onClicked: row.iconRequested(this)
            background: Rectangle { radius: Theme.radiusButton; color: parent.hovered ? Theme.hover : "transparent" }
            contentItem: Text {
                text: row.icon || "💡"; font.family: "Segoe UI Emoji"; font.pixelSize: 19
                renderType: Text.NativeRendering; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
        }
        Rectangle {
            objectName: "dividerLine"
            visible: row.kind === "divider"
            Layout.fillWidth: true; Layout.preferredHeight: 1; Layout.topMargin: 15; Layout.bottomMargin: 15; color: Theme.line
        }
        Loader {
            id: photoItem; active: row.kind === "image"; visible: active; Layout.fillWidth: true
            sourceComponent: PhotoBlock {
                asset: row.asset; caption: row.body; percent: row.photoPercent; editable: row.editable
                align: row.align; frame: row.frame
                onViewRequested: row.photoAction("view")
                onResized: function(v) { row.resizePhoto(v) }
                onCaptionEdited: function(s) { row.editContent(s,"[]") }
                onFocused: function(field) { row.editing(field,-1) }
            }
        }
        TextArea {
            id: input; objectName: "blockInput"
            visible: row.textual
            // The selection bubble reads these from the focused editor.
            property alias formatter: fmt
            property string blockKind: row.kind
            property int blockLevel: row.level
            property bool selecting: false
            textFormat: TextEdit.PlainText; readOnly: !row.editable
            selectByMouse: true; persistentSelection: true; wrapMode: TextEdit.Wrap
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(31,contentHeight+topPadding+bottomPadding)
            leftPadding: 0; rightPadding: 0; topPadding: 3; bottomPadding: 4
            font.family: row.kind === "code" ? Theme.mono : row.family
            font.pixelSize: row.kind === "heading" ? (row.smallText ? [21,25,19,16] : [24,28,22,18])[row.level]
                            : row.kind === "code" ? (row.smallText ? 13 : 14) : row.smallText ? 14 : 16
            horizontalAlignment: ({center: TextEdit.AlignHCenter, right: TextEdit.AlignRight, justify: TextEdit.AlignJustify})[row.align] || TextEdit.AlignLeft
            font.weight: row.kind === "heading" ? Font.DemiBold : Font.Normal
            font.strikeout: row.kind === "task" && row.done
            color: row.done ? Theme.muted : row.tint && Theme.tones[row.tint] ? Theme.tones[row.tint][0] : row.kind === "code" ? Theme.textSoft : Theme.text
            selectionColor: Theme.selection; selectedTextColor: Theme.text
            placeholderTextColor: Theme.faint
            placeholderText: row.kind === "paragraph" && activeFocus && row.editable ? "Escribe, pulsa «/» para bloques o Espacio para la IA…"
                             : row.kind === "heading" ? "Encabezado " + row.level
                             : ({"paragraph": "Escribe un párrafo…", "task": "Describe la tarea…", "list": "Elemento de lista…",
                                 "numbered": "Elemento de lista…", "quote": "Cita…", "callout": "Escribe una nota…",
                                 "code": "Código…", "toggle": "Desplegable…"})[row.kind] || ""
            background: Item {}
            onActiveFocusChanged: if (activeFocus) row.editing(input,row.index)
            onPressed: selecting = true
            onReleased: selecting = false
            // Putting the cursor in commented text opens its card.
            onCursorPositionChanged: if (activeFocus && !selectedText)
                row.commentFocused(fmt.threadAt(cursorPosition) || fmt.threadAt(cursorPosition-1))
            Keys.onShortcutOverride: function(event) {
                if (row.formatKey(event,false) || (row.slashOpen && event.key === Qt.Key_Escape) ||
                    event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) event.accepted = true
            }
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape && row.escapeKey()) { event.accepted = true; return }
                if (event.matches(StandardKey.Paste) && row.editable && row.pastePhoto()) { event.accepted = true; return }
                // Once this block's text has nothing left to undo, Ctrl+Z undoes the last change to the blocks.
                if (event.matches(StandardKey.Undo) && !input.canUndo && row.undoStructure()) { event.accepted = true; return }
                if (event.matches(StandardKey.Redo) && !input.canRedo && row.redoStructure()) { event.accepted = true; return }
                if (row.blockKey(event) || row.formatKey(event,true)) { event.accepted = true; return }
                // After the character lands: "/" opens the block menu; "---" makes a divider;
                // closing marks turn Markdown into styles.
                const typed = event.text
                if (!row.editable || row.kind === "code") return
                if (typed === "/" || typed === "@") {
                    const before = input.cursorPosition === 0 ? "" : input.getText(input.cursorPosition-1,input.cursorPosition)
                    if (!before || /\s/.test(before)) Qt.callLater(function() {
                        if (typed === "/") row.slashTyped(input.cursorPosition-1); else row.mentionTyped(input.cursorPosition-1,1)
                    })
                } else if (typed === "[") {
                    Qt.callLater(function() { const p = input.cursorPosition; if (p >= 2 && input.getText(p-2,p) === "[[") row.mentionTyped(p-2,2) })
                } else if (typed === "-" && row.kind === "paragraph") {
                    Qt.callLater(function() { if (input.text === "---") row.changeKind("divider") })
                } else if (typed === "*" || typed === "_" || typed === "`" || typed === "~") {
                    Qt.callLater(function() { const p = fmt.markdownAt(input.cursorPosition); if (p >= 0) input.cursorPosition = p })
                }
            }
            HoverHandler {
                id: textHover
                onPointChanged: row.updateTip(point.position)
                onHoveredChanged: if (!hovered) row.tip = ""
            }
            ToolTip {
                parent: input; delay: 450
                visible: textHover.hovered && !!row.tip && !input.selecting
                x: Math.min(textHover.point.position.x + 10, input.width - width)
                y: textHover.point.position.y + 20
                text: row.tip
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton; acceptedModifiers: Qt.ControlModifier
                onTapped: function(eventPoint) {
                    const link = input.linkAt(eventPoint.position.x,eventPoint.position.y)
                    if (link.indexOf("lunqio://page/") === 0) row.openPage(link.slice(14))
                    else if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link)
                }
            }
            // As in Notion, a page mention opens with a single click.
            TapHandler {
                acceptedButtons: Qt.LeftButton; acceptedModifiers: Qt.NoModifier
                onTapped: function(eventPoint) {
                    const link = input.linkAt(eventPoint.position.x,eventPoint.position.y)
                    if (link.indexOf("lunqio://page/") === 0) row.openPage(link.slice(14))
                }
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: function(eventPoint) {
                    const pos = input.positionAt(eventPoint.position.x,eventPoint.position.y)
                    if (pos < input.selectionStart || pos > input.selectionEnd || !input.selectedText) input.cursorPosition = pos
                    input.forceActiveFocus()
                    context.popup(input,eventPoint.position.x,eventPoint.position.y)
                }
            }
            Menu {
                id: context
                MenuItem { text: "Editar con IA…"; enabled: row.editable && !!input.selectedText; onTriggered: row.askAi() }
                MenuSeparator {}
                MenuItem { text: "Cortar"; enabled: row.editable && !!input.selectedText; onTriggered: { input.forceActiveFocus(); input.cut() } }
                MenuItem { text: "Copiar"; enabled: !!input.selectedText; onTriggered: input.copy() }
                MenuItem { text: "Pegar"; enabled: row.editable && (input.canPaste || backend.clipboardPhoto)
                    onTriggered: { input.forceActiveFocus(); if (!row.pastePhoto()) input.paste() } }
                MenuItem { text: "Seleccionar todo"; onTriggered: { input.forceActiveFocus(); input.selectAll() } }
            }
        }
    }
}
