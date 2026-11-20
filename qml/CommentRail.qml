import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The page's comment cards, each next to the text it is about. When the window is too
// narrow for a margin column, only the open card floats over the right edge.
Item {
    id: rail
    property var threads: []
    property var draft: null              // {index, start, end} while a new comment is written
    property string activeId: ""
    property bool showResolved: false
    property bool floating: false
    property string me: ""
    property var anchorFor: function(index, start) { return 0 }
    property real contentBottom: 0
    signal activate(string id)
    signal reply(var thread, string text)
    signal resolve(var thread, bool value)
    signal edit(var thread, string text)
    signal remove(var thread)
    signal removeReply(var thread, int index)
    signal submitDraft(string text)
    signal cancelDraft()
    signal rename()
    readonly property int resolvedCount: threads.filter(t => t.resolved).length
    readonly property var shown: threads.filter(t => (showResolved || !t.resolved) && (!floating || t.id === activeId))
    visible: shown.length > 0 || !!draft || (!floating && resolvedCount > 0)
    function schedule() { relayout.restart() }
    // Cards sit at their text; when they would overlap, later ones move down. The open card wins its place.
    function layout() {
        const items = []
        for (let i = 0; i < cards.count; ++i) {
            const c = cards.itemAt(i)
            if (!c) continue
            c.anchorY = anchorFor(c.thread.index,c.thread.start)
            items.push(c)
        }
        if (draft) { draftCard.anchorY = anchorFor(draft.index,draft.start); items.push(draftCard) }
        items.sort((a,b) => a.anchorY - b.anchorY)
        const top = header.visible ? header.height + 8 : 0
        const lead = items.findIndex(c => c.draft || c.thread.id === activeId)
        let bottom = top
        const placed = []
        for (const c of items) { const y = Math.max(c.anchorY - 6,bottom); placed.push(y); bottom = y + c.height + 10 }
        if (lead > 0) {
            // Pull the open card up to its text and push the earlier ones above it.
            placed[lead] = Math.max(top,items[lead].anchorY - 6)
            for (let i = lead-1; i >= 0; --i) placed[i] = Math.min(placed[i],placed[i+1] - items[i].height - 10)
            for (let i = lead+1; i < items.length; ++i) placed[i] = Math.max(items[i].anchorY - 6,placed[i-1] + items[i-1].height + 10)
        }
        for (let i = 0; i < items.length; ++i) items[i].y = placed[i]
        contentBottom = items.length ? placed[items.length-1] + items[items.length-1].height : top
    }
    onThreadsChanged: schedule()
    // Take the keyboard at once so no keystroke lands in the page text.
    onDraftChanged: {
        schedule()
        if (!draft) return
        draftCard.visible = true
        draftCard.focusDraft()
    }
    onActiveIdChanged: schedule()
    onShowResolvedChanged: schedule()
    onFloatingChanged: schedule()
    Timer { id: relayout; interval: 0; onTriggered: rail.layout() }

    RowLayout {
        id: header
        visible: !rail.floating && rail.resolvedCount > 0
        width: parent.width; spacing: 6
        Label { text: rail.resolvedCount + (rail.resolvedCount === 1 ? " comentario resuelto" : " comentarios resueltos"); color: Theme.muted; font.pixelSize: 12; Layout.fillWidth: true }
        UiButton { text: rail.showResolved ? "Ocultar" : "Mostrar"; quiet: true; focusPolicy: Qt.NoFocus; onClicked: rail.showResolved = !rail.showResolved }
    }
    Repeater {
        id: cards
        model: rail.shown
        delegate: CommentCard {
            required property var modelData
            thread: modelData; me: rail.me; width: rail.width
            active: modelData.id === rail.activeId
            onHeightChanged: rail.schedule()
            onActivate: rail.activate(modelData.id)
            onReply: function(text) { rail.reply(modelData,text) }
            onResolve: function(value) { rail.resolve(modelData,value) }
            onEdit: function(text) { rail.edit(modelData,text) }
            onRemove: rail.remove(modelData)
            onRemoveReply: function(i) { rail.removeReply(modelData,i) }
            onRename: rail.rename()
        }
    }
    CommentCard {
        id: draftCard; objectName: "commentDraft"
        visible: false; draft: true; me: rail.me; width: rail.width
        Connections { target: rail; function onDraftChanged() { if (!rail.draft) draftCard.visible = false } }
        onHeightChanged: rail.schedule()
        onSubmit: function(text) { rail.submitDraft(text) }
        onCancel: rail.cancelDraft()
    }
}
