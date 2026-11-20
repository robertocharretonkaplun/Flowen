import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// One comment thread as a card: author, time, resolve, menu, replies and a reply field.
Rectangle {
    id: card
    property var thread: ({})          // {id, text, author, at, resolved, replies}
    property bool draft: false          // a new comment being written
    property bool active: false
    property string me: ""              // the person writing now
    property real anchorY: 0
    property bool editing: false
    signal activate()
    signal reply(string text)
    signal resolve(bool value)
    signal edit(string text)
    signal remove()
    signal removeReply(int index)
    signal submit(string text)
    signal cancel()
    signal rename()

    function initials(name) {
        const words = (name || "").trim().split(/\s+/).filter(w => w)
        if (!words.length) return "?"
        return (words[0][0] + (words.length > 1 ? words[words.length-1][0] : "")).toUpperCase()
    }
    function tint(name) {
        const colors = ["#5b7fa6","#7a6aa8","#3f8f7a","#a8734f","#a0577a","#6b8f3f","#4f86a8"]
        let h = 0
        for (let i = 0; i < (name || "").length; ++i) h = (h*31 + name.charCodeAt(i)) % 9973
        return name ? colors[h % colors.length] : Theme.line
    }
    function when(iso) {
        if (!iso) return ""
        const d = new Date(iso)
        if (isNaN(d.getTime())) return ""
        const now = new Date()
        const days = Math.round((new Date(now.getFullYear(),now.getMonth(),now.getDate()) - new Date(d.getFullYear(),d.getMonth(),d.getDate()))/86400000)
        const time = Qt.formatTime(d,"HH:mm")
        if (days === 0) return time + " Hoy"
        if (days === 1) return time + " Ayer"
        return Qt.formatDate(d,"d MMM") + (d.getFullYear() !== now.getFullYear() ? " " + d.getFullYear() : "")
    }
    // Plain text with clickable web addresses.
    function rich(text) {
        const safe = (text || "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")
        return safe.replace(/(https?:\/\/[^\s<]+)/g,'<a href="$1">$1</a>').replace(/\n/g,"<br>")
    }
    function open(link) { if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link) }
    function startEdit() { editing = true; field.text = thread.text || ""; field.forceActiveFocus(); field.selectAll() }
    function focusDraft() { field.text = ""; field.forceActiveFocus() }
    function send() {
        const text = field.text.trim()
        if (!text) return
        if (draft) submit(text); else { edit(text); editing = false }
    }

    width: parent ? parent.width : 300
    height: body.implicitHeight + 28
    radius: 12
    color: active || draft ? Theme.raised : Theme.surface
    border.color: active || draft ? Theme.line : Theme.hover
    Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Rectangle { visible: card.active || card.draft; z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 2; anchors.bottomMargin: -5; radius: 14; color: Theme.shadow }
    TapHandler { onTapped: card.activate() }

    component Avatar: Rectangle {
        property string name: ""
        property int size: 32
        implicitWidth: size; implicitHeight: size; radius: size/2
        color: card.tint(name)
        Label { anchors.centerIn: parent; text: card.initials(parent.name); color: Theme.text; font.pixelSize: Math.round(parent.size*0.4); font.weight: Font.DemiBold }
    }
    component Pill: TextField {
        id: pill
        Layout.fillWidth: true; selectByMouse: true; maximumLength: 1024
        font.pixelSize: 13; color: Theme.text; placeholderTextColor: Theme.muted
        leftPadding: 14; rightPadding: 14; topPadding: 9; bottomPadding: 9
        background: Rectangle { radius: 18; color: Theme.base; border.color: pill.activeFocus ? Theme.focus : Theme.line }
    }

    ColumnLayout {
        id: body
        x: 14; y: 14; width: parent.width-28
        spacing: 10
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Avatar { name: card.draft ? card.me : card.thread.author }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 1
                Label {
                    Layout.fillWidth: true; elide: Text.ElideRight
                    text: card.draft ? card.me : (card.thread.author || "Comentario")
                    font.pixelSize: 14; font.weight: Font.DemiBold; color: Theme.text
                }
                Label {
                    visible: !!text; Layout.fillWidth: true
                    text: card.draft ? "" : card.thread.resolved ? "Resuelto · " + card.when(card.thread.at) : card.when(card.thread.at)
                    font.pixelSize: 12; color: Theme.muted
                }
            }
            AbstractButton {
                objectName: "commentResolve"
                visible: !card.draft && !card.thread.resolved
                implicitWidth: 30; implicitHeight: 30; hoverEnabled: true; focusPolicy: Qt.NoFocus
                Accessible.name: "Resolver comentario"
                ToolTip.visible: hovered; ToolTip.delay: 450; ToolTip.text: "Marcar como resuelto y ocultar"
                onClicked: card.resolve(true)
                background: Rectangle { radius: 15; color: parent.down ? Theme.pressed : parent.hovered ? Theme.hover : "transparent" }
                contentItem: Glyph { name: "check"; color: Theme.accent; font.pixelSize: 16 }
            }
            UiButton {
                visible: !card.draft && !!card.thread.resolved
                text: "Reabrir"; quiet: true; focusPolicy: Qt.NoFocus; onClicked: card.resolve(false)
            }
            UiButton {
                visible: !card.draft
                symbol: "more"; quiet: true; hint: "Más opciones del comentario"; focusPolicy: Qt.NoFocus
                Layout.preferredWidth: 30
                onClicked: menu.popup()
                UiMenu {
                    id: menu
                    UiMenuItem { text: "Editar"; onTriggered: card.startEdit() }
                    UiMenuItem { text: "Eliminar"; onTriggered: card.remove() }
                    UiMenuSeparator {}
                    UiMenuItem { text: "Cambiar mi nombre…"; onTriggered: card.rename() }
                }
            }
        }
        Text {
            visible: !card.draft && !card.editing
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: card.rich(card.thread.text); textFormat: Text.StyledText
            color: Theme.text; linkColor: Theme.accent; font.pixelSize: 14; lineHeight: 1.15
            onLinkActivated: function(link) { card.open(link) }
            HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        TextArea {
            id: field; objectName: card.draft ? "commentDraftField" : "commentEditField"
            visible: card.draft || card.editing
            Layout.fillWidth: true; wrapMode: TextEdit.Wrap; selectByMouse: true
            placeholderText: "Comentar…"; placeholderTextColor: Theme.muted
            font.pixelSize: 14; color: Theme.text; leftPadding: 12; rightPadding: 12; topPadding: 9; bottomPadding: 9
            background: Rectangle { radius: Theme.radiusPanel; color: Theme.base; border.color: field.activeFocus ? Theme.focus : Theme.line }
            Keys.onReturnPressed: function(event) {
                if (event.modifiers & Qt.ShiftModifier) { event.accepted = false; return }
                event.accepted = true; card.send()
            }
            Keys.onEscapePressed: function(event) {
                event.accepted = true
                if (card.draft) card.cancel(); else card.editing = false
            }
        }
        RowLayout {
            visible: card.draft || card.editing
            Layout.fillWidth: true; spacing: 8
            Item { Layout.fillWidth: true }
            UiButton { text: "Cancelar"; quiet: true; onClicked: card.draft ? card.cancel() : (card.editing = false) }
            UiButton { objectName: "commentSend"; text: card.draft ? "Comentar" : "Guardar"; primary: true; enabled: !!field.text.trim(); onClicked: card.send() }
        }
        Repeater {
            model: card.draft ? [] : (card.thread.replies || [])
            delegate: ColumnLayout {
                id: answer
                required property var modelData
                required property int index
                Layout.fillWidth: true; Layout.topMargin: 4; spacing: 6
                HoverHandler { id: answerHover }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Avatar { name: answer.modelData.author; size: 26 }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        Label { text: answer.modelData.author || "Respuesta"; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: card.when(answer.modelData.at); font.pixelSize: 11; color: Theme.muted; visible: !!text }
                    }
                    UiButton {
                        visible: answerHover.hovered; symbol: "trash"; quiet: true; hint: "Eliminar respuesta"; focusPolicy: Qt.NoFocus
                        Layout.preferredWidth: 28; onClicked: card.removeReply(answer.index)
                    }
                }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: card.rich(answer.modelData.text); textFormat: Text.StyledText
                    color: Theme.text; linkColor: Theme.accent; font.pixelSize: 14
                    onLinkActivated: function(link) { card.open(link) }
                }
            }
        }
        Pill {
            id: replyField; objectName: "commentReply"
            visible: !card.draft && !card.editing && !card.thread.resolved && (card.active || !!text)
            placeholderText: "Responder…"
            Accessible.name: "Responder al comentario"
            onActiveFocusChanged: if (activeFocus) card.activate()
            onAccepted: if (text.trim()) { card.reply(text); text = "" }
            Keys.onEscapePressed: function(event) { event.accepted = true; text = "" }
        }
    }
}
