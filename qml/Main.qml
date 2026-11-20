import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs as Native

ApplicationWindow {
    id: win
    width: 1240; height: 800; minimumWidth: 780; minimumHeight: 520
    visible: true; title: "Lunqio"
    color: Theme.canvas; font.family: Theme.family; font.pixelSize: 14
    palette.window: Theme.surface; palette.windowText: Theme.text; palette.text: Theme.text
    palette.base: Theme.base; palette.button: Theme.surface; palette.buttonText: Theme.text
    palette.light: Theme.pressed; palette.midlight: Theme.line; palette.mid: Theme.line; palette.dark: Theme.hover
    palette.highlight: Theme.accentLine; palette.highlightedText: Theme.text; palette.placeholderText: Theme.muted
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
    // The saved theme (Ver → Tema) drives every colour in Theme.
    Binding { target: Theme; property: "mode"; value: backend.theme }
    function format(style) { if (canFormat) textTarget.formatter.toggle(style) }
    function editLink() { if (canFormat) bubble.openLink() }
    // value is a block type, or "heading1".."heading3" for a heading of that size.
    function setKind(index, value) {
        if (index < 0 || index >= blocks.count) return
        rememberStructure()
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
    // The page's typography (⋯ menu): font, smaller text and full width.
    property string pageFont: "sans"
    property bool pageSmall: false
    property bool pageWide: false
    readonly property string pageFamily: pageFont === "serif" ? "Georgia" : pageFont === "mono" ? Theme.mono : Theme.family
    function setPageLook(field, value) {
        if (!currentId || deleted) return
        const change = {}
        change[field] = value
        action("update_page",change)
    }
    // Templates: Lunqio's own (TemplateStrip) and yours, offered while the page is empty.
    property var userTemplates: []
    readonly property bool pageEmpty: {
        structure; blocks.count
        if (!currentId || deleted || blocks.count > 1) return false
        return blocks.count === 0 || (blocks.get(0).kind === "paragraph" && !blocks.get(0).body)
    }
    function today() { return new Date().toLocaleDateString(Qt.locale(),"d 'de' MMMM 'de' yyyy") }
    // The page takes the template's blocks, its look and, while it has no name of its own, its title.
    function applyTemplate(t) {
        if (!currentId || deleted || !t) return
        rememberStructure()
        const dated = s => (s || "").split("{fecha}").join(today())
        if (!titleInput.text.trim() || titleInput.text === "Sin título") titleInput.text = dated(t.title) || "Sin título"
        textTarget = null; editIndex = -1
        blocks.clear()
        for (const b of t.blocks || []) { const copy = Object.assign({}, b); delete copy.id; copy.text = dated(copy.text); blocks.append(rowOf(copy)) }
        if (!blocks.count) blocks.append(rowOf({type: "paragraph"}))
        markDirty()
        const look = {}
        if (t.icon) look.icon = t.icon
        if (t.cover) look.cover = t.cover
        if (t.font && t.font !== "sans") look.font = t.font
        if (t.small_text) look.small_text = true
        if (t.full_width) look.full_width = true
        if (Object.keys(look).length) action("update_page",look); else flush()
        Qt.callLater(function() { const row = blockRepeater.itemAt(0); if (row) row.focusAt(-1) })
    }
    function saveTemplate(name) {
        if (!flush()) return false
        const r = call("save_template",{id: currentId, name: name})
        if (!r) return false
        userTemplates = r.templates; info("Plantilla guardada.")
        return true
    }
    function removeTemplate(id) { const r = call("remove_template",{template: id}); if (r) userTemplates = r.templates }
    // A block's look from its menu (align, tint, fill or frame); one undo step.
    function setBlockLook(index, role, value) {
        if (index < 0 || index >= blocks.count || blocks.get(index)[role] === value) return
        rememberStructure()
        blocks.setProperty(index,role,value)
        markDirty()
    }
    // What a photo's menu asks for: see it large, replace, save or copy the picture.
    property int photoIndex: -1
    function photoAction(index, name) {
        const b = index >= 0 && index < blocks.count ? blocks.get(index) : null
        if (!b || b.kind !== "image") return
        photoIndex = index
        if (name === "view") photoViewer.show(b.asset,b.body)
        else if (name === "replace" && !deleted) replaceDialog.open()
        else if (name === "save") {
            savePhotoDialog.selectedFile = backend.suggestedFile(savePhotoDialog.currentFolder,b.body || "Foto")
            savePhotoDialog.open()
        } else if (name === "copy" && call("photo_copy",{asset: b.asset})) info("Imagen copiada.")
    }
    function replacePhoto(url) {
        const r = call("store_photo",{url: url.toString()})
        if (!r || photoIndex < 0 || photoIndex >= blocks.count) return false
        rememberStructure()
        blocks.setProperty(photoIndex,"asset",r.asset)
        markDirty()
        return flush()
    }
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
        rememberStructure()
        const current = blocks.get(index).indent || 0
        const limit = index > 0 ? Math.min(6,(blocks.get(index-1).indent || 0)+1) : 0
        const next = Math.max(0,Math.min(limit,current+step))
        if (next === current) return
        blocks.setProperty(index,"indent",next)
        markDirty(); commentTick++
    }
    function toggleCollapse(index) {
        if (index < 0 || index >= blocks.count) return
        rememberStructure()
        blocks.setProperty(index,"collapsed",!blocks.get(index).collapsed)
        markDirty(); commentTick++
    }
    function remember(input, index) {
        if (textTarget && textTarget !== input) textTarget.deselect()
        textTarget = input; editIndex = index
    }
    function textCommand(name) {
        if (!textTarget) return
        textTarget.forceActiveFocus()
        if (name === "paste" && editIndex >= 0 && pastePhoto(editIndex)) return
        if (name === "undo" && editIndex >= 0 && !textTarget.canUndo && undoStructure()) return
        if (name === "redo" && editIndex >= 0 && !textTarget.canRedo && redoStructure()) return
        textTarget[name]()
    }
    // Photos (each {asset, caption}) become blocks below the block at `index`, as in Notion; an empty
    // paragraph there turns into them. With no block in use they go at the end. The caret ends right after.
    function insertPhotos(index, photos, exact) {
        if (!photos.length) return false
        rememberStructure()
        const current = !exact && index >= 0 && index < blocks.count ? blocks.get(index) : null
        // exact: `index` is the place itself (a drop), not the block being edited.
        let at = exact ? Math.max(0,Math.min(index,blocks.count)) : current ? index+1 : blocks.count
        if (current && current.kind === "paragraph" && !current.body) { blocks.remove(index); at = index }
        editIndex = -1
        for (const p of photos)
            blocks.insert(at++,rowOf({type: "image", text: p.caption, asset: p.asset, width_percent: 100}))
        markDirty(); commentTick++
        // Keep writing right after the photo.
        if (at >= blocks.count || blocks.get(at).kind === "image" || blocks.get(at).kind === "divider") insertBlock(at,"paragraph","","[]",0)
        else Qt.callLater(function() { const row = blockRepeater.itemAt(at); if (row) row.focusAt(0) })
        reveal(at)
        return true
    }
    // Scrolls so the block at `index` and what is just above it show; again while photos finish loading.
    function reveal(index) { revealTimer.index = index; revealTimer.left = 4; revealTimer.restart() }
    Timer {
        id: revealTimer
        property int index: -1
        property int left: 0
        interval: 90; repeat: true
        onTriggered: {
            const row = blockRepeater.itemAt(index), flick = pageScroll.contentItem
            if (row && flick) {
                const top = row.mapToItem(flick.contentItem,0,0).y, bottom = top+row.height
                const view = pageScroll.availableHeight, most = Math.max(0,pageScroll.contentHeight-view)
                if (bottom+24 > flick.contentY+view) flick.contentY = Math.min(most,bottom+24-view)
                else if (top < flick.contentY) flick.contentY = Math.max(0,top-24)
            }
            if (--left <= 0) stop()
        }
    }
    // A photo on the clipboard (a screenshot, "Copiar imagen", image files) goes in like a chosen one.
    function pastePhoto(index) {
        if (!currentId || deleted || !backend.clipboardPhoto) return false
        const r = call("clipboard_photo")
        if (!r) return true                       // The notice says why (too large, unreadable).
        return insertPhotos(index,r.photos)
    }
    // Photo files chosen in the dialog or dropped on the page; saved at once.
    function insertPhotoFiles(urls, index, exact) {
        if (!currentId || deleted) return false
        const photos = []
        for (const url of urls) {
            const r = call("store_photo",{url: url.toString()})
            if (!r) return false
            photos.push(r)
        }
        return insertPhotos(index,photos,exact) && flush()
    }
    function insertPhoto(url) { return insertPhotoFiles([url],editIndex) }
    function focusSearch() { enterEditor(); sidebarShown = true; pagesExpanded = true; search.forceActiveFocus(); search.selectAll() }
    function openHelp() { helpDialog.open() }
    function openAbout() { aboutDialog.open() }
    function openConnection() { workspaceTabs.currentIndex = 1 }
    function enterEditor() {
        if (resumeWriting) { resumeWriting = false; assistant.cancel() }
        workspaceTabs.currentIndex = 0
    }
    function openTrashConfirmation() { trashDialog.open() }
    // "Foto", "/Foto" or Edición → Insertar foto: the photos land where you are writing.
    property int photoTarget: -1
    function choosePhoto(index) {
        if (!currentId || deleted) return
        photoTarget = index === undefined ? editIndex : index
        photoDialog.open()
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
        rememberStructure()
        blocks.insert(index,rowOf({type: "paragraph", text: text, spans: styles || "[]", indent: indent}))
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
        rememberStructure()
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
        rememberStructure()
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
    // The same inline menu serves "/" (blocks) and "@" or "[[" (page mentions).
    function openSlash(index, start) { slashMenu.query = ""; slash = {index: index, start: start, mode: "blocks", marker: "/"} }
    function openMention(index, start, length) {
        mentionMenu.query = ""
        slash = {index: index, start: start, mode: "pages", marker: length === 2 ? "[[" : "@"}
    }
    function closeSlash() { slash = null }
    function updateSlash() {
        if (!slash) return
        const row = blockRepeater.itemAt(slash.index)
        if (!row || !row.editor.activeFocus) { slash = null; return }
        const editor = row.editor, position = editor.cursorPosition, mark = slash.marker
        if (position < slash.start+mark.length || editor.getText(slash.start,slash.start+mark.length) !== mark) { slash = null; return }
        const query = editor.getText(slash.start+mark.length,position)
        if (query.length > 40 || /\n|\s\s/.test(query)) { slash = null; return }
        if (slash.mode === "pages") { mentionMenu.query = query; return }
        if (position === slash.start) { slash = null; return }
        slashMenu.query = query
        if (!slashMenu.matches.length && /\s$/.test(query)) slash = null
    }
    function slashKey(key) {
        const menu = slash && slash.mode === "pages" ? mentionMenu : slashMenu
        if (key === Qt.Key_Up) menu.move(-1)
        else if (key === Qt.Key_Down) menu.move(1)
        else if (key === Qt.Key_Escape) closeSlash()
        else if (menu === mentionMenu) runMention(mentionMenu.current())
        else runSlash(slashMenu.current())
    }
    // The typed "@query" becomes a mention; "Nueva página" first creates it as a subpage of this one.
    function runMention(entry) {
        const open = slash
        slash = null
        if (!open || !entry) return
        const row = blockRepeater.itemAt(open.index)
        if (!row) return
        let id = entry.id
        if (entry.create) {
            const made = call("create_page",{title: entry.title, parent_id: currentId || null, blocks: [{type: "paragraph", text: ""}]})
            if (!made) return
            id = made.id
            refreshNavigation()
        }
        const caret = row.formatter.insertMention(open.start,Math.max(open.start+open.marker.length,row.editor.cursorPosition),entry.title,id)
        if (caret >= 0) row.focusAt(caret)
    }
    // Pages that mention this one, shown under the title.
    property var backlinks: []
    property bool backlinksOpen: false
    function refreshBacklinks() {
        const found = currentId ? call("backlinks",{id: currentId}) : null
        backlinks = found ? found.pages : []
    }
    // Favorites (in the user's order) and recently visited pages. Neither creates a page revision.
    property var favoriteIds: []
    property var recentVisits: []
    property double clock: Date.now()
    Timer { interval: 60000; repeat: true; running: true; onTriggered: win.clock = Date.now() }
    readonly property bool isFavorite: !!currentId && favoriteIds.indexOf(currentId) >= 0
    readonly property var favoriteRows: favoriteIds.map(id => pages.find(p => p.id === id)).filter(p => !!p)
    readonly property var recentRows: recentVisits.map(v => {
        const p = pages.find(x => x.id === v.id)
        return p ? Object.assign({}, p, {at: v.at, detail: ago(v.at, true)}) : null
    }).filter(p => !!p)
    function setFavorite(id, on, index) {
        const r = call("favorite", index === undefined ? {id: id, on: on} : {id: id, on: on, index: index})
        if (r) favoriteIds = r.favorites
    }
    // "hace 5 min" (or "5 min" in the sidebar), "ayer", "12 nov".
    function ago(at, brief) {
        const then = new Date(at), minutes = Math.floor((clock-then.getTime())/60000)
        if (isNaN(minutes)) return ""
        if (minutes < 1) return "ahora"
        if (minutes < 60) return (brief ? "" : "hace ") + minutes + " min"
        if (minutes < 24*60) return (brief ? "" : "hace ") + Math.floor(minutes/60) + " h"
        const days = Math.round((new Date(clock).setHours(0,0,0,0)-new Date(then).setHours(0,0,0,0))/86400000)
        if (days <= 1) return "ayer"
        if (days < 7) return (brief ? "" : "hace ") + days + (brief ? " d" : " días")
        return then.toLocaleDateString(Qt.locale(),"d MMM")
    }
    function runSlash(command) {
        const open = slash
        slash = null
        if (!open || !command) return
        const row = blockRepeater.itemAt(open.index)
        if (!row) return
        row.editor.remove(open.start,Math.max(open.start+1,row.editor.cursorPosition))
        const empty = !row.formatter.text().trim()
        if (command.key === "image") choosePhoto(open.index)
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
        dropAt = placeLine(sceneY)
    }
    // Where something dropped at sceneY lands (before that block, or the end), with the line placed there.
    function placeLine(sceneY) {
        let target = blocks.count
        for (let i = 0; i < blocks.count; ++i) {
            const row = blockRepeater.itemAt(i), top = row.mapToItem(null,0,0).y
            if (row.visible && sceneY < top+row.height/2) { target = i; break }
        }
        const edge = target < blocks.count ? blockRepeater.itemAt(target) : blockRepeater.itemAt(blocks.count-1)
        if (!edge) { dropX = pageColumn.mapToItem(win.contentItem,0,0).x; dropY = pageColumn.mapToItem(win.contentItem,0,0).y; return target }
        const corner = edge.mapToItem(win.contentItem,0,0)
        dropY = target < blocks.count ? corner.y-5 : corner.y+edge.height+3
        dropX = corner.x
        return target
    }
    // Photo files dragged from the Explorer onto the page.
    property int photoDropAt: -1
    function photoFiles(urls) {
        return (urls || []).filter(u => /^file:/i.test(String(u)) && /\.(png|jpe?g)$/i.test(String(u))).slice(0,20)
    }
    function dragEnd() {
        const from = dragFrom, to = dropAt > dragFrom ? dropAt-1 : dropAt
        dragFrom = -1; dropAt = -1
        if (from < 0 || to < 0 || to === from) return
        rememberStructure()
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
    // Undo for what a text field cannot undo by itself: splitting and joining blocks, adding, moving or
    // removing them, changing their type, indent or look. Each step keeps the page as it was and the caret.
    // Everything changed during one key press or click is one step. Ctrl+Z reaches it once the block's
    // own text has nothing left to undo; Ctrl+Y brings it back.
    property var undoStack: []
    property var redoStack: []
    property bool restoring: false
    property bool structureMarked: false
    // Lengths of the stacks, for the menu (pushing to a var property notifies nobody).
    property int undoDepth: 0
    property int redoDepth: 0
    function snapshot() {
        return {blocks: draft(), index: editIndex,
                caret: textTarget && editIndex >= 0 && textTarget.cursorPosition !== undefined ? textTarget.cursorPosition : -1}
    }
    function rememberStructure() {
        if (loadingPage || restoring || structureMarked || !currentId) return
        structureMarked = true
        Qt.callLater(function() { win.structureMarked = false })
        undoStack.push(snapshot())
        if (undoStack.length > 80) undoStack.shift()
        redoStack = []
        undoDepth = undoStack.length; redoDepth = 0
    }
    function restoreStructure(from, to) {
        if (!from.length || deleted) return false
        const step = from.pop()
        to.push(snapshot())
        undoDepth = undoStack.length; redoDepth = redoStack.length
        // After the key press that asked for it: the block handling that key is rebuilt too.
        Qt.callLater(function() {
            restoring = true
            textTarget = null; editIndex = -1; slash = null
            // Blocks the page no longer has (removed and saved since) come back as new blocks.
            const known = {}
            for (let i = 0; i < blocks.count; ++i) if (blocks.get(i).key) known[blocks.get(i).key] = true
            blocks.clear()
            for (const b of step.blocks) blocks.append(rowOf(Object.assign({}, b, {id: known[b.id] ? b.id : ""})))
            restoring = false
            markDirty(); commentTick++
            if (step.index >= 0 && step.index < blocks.count)
                Qt.callLater(function() { const row = blockRepeater.itemAt(step.index); if (row) row.focusAt(step.caret) })
        })
        return true
    }
    function undoStructure() { return restoreStructure(undoStack,redoStack) }
    function redoStructure() { return restoreStructure(redoStack,undoStack) }
    // A block of the library as a row of the page model, and back (draft). align, tint (text colour),
    // fill (background) and frame (photo style) are the block's look; empty means the default.
    function rowOf(b) {
        return {key: b.id || "", kind: b.type, body: b.text || "",
                spans: typeof b.spans === "string" ? b.spans : JSON.stringify(b.spans || []),
                done: !!b.checked, asset: b.asset || "", photoPercent: b.width_percent || 100, level: b.level || 1,
                indent: b.indent || 0, icon: b.icon || "", collapsed: !!b.collapsed,
                align: b.align || "", tint: b.color || "", fill: b.background || "", frame: b.frame || ""}
    }
    function draft() {
        const data = []
        for (let i = 0; i < blocks.count; ++i) {
            const r = blocks.get(i)
            const b = {id:r.key, type:r.kind, text:r.body}
            if (b.type !== "image" && r.spans && r.spans !== "[]") b.spans = JSON.parse(r.spans)
            if (b.type === "task") b.checked = r.done
            if (b.type === "image") { b.asset = r.asset; b.width_percent = r.photoPercent; if (r.frame) b.frame = r.frame }
            if (b.type === "heading") b.level = r.level || 1
            if (b.type === "callout") b.icon = r.icon || "💡"
            if (b.type === "toggle") b.collapsed = !!r.collapsed
            if (b.type === "divider") { b.text = ""; delete b.spans }
            else {
                if (r.align && (b.type !== "image" || r.align !== "justify")) b.align = r.align
                if (b.type !== "image" && r.tint) b.color = r.tint
                if (b.type !== "image" && r.fill) b.background = r.fill
            }
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
        // Reloading the page you are on (after a save, say) keeps its undo history.
        const samePage = !!id && id === currentId
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
        pageFont = p && p.font ? p.font : "sans"; pageSmall = !!(p && p.small_text); pageWide = !!(p && p.full_width)
        blocks.clear()
        if (p) for (const b of p.blocks) blocks.append(rowOf(b))
        if (!samePage) { undoStack = []; redoStack = []; undoDepth = 0; redoDepth = 0 }
        loadingPage = false
        const parent = p && pages.find(x => x.id === p.parent_id)
        location = deleted ? "Papelera" : parent ? parent.title : "Biblioteca"
        if (pageScroll.contentItem) pageScroll.contentItem.contentY = 0
        backlinksOpen = false; refreshBacklinks()
        if (id && !deleted) {
            const seen = call("visit",{id: id})
            if (seen) recentVisits = seen.recent
        }
    }
    function selectPage(id) { if (flush()) { enterEditor(); info(""); showPage(id) } }
    function refreshNavigation() {
        const nav = call("navigation")
        if (!nav) return
        pages = nav.pages; favoriteIds = nav.favorites; recentVisits = nav.recent
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
        generation = g.value; refreshNavigation(); refreshBacklinks()
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
        rememberStructure()
        blocks.append(rowOf({type: kind})); markDirty()
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
        const saved = call("templates")
        if (saved) userTemplates = saved.templates
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
    function openAsk() { if (flush()) workspaceTabs.currentIndex = 3 }
    RowLayout {
        anchors.fill: parent; spacing: 0
        Rectangle {
            id: sidebar
            visible: win.sidebarShown
            Layout.preferredWidth: Math.max(200,Math.min(win.width-525,win.sidebarPreferredWidth || Math.min(320,Math.round(win.width*0.225))))
            Layout.fillHeight: true
            color: Theme.sidebar
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
                        radius: Theme.radiusButton; border.color: search.activeFocus ? Theme.accent : Theme.line; color: Theme.surface
                        Glyph { name: "search"; anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 14 }
                        Rectangle { width: 39; height: 19; radius: 4; color: Theme.hover; anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter; visible: !search.text
                            Label { anchors.centerIn: parent; text: "Ctrl+K"; font.pixelSize: 10; color: Theme.secondary } }
                    }
                    onTextChanged: if (win.initialized) { if (text) { win.trashMode = false; win.pagesExpanded = true } win.refreshNavigation() }
                }
                UiButton { Layout.topMargin: 12; Layout.leftMargin: 9
                    alignLeft: true; quiet: win.settingsShown || !!win.currentId || win.trashMode; symbol: "home"; text: "Inicio"
                    onClicked: win.browseTrash(false) }
                UiButton { objectName: "askEntry"; Layout.leftMargin: 9
                    alignLeft: true; quiet: workspaceTabs.currentIndex !== 3; symbol: "sparkles"; text: "Preguntar a Lunqio"
                    hint: "Preguntar sobre tus notas (Ctrl+Shift+P)"; onClicked: win.openAsk() }
                ListView {
                    id: navList; Layout.fillWidth: true; Layout.fillHeight: true; Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.topMargin: 4
                    clip: true; spacing: 2; model: win.pagesExpanded ? win.navigationRows : []
                    ScrollBar.vertical: ScrollBar {}
                    // Favoritos and Recientes scroll with the page tree; searching or the trash hides them.
                    readonly property bool shortcuts: !win.trashMode && !search.text.trim()
                    header: ColumnLayout {
                        width: navList.width; spacing: 0
                        SidebarSection {
                            objectName: "favorites"; Layout.fillWidth: true
                            visible: navList.shortcuts && win.favoriteRows.length > 0
                            title: "Favoritos"; favorites: true; rows: win.favoriteRows
                            currentId: win.settingsShown ? "" : win.currentId
                            onChosen: function(id) { win.selectPage(id) }
                            onUnfavorite: function(id) { win.setFavorite(id,false) }
                            onMoved: function(id, index) { win.setFavorite(id,true,index) }
                            onMenuRequested: function(id) { pageRowMenu.show(id) }
                        }
                        SidebarSection {
                            objectName: "recent"; Layout.fillWidth: true
                            visible: navList.shortcuts && win.recentRows.length > 0
                            title: "Recientes"; rows: win.recentRows.slice(0,5)
                            currentId: win.settingsShown ? "" : win.currentId
                            onChosen: function(id) { win.selectPage(id) }
                            onMenuRequested: function(id) { pageRowMenu.show(id) }
                        }
                        RowLayout {
                            Layout.fillWidth: true; Layout.topMargin: 8; Layout.bottomMargin: 2
                            UiButton { text: win.trashMode ? "Papelera" : search.text.trim() ? "Resultados" : "Privado"
                                quiet: true; alignLeft: true; symbol: win.pagesExpanded ? "down" : "right"; hint: "Mostrar u ocultar las páginas"
                                onClicked: win.pagesExpanded = !win.pagesExpanded }
                            Item { Layout.fillWidth: true }
                            UiButton { symbol: "add"; quiet: true; hint: "Crear página en la raíz"; onClicked: win.newPage(null) }
                        }
                    }
                    Menu {
                        id: pageRowMenu
                        property string pageId: ""
                        readonly property bool favorite: win.favoriteIds.indexOf(pageId) >= 0
                        function show(id) { pageId = id; popup() }
                        MenuItem { text: pageRowMenu.favorite ? "Quitar de favoritos" : "Añadir a favoritos"
                            onTriggered: win.setFavorite(pageRowMenu.pageId,!pageRowMenu.favorite) }
                        MenuItem { text: "Nueva subpágina"; onTriggered: win.newPage(pageRowMenu.pageId) }
                    }
                    delegate: Rectangle {
                        id: navRow
                        required property var modelData
                        HoverHandler { id: rowHover }
                        TapHandler { acceptedButtons: Qt.RightButton; enabled: !win.trashMode; onTapped: pageRowMenu.show(navRow.modelData.page.id) }
                        width: navList.width; height: 34; radius: 5
                        color: !win.settingsShown && modelData.page.id === win.currentId ? Theme.hover : rowHover.hovered ? Theme.raised : "transparent"
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 8 + Math.min(6,navRow.modelData.depth)*12; anchors.rightMargin: 6; spacing: 3
                            UiButton {
                                visible: navRow.modelData.branch; Layout.preferredWidth: 19; quiet: true; hint: "Mostrar u ocultar subpáginas"
                                symbol: win.collapsed[navRow.modelData.page.id] ? "right" : "down"
                                onClicked: { win.collapsed[navRow.modelData.page.id] = !win.collapsed[navRow.modelData.page.id]; win.refreshNavigation() }
                            }
                            Button {
                                id: navButton; flat: true; Layout.fillWidth: true; Layout.fillHeight: true; padding: 3
                                background: Rectangle { color: "transparent"; radius: 4; border.width: navButton.visualFocus ? 1 : 0; border.color: Theme.focus }
                                contentItem: RowLayout {
                                    spacing: 9
                                    PageIcon { icon: navRow.modelData.page.icon || ""; size: 15 }
                                    Label { text: navRow.modelData.page.title; color: navRow.modelData.page.id === win.currentId ? Theme.text : Theme.secondary; Layout.fillWidth: true; elide: Text.ElideRight }
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
                    Label { visible: win.pagesExpanded && !navList.count; anchors.left: parent.left; anchors.leftMargin: 12; text: win.trashMode ? "Papelera vacía" : search.text ? "Sin coincidencias" : "Aún no hay páginas"; color: Theme.muted; font.pixelSize: 13 }
                }
                UiButton { Layout.fillWidth: true; Layout.margins: 9; quiet: !win.trashMode; alignLeft: true; text: "Papelera"; symbol: "trash"; onClicked: win.browseTrash(!win.trashMode) }
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hover }
                RowLayout {
                    Layout.fillWidth: true; Layout.margins: 10; spacing: 3
                    Image { objectName: "appLogo"; source: "../assets/lunqio-64.png"; sourceSize: Qt.size(64,64)
                        Layout.preferredWidth: 29; Layout.preferredHeight: 29; smooth: true; mipmap: true; Accessible.ignored: true }
                    Button {
                        id: mcpBadge; flat: true; Layout.fillWidth: true; implicitHeight: 39
                        Accessible.name: mcpText.text + ". Ajustes de conexión"; onClicked: win.openConnection()
                        background: Rectangle { radius: 5; color: mcpBadge.hovered ? Theme.hover : "transparent"; border.width: mcpBadge.visualFocus ? 1 : 0; border.color: Theme.focus }
                        contentItem: ColumnLayout {
                            spacing: 1
                            Label { text: "Lunqio"; font.weight: Font.DemiBold; font.pixelSize: 14 }
                            RowLayout { spacing: 5
                                Rectangle { width: 6; height: 6; radius: 3; color: win.assistant.link.state === "connected" ? Theme.success : win.assistant.link.state === "connecting" ? Theme.warning : Theme.muted }
                                Label { id: mcpText; font.pixelSize: 11; color: Theme.secondary; text: win.assistant.link.state === "connected" ? "MCP conectado" : win.assistant.link.state === "connecting" ? "Conectando MCP…" : "MCP desconectado" }
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
            color: splitter.containsMouse ? Theme.accent : Theme.hover
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
                background: Rectangle { color: Theme.base; Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.hover } }
                component WorkspaceTab: TabButton {
                    id: tab; width: implicitWidth; horizontalPadding: 16; implicitHeight: 36
                    contentItem: Text { text: tab.text; color: tab.checked ? Theme.text : Theme.muted; font.weight: tab.checked ? Font.DemiBold : Font.Normal; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { color: tab.hovered || tab.visualFocus ? Theme.hover : "transparent"
                        Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: parent.width-18; height: 2; color: Theme.accent; visible: tab.checked } }
                }
                WorkspaceTab { text: "Editor"; objectName: "editorTab" }
                WorkspaceTab { text: "Conectores"; objectName: "connectorsTab"; Accessible.name: "Conectores MCP" }
                WorkspaceTab { text: "Uso"; objectName: "usageTab"; Accessible.name: "Uso de tokens de IA" }
                WorkspaceTab { text: "Preguntar"; objectName: "askTab"; Accessible.name: "Preguntar a Lunqio sobre tus notas" }
                onCurrentIndexChanged: if (currentIndex === 0 && win.resumeWriting) {
                    win.resumeWriting = false
                    if (writing.selection.id === win.currentId && writing.selection.expected_revision === win.revision) writing.open()
                    else win.assistant.cancel()
                }
            }
            ConnectorsPage { visible: workspaceTabs.currentIndex === 1; Layout.fillWidth: true; Layout.fillHeight: true
                assistant: win.assistant; onChooseCodex: cliDialog.open(); onChooseClaude: claudeDialog.open() }
            UsagePage { objectName: "usagePage"; visible: workspaceTabs.currentIndex === 2; Layout.fillWidth: true; Layout.fillHeight: true; assistant: win.assistant }
            AskPage { id: askPage; objectName: "askPage"; visible: workspaceTabs.currentIndex === 3; Layout.fillWidth: true; Layout.fillHeight: true; assistant: win.assistant; workspace: win }
            RowLayout {
                visible: !win.settingsShown
                Layout.fillWidth: true; Layout.preferredHeight: 48; Layout.leftMargin: 18; Layout.rightMargin: 14; spacing: 8
                UiButton { visible: !win.sidebarShown; symbol: "panel"; hint: "Mostrar barra lateral"; quiet: true; onClicked: win.sidebarShown = true }
                PageIcon { icon: win.currentId ? win.pageIcon : ""; glyph: win.currentId ? "page" : "home"; size: 15 }
                Label { text: win.currentId ? titleInput.text : win.trashMode ? "Papelera" : "Inicio"; elide: Text.ElideRight; Layout.maximumWidth: 290; font.pixelSize: 14 }
                Glyph { name: "lock"; font.pixelSize: 11; visible: !!win.currentId }
                Label { visible: !!win.currentId; text: win.deleted ? "Papelera" : "Privada"; color: Theme.muted; font.pixelSize: 12 }
                Item { Layout.fillWidth: true }
                Label { visible: !!win.currentId; text: win.conflict ? "Conflicto de edición" : win.dirty ? "Cambios pendientes" : "Guardado · v" + win.revision; color: win.dirty ? Theme.warning : Theme.muted; font.pixelSize: 12 }
                UiButton { visible: !win.sidebarShown; symbol: "link"; text: mcpText.text; quiet: true; hint: "Conectores"; onClicked: win.openConnection() }
                UiButton {
                    objectName: "favoriteButton"; visible: !!win.currentId && !win.deleted; quiet: true
                    symbol: win.isFavorite ? "starFilled" : "star"; symbolColor: win.isFavorite ? Theme.favorite : Theme.secondary
                    hint: win.isFavorite ? "Quitar de favoritos" : "Añadir a favoritos"
                    onClicked: win.setFavorite(win.currentId,!win.isFavorite)
                }
                UiButton {
                    symbol: "more"; hint: "Opciones de página"; quiet: true; visible: !!win.currentId && !win.deleted
                    onClicked: pageMenu.popup()
                    Menu { id: pageMenu
                        MenuItem { text: win.isFavorite ? "Quitar de favoritos" : "Añadir a favoritos"; onTriggered: win.setFavorite(win.currentId,!win.isFavorite) }
                        Menu {
                            title: "Fuente"
                            MenuItem { text: "Predeterminada"; checkable: true; checked: win.pageFont === "sans"; onTriggered: win.setPageLook("font","sans") }
                            MenuItem { text: "Serif"; checkable: true; checked: win.pageFont === "serif"; onTriggered: win.setPageLook("font","serif") }
                            MenuItem { text: "Mono"; checkable: true; checked: win.pageFont === "mono"; onTriggered: win.setPageLook("font","mono") }
                        }
                        MenuItem { text: "Texto pequeño"; checkable: true; checked: win.pageSmall; onTriggered: win.setPageLook("small_text",!win.pageSmall) }
                        MenuItem { text: "Ancho completo"; checkable: true; checked: win.pageWide; onTriggered: win.setPageLook("full_width",!win.pageWide) }
                        MenuItem { text: "Guardar como plantilla…"; onTriggered: { templateName.text = titleInput.text; templateDialog.open() } }
                        MenuSeparator {}
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
                Label { text: win.notice; wrapMode: Text.Wrap; Layout.fillWidth: true; color: win.noticeError ? Theme.danger : Theme.success }
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
                    RecentCards {
                        objectName: "recentCards"; Layout.fillWidth: true; Layout.topMargin: 6
                        visible: !win.trashMode && win.recentRows.length > 0
                        rows: win.recentRows; covers: win.covers; describe: function(at) { return win.ago(at,false) }
                        onChosen: function(id) { win.selectPage(id) }
                    }
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
                    width: Math.min(win.pageWide ? 1600 : 780, pageScroll.availableWidth-pageScroll.gutter-(pageScroll.withRail && pageScroll.railFits ? 332 : 0))
                    spacing: 9
                    onHeightChanged: rail.schedule()
                    onWidthChanged: rail.schedule()
                    Item { Layout.preferredHeight: win.pageCover ? (win.pageIcon ? 0 : 20) : Math.min(94,win.height*0.1) }
                    PageHeader { id: pageHeader; Layout.fillWidth: true; page: win; picker: emojiPicker; titleHovered: titleArea.hovered || titleInput.activeFocus }
                    Label { visible: win.location !== "Biblioteca" && !win.deleted; text: win.location; color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                    TextArea {
                        id: titleInput; objectName: "titleInput"; Layout.fillWidth: true
                        wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText; font.pixelSize: (win.width >= 1150 ? 38 : 32)-(win.pageSmall ? 4 : 0); font.weight: Font.DemiBold; font.family: win.pageFamily
                        color: Theme.text; padding: 0; bottomPadding: 12; background: Item {}
                        placeholderText: "Sin título"; Accessible.name: "Título de la página"; placeholderTextColor: Theme.faint
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
                    TemplateStrip {
                        objectName: "templateStrip"; Layout.fillWidth: true; Layout.bottomMargin: 8
                        visible: win.pageEmpty
                        saved: win.userTemplates
                        onChosen: function(page) { win.applyTemplate(page) }
                        onRemoveRequested: function(id) { win.removeTemplate(id) }
                    }
                    // Backlinks: pages that mention this one (as in Notion, under the title).
                    ColumnLayout {
                        objectName: "backlinks"
                        visible: win.backlinks.length > 0
                        Layout.fillWidth: true; Layout.bottomMargin: 6; spacing: 2
                        UiButton {
                            objectName: "backlinksToggle"; quiet: true; alignLeft: true
                            text: "↩  " + win.backlinks.length + (win.backlinks.length === 1 ? " página enlaza aquí" : " páginas enlazan aquí")
                            onClicked: win.backlinksOpen = !win.backlinksOpen
                        }
                        Repeater {
                            model: win.backlinksOpen ? win.backlinks : []
                            delegate: AbstractButton {
                                id: backlink
                                required property var modelData
                                Layout.fillWidth: true; implicitHeight: 46; leftPadding: 12; rightPadding: 12
                                hoverEnabled: true
                                Accessible.name: "Abrir " + modelData.title
                                onClicked: win.selectPage(modelData.id)
                                background: Rectangle { radius: Theme.radiusButton; color: backlink.hovered ? Theme.raised : "transparent" }
                                contentItem: RowLayout {
                                    spacing: 10
                                    PageIcon { icon: backlink.modelData.icon || ""; size: 15 }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Text { text: backlink.modelData.title; color: Theme.text; font.pixelSize: 14; elide: Text.ElideRight; Layout.fillWidth: true }
                                        Text { text: backlink.modelData.snippet; color: Theme.muted; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                }
                            }
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
                            onMentionTyped: function(start, marker) { win.openMention(index,start,marker) }
                            onOpenPage: function(id) { win.selectPage(id) }
                            pastePhoto: function() { return win.pastePhoto(index) }
                            undoStructure: function() { return win.undoStructure() }
                            escapeKey: function() { if (!bubble.paletteOpen) return false; bubble.closePalette(); return true }
                            redoStructure: function() { return win.redoStructure() }
                            onSlashKey: function(key) { win.slashKey(key) }
                            onAddBelow: win.addBlockBelow(index)
                            onDragStarted: { win.dragFrom = index; win.dropAt = -1 }
                            onDragMoved: function(sceneY) { win.dragMove(sceneY) }
                            onDragFinished: win.dragEnd()
                            onCheck: function(value) { blocks.setProperty(index,"done",value); win.markDirty() }
                            onResizePhoto: function(value) { blocks.setProperty(index,"photoPercent",value); win.markDirty() }
                            onShift: function(offset) { win.rememberStructure(); blocks.move(index,index+offset,1); win.editIndex = -1; win.markDirty() }
                            onRemoveRow: { win.rememberStructure(); win.editIndex = -1; blocks.remove(index); win.markDirty() }
                            onChangeKind: function(value) { win.setKind(index,value) }
                            onLookRequested: function(role, value) { win.setBlockLook(index,role,value) }
                            onPhotoAction: function(name) { win.photoAction(index,name) }
                            pageFont: win.pageFont; smallText: win.pageSmall
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
                UiButton { objectName: "composeButton"; symbol: "sparkles"; text: "Crear con IA"; hint: "Crear con IA (Ctrl+J)"; onClicked: win.openComposer(-2) }
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
    Shortcut { sequence: "Escape"; enabled: bubble.shown && (!bubble.menuOpen || bubble.paletteOpen); onActivated: bubble.paletteOpen ? bubble.closePalette() : bubble.dismiss() }
    Shortcut { sequence: "Ctrl+J"; enabled: !win.settingsShown && !!win.currentId && !win.deleted; onActivated: win.openComposer(-2) }
    Shortcut {
        sequence: "Escape"; enabled: composer.visible && !bubble.shown
        onActivated: composer.busy ? win.assistant.cancel() : composer.close()
    }
    // Where the "/" or "@" was typed, in window coordinates.
    readonly property var slashSpot: {
        win.width; win.height; pageScroll.contentItem ? pageScroll.contentItem.contentY : 0
        if (!win.slash) return Qt.point(0,0)
        const row = blockRepeater.itemAt(win.slash.index)
        if (!row) return Qt.point(0,0)
        const r = row.editor.positionToRectangle(win.slash.start)
        return row.editor.mapToItem(win.contentItem,r.x,r.y+r.height+6)
    }
    SlashMenu {
        id: slashMenu; objectName: "slashMenu"
        visible: !!win.slash && win.slash.mode === "blocks" && !win.settingsShown
        x: Math.max(8,Math.min(win.slashSpot.x-8,win.contentItem.width-width-8))
        y: win.slashSpot.y+height+12 > win.contentItem.height ? Math.max(8,win.slashSpot.y-height-40) : win.slashSpot.y
        onChosen: function(command) { win.runSlash(command) }
    }
    PageMenu {
        id: mentionMenu; objectName: "pageMenu"
        visible: !!win.slash && win.slash.mode === "pages" && !win.settingsShown
        pages: win.pages; currentId: win.currentId
        x: Math.max(8,Math.min(win.slashSpot.x-8,win.contentItem.width-width-8))
        y: win.slashSpot.y+height+12 > win.contentItem.height ? Math.max(8,win.slashSpot.y-height-40) : win.slashSpot.y
        onChosen: function(entry) { win.runMention(entry) }
    }
    Connections {
        target: win.slash ? blockRepeater.itemAt(win.slash.index).editor : null
        function onTextChanged() { win.updateSlash() }
        function onCursorPositionChanged() { win.updateSlash() }
        function onActiveFocusChanged() { Qt.callLater(win.updateSlash) }
    }
    Rectangle {
        objectName: "dropLine"
        visible: (win.dragFrom >= 0 && win.dropAt >= 0) || win.photoDropAt >= 0
        x: win.dropX; y: win.dropY
        width: pageColumn.width; height: 3; radius: 1.5; color: Theme.accent; z: 30
    }
    // PNG or JPEG files dragged from the Explorer become photos where the line shows.
    DropArea {
        objectName: "photoDrop"
        anchors.fill: parent; z: 40
        enabled: !win.settingsShown && !!win.currentId && !win.deleted
        onEntered: function(drag) {
            if (!win.photoFiles(drag.urls).length) { drag.accepted = false; return }
            drag.accept(Qt.CopyAction)
            win.photoDropAt = win.placeLine(mapToItem(null,drag.x,drag.y).y)
        }
        onPositionChanged: function(drag) { if (win.photoDropAt >= 0) win.photoDropAt = win.placeLine(mapToItem(null,drag.x,drag.y).y) }
        onExited: win.photoDropAt = -1
        onDropped: function(drop) {
            const files = win.photoFiles(drop.urls), at = win.placeLine(mapToItem(null,drop.x,drop.y).y)
            win.photoDropAt = -1
            if (!files.length) return
            drop.accept(Qt.CopyAction)
            win.insertPhotoFiles(files,at,true)
        }
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
            Label { text: "Aparece en los comentarios y respuestas nuevos."; color: Theme.secondary; wrapMode: Text.Wrap; Layout.fillWidth: true }
            TextField { id: authorField; Layout.fillWidth: true; maximumLength: 80; selectByMouse: true; onAccepted: authorDialog.accept() }
        }
    }
    Dialog {
        id: templateDialog; objectName: "templateDialog"; title: "Guardar como plantilla"; modal: true; anchors.centerIn: parent; width: 400
        standardButtons: Dialog.Save | Dialog.Cancel
        onAccepted: if (templateName.text.trim()) win.saveTemplate(templateName.text)
        contentItem: ColumnLayout {
            spacing: 8
            Label { text: "Guarda el título, el aspecto y los bloques de esta página (sin comentarios). Aparecerá en las páginas vacías."; color: Theme.secondary; wrapMode: Text.Wrap; Layout.fillWidth: true }
            TextField { id: templateName; objectName: "templateName"; Layout.fillWidth: true; maximumLength: 80; selectByMouse: true; placeholderText: "Nombre de la plantilla"; onAccepted: templateDialog.accept() }
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
                Label { Layout.fillWidth: true; text: "v"+modelData.revision+" · "+(modelData.actor === "mcp" ? "MCP" : "Manual")+"\n"+new Date(modelData.at).toLocaleString(); color: Theme.text }
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
        id: photoDialog; title: "Insertar fotos"; fileMode: Native.FileDialog.OpenFiles
        nameFilters: ["Fotos (*.jpg *.jpeg *.png)"]; onAccepted: win.insertPhotoFiles(selectedFiles,win.photoTarget)
    }
    Native.FileDialog {
        id: replaceDialog; title: "Reemplazar foto"; fileMode: Native.FileDialog.OpenFile
        nameFilters: ["Fotos (*.jpg *.jpeg *.png)"]; onAccepted: win.replacePhoto(selectedFile)
    }
    Native.FileDialog {
        id: savePhotoDialog; title: "Guardar foto"; fileMode: Native.FileDialog.SaveFile
        nameFilters: ["Imagen (*.png *.jpg)"]
        onAccepted: if (win.photoIndex >= 0 && win.call("photo_save",{asset: blocks.get(win.photoIndex).asset, url: selectedFile.toString()})) win.info("Foto guardada.")
    }
    // A photo at full size over the window; a click, Escape or the close button hides it.
    Popup {
        id: photoViewer; objectName: "photoViewer"
        property string asset: ""
        property string caption: ""
        function show(a, c) { asset = a; caption = c; open() }
        parent: Overlay.overlay; x: 0; y: 0; width: parent ? parent.width : 0; height: parent ? parent.height : 0
        modal: true; dim: false; padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: "#E6100C0B" }
        contentItem: Item {
            TapHandler { onTapped: photoViewer.close() }
            Image {
                anchors.fill: parent; anchors.margins: 48; anchors.bottomMargin: photoViewer.caption ? 84 : 48
                source: photoViewer.asset ? backend.photoUrl(photoViewer.asset) : ""
                fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; asynchronous: true
            }
            Label {
                visible: !!photoViewer.caption; text: photoViewer.caption; color: "#FBF1E0"; font.pixelSize: 15
                anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 36
                width: Math.min(implicitWidth,parent.width-96); elide: Text.ElideRight
            }
            UiButton {
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14
                symbol: "close"; symbolColor: "#FBF1E0"; quiet: true; hint: "Cerrar (Esc)"; onClicked: photoViewer.close()
            }
        }
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
