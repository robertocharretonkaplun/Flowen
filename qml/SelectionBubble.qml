import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQml.Models
import Flowen

// Selection menu modelled on Notion's: it appears beside a text selection once the
// mouse is released (or the keyboard selection settles) and applies styles in place.
Rectangle {
    id: bubble
    property Item target: null        // focused block TextArea: exposes formatter, blockKind and selecting
    property Item viewport: null      // visible page area; the menu hides when the selection scrolls away
    property real scrollOffset: 0     // page scroll, only used to recompute the position
    property bool allowed: false
    signal kindChosen(string kind)
    signal aiRequested(string instruction)
    signal commentRequested()

    readonly property InlineEditor formatter: target ? target.formatter : null
    readonly property int styles: formatter ? formatter.activeStyles : 0
    readonly property string kind: target ? target.blockKind : "paragraph"
    readonly property int level: target && target.blockLevel ? target.blockLevel : 1
    readonly property var kindInfo: ({
        paragraph: {text: "Texto", mark: "T", glyph: "text"},
        heading: {text: "Encabezado " + level, mark: "H" + level, glyph: "heading"},
        list: {text: "Lista con viñetas", mark: "", glyph: "list"},
        numbered: {text: "Lista numerada", mark: "1.", glyph: "numbered"},
        task: {text: "Tarea", mark: "", glyph: "task"},
        toggle: {text: "Desplegable", mark: "", glyph: "toggle"},
        quote: {text: "Cita", mark: "❝", glyph: "quote"},
        callout: {text: "Nota destacada", mark: "!", glyph: "callout"},
        code: {text: "Código", mark: "</>", glyph: "code"}
    })[kind] || {text: "Texto", mark: "T", glyph: "text"}
    property string mode: "menu"      // menu | link
    property string linkError: ""
    property bool dismissed: false
    property bool settled: false
    readonly property bool menuOpen: turnMenu.opened || moreMenu.opened || colorPopup.opened
    // The palette leaves the focus in the text, so the window's Escape closes it (menus handle their own).
    readonly property bool paletteOpen: colorPopup.opened
    function closePalette() { colorPopup.close() }
    readonly property bool engaged: mode !== "menu" || menuOpen
    readonly property bool shown: allowed && !!formatter && settled && !dismissed && !target.selecting
                                   && (target.activeFocus || engaged) && placement.inView

    // Beside the end of the selection, like Notion. Without room on the right it drops
    // below the selection, or above it near the bottom of the window.
    readonly property var placement: {
        scrollOffset
        if (!target || !parent || !allowed) return {x: 0, y: 0, inView: false}
        const w = width, h = height, margin = 8, area = parent
        const first = target.positionToRectangle(target.selectionStart)
        const last = target.positionToRectangle(target.selectionEnd)
        target.width; target.contentHeight; area.width; area.height   // re-place on reflow or resize
        if (viewport) { viewport.width; viewport.height }
        const a = target.mapToItem(area,first.x,first.y), b = target.mapToItem(area,last.x,last.y)
        const top = viewport ? viewport.mapToItem(area,0,0).y : 0
        const bottom = viewport ? top + viewport.height : area.height
        const inView = b.y + last.height > top + 4 && b.y < bottom - 4
        let x = b.x + 16, y = b.y - 14
        if (x + w > area.width - margin) {
            x = Math.max(margin,Math.min(b.x - 40,area.width - w - margin))
            y = b.y + last.height + 10
            if (y + h > area.height - margin) y = a.y - h - 10
        }
        y = Math.max(top + margin,Math.min(y,area.height - h - margin))
        return {x: Math.round(x), y: Math.round(y), inView: inView}
    }

    function selectionMoved() {
        dismissed = false; settled = false; linkError = ""
        if (mode !== "menu") mode = "menu"
        settle.restart()
    }
    function refocus() { if (target) target.forceActiveFocus() }
    function back() { mode = "menu"; refocus() }
    function dismiss() { mode = "menu"; dismissed = true; turnMenu.close(); moreMenu.close(); refocus() }
    function toggle(style) { if (formatter) formatter.toggle(style) }
    function openLink() {
        if (!formatter) return
        dismissed = false; settled = true; linkError = ""
        linkField.text = formatter.activeLink
        mode = "link"
        linkField.forceActiveFocus(); linkField.selectAll()
    }
    function applyLink() {
        if (!formatter) return
        if (!formatter.setLink(linkField.text)) {
            linkError = "Escribe una dirección web válida, por ejemplo https://ejemplo.com"
            return
        }
        back()
    }
    // Comments are written in a card beside the text (see CommentRail); the menu steps aside.
    function openComment() {
        if (!formatter) return
        mode = "menu"; dismissed = true
        commentRequested()
    }

    onTargetChanged: selectionMoved()
    onAllowedChanged: if (!allowed && mode !== "menu") mode = "menu"
    Connections {
        target: bubble.target
        function onSelectionStartChanged() { bubble.selectionMoved() }
        function onSelectionEndChanged() { bubble.selectionMoved() }
    }
    Timer { id: settle; interval: 140; onTriggered: bubble.settled = true }

    x: placement.x; y: placement.y; z: 20
    width: 240; height: content.implicitHeight + 12
    radius: Theme.radiusPanel; color: Theme.surface; border.color: Theme.line
    visible: opacity > 0; enabled: shown
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.97
    transformOrigin: Item.TopLeft
    Behavior on opacity { enabled: bubble.shown; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Behavior on scale { enabled: bubble.shown; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

    // Soft drop shadow drawn with two translucent layers behind the panel.
    Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 2; anchors.bottomMargin: -5; radius: Theme.radiusPanel+1; color: Theme.shadow }
    Rectangle { z: -2; anchors.fill: parent; anchors.margins: -5; anchors.bottomMargin: -14; radius: Theme.radiusPanel+4; color: Theme.shadowSoft }
    // Keeps clicks on the panel from reaching the text underneath.
    MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons; onWheel: function(wheel) { wheel.accepted = false } }

    component Divider: Rectangle { Layout.fillWidth: true; Layout.topMargin: 5; Layout.bottomMargin: 5; implicitHeight: 1; color: Theme.hover }
    component MenuRow: AbstractButton {
        id: menuRow
        property string glyph: ""
        property string mark: ""
        property string trailing: ""
        property bool chevron: false
        property bool active: false
        Layout.fillWidth: true
        implicitHeight: 30; leftPadding: 8; rightPadding: 8
        focusPolicy: Qt.NoFocus; hoverEnabled: true
        Accessible.name: text
        background: Rectangle { radius: Theme.radiusButton; color: menuRow.down ? Theme.pressed : menuRow.hovered || menuRow.active ? Theme.raised : "transparent" }
        contentItem: RowLayout {
            spacing: 10
            Item {
                visible: !!menuRow.glyph || !!menuRow.mark; implicitWidth: 18; implicitHeight: 18
                Glyph { anchors.centerIn: parent; visible: !!menuRow.glyph; name: menuRow.glyph }
                Text { anchors.centerIn: parent; visible: !menuRow.glyph; text: menuRow.mark; color: Theme.secondary; font.pixelSize: 15; font.weight: Font.DemiBold }
            }
            Text { text: menuRow.text; color: Theme.text; font.pixelSize: 14; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { visible: !!menuRow.trailing; text: menuRow.trailing; color: Theme.muted; font.pixelSize: 12 }
            Glyph { visible: menuRow.chevron; name: "right"; font.pixelSize: 10; color: Theme.muted }
        }
    }
    component FormatButton: AbstractButton {
        id: formatButton
        property string glyph: ""
        property string hint: ""
        property bool active: false
        property bool heavy: false
        property bool slanted: false
        property bool lined: false
        property bool struck: false
        property bool swatch: false
        property bool mono: false
        readonly property color tint: active ? Theme.accent : Theme.textSoft
        implicitWidth: 44; implicitHeight: 32
        focusPolicy: Qt.NoFocus; hoverEnabled: true
        Accessible.name: hint
        Accessible.checkable: true
        Accessible.checked: active
        ToolTip.visible: hovered; ToolTip.text: hint; ToolTip.delay: 450
        background: Rectangle {
            radius: Theme.radiusButton
            color: formatButton.down ? Theme.pressed : formatButton.hovered ? Theme.hover : formatButton.active ? Theme.hover : "transparent"
        }
        contentItem: Item {
            Glyph { anchors.centerIn: parent; visible: !!formatButton.glyph; name: formatButton.glyph; color: formatButton.active ? Theme.accent : Theme.glyph; font.pixelSize: 15 }
            Text {
                id: letter
                anchors.centerIn: parent; anchors.verticalCenterOffset: formatButton.swatch ? -2 : 0
                visible: !formatButton.glyph; text: formatButton.text; textFormat: Text.RichText
                color: formatButton.tint; font.pixelSize: formatButton.mono ? 13 : 16
                font.family: formatButton.mono ? Theme.mono : Theme.family
                font.weight: formatButton.heavy ? Font.Bold : Font.Medium
                font.italic: formatButton.slanted; font.underline: formatButton.lined; font.strikeout: formatButton.struck
            }
            Rectangle {
                visible: formatButton.swatch; width: 13; height: 3; radius: 1.5; color: "#d6ab4a"
                anchors.horizontalCenter: parent.horizontalCenter; anchors.top: letter.bottom; anchors.topMargin: -1
            }
        }
    }

    ColumnLayout {
        id: content
        x: 6; y: 6; width: parent.width - 12
        spacing: 0
        ColumnLayout {
            visible: bubble.mode === "menu"
            Layout.fillWidth: true; spacing: 0
            MenuRow {
                id: turnRow; objectName: "bubbleTurnInto"
                text: bubble.kindInfo.text; glyph: bubble.kindInfo.glyph; mark: bubble.kindInfo.mark
                chevron: true; active: turnMenu.opened
                Accessible.name: "Convertir bloque. Ahora: " + bubble.kindInfo.text
                onClicked: turnMenu.popup(turnRow,turnRow.width + 8,-6)
            }
            Divider {}
            GridLayout {
                columns: 5; rowSpacing: 2; columnSpacing: 2
                Layout.alignment: Qt.AlignHCenter
                FormatButton { objectName: "formatHighlight"; glyph: "highlight"; hint: "Resaltar (Ctrl+Shift+H)"
                    active: bubble.styles & InlineEditor.Highlight; onClicked: bubble.toggle(InlineEditor.Highlight) }
                FormatButton { objectName: "formatBold"; glyph: "bold"; hint: "Negrita (Ctrl+B)"
                    active: bubble.styles & InlineEditor.Bold; onClicked: bubble.toggle(InlineEditor.Bold) }
                FormatButton { objectName: "formatItalic"; glyph: "italic"; hint: "Cursiva (Ctrl+I)"
                    active: bubble.styles & InlineEditor.Italic; onClicked: bubble.toggle(InlineEditor.Italic) }
                FormatButton { objectName: "formatUnderline"; glyph: "underline"; hint: "Subrayado (Ctrl+U)"
                    active: bubble.styles & InlineEditor.Underline; onClicked: bubble.toggle(InlineEditor.Underline) }
                FormatButton { objectName: "formatClear"; text: "T<sub>x</sub>"; hint: "Quitar formato"
                    onClicked: if (bubble.formatter) bubble.formatter.clearStyles() }
                FormatButton { objectName: "formatLink"; glyph: "link"; hint: "Enlace (Ctrl+K)"
                    active: !!bubble.formatter && !!bubble.formatter.activeLink; onClicked: bubble.openLink() }
                FormatButton { objectName: "formatStrike"; glyph: "strike"; hint: "Tachado (Ctrl+Shift+X)"
                    active: bubble.styles & InlineEditor.Strike; onClicked: bubble.toggle(InlineEditor.Strike) }
                FormatButton { objectName: "formatCode"; glyph: "code"; hint: "Código en línea (Ctrl+E)"
                    active: bubble.styles & InlineEditor.Code; onClicked: bubble.toggle(InlineEditor.Code) }
                FormatButton { objectName: "formatSuperscript"; text: "x²"; hint: "Superíndice"
                    active: bubble.styles & InlineEditor.Superscript; onClicked: bubble.toggle(InlineEditor.Superscript) }
                FormatButton { id: moreButton; objectName: "formatMore"; glyph: "more"; hint: "Más acciones"
                    active: moreMenu.opened; onClicked: moreMenu.popup(moreButton,0,moreButton.height + 4) }
            }
            Divider {}
            // Colour of the selected text or behind it, from the palette of the theme (as in Notion).
            MenuRow {
                id: colorRow; objectName: "bubbleColor"; glyph: "palette"; text: "Color"
                chevron: true; active: colorPopup.opened
                onClicked: colorPopup.open()
                Popup {
                    id: colorPopup; objectName: "colorPopup"
                    x: colorRow.width+8; y: -8; width: 232; padding: 10
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                    background: Rectangle {
                        radius: Theme.radiusPanel; color: Theme.surface; border.color: Theme.line
                        Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 2; anchors.bottomMargin: -5; radius: Theme.radiusPanel+1; color: Theme.shadow }
                    }
                    contentItem: ColumnLayout {
                        spacing: 6
                        Repeater {
                            model: [{role: "color", title: "Color del texto"}, {role: "background", title: "Fondo"}]
                            delegate: ColumnLayout {
                                id: group
                                required property var modelData
                                spacing: 4
                                Text { text: group.modelData.title; color: Theme.muted; font.pixelSize: 12 }
                                Grid {
                                    columns: 5; spacing: 4
                                    Repeater {
                                        model: [""].concat(Theme.toneNames)
                                        delegate: AbstractButton {
                                            id: swatch
                                            required property string modelData
                                            readonly property bool forText: group.modelData.role === "color"
                                            readonly property bool current: !!bubble.formatter &&
                                                (forText ? bubble.formatter.activeColor : bubble.formatter.activeBackground) === modelData
                                            objectName: (forText ? "textTone-" : "backTone-") + (modelData || "none")
                                            width: 38; height: 30; hoverEnabled: true; focusPolicy: Qt.NoFocus
                                            Accessible.name: (forText ? "Texto " : "Fondo ") + (modelData ? Theme.toneLabels[modelData] : "predeterminado")
                                            ToolTip.visible: hovered; ToolTip.delay: 400
                                            ToolTip.text: modelData ? Theme.toneLabels[modelData] : (forText ? "Predeterminado" : "Sin fondo")
                                            onClicked: if (bubble.formatter) {
                                                if (forText) bubble.formatter.setColor(modelData); else bubble.formatter.setBackground(modelData)
                                            }
                                            background: Rectangle {
                                                radius: 6
                                                color: !swatch.forText && swatch.modelData ? Theme.tones[swatch.modelData][1] : swatch.hovered ? Theme.hover : "transparent"
                                                border.width: swatch.current ? 2 : 1
                                                border.color: swatch.current ? Theme.accent : swatch.hovered || !swatch.forText ? Theme.line : "transparent"
                                            }
                                            contentItem: Text {
                                                text: swatch.forText ? "A" : (swatch.modelData ? "" : "∅")
                                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                                font.pixelSize: 15; font.weight: Font.DemiBold
                                                color: swatch.forText && swatch.modelData ? Theme.tones[swatch.modelData][0] : Theme.secondary
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            MenuRow {
                objectName: "bubbleComment"; glyph: "comment"
                text: !!bubble.formatter && !!bubble.formatter.activeThread ? "Ver comentario" : "Comentar"
                onClicked: bubble.openComment()
            }
            Divider {}
            Text { text: "Acciones de IA"; color: Theme.muted; font.pixelSize: 12; Layout.leftMargin: 8; Layout.topMargin: 1; Layout.bottomMargin: 3 }
            MenuRow { glyph: "improve"; text: "Mejorar redacción"; onClicked: bubble.aiRequested("Mejora la redacción conservando el significado.") }
            MenuRow { glyph: "proofread"; text: "Corregir ortografía"; onClicked: bubble.aiRequested("Corrige la ortografía y la gramática.") }
            MenuRow { glyph: "shrink"; text: "Acortar"; onClicked: bubble.aiRequested("Acorta el texto conservando las ideas principales.") }
            Divider {}
            MenuRow { objectName: "bubbleWriting"; glyph: "sparkles"; text: "Editar con IA"; trailing: "Ctrl+Shift+I"; onClicked: bubble.aiRequested("") }
        }
        ColumnLayout {
            visible: bubble.mode === "link"
            Layout.fillWidth: true; Layout.margins: 6; spacing: 8
            Text { text: "Enlace"; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
            TextField {
                id: linkField; objectName: "bubbleLinkField"
                Layout.fillWidth: true; maximumLength: 2048; selectByMouse: true
                placeholderText: "Pega o escribe una dirección web"; Accessible.name: "Dirección del enlace"
                onAccepted: bubble.applyLink()
                onTextChanged: bubble.linkError = ""
            }
            Text { visible: !!bubble.linkError; text: bubble.linkError; color: Theme.danger; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
            RowLayout {
                Layout.fillWidth: true
                UiButton { visible: !!bubble.formatter && !!bubble.formatter.activeLink; quiet: true; text: "Quitar"; focusPolicy: Qt.NoFocus
                    onClicked: { bubble.formatter.setLink(""); bubble.back() } }
                Item { Layout.fillWidth: true }
                UiButton { primary: true; text: "Aplicar"; focusPolicy: Qt.NoFocus; enabled: !!linkField.text.trim(); onClicked: bubble.applyLink() }
            }
        }
    }

    UiMenu {
        id: turnMenu
        onClosed: bubble.refocus()
        Instantiator {
            onObjectAdded: function(index, object) { turnMenu.insertItem(index,object) }
            onObjectRemoved: function(index, object) { turnMenu.removeItem(object) }
            model: [{key: "paragraph", text: "Texto"},{key: "heading1", text: "Encabezado 1"},{key: "heading2", text: "Encabezado 2"},
                    {key: "heading3", text: "Encabezado 3"},{key: "list", text: "Lista con viñetas"},{key: "numbered", text: "Lista numerada"},
                    {key: "task", text: "Tarea"},{key: "toggle", text: "Desplegable"},{key: "quote", text: "Cita"},
                    {key: "callout", text: "Nota destacada"},{key: "code", text: "Código"}]
            delegate: UiMenuItem {
                required property var modelData
                text: modelData.text; checkable: true
                checked: modelData.key === bubble.kind || modelData.key === "heading" + bubble.level && bubble.kind === "heading"
                onTriggered: bubble.kindChosen(modelData.key)
            }
        }
    }
    UiMenu {
        id: moreMenu
        onClosed: bubble.refocus()
        UiMenuItem { glyph: "copy"; text: "Copiar    Ctrl+C"; onTriggered: if (bubble.target) bubble.target.copy() }
        UiMenuItem { text: "Cortar    Ctrl+X"; enabled: !!bubble.target && !bubble.target.readOnly; onTriggered: bubble.target.cut() }
        UiMenuSeparator {}
        UiMenuItem { text: "Quitar enlace"; enabled: !!bubble.formatter && !!bubble.formatter.activeLink; onTriggered: bubble.formatter.setLink("") }
        UiMenuItem {
            text: "Quitar comentario"; enabled: !!bubble.formatter && !!bubble.formatter.activeComment
            onTriggered: bubble.formatter.activeThread ? bubble.formatter.removeComment(bubble.formatter.activeThread) : bubble.formatter.setComment("")
        }
    }
}
