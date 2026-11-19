import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs as Native

ApplicationWindow {
    id: win
    width: 1240; height: 800; minimumWidth: 780; minimumHeight: 520
    visible: true; title: "Lunqio"
    color: "#191919"; font.family: "Segoe UI"; font.pixelSize: 14
    palette.window: "#242425"; palette.windowText: "#efedef"; palette.text: "#efedef"
    palette.base: "#1e1e20"; palette.button: "#272729"; palette.buttonText: "#e7e6e8"
    palette.light: "#38383b"; palette.midlight: "#404044"; palette.mid: "#414144"; palette.dark: "#333336"
    palette.highlight: "#355478"; palette.highlightedText: "#ffffff"; palette.placeholderText: "#a5a2a9"
    property bool sidebarShown: true
    property int sidebarPreferredWidth: 0
    property bool pagesExpanded: true
    property var textTarget: null
    property int editIndex: -1
    property bool loadingPage: false
    readonly property bool settingsShown: workspaceTabs.currentIndex !== 0
    property bool resumeWriting: false
    readonly property var assistant: backend.assistant
    readonly property bool canEditSelection: !settingsShown && !!currentId && !deleted && !conflict && !!textTarget && editIndex >= 0 && !!textTarget.selectedText
    readonly property bool canFormat: canEditSelection && !!textTarget.formatter
    menuBar: WorkspaceMenus { workspace: win }
    function format(style) { if (canFormat) textTarget.formatter.toggle(style) }
    function editLink() { if (canFormat) bubble.openLink() }
    // value is a block type, or "heading1".."heading3" for a heading of that size.
    function setKind(index, value) {
        if (index < 0 || index >= blocks.count) return
        let kind = value, level = 0
        if (/^heading[1-3]$/.test(value)) { kind = "heading"; level = Number(value.charAt(7)) }
        blocks.setProperty(index,"kind",kind)
        if (level) blocks.setProperty(index,"level",level)
        if (kind !== "task") blocks.setProperty(index,"done",false)
        if (kind === "callout" && !blocks.get(index).icon) blocks.setProperty(index,"icon","💡")
        if (kind === "divider") { blocks.setProperty(index,"body",""); blocks.setProperty(index,"spans","[]") }
        markDirty()
    }
    // The page's look: an emoji icon and a cover (a gradient by name, or a photo of the library).
    property string pageIcon: ""
    property string pageCover: ""
    readonly property var covers: ({aurora: ["#1f3b5a","#5b3a6e"], atardecer: ["#c8654a","#e8a764"], bosque: ["#1e4b3f","#5f9a6d"],
                                    oceano: ["#1b5f7d","#58a9c2"], noche: ["#151d2e","#2f405f"], arena: ["#a87e62","#d8b285"],
                                    menta: ["#2f8f7a","#2b5c8f"], niebla: ["#4d555e","#8d97a1"]})
    function setPageIcon(emoji) { if (currentId && !deleted) action("update_page",{icon: emoji ? emoji : null}) }
    function setPageCover(value) { if (currentId && !deleted) action("update_page",{cover: value ? value : null}) }
    // Numbers for numbered lists and what closed toggles hide, recomputed on every edit.
    property int structure: 0
    readonly property var outline: {
        structure; blocks.count
        const out = [], counters = [0,0,0,0,0,0,0,0]
        let hideBelow = -1
        for (let i = 0; i < blocks.count; ++i) {
            const b = blocks.get(i), indent = b.indent || 0
            if (hideBelow >= 0 && indent <= hideBelow) hideBelow = -1
            const hidden = hideBelow >= 0
            for (let d = indent+1; d < counters.length; ++d) counters[d] = 0
            let number = 0
            if (b.kind === "numbered") number = ++counters[indent]; else counters[indent] = 0
            const next = i+1 < blocks.count ? (blocks.get(i+1).indent || 0) : -1
            out.push({number: number, hidden: hidden, parent: next > indent})
            if (!hidden && b.kind === "toggle" && b.collapsed) hideBelow = indent
        }
        return out
    }
    // Tab nests a block under the one above (one level deeper at most); Shift+Tab brings it back.
    function setIndent(index, step) {
        if (index < 0 || index >= blocks.count) return
        const current = blocks.get(index).indent || 0
        const limit = index > 0 ? Math.min(6,(blocks.get(index-1).indent || 0)+1) : 0
        const next = Math.max(0,Math.min(limit,current+step))
        if (next === current) return
        blocks.setProperty(index,"indent",next)
        markDirty(); commentTick++
    }
    function toggleCollapse(index) {
        if (index < 0 || index >= blocks.count) return
        blocks.setProperty(index,"collapsed",!blocks.get(index).collapsed)
        markDirty(); commentTick++
    }
    function remember(input, index) {
        if (textTarget && textTarget !== input) textTarget.deselect()
        textTarget = input; editIndex = index
    }
    function textCommand(name) {
        if (textTarget) { textTarget.forceActiveFocus(); textTarget[name]() }
    }
    function focusSearch() { enterEditor(); sidebarShown = true; pagesExpanded = true; search.forceActiveFocus(); search.selectAll() }
    function openHelp() { helpDialog.open() }
    function openAbout() { aboutDialog.open() }
    function openConnection() { workspaceTabs.currentIndex = 1 }
    function enterEditor() {
        if (resumeWriting) { resumeWriting = false; assistant.cancel() }
        workspaceTabs.currentIndex = 0
    }
    function openTrashConfirmation() { trashDialog.open() }
    function choosePhoto() { if (currentId && !deleted && flush()) photoDialog.open() }
    function insertPhoto(url) {
        if (!action("insert_photo",{url:url.toString()})) return false
        Qt.callLater(function() { if (pageScroll.contentItem) pageScroll.contentItem.contentY = Math.max(0,pageScroll.contentHeight-pageScroll.availableHeight) })
        return true
    }
    function openHistory() {
        if (!flush()) return
        const r = call("history",{id:currentId})
        if (r) { historyRows = r.rows; historyDialog.open() }
    }
    function browseTrash(trashed) {
        if (!flush()) return
        enterEditor()
        info(""); search.clear(); pagesExpanded = true; trashMode = trashed; refreshNavigation()
        showPage(trashed && navigationRows.length ? navigationRows[0].page.id : "")
    }
    // Comment threads of the open page, gathered from each block for the comment cards.
    property int commentTick: 0
    property string activeComment: ""
    property var commentDraft: null
    readonly property var pageComments: {
        commentTick; blocks.count
        const out = []
        for (let i = 0; i < blocks.count; ++i) {
            const row = blockRepeater.itemAt(i)
            if (!row || !row.formatter || row.kind === "image") continue
            for (const thread of row.formatter.comments()) { thread.index = i; out.push(thread) }
        }
        return out
    }
    function startCommentDraft() {
        if (!canFormat) return
        const existing = textTarget.formatter.activeThread
        if (existing) { activeComment = existing; return }
        commentDraft = {index: editIndex, start: textTarget.selectionStart, end: textTarget.selectionEnd}
        activeComment = ""
    }
    function finishCommentDraft(text) {
        const draft = commentDraft
        const row = draft ? blockRepeater.itemAt(draft.index) : null
        commentDraft = null
        if (!row || !row.formatter) return
        const id = row.formatter.addComment(draft.start,draft.end,text,backend.author)
        if (id) activeComment = id
    }
    function cancelCommentDraft() {
        const draft = commentDraft
        commentDraft = null
        const row = draft ? blockRepeater.itemAt(draft.index) : null
        if (row) row.focusEditor()
    }
    function commentAction(thread, name, value) {
        const row = blockRepeater.itemAt(thread.index)
        if (!row || !row.formatter || deleted) return
        const f = row.formatter
        if (name === "reply") f.reply(thread.id,value,backend.author)
        else if (name === "resolve") { f.setResolved(thread.id,value); if (value && activeComment === thread.id) activeComment = "" }
        else if (name === "edit") f.editComment(thread.id,value)
        else if (name === "remove") { f.removeComment(thread.id); if (activeComment === thread.id) activeComment = "" }
        else if (name === "removeReply") f.removeReply(thread.id,value)
    }
    // Writing like Notion: blocks split on Enter, join on Backspace, and are chosen or moved with "/" and ⋮⋮.
    property var slash: null            // {index, start} while the "/" menu is open
    property int dragFrom: -1
    property int dropAt: -1
    property real dropY: 0
    property real dropX: 0
    function insertBlock(index, kind, text, styles, caret, after, indent) {
        blocks.insert(index,{key:"",kind:"paragraph",body:text || "",spans:styles || "[]",done:false,asset:"",photoPercent:100,
                             level:1,indent:indent || 0,icon:"",collapsed:false})
        setKind(index,kind)
        commentTick++
        Qt.callLater(function() {
            const row = blockRepeater.itemAt(index)
            if (!row) return
            row.focusAt(caret === undefined ? -1 : caret)
            if (after) after(row)
        })
    }
    function splitBlock(index, position) {
        const block = blocks.get(index), row = blockRepeater.itemAt(index)
        if (!row || block.kind === "image") return
        const listLike = block.kind === "list" || block.kind === "numbered" || block.kind === "task"
        // An empty list item leaves the list (first its nesting), as in Notion.
        if (listLike && !block.body.trim()) { if (block.indent > 0) setIndent(index,-1); else setKind(index,"paragraph"); return }
        const tail = row.formatter.takeTail(position)
        // Lists continue; an open toggle gets its first child; everything else continues as text.
        const child = block.kind === "toggle" && !block.collapsed
        insertBlock(index+1,listLike ? block.kind : "paragraph",tail.text,tail.spans,0,undefined,(block.indent || 0)+(child ? 1 : 0))
    }
    function mergeBlock(index) {
        if (index <= 0) return
        const current = blockRepeater.itemAt(index), previous = blockRepeater.itemAt(index-1)
        if (!current || !previous) return
        textTarget = null; editIndex = -1
        if (blocks.get(index-1).kind === "divider") {
            blocks.remove(index-1); markDirty(); commentTick++
            Qt.callLater(function() { const row = blockRepeater.itemAt(index-1); if (row) row.focusAt(0) })
            return
        }
        if (blocks.get(index-1).kind === "image") {
            if (!current.formatter.text()) { blocks.remove(index); markDirty(); commentTick++ }
            Qt.callLater(function() { const row = blockRepeater.itemAt(index-1); if (row) row.focusEditor() })
            return
        }
        const at = previous.formatter.append(current.formatter.text(),current.formatter.spans())
        blocks.remove(index); markDirty(); commentTick++
        Qt.callLater(function() { const row = blockRepeater.itemAt(index-1); if (row) row.focusAt(at) })
    }
    function navigateBlock(index, direction) {
        for (let i = index+direction; i >= 0 && i < blocks.count; i += direction) {
            if (blocks.get(i).kind === "image") continue
            blockRepeater.itemAt(i).focusAt(direction < 0 ? -1 : 0)
            return
        }
        if (direction < 0) { titleInput.forceActiveFocus(); titleInput.cursorPosition = titleInput.length }
    }
    function addBlockBelow(index) {
        insertBlock(index+1,"paragraph","","[]",0,function(row) { row.editor.insert(0,"/"); win.openSlash(index+1,0) })
    }
    function openSlash(index, start) { slashMenu.query = ""; slash = {index: index, start: start} }
    function closeSlash() { slash = null }
    function updateSlash() {
        if (!slash) return
        const row = blockRepeater.itemAt(slash.index)
        if (!row || !row.editor.activeFocus) { slash = null; return }
        const editor = row.editor, position = editor.cursorPosition
        if (position <= slash.start || editor.getText(slash.start,slash.start+1) !== "/") { slash = null; return }
        const query = editor.getText(slash.start+1,position)
        if (query.length > 30 || /\n|\s\s/.test(query)) { slash = null; return }
        slashMenu.query = query
        if (!slashMenu.matches.length && /\s$/.test(query)) slash = null
    }
    function slashKey(key) {
        if (key === Qt.Key_Up) slashMenu.move(-1)
        else if (key === Qt.Key_Down) slashMenu.move(1)
        else if (key === Qt.Key_Escape) closeSlash()
        else runSlash(slashMenu.current())
    }
    function runSlash(command) {
        const open = slash
        slash = null
        if (!open || !command) return
        const row = blockRepeater.itemAt(open.index)
        if (!row) return
        row.editor.remove(open.start,Math.max(open.start+1,row.editor.cursorPosition))
        const empty = !row.formatter.text().trim()
        if (command.key === "image") choosePhoto()
        else if (command.key === "ai") openComposer(open.index)
        else if (command.key === "divider") { if (empty) setKind(open.index,"divider"); else insertBlock(open.index+1,"divider","","[]",0); insertBlock(open.index+(empty ? 1 : 2),"paragraph","","[]",0) }
        else if (empty) { setKind(open.index,command.key); row.focusAt(0) }
        else insertBlock(open.index+1,command.key,"","[]",0,undefined,blocks.get(open.index).indent || 0)
    }
    // Dragging by ⋮⋮: a blue line marks where the block will land; the page scrolls near its edges.
    function dragMove(sceneY) {
        if (dragFrom < 0) return
        const area = pageScroll.mapToItem(null,0,0), flick = pageScroll.contentItem
        if (sceneY < area.y+48) flick.contentY = Math.max(0,flick.contentY-14)
        else if (sceneY > area.y+pageScroll.height-48) flick.contentY = Math.min(Math.max(0,pageScroll.contentHeight-pageScroll.height),flick.contentY+14)
        let target = blocks.count
        for (let i = 0; i < blocks.count; ++i) {
            const row = blockRepeater.itemAt(i), top = row.mapToItem(null,0,0).y
            if (sceneY < top+row.height/2) { target = i; break }
        }
        dropAt = target
        const edge = target < blocks.count ? blockRepeater.itemAt(target) : blockRepeater.itemAt(blocks.count-1)
        const corner = edge.mapToItem(win.contentItem,0,0)
        dropY = target < blocks.count ? corner.y-5 : corner.y+edge.height+3
        dropX = corner.x
    }
    function dragEnd() {
        const from = dragFrom, to = dropAt > dragFrom ? dropAt-1 : dropAt
        dragFrom = -1; dropAt = -1
        if (from < 0 || to < 0 || to === from) return
        textTarget = null; editIndex = -1
        blocks.move(from,to,1); markDirty(); commentTick++
    }
    // "Crear con IA" at a block (its index), or -2 for the line being edited (else the end of the page).
    function openComposer(index) {
        if (settingsShown || !currentId || deleted || conflict) return
        if (index === -2) index = editIndex >= 0 && !!textTarget && !!textTarget.formatter ? editIndex : blocks.count-1
        if (!flush()) return
        const texts = []
        for (let i = 0; i < blocks.count; ++i) { const b = blocks.get(i); texts.push(b.kind === "image" ? "" : b.body) }
        const anchor = index >= 0 ? blocks.get(index) : null
        const empty = !!anchor && anchor.kind !== "image" && !anchor.body.trim()
        composer.show({id: currentId, expected_revision: revision, index: index, block_id: anchor ? anchor.key : "", empty: empty,
                       title: titleInput.text, before: texts.slice(0,empty ? index : index+1).filter(t => t).join("\n").slice(-6000),
                       after: texts.slice(index+1).filter(t => t).join("\n").slice(0,2000)},
                      index >= 0 ? blockRepeater.itemAt(index) : null)
    }
    function openWriting(instruction) {
        if (!canEditSelection || !flush()) return
        const row = blockRepeater.itemAt(editIndex)
        if (!row || row.editor !== textTarget || !textTarget.selectedText) return
        writing.begin({id:currentId, expected_revision:revision, index:editIndex,
            block_id:blocks.get(editIndex).key,start:textTarget.selectionStart,original:textTarget.selectedText},instruction || "")
    }
    property string currentId: ""
    property int revision: 0
    property bool deleted: false
    property bool dirty: false
    property bool conflict: false
    property bool trashMode: false
    property string notice: ""
    property bool noticeError: false
    property var pages: []
    property var navigationRows: []
    property var historyRows: []
    property var collapsed: ({})
    property double generation: -1
    property bool initialized: false
    property string location: "Biblioteca"
    property string fileAction: ""
    ListModel { id: blocks }
    function call(name, args) {
        const r = backend.run(name, args || {})
        if (!r.ok) {
            notice = r.message; noticeError = true
            if (r.code === "revision_conflict") conflict = true
            return null
        }
        return r.data
    }
    function info(text) { noticeError = false; notice = text }
    function draft() {
        const data = []
        for (let i = 0; i < blocks.count; ++i) {
            const r = blocks.get(i)
            const b = {id:r.key, type:r.kind, text:r.body}
            if (b.type !== "image" && r.spans && r.spans !== "[]") b.spans = JSON.parse(r.spans)
            if (b.type === "task") b.checked = r.done
            if (b.type === "image") { b.asset = r.asset; b.width_percent = r.photoPercent }
            if (b.type === "heading") b.level = r.level || 1
            if (b.type === "callout") b.icon = r.icon || "💡"
            if (b.type === "toggle") b.collapsed = !!r.collapsed
            if (b.type === "divider") { b.text = ""; delete b.spans }
            if (r.indent > 0) b.indent = r.indent
            data.push(b)
        }
        return data
    }
    function markDirty() {
        dirty = true
        structure++
        if (!conflict) autosave.restart()
    }
    function flush() {
        autosave.stop()
        if (!dirty) return true
        if (conflict) return false
        const p = call("save",{id:currentId,expected_revision:revision,title:titleInput.text,blocks:draft()})
        if (!p) return false
        revision = p.revision
        for (let i = 0; i < blocks.count; ++i) blocks.setProperty(i,"key",p.blocks[i].id)
        dirty = false; info(""); refreshNavigation()
        return true
    }
    function showPage(id) {
        const p = id ? call("page",{id:id}) : null
        if (id && !p) return
        textTarget = null; editIndex = -1; loadingPage = true
        commentDraft = null; activeComment = ""
        Qt.callLater(function() { win.commentTick++ })
        currentId = id; revision = p ? p.revision : 0
        deleted = p ? !!p.deleted_at : false
        dirty = false; conflict = false
        titleInput.text = p ? p.title : ""
        pageIcon = p && p.icon ? p.icon : ""; pageCover = p && p.cover ? p.cover : ""
        blocks.clear()
        if (p) for (const b of p.blocks) blocks.append({key:b.id,kind:b.type,body:b.text,spans:JSON.stringify(b.spans || []),
            done:!!b.checked,asset:b.asset || "",photoPercent:b.width_percent || 100,level:b.level || 1,indent:b.indent || 0,
            icon:b.icon || "",collapsed:!!b.collapsed})
        loadingPage = false
        const parent = p && pages.find(x => x.id === p.parent_id)
        location = deleted ? "Papelera" : parent ? parent.title : "Biblioteca"
        if (pageScroll.contentItem) pageScroll.contentItem.contentY = 0
    }
    function selectPage(id) { if (flush()) { enterEditor(); info(""); showPage(id) } }
    function refreshNavigation() {
        const nav = call("navigation")
        if (!nav) return
        pages = nav.pages
        const rows = []
        if (trashMode || search.text.trim()) {
            const name = trashMode ? "list_pages" : "search_notes"
            let cursor = 0
            do {
                const a = trashMode ? {trashed:true} : {query:search.text.trim()}
                a.limit = 50; a.cursor = cursor
                const r = call(name,a)
                if (!r) return
                for (const p of r.pages) rows.push({page:p,depth:0,branch:false})
                cursor = r.next_cursor
            } while (cursor !== null && cursor !== undefined)
        } else {
            const children = ({})
            for (const p of pages) {
                const parent = p.parent_id || ""
                if (!children[parent]) children[parent] = []
                children[parent].push(p)
            }
            const stack = (children[""] || []).map(p => ({page:p,depth:0})).reverse()
            while (stack.length) {
                const row = stack.pop(), kids = children[row.page.id] || []
                row.branch = kids.length > 0; rows.push(row)
                if (!collapsed[row.page.id])
                    for (let i = kids.length-1; i >= 0; --i) stack.push({page:kids[i],depth:row.depth+1})
            }
        }
        navigationRows = rows
    }
    function poll() {
        const g = call("generation")
        if (!g || g.value === generation) return
        generation = g.value; refreshNavigation()
        if (currentId) {
            const p = call("page",{id:currentId})
            if (p && p.revision !== revision) {
                if (dirty) {
                    conflict = true; autosave.stop()
                    notice = "Hay una revisión más reciente. Tu borrador sigue abierto."; noticeError = true
                } else showPage(currentId)
            }
        }
    }
    function newPage(parent) {
        if (!flush()) return
        const p = call("create_page",{title:"Sin título",parent_id:parent || null,blocks:[{type:"paragraph",text:""}]})
        if (!p) return
        enterEditor()
        trashMode = false; pagesExpanded = true; search.clear(); info("")
        if (parent) collapsed[parent] = false
        refreshNavigation(); showPage(p.id)
        titleInput.forceActiveFocus(); titleInput.selectAll()
    }
    function action(name, extra) {
        if (!flush()) return false
        const args = Object.assign({id:currentId,expected_revision:revision},extra || {})
        if (!call(name,args)) return false
        info(""); refreshNavigation(); showPage(currentId)
        return true
    }
    function add(kind) {
        blocks.append({key:"",kind:kind,body:"",spans:"[]",done:false,asset:"",photoPercent:100,level:1,indent:0,icon:"",collapsed:false}); markDirty()
        Qt.callLater(function() {
            const row = blockRepeater.itemAt(blocks.count-1)
            if (row) row.focusEditor()
            if (pageScroll.contentItem) pageScroll.contentItem.contentY = Math.max(0,pageScroll.contentHeight-pageScroll.availableHeight)
        })
    }
    function requestFile(kind) {
        if (kind !== "draft" && !flush()) return
        fileAction = kind
        fileDialog.selectedFile = backend.suggestedFile(fileDialog.currentFolder,kind === "backup" ? "Copia de Lunqio" : titleInput.text)
        fileDialog.open()
    }
    Component.onCompleted: {
        initialized = true; poll()
        if (navigationRows.length) showPage(navigationRows[0].page.id)
    }
    onActiveChanged: if (active && initialized) {
        poll()
        // Coming back from signing in to Claude in the browser.
        if (assistant.engine === "claude" && assistant.claudeAccount === "out") assistant.checkClaude()
    }
    onClosing: function(close) { if (assistant.phase === "applying" || !flush()) close.accepted = false }
    Timer { id: autosave; interval: 750; onTriggered: win.flush() }
    Timer { interval: 1000; repeat: true; running: win.active && win.initialized; onTriggered: win.poll() }
    Shortcut { sequence: StandardKey.Find; onActivated: win.focusSearch() }
    Shortcut { sequence: "F1"; onActivated: win.openHelp() }
    RowLayout {
        anchors.fill: parent; spacing: 0
        Rectangle {
            id: sidebar
            visible: win.sidebarShown
            Layout.preferredWidth: Math.max(200,Math.min(win.width-525,win.sidebarPreferredWidth || Math.min(320,Math.round(win.width*0.225))))
            Layout.fillHeight: true
            color: "#202020"
            ColumnLayout {
                anchors.fill: parent; spacing: 0
                RowLayout {
                    Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.preferredHeight: 45
                    UiButton { symbol: "panel"; hint: "Ocultar barra lateral"; quiet: true; onClicked: win.sidebarShown = false }
                    Item { Layout.fillWidth: true }
                    UiButton { symbol: "history"; hint: "Historial de esta página"; enabled: !win.settingsShown && !!win.currentId && !win.deleted; quiet: true; onClicked: win.openHistory() }
                    UiButton { symbol: "newPage"; hint: "Nueva página (Ctrl+N)"; quiet: true; onClicked: win.newPage(null) }
                }
                TextField {
                    id: search; Layout.fillWidth: true; Layout.leftMargin: 9; Layout.rightMargin: 11; Layout.preferredHeight: 36
                    placeholderText: "Buscar páginas"; Accessible.name: "Buscar páginas"; maximumLength: 240
                    leftPadding: 32; rightPadding: 48; selectByMouse: true
                    onActiveFocusChanged: if (activeFocus) win.remember(search,-1)
                    background: Rectangle {
                        radius: 6; border.color: search.activeFocus ? "#789cc8" : "#414143"; color: "#242424"
                        Glyph { name: "search"; anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 14 }
                        Rectangle { width: 39; height: 19; radius: 4; color: "#343434"; anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter; visible: !search.text
                            Label { anchors.centerIn: parent; text: "Ctrl+K"; font.pixelSize: 10; color: "#c1bfc3" } }
                    }
                    onTextChanged: if (win.initialized) { if (text) { win.trashMode = false; win.pagesExpanded = true } win.refreshNavigation() }
                }
                UiButton { Layout.topMargin: 12; Layout.leftMargin: 9
                    alignLeft: true; quiet: win.settingsShown || !!win.currentId || win.trashMode; symbol: "home"; text: "Inicio"
                    onClicked: win.browseTrash(false) }
                RowLayout {
                    Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 9; Layout.topMargin: 12; Layout.bottomMargin: 2
                    UiButton { text: win.trashMode ? "Papelera" : search.text.trim() ? "Resultados" : "Privado"
                        quiet: true; alignLeft: true; symbol: win.pagesExpanded ? "down" : "right"; hint: "Mostrar u ocultar las páginas"
                        onClicked: win.pagesExpanded = !win.pagesExpanded }
                    Item { Layout.fillWidth: true }
                    UiButton { symbol: "add"; quiet: true; hint: "Crear página en la raíz"; onClicked: win.newPage(null) }
                }
                ListView {
                    id: navList; Layout.fillWidth: true; Layout.fillHeight: true; Layout.leftMargin: 8; Layout.rightMargin: 8
                    clip: true; spacing: 2; model: win.pagesExpanded ? win.navigationRows : []
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        id: navRow
                        required property var modelData
                        HoverHandler { id: rowHover }
                        width: navList.width; height: 34; radius: 5
                        color: !win.settingsShown && modelData.page.id === win.currentId ? "#303030" : rowHover.hovered ? "#292929" : "transparent"
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 8 + Math.min(6,navRow.modelData.depth)*12; anchors.rightMargin: 6; spacing: 3
                            UiButton {
                                visible: navRow.modelData.branch; Layout.preferredWidth: 19; quiet: true; hint: "Mostrar u ocultar subpáginas"
                                symbol: win.collapsed[navRow.modelData.page.id] ? "right" : "down"
                                onClicked: { win.collapsed[navRow.modelData.page.id] = !win.collapsed[navRow.modelData.page.id]; win.refreshNavigation() }
                            }
                            Button {
                                id: navButton; flat: true; Layout.fillWidth: true; Layout.fillHeight: true; padding: 3
                                background: Rectangle { color: "transparent"; radius: 4; border.width: navButton.visualFocus ? 1 : 0; border.color: "#91b5ea" }
                                contentItem: RowLayout {
                                    spacing: 9
                                    PageIcon { icon: navRow.modelData.page.icon || ""; size: 15 }
                                    Label { text: navRow.modelData.page.title; color: navRow.modelData.page.id === win.currentId ? "#f4f3f4" : "#c4c2c6"; Layout.fillWidth: true; elide: Text.ElideRight }
                                }
                                Accessible.name: navRow.modelData.page.title; onClicked: win.selectPage(navRow.modelData.page.id)
                                ToolTip.visible: hovered && !!navRow.modelData.page.snippet
                                ToolTip.text: navRow.modelData.page.snippet || ""
                            }
                            UiButton { visible: (rowHover.hovered || visualFocus) && !win.trashMode
                                symbol: "add"; quiet: true; hint: "Crear subpágina"; Layout.preferredWidth: 26
                                onClicked: win.newPage(navRow.modelData.page.id) }
                        }
                    }
                    Label { visible: win.pagesExpanded && !navList.count; anchors.left: parent.left; anchors.leftMargin: 12; text: win.trashMode ? "Papelera vacía" : search.text ? "Sin coincidencias" : "Aún no hay páginas"; color: "#a5a3a6"; font.pixelSize: 13 }
                }
                UiButton { Layout.fillWidth: true; Layout.margins: 9; quiet: !win.trashMode; alignLeft: true; text: "Papelera"; symbol: "trash"; onClicked: win.browseTrash(!win.trashMode) }
                Rectangle { Layout.fillWidth: true; height: 1; color: "#343435" }
                RowLayout {
                    Layout.fillWidth: true; Layout.margins: 10; spacing: 3
                    Rectangle { width: 29; height: 29; radius: 7; color: "#dcd8e0"
                        Label { anchors.centerIn: parent; text: "L"; font.pixelSize: 18; font.weight: Font.Bold; color: "#29252e" } }
                    Button {
                        id: mcpBadge; flat: true; Layout.fillWidth: true; implicitHeight: 39
                        Accessible.name: mcpText.text + ". Ajustes de conexión"; onClicked: win.openConnection()
                        background: Rectangle { radius: 5; color: mcpBadge.hovered ? "#313133" : "transparent"; border.width: mcpBadge.visualFocus ? 1 : 0; border.color: "#91b5ea" }
                        contentItem: ColumnLayout {
                            spacing: 1
                            Label { text: "Lunqio"; font.weight: Font.DemiBold; font.pixelSize: 14 }
                            RowLayout { spacing: 5
                                Rectangle { width: 6; height: 6; radius: 3; color: win.assistant.link.state === "connected" ? "#7abb99" : win.assistant.link.state === "connecting" ? "#d6af77" : "#a3a0a7" }
                                Label { id: mcpText; font.pixelSize: 11; color: "#b2afb6"; text: win.assistant.link.state === "connected" ? "MCP conectado" : win.assistant.link.state === "connecting" ? "Conectando MCP…" : "MCP desconectado" }
                            }
                        }
                    }
                    UsageButton { objectName: "usageButton"; assistant: win.assistant; onOpenUsage: workspaceTabs.currentIndex = 2 }
                    UiButton { symbol: "settings"; quiet: true; hint: "Conectores"; onClicked: win.openConnection() }
                }
            }
        }
        Rectangle {
            visible: win.sidebarShown; Layout.preferredWidth: 1; Layout.fillHeight: true; z: 5
            color: splitter.containsMouse ? "#789cc8" : "#303031"
            MouseArea {
                id: splitter; anchors.fill: parent; anchors.leftMargin: -3; anchors.rightMargin: -3
                hoverEnabled: true; cursorShape: Qt.SplitHCursor; preventStealing: true
                property real offset
                onPressed: function(mouse) { offset = mapToItem(win.contentItem,mouse.x,0).x-sidebar.width }
                onPositionChanged: function(mouse) { if (pressed) win.sidebarPreferredWidth = Math.round(Math.max(200,Math.min(390,mapToItem(win.contentItem,mouse.x,0).x-offset))) }
                onDoubleClicked: win.sidebarPreferredWidth = 0
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            TabBar {
                id: workspaceTabs; objectName: "workspaceTabs"; Layout.fillWidth: true
                implicitHeight: 36; leftPadding: 12; spacing: 3
                background: Rectangle { color: "#1d1d1e"; Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#343435" } }
                component WorkspaceTab: TabButton {
                    id: tab; width: implicitWidth; horizontalPadding: 16; implicitHeight: 36
                    contentItem: Text { text: tab.text; color: tab.checked ? "#f1eff1" : "#aaa8af"; font.weight: tab.checked ? Font.DemiBold : Font.Normal; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { color: tab.hovered || tab.visualFocus ? "#303031" : "transparent"
                        Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: parent.width-18; height: 2; color: "#a4bfe5"; visible: tab.checked } }
                }
                WorkspaceTab { text: "Editor"; objectName: "editorTab" }
                WorkspaceTab { text: "Conectores"; objectName: "connectorsTab"; Accessible.name: "Conectores MCP" }
                WorkspaceTab { text: "Uso"; objectName: "usageTab"; Accessible.name: "Uso de tokens de IA" }
                onCurrentIndexChanged: if (currentIndex === 0 && win.resumeWriting) {
                    win.resumeWriting = false
                    if (writing.selection.id === win.currentId && writing.selection.expected_revision === win.revision) writing.open()
                    else win.assistant.cancel()
                }
            }
            ConnectorsPage { visible: workspaceTabs.currentIndex === 1; Layout.fillWidth: true; Layout.fillHeight: true
                assistant: win.assistant; onChooseCodex: cliDialog.open(); onChooseClaude: claudeDialog.open() }
            UsagePage { objectName: "usagePage"; visible: workspaceTabs.currentIndex === 2; Layout.fillWidth: true; Layout.fillHeight: true; assistant: win.assistant }
            RowLayout {
                visible: !win.settingsShown
                Layout.fillWidth: true; Layout.preferredHeight: 48; Layout.leftMargin: 18; Layout.rightMargin: 14; spacing: 8
                UiButton { visible: !win.sidebarShown; symbol: "panel"; hint: "Mostrar barra lateral"; quiet: true; onClicked: win.sidebarShown = true }
                PageIcon { icon: win.currentId ? win.pageIcon : ""; glyph: win.currentId ? "page" : "home"; size: 15 }
                Label { text: win.currentId ? titleInput.text : win.trashMode ? "Papelera" : "Inicio"; elide: Text.ElideRight; Layout.maximumWidth: 290; font.pixelSize: 14 }
                Glyph { name: "lock"; font.pixelSize: 11; visible: !!win.currentId }
                Label { visible: !!win.currentId; text: win.deleted ? "Papelera" : "Privada"; color: "#a6a3a9"; font.pixelSize: 12 }
                Item { Layout.fillWidth: true }
                Label { visible: !!win.currentId; text: win.conflict ? "Conflicto de edición" : win.dirty ? "Cambios pendientes" : "Guardado · v" + win.revision; color: win.dirty ? "#ddba84" : "#a7a4ab"; font.pixelSize: 12 }
                UiButton { visible: !win.sidebarShown; symbol: "link"; text: mcpText.text; quiet: true; hint: "Conectores"; onClicked: win.openConnection() }
                UiButton {
                    symbol: "more"; hint: "Opciones de página"; quiet: true; visible: !!win.currentId && !win.deleted
                    onClicked: pageMenu.popup()
                    Menu { id: pageMenu
                        MenuItem { text: "Nueva subpágina"; onTriggered: win.newPage(win.currentId) }
                        MenuItem { text: "Mover página…"; onTriggered: if (win.flush()) moveDialog.open() }
                        MenuItem { text: "Historial de revisiones…"; onTriggered: win.openHistory() }
                        MenuItem { text: "Guardar como…"; onTriggered: win.requestFile("export") }
                        MenuItem { text: "Insertar foto…"; onTriggered: win.choosePhoto() }
                        MenuSeparator {}
                        MenuItem { text: "Enviar a la papelera…"; onTriggered: win.openTrashConfirmation() }
                    }
                }
            }
            RowLayout {
                visible: !win.settingsShown && !!win.notice; Layout.fillWidth: true; Layout.margins: 12
                Label { text: win.notice; wrapMode: Text.Wrap; Layout.fillWidth: true; color: win.noticeError ? "#efb69c" : "#a9c9b7" }
                UiButton { visible: win.dirty; text: "Exportar borrador"; onClicked: win.requestFile("draft") }
                UiButton { visible: win.dirty; text: "Descartar…"; onClicked: reloadDialog.open() }
                UiButton { visible: !win.conflict && win.dirty; text: "Reintentar"; onClicked: win.flush() }
                UiButton { visible: !win.dirty; quiet: true; symbol: "close"; hint: "Cerrar aviso"; onClicked: win.info("") }
            }
            Item {
                visible: !win.settingsShown && !win.currentId; Layout.fillWidth: true; Layout.fillHeight: true
                ColumnLayout {
                    anchors.horizontalCenter: parent.horizontalCenter; y: Math.min(110,parent.height*0.15)
                    width: Math.min(700,parent.width-100); spacing: 18
                    Glyph { name: win.trashMode ? "trash" : "pages"; font.pixelSize: 32 }
                    Label { text: win.trashMode ? "Papelera" : "Tu biblioteca"; font.pixelSize: 43; font.bold: true }
                    UiButton { primary: true; symbol: "add"; text: "Nueva página"; onClicked: win.newPage(null) }
                    ListView {
                        Layout.fillWidth: true; Layout.preferredHeight: Math.min(260,contentHeight); clip: true
                        model: win.navigationRows; spacing: 3
                        delegate: UiButton { required property var modelData; width: ListView.view.width; quiet: true; alignLeft: true; symbol: "page"; text: modelData.page.title; onClicked: win.selectPage(modelData.page.id) }
                    }
                }
            }
            ScrollView {
                id: pageScroll; visible: !win.settingsShown && !!win.currentId; Layout.fillWidth: true; Layout.fillHeight: true
                clip: true; contentWidth: availableWidth
                contentHeight: pageColumn.y+Math.max(pageColumn.implicitHeight,rail.visible && !rail.floating ? rail.contentBottom+40 : 0)
                // With comments, the text column narrows to leave a 300 px margin for the cards (as in Google Docs).
                readonly property int gutter: win.width >= 1150 ? 148 : 72
                readonly property bool withRail: rail.threads.length > 0 || !!win.commentDraft
                readonly property bool railFits: availableWidth-gutter-332 >= 460
                PageCover {
                    id: pageCoverItem; objectName: "pageCover"
                    page: win; width: pageScroll.availableWidth; height: 200
                    onUploadRequested: coverDialog.open()
                }
                ColumnLayout {
                    id: pageColumn
                    y: win.pageCover ? (win.pageIcon ? 156 : 200) : 0
                    x: pageScroll.withRail && pageScroll.railFits ? Math.round((pageScroll.availableWidth-width-332)/2) : Math.round((pageScroll.availableWidth-width)/2)
                    width: Math.min(780, pageScroll.availableWidth-pageScroll.gutter-(pageScroll.withRail && pageScroll.railFits ? 332 : 0))
                    spacing: 9
                    onHeightChanged: rail.schedule()
                    onWidthChanged: rail.schedule()
                    Item { Layout.preferredHeight: win.pageCover ? (win.pageIcon ? 0 : 20) : Math.min(94,win.height*0.1) }
                    PageHeader { id: pageHeader; Layout.fillWidth: true; page: win; picker: emojiPicker; titleHovered: titleArea.hovered || titleInput.activeFocus }
                    Label { visible: win.location !== "Biblioteca" && !win.deleted; text: win.location; color: "#a6a3a9"; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                    TextArea {
                        id: titleInput; objectName: "titleInput"; Layout.fillWidth: true
                        wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText; font.pixelSize: win.width >= 1150 ? 44 : 37; font.weight: Font.Bold
                        color: "#f2f1f2"; padding: 0; bottomPadding: 12; background: Item {}
                        placeholderText: "Sin título"; Accessible.name: "Título de la página"; placeholderTextColor: "#757477"
                        selectByMouse: true; readOnly: win.deleted; persistentSelection: true
                        onTextChanged: if (activeFocus && !win.loadingPage) win.markDirty()
                        onActiveFocusChanged: if (activeFocus) win.remember(titleInput,-1)
                        HoverHandler { id: titleArea }
                        Keys.onReturnPressed: function(event) {
                            if (win.deleted) return
                            event.accepted = true
                            if (blocks.count) blockRepeater.itemAt(0).focusEditor()
                            else win.add("paragraph")
                        }
                    }
                    Repeater {
                        id: blockRepeater; model: blocks
                        delegate: BlockRow {
                            Layout.fillWidth: true; total: blocks.count; editable: !win.deleted
                            onEditing: function(field,i) { win.remember(field,i) }
                            onAskAi: win.openWriting()
                            onComposeRequested: win.openComposer(index)
                            onLinkRequested: win.editLink()
                            onEditContent: function(value, styles) {
                                blocks.setProperty(index,"body",value); blocks.setProperty(index,"spans",styles); win.markDirty()
                                win.commentTick++
                            }
                            onCommentFocused: function(id) { if (id || !win.commentDraft) win.activeComment = id }
                            slashOpen: !!win.slash && win.slash.index === index
                            number: win.outline[index] ? win.outline[index].number : 0
                            hasChildren: !!win.outline[index] && win.outline[index].parent
                            visible: !(win.outline[index] && win.outline[index].hidden)
                            onIndentRequested: function(step) { win.setIndent(index,step) }
                            onCollapseRequested: win.toggleCollapse(index)
                            onIconRequested: function(anchor) { emojiPicker.pick(anchor,function(emoji) { blocks.setProperty(index,"icon",emoji || "💡"); win.markDirty() }) }
                            lifted: win.dragFrom === index
                            onSplitRequested: function(position) { win.splitBlock(index,position) }
                            onMergeRequested: win.mergeBlock(index)
                            onNavigate: function(direction) { win.navigateBlock(index,direction) }
                            onSlashTyped: function(start) { win.openSlash(index,start) }
                            onSlashKey: function(key) { win.slashKey(key) }
                            onAddBelow: win.addBlockBelow(index)
                            onDragStarted: { win.dragFrom = index; win.dropAt = -1 }
                            onDragMoved: function(sceneY) { win.dragMove(sceneY) }
                            onDragFinished: win.dragEnd()
                            onCheck: function(value) { blocks.setProperty(index,"done",value); win.markDirty() }
                            onResizePhoto: function(value) { blocks.setProperty(index,"photoPercent",value); win.markDirty() }
                            onShift: function(offset) { blocks.move(index,index+offset,1); win.editIndex = -1; win.markDirty() }
                            onRemoveRow: { win.editIndex = -1; blocks.remove(index); win.markDirty() }
                            onChangeKind: function(value) { win.setKind(index,value) }
                        }
                    }
                    UiButton { visible: win.deleted; primary: true; text: "Restaurar página"; onClicked: if (win.action("restore_page")) { win.trashMode = false; win.refreshNavigation() } }
                    Item { Layout.preferredHeight: 28 }
                }
                CommentRail {
                    id: rail; objectName: "commentRail"
                    floating: !pageScroll.railFits
                    width: 300
                    x: floating ? pageScroll.availableWidth-width-16 : pageColumn.x+pageColumn.width+32
                    y: pageColumn.y; height: pageColumn.height; z: 5
                    threads: win.pageComments
                    draft: win.commentDraft
                    activeId: win.activeComment
                    me: backend.author
                    anchorFor: function(index, start) {
                        const row = blockRepeater.itemAt(index)
                        if (!row || !row.editor) return 0
                        const r = row.editor.positionToRectangle(Math.min(start,row.editor.length))
                        return row.editor.mapToItem(rail,r.x,r.y).y
                    }
                    onActivate: function(id) { win.activeComment = id }
                    onReply: function(thread, text) { win.commentAction(thread,"reply",text) }
                    onResolve: function(thread, value) { win.commentAction(thread,"resolve",value) }
                    onEdit: function(thread, text) { win.commentAction(thread,"edit",text) }
                    onRemove: function(thread) { win.commentAction(thread,"remove") }
                    onRemoveReply: function(thread, i) { win.commentAction(thread,"removeReply",i) }
                    onSubmitDraft: function(text) { win.finishCommentDraft(text) }
                    onCancelDraft: win.cancelCommentDraft()
                    onRename: { authorField.text = backend.author; authorDialog.open() }
                }
            }
            Flow {
                visible: !win.settingsShown && !!win.currentId && !win.deleted; Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height
                Layout.leftMargin: Math.max(22,pageColumn.x)
                Layout.rightMargin: 16; Layout.bottomMargin: 20; spacing: 6
                Repeater {
                    model: [{k:"paragraph",s:"text",t:"Párrafo"},{k:"heading",s:"heading",t:"Encabezado"},{k:"list",s:"list",t:"Lista"},{k:"task",s:"task",t:"Tarea"},{k:"image",s:"photo",t:"Foto"}]
                    delegate: UiButton { required property var modelData; text: modelData.t; symbol: modelData.s; hint: "Añadir " + modelData.t.toLowerCase(); onClicked: modelData.k === "image" ? win.choosePhoto() : win.add(modelData.k) }
                }
                UiButton { objectName: "composeButton"; text: "✦  Crear con IA"; hint: "Crear con IA (Ctrl+J)"; onClicked: win.openComposer(-2) }
            }
        }
    }
    SelectionBubble {
        id: bubble; objectName: "selectionBubble"
        target: win.canFormat ? win.textTarget : null
        allowed: win.canFormat && !writing.visible
        viewport: pageScroll
        scrollOffset: pageScroll.contentItem ? pageScroll.contentItem.contentY : 0
        onKindChosen: function(value) { win.setKind(win.editIndex,value) }
        onAiRequested: function(instruction) { win.openWriting(instruction) }
        onCommentRequested: win.startCommentDraft()
    }
    Shortcut { sequence: "Escape"; enabled: bubble.shown && !bubble.menuOpen; onActivated: bubble.dismiss() }
    Shortcut { sequence: "Ctrl+J"; enabled: !win.settingsShown && !!win.currentId && !win.deleted; onActivated: win.openComposer(-2) }
    Shortcut {
        sequence: "Escape"; enabled: composer.visible && !bubble.shown
        onActivated: composer.busy ? win.assistant.cancel() : composer.close()
    }
    SlashMenu {
        id: slashMenu; objectName: "slashMenu"
        visible: !!win.slash && !win.settingsShown
        readonly property var spot: {
            win.width; win.height; pageScroll.contentItem ? pageScroll.contentItem.contentY : 0
            if (!win.slash) return Qt.point(0,0)
            const row = blockRepeater.itemAt(win.slash.index)
            if (!row) return Qt.point(0,0)
            const r = row.editor.positionToRectangle(win.slash.start)
            return row.editor.mapToItem(win.contentItem,r.x,r.y+r.height+6)
        }
        x: Math.max(8,Math.min(spot.x-8,win.contentItem.width-width-8))
        y: spot.y+height+12 > win.contentItem.height ? Math.max(8,spot.y-height-40) : spot.y
        onChosen: function(command) { win.runSlash(command) }
    }
    Connections {
        target: win.slash ? blockRepeater.itemAt(win.slash.index).editor : null
        function onTextChanged() { win.updateSlash() }
        function onCursorPositionChanged() { win.updateSlash() }
        function onActiveFocusChanged() { Qt.callLater(win.updateSlash) }
    }
    Rectangle {
        objectName: "dropLine"
        visible: win.dragFrom >= 0 && win.dropAt >= 0
        x: win.dropX; y: win.dropY
        width: pageColumn.width; height: 3; radius: 1.5; color: "#3b8beb"; z: 30
    }
    AiComposer {
        id: composer; objectName: "aiComposer"
        assistant: win.assistant
        visible: active && !win.settingsShown
        viewport: pageScroll
        scrollOffset: pageScroll.contentItem ? pageScroll.contentItem.contentY : 0
        onOpenConnectors: win.openConnection()
    }
    WritingDialog {
        id: writing; assistant: win.assistant; suspended: win.resumeWriting
        onSettingsRequested: { win.resumeWriting = true; writing.close(); win.openConnection() }
    }
    Connections {
        target: win.assistant
        function onApplied(id) {
            const created = win.assistant.mode === "create"
            writing.close()
            if (composer.active) composer.close()
            if (win.currentId === id && !win.dirty) win.showPage(id)
            win.refreshNavigation()
            win.info(created ? "Contenido insertado." : "Cambio aplicado.")
        }
    }
    onCurrentIdChanged: if (composer.active) composer.close()
    Native.FileDialog { id: cliDialog; title: "Elegir ejecutable de Codex"; nameFilters: ["Ejecutable de Windows (*.exe)"]; onAccepted: win.assistant.setExecutable(selectedFile) }
    Native.FileDialog {
        id: claudeDialog; title: "Elegir ejecutable de Claude Code"; nameFilters: ["Claude Code (claude.exe claude.cmd)","Ejecutable de Windows (*.exe *.cmd)"]
        onAccepted: if (!win.assistant.connectors.claudeCode.chooseProgram(selectedFile)) { win.notice = "Elige claude.exe o claude.cmd."; win.noticeError = true }
    }
    Dialog {
        id: helpDialog; title: "Guía y atajos"; modal: true; anchors.centerIn: parent; width: Math.min(470,win.width-40); standardButtons: Dialog.Close
        contentItem: ColumnLayout {
            spacing: 12
            Label { text: "Selecciona texto dentro de un bloque para abrir el menú de formato. Desde ahí puedes convertir el bloque, aplicar estilos, añadir un enlace o un comentario y editar con IA."; Layout.fillWidth: true; wrapMode: Text.Wrap }
            Label { text: "Ctrl+B    Negrita\nCtrl+I    Cursiva\nCtrl+U    Subrayado\nCtrl+Shift+X    Tachado\nCtrl+E    Código en línea\nCtrl+Shift+H    Resaltar\nCtrl+K    Enlace (con texto seleccionado)"; lineHeight: 1.35 }
            Label { text: "Ctrl+N    Nueva página\nCtrl+K    Buscar páginas\nCtrl+S    Guardar\nCtrl+Shift+S    Guardar como…\nCtrl+Shift+I    Editar selección con IA\nF1    Ayuda"; lineHeight: 1.35 }
        }
    }
    Dialog {
        id: authorDialog; title: "Tu nombre en los comentarios"; modal: true; anchors.centerIn: parent; width: 380
        standardButtons: Dialog.Save | Dialog.Cancel
        onAccepted: if (authorField.text.trim()) backend.author = authorField.text
        contentItem: ColumnLayout {
            spacing: 8
            Label { text: "Aparece en los comentarios y respuestas nuevos."; color: "#b5b2b9"; wrapMode: Text.Wrap; Layout.fillWidth: true }
            TextField { id: authorField; Layout.fillWidth: true; maximumLength: 80; selectByMouse: true; onAccepted: authorDialog.accept() }
        }
    }
    Dialog { id: aboutDialog; title: "Acerca de Lunqio"; modal: true; anchors.centerIn: parent; width: 390; implicitWidth: 390; standardButtons: Dialog.Close
        contentItem: Label { text: "Lunqio 0.4.0\nEditor local de páginas, fotos y tareas para Windows."; padding: 6; lineHeight: 1.4 }
    }
    Dialog {
        id: reloadDialog; title: "¿Descartar el borrador y recargar?"; anchors.centerIn: parent; modal: true
        standardButtons: Dialog.Yes | Dialog.Cancel
        onAccepted: { win.showPage(win.currentId); win.info("") }
    }
    Dialog {
        id: trashDialog; title: "¿Enviar la página y sus subpáginas a la papelera?"; anchors.centerIn: parent; modal: true
        standardButtons: Dialog.Yes | Dialog.Cancel
        onAccepted: if (win.action("trash_page")) win.showPage(win.navigationRows.length ? win.navigationRows[0].page.id : "")
    }
    Dialog {
        id: historyDialog; title: "Historial de revisiones"; modal: true; anchors.centerIn: parent
        width: Math.min(500,win.width-60); height: Math.min(430,win.height-60); standardButtons: Dialog.Close
        contentItem: ListView {
            clip: true; model: win.historyRows; spacing: 4
            delegate: RowLayout {
                required property var modelData; width: ListView.view.width
                Label { Layout.fillWidth: true; text: "v"+modelData.revision+" · "+(modelData.actor === "mcp" ? "MCP" : "Manual")+"\n"+new Date(modelData.at).toLocaleString(); color: "#eceaed" }
                UiButton { text: "Restaurar"; enabled: modelData.revision !== win.revision; onClicked: {
                        if (win.action("restore_revision",{target:modelData.revision})) historyDialog.close()
                    } }
            }
        }
    }
    Dialog {
        id: moveDialog; title: "Mover a…"; modal: true; anchors.centerIn: parent; standardButtons: Dialog.Close
        width: 350; height: Math.min(400,win.height-60)
        contentItem: ListView {
            model: [{id:null,title:"Raíz de la biblioteca"}].concat(win.pages.filter(p=>p.id!==win.currentId))
            clip: true; spacing: 3
            delegate: UiButton {
                required property var modelData; width: ListView.view.width; text: modelData.title
                onClicked: if (win.action("update_page",{parent_id:modelData.id})) moveDialog.close()
            }
        }
    }
    Native.FileDialog {
        id: coverDialog; title: "Elegir una foto de portada"; fileMode: Native.FileDialog.OpenFile
        nameFilters: ["Fotos (*.jpg *.jpeg *.png)"]; onAccepted: win.action("cover_photo",{url: selectedFile.toString()})
    }
    EmojiPicker { id: emojiPicker; objectName: "emojiPicker" }
    Native.FileDialog {
        id: photoDialog; title: "Insertar foto"; fileMode: Native.FileDialog.OpenFile
        nameFilters: ["Fotos (*.jpg *.jpeg *.png)"]; onAccepted: win.insertPhoto(selectedFile)
    }
    Native.FileDialog {
        id: fileDialog; fileMode: Native.FileDialog.SaveFile
        title: win.fileAction === "backup" ? "Guardar copia de seguridad" : "Guardar página como"
        defaultSuffix: win.fileAction === "backup" ? "sqlite3" : (["md","pdf","html","txt"][selectedNameFilter.index] || "md")
        nameFilters: win.fileAction === "backup" ? ["Biblioteca SQLite (*.sqlite3)"] : ["Markdown (*.md)","Documento PDF (*.pdf)","Página HTML (*.html)","Texto plano (*.txt)"]
        onAccepted: {
            const a = {id:win.currentId,url:selectedFile.toString()}
            if (win.fileAction === "draft") { a.title = titleInput.text; a.blocks = win.draft() }
            if (win.call(win.fileAction,a)) {
                if (!win.dirty) win.info("Archivo guardado.")
                else { win.notice = "Borrador exportado. Puedes descartar los cambios para recargar la página."; win.noticeError = false }
            }
        }
    }
}
