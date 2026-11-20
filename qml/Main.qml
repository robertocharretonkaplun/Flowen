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
    property alias search: sidebar.searchField
    readonly property bool askOpen: workspaceTabs.currentIndex === 3
    function openUsage() { workspaceTabs.currentIndex = 2 }
    property int sidebarPreferredWidth: 0
    property bool pagesExpanded: true
    property var textTarget: null
    property int editIndex: -1
    property bool loadingPage: false
    readonly property bool settingsShown: workspaceTabs.currentIndex !== 0
    property bool resumeWriting: false
    readonly property var assistant: backend.assistant
    readonly property bool canEditSelection: !settingsShown && !!currentId && !locked && !conflict && !!textTarget && editIndex >= 0 && !!textTarget.selectedText
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
    function setPageIcon(emoji) { if (currentId && !locked) action("update_page",{icon: emoji ? emoji : null}) }
    function setPageCover(value) { if (currentId && !locked) action("update_page",{cover: value ? value : null}) }
    // The page's typography (⋯ menu): font, smaller text and full width.
    property string pageFont: "sans"
    property bool pageSmall: false
    property bool pageWide: false
    readonly property string pageFamily: pageFont === "serif" ? "Georgia" : pageFont === "mono" ? Theme.mono : Theme.family
    // How pages are shown (the view buttons of the top bar, Ver): "edit"; "read", Modo lectura, where the
    // page cannot be changed and the tools around the text go away; or "page", Diseño de página, the page
    // on sheets of paper with margins and numbers, as in Word. Kept between sessions, like the paper.
    readonly property var viewModes: ["edit","read","page"]
    property string viewMode: { const v = String(backend.preference("viewMode","edit")); return viewModes.indexOf(v) >= 0 ? v : "edit" }
    readonly property bool reading: viewMode === "read"
    readonly property bool paged: viewMode === "page"
    // Nothing on the page can change: it is in the trash, or being read.
    readonly property bool locked: deleted || reading
    function setViewMode(mode) {
        if (viewModes.indexOf(mode) < 0 || mode === viewMode) return
        if (mode === "read") {
            slash = null; commentDraft = null
            if (textTarget) textTarget.deselect()
            flush()
        }
        viewMode = mode
        backend.setPreference("viewMode",mode)
    }
    // The sheet of Diseño de página and of PDF files: Carta or A4 (as the region uses, until one is chosen),
    // with Word's margins: normales 2,54 cm, estrechos 1,27 cm, anchos 5,08 cm at the sides. 96 px per inch.
    property string paper: { const v = String(backend.preference("paper","")); return v === "letter" || v === "a4" ? v : regionPaper() }
    property string margins: { const v = String(backend.preference("margins","normal")); return ["normal","narrow","wide"].indexOf(v) >= 0 ? v : "normal" }
    function regionPaper() {
        const letter = ["US","CA","MX","CO","VE","CL","PH","GT","CR","PA","DO","PR","SV","HN","NI"]
        return letter.indexOf(Qt.locale().name.split("_")[1] || "") >= 0 ? "letter" : "a4"
    }
    function setPaper(value) { if (value === "letter" || value === "a4") { paper = value; backend.setPreference("paper",value) } }
    function setMargins(value) { if (["normal","narrow","wide"].indexOf(value) >= 0) { margins = value; backend.setPreference("margins",value) } }
    readonly property int paperWidth: paper === "letter" ? 816 : 794
    readonly property int paperHeight: paper === "letter" ? 1056 : 1123
    readonly property int marginX: margins === "narrow" ? 48 : margins === "wide" ? 192 : 96
    readonly property int marginY: margins === "narrow" ? 48 : 96
    readonly property int sheetGap: 24
    readonly property int deskMargin: 28
    // Where blocks start a new sheet. A block that does not fit in what is left of a sheet moves to the top
    // of the next one, and a heading right above it goes along; a block taller than a whole sheet stays.
    // pageBreaks[i] is the room added above block i; the sheets are as many as the text needs.
    property var pageBreaks: []
    property int sheetCount: 1
    function paginate() {
        if (!paged || !currentId) {
            if (pageBreaks.length) pageBreaks = []
            sheetCount = 1
            return
        }
        // Hidden behind another tab the blocks are not laid out; this runs again when the page shows.
        if (!pageScroll.visible) return
        const stride = paperHeight+sheetGap, usable = paperHeight-2*marginY
        // The visible blocks where they would be without the added room.
        const rows = []
        let present = 0
        for (let i = 0; i < blocks.count; ++i) {
            const row = blockRepeater.itemAt(i)
            if (!row || !row.visible) continue
            present += row.breakGap
            rows.push({index: i, top: row.y-present, height: row.height, heading: row.kind === "heading"})
        }
        const gaps = []
        for (let i = 0; i < blocks.count; ++i) gaps.push(0)
        let added = 0
        for (let k = 0; k < rows.length; ++k) {
            const r = rows[k], top = r.top+added
            const sheet = Math.floor(top/stride), local = top-sheet*stride
            if (local <= 0 || local+r.height <= usable || r.height > usable) continue
            const prev = k > 0 ? rows[k-1] : null
            if (prev && prev.heading && !gaps[prev.index]) {
                const above = prev.top+added, at = Math.floor(above/stride)
                if (at === sheet && above-at*stride > 0) {
                    gaps[prev.index] = (sheet+1)*stride-above
                    added += gaps[prev.index]
                    --k          // This block follows its heading on the next sheet; check it again there.
                    continue
                }
            }
            gaps[r.index] = (sheet+1)*stride-top
            added += gaps[r.index]
        }
        const height = pageColumn.implicitHeight-present+added
        const count = Math.max(1,Math.floor(Math.max(0,height-1)/stride)+1)
        if (JSON.stringify(gaps) !== JSON.stringify(pageBreaks)) pageBreaks = gaps
        if (count !== sheetCount) sheetCount = count
    }
    Timer { id: paginateTimer; interval: 40; onTriggered: win.paginate() }
    function schedulePages() { if (paged || pageBreaks.length) paginateTimer.restart() }
    onPagedChanged: schedulePages()
    onPaperChanged: schedulePages()
    onMarginsChanged: schedulePages()
    onStructureChanged: schedulePages()
    // The sheet in the middle of the view, for "Página 2 de 5".
    readonly property int currentSheet: {
        if (!paged || !pageScroll.contentItem) return 1
        const middle = pageScroll.contentItem.contentY+pageScroll.availableHeight/3-deskMargin
        return Math.max(1,Math.min(sheetCount,Math.floor(middle/(paperHeight+sheetGap))+1))
    }
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
        if (!currentId || locked || blocks.count > 1) return false
        return blocks.count === 0 || (blocks.get(0).kind === "paragraph" && !blocks.get(0).body)
    }
    function today() { return new Date().toLocaleDateString(Qt.locale(),"d 'de' MMMM 'de' yyyy") }
    // The page takes the template's blocks, its look and, while it has no name of its own, its title.
    function applyTemplate(t) {
        if (!currentId || locked || !t) return
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
    // The pages above the open one, nearest last (at most three).
    readonly property var ancestors: {
        const out = []
        let page = pages.find(x => x.id === currentId)
        for (let guard = 0; page && page.parent_id && guard < 32; ++guard) {
            page = pages.find(x => x.id === page.parent_id)
            if (page) out.unshift(page)
        }
        return out.slice(-3)
    }
    // The headings of the page, for its outline.
    readonly property var headings: {
        structure; blocks.count
        const out = []
        for (let i = 0; i < blocks.count; ++i) {
            const b = blocks.get(i)
            if (b.kind === "heading" && b.body.trim()) out.push({index: i, level: b.level || 1, text: b.body.trim()})
        }
        return out
    }
    // Scrolls a block to the top of the page area and puts the caret in it.
    function goToBlock(index) {
        const row = blockRepeater.itemAt(index), flick = pageScroll.contentItem
        if (!row || !flick) return
        const top = row.mapToItem(flick.contentItem,0,0).y
        flick.contentY = Math.max(0,Math.min(top-32,pageScroll.contentHeight-pageScroll.availableHeight))
        row.focusAt(-1)
    }
    // Ctrl+D or Duplicar: a copy right below, without comments.
    function duplicateBlock(index) {
        if (index < 0 || index >= blocks.count || locked) return
        rememberStructure()
        const copy = Object.assign({}, draft()[index], {id: ""})
        if (copy.spans) copy.spans = copy.spans.map(s => { const t = Object.assign({}, s); delete t.comment; delete t.thread; return t })
                                         .filter(s => s.style || s.link || s.color || s.background)
        blocks.insert(index+1,rowOf(copy))
        markDirty(); commentTick++
        Qt.callLater(function() { const row = blockRepeater.itemAt(index+1); if (row) row.focusAt(-1) })
    }
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
        else if (name === "replace" && !locked) replaceDialog.open()
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
        if (index < 0 || index >= blocks.count || locked) return
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
        if (!currentId || locked || !backend.clipboardPhoto) return false
        const r = call("clipboard_photo")
        if (!r) return true                       // The notice says why (too large, unreadable).
        return insertPhotos(index,r.photos)
    }
    // Photo files chosen in the dialog or dropped on the page; saved at once.
    function insertPhotoFiles(urls, index, exact) {
        if (!currentId || locked) return false
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
    // The open page goes to the trash at once; the notice offers to bring it back (as in Notion).
    function openTrashConfirmation() { trashPage(currentId) }
    // Operations on any page of the sidebar (right click), not only the open one.
    function trashPage(id) {
        if (!id || (id === currentId && !flush())) return false
        const p = call("page",{id: id})
        if (!p || p.deleted_at || !call("trash_page",{id: id, expected_revision: p.revision})) return false
        refreshNavigation()
        // When the open page (or one above it) went too, show the first page left.
        if (currentId && !pages.some(x => x.id === currentId)) showPage(navigationRows.length ? navigationRows[0].page.id : "")
        toast("«" + p.title + "» está en la papelera.","Deshacer",function() { restorePage(id) })
        return true
    }
    function restorePage(id) {
        const p = call("page",{id: id})
        if (!p || !p.deleted_at || !call("restore_page",{id: id, expected_revision: p.revision})) return false
        refreshNavigation()
        if (id === currentId) showPage(id)
        toast("«" + p.title + "» se restauró.")
        return true
    }
    // A copy next to the page: its look and blocks, without comments (subpages stay with the original).
    function duplicatePage(id) {
        if (id === currentId && !flush()) return ""
        const p = call("page",{id: id})
        if (!p) return ""
        const copies = p.blocks.map(b => {
            const c = Object.assign({}, b)
            delete c.id
            if (c.spans) c.spans = c.spans.map(s => { const t = Object.assign({}, s); delete t.comment; delete t.thread; return t })
                                     .filter(s => s.style || s.link || s.color || s.background)
            if (c.spans && !c.spans.length) delete c.spans
            return c
        })
        const made = call("create_page",{title: (p.title + " (copia)").slice(0,240), parent_id: p.parent_id, icon: p.icon,
                                         cover: p.cover, font: p.font || "sans", small_text: !!p.small_text, full_width: !!p.full_width,
                                         blocks: copies.slice(0,128)})
        if (!made) return ""
        // create_page takes 128 blocks at a time; the rest follow in order.
        let revision = made.revision
        for (let at = 128; at < copies.length; at += 128) {
            const r = call("apply_block_changes",{id: made.id, expected_revision: revision, changes: copies.slice(at,at+128).map(b => ({op: "insert", block: b}))})
            if (!r) break
            revision = r.revision
        }
        refreshNavigation(); selectPage(made.id)
        toast("Se duplicó «" + p.title + "».")
        return made.id
    }
    function renamePage(id, title) {
        title = (title || "").trim()
        if (!title) return false
        if (id === currentId) { titleInput.text = title; markDirty(); return flush() }
        const p = call("page",{id: id})
        if (!p || !call("update_page",{id: id, expected_revision: p.revision, title: title})) return false
        refreshNavigation()
        return true
    }
    function movePage(id, parent) {
        if (id === currentId) return action("update_page",{parent_id: parent})
        const p = call("page",{id: id})
        if (!p || !call("update_page",{id: id, expected_revision: p.revision, parent_id: parent})) return false
        if (parent) collapsed[parent] = false
        refreshNavigation()
        return true
    }
    function openRename(id) {
        const p = pages.find(x => x.id === id)
        renameDialog.pageId = id; renameField.text = p ? p.title : ""; renameDialog.open()
    }
    function openMove(id) { if (id !== currentId || flush()) { moveDialog.pageId = id; moveDialog.open() } }
    // A short notice at the bottom, with one action (Deshacer); it leaves by itself.
    function toast(message, label, run) {
        toastBox.message = message; toastBox.label = label || ""; toastBox.run = run || null
        toastTimer.restart()
    }
    // "Foto", "/Foto" or Edición → Insertar foto: the photos land where you are writing.
    property int photoTarget: -1
    function choosePhoto(index) {
        if (!currentId || locked) return
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
        if (!row || !row.formatter || locked) return
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
        if (locked) return
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
        if (locked) return
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
        if (index <= 0 || locked) return
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
        if (settingsShown || !currentId || locked || conflict) return
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
        if (!from.length || locked) return false
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
        // A new page is for writing: Modo lectura gives way to Edición.
        if (reading) setViewMode("edit")
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
        if (!currentId || locked) return
        rememberStructure()
        blocks.append(rowOf({type: kind})); markDirty()
        Qt.callLater(function() {
            const row = blockRepeater.itemAt(blocks.count-1)
            if (row) row.focusEditor()
            if (pageScroll.contentItem) pageScroll.contentItem.contentY = Math.max(0,pageScroll.contentHeight-pageScroll.availableHeight)
        })
    }
    // kind: "export", "draft" or "backup"; format "pdf" picks that type in the dialog.
    function requestFile(kind, format) {
        if (kind !== "draft" && !flush()) return
        fileAction = kind
        if (format === "pdf") fileDialog.selectedNameFilter.index = 1
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
        Sidebar { id: sidebar; workspace: win }
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
                // Breadcrumbs: the pages above this one (the last three), each a click away.
                Repeater {
                    model: win.currentId ? win.ancestors : []
                    delegate: RowLayout {
                        id: crumb
                        required property var modelData
                        spacing: 2
                        AbstractButton {
                            implicitHeight: 28; leftPadding: 6; rightPadding: 6; hoverEnabled: true
                            Accessible.name: "Abrir " + crumb.modelData.title
                            onClicked: win.selectPage(crumb.modelData.id)
                            background: Rectangle { radius: 6; color: parent.hovered ? Theme.hover : "transparent" }
                            contentItem: RowLayout {
                                spacing: 6
                                PageIcon { icon: crumb.modelData.icon || ""; size: 13 }
                                Text { text: crumb.modelData.title; color: Theme.secondary; font.pixelSize: 13; elide: Text.ElideRight; Layout.maximumWidth: 150 }
                            }
                        }
                        Text { text: "/"; color: Theme.faint; font.pixelSize: 13 }
                    }
                }
                PageIcon { icon: win.currentId ? win.pageIcon : ""; glyph: win.currentId ? "page" : "home"; size: 15 }
                Label { text: win.currentId ? titleInput.text : win.trashMode ? "Papelera" : "Inicio"; elide: Text.ElideRight; Layout.maximumWidth: 290; font.pixelSize: 14 }
                Glyph { name: "lock"; font.pixelSize: 11; visible: !!win.currentId }
                Label { visible: !!win.currentId; text: win.deleted ? "Papelera" : "Privada"; color: Theme.muted; font.pixelSize: 12 }
                Item { Layout.fillWidth: true }
                Label { visible: !!win.currentId; text: win.conflict ? "Conflicto de edición" : win.dirty ? "Cambios pendientes" : "Guardado · v" + win.revision; color: win.dirty ? Theme.warning : Theme.muted; font.pixelSize: 12 }
                UiButton { visible: !win.sidebarShown; symbol: "link"; text: sidebar.mcpLabel; quiet: true; hint: "Conectores"; onClicked: win.openConnection() }
                // Diseño de página: where you are, and the paper (as Word's status bar and Disposición menu).
                Label {
                    objectName: "sheetCounter"; visible: win.paged && !!win.currentId
                    text: "Página " + win.currentSheet + " de " + win.sheetCount; color: Theme.muted; font.pixelSize: 12
                    font.features: {"tnum": 1}
                }
                UiButton {
                    objectName: "paperButton"; visible: win.paged && !!win.currentId; quiet: true
                    symbol: "page"; text: win.paper === "letter" ? "Carta" : "A4"
                    hint: "Tamaño del papel y márgenes"
                    onClicked: paperMenu.popup(this,0,height+4)
                    PaperMenu {
                        id: paperMenu; objectName: "paperMenu"; workspace: win
                        UiMenuSeparator {}
                        UiMenuItem { glyph: "download"; text: "Guardar como PDF…"; onTriggered: win.requestFile("export","pdf") }
                    }
                }
                ViewSwitch {
                    objectName: "viewSwitch"; visible: !!win.currentId
                    mode: win.viewMode
                    onChosen: function(mode) { win.setViewMode(mode) }
                }
                UiButton {
                    objectName: "favoriteButton"; visible: !!win.currentId && !win.deleted; quiet: true
                    symbol: win.isFavorite ? "starFilled" : "star"; symbolColor: win.isFavorite ? Theme.favorite : Theme.secondary
                    hint: win.isFavorite ? "Quitar de favoritos" : "Añadir a favoritos"
                    onClicked: win.setFavorite(win.currentId,!win.isFavorite)
                }
                UiButton {
                    symbol: "more"; hint: "Opciones de página"; quiet: true; visible: !!win.currentId && !win.deleted
                    onClicked: pageMenu.popup()
                    UiMenu { id: pageMenu
                        UiMenuItem { text: win.isFavorite ? "Quitar de favoritos" : "Añadir a favoritos"; onTriggered: win.setFavorite(win.currentId,!win.isFavorite) }
                        UiMenu {
                            title: "Fuente"; glyph: "text"
                            UiMenuItem { text: "Predeterminada"; checkable: true; checked: win.pageFont === "sans"; onTriggered: win.setPageLook("font","sans") }
                            UiMenuItem { text: "Serif"; checkable: true; checked: win.pageFont === "serif"; onTriggered: win.setPageLook("font","serif") }
                            UiMenuItem { text: "Mono"; checkable: true; checked: win.pageFont === "mono"; onTriggered: win.setPageLook("font","mono") }
                        }
                        UiMenuItem { glyph: "text"; text: "Texto pequeño"; checkable: true; checked: win.pageSmall; onTriggered: win.setPageLook("small_text",!win.pageSmall) }
                        UiMenuItem { glyph: "expand"; text: "Ancho completo"; checkable: true; checked: win.pageWide; onTriggered: win.setPageLook("full_width",!win.pageWide) }
                        UiMenuItem { glyph: "bookmark"; text: "Guardar como plantilla…"; onTriggered: { templateName.text = titleInput.text; templateDialog.open() } }
                        UiMenuSeparator {}
                        UiMenuItem { glyph: "newPage"; text: "Nueva subpágina"; onTriggered: win.newPage(win.currentId) }
                        UiMenuItem { glyph: "move"; text: "Mover página…"; onTriggered: if (win.flush()) moveDialog.open() }
                        UiMenuItem { glyph: "history"; text: "Historial de revisiones…"; onTriggered: win.openHistory() }
                        UiMenuItem { glyph: "download"; text: "Guardar como…"; onTriggered: win.requestFile("export") }
                        UiMenuItem { glyph: "photo"; text: "Insertar foto…"; onTriggered: win.choosePhoto() }
                        UiMenuSeparator {}
                        UiMenuItem { glyph: "trash"; danger: true; text: "Enviar a la papelera"; onTriggered: win.openTrashConfirmation() }
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
                clip: true
                // Diseño de página: the desk scrolls sideways when the sheet is wider than the window.
                contentWidth: win.paged ? Math.max(availableWidth,win.paperWidth+2*win.deskMargin+(withRail && railFits ? 332 : 0)) : availableWidth
                contentHeight: Math.max(win.paged ? sheets.y+sheets.height+win.deskMargin : pageColumn.y+pageColumn.implicitHeight,
                                        rail.visible && !rail.floating ? pageColumn.y+rail.contentBottom+40 : 0)
                // With comments, the text column narrows to leave a 300 px margin for the cards (as in Google Docs).
                readonly property int gutter: win.width >= 1150 ? 148 : 72
                readonly property bool withRail: rail.threads.length > 0 || !!win.commentDraft
                readonly property bool railFits: win.paged ? availableWidth-win.paperWidth-2*win.deskMargin-332 >= 0
                                                           : availableWidth-gutter-332 >= 460
                background: Rectangle { color: win.paged ? Theme.desk : "transparent" }
                onVisibleChanged: if (visible) win.schedulePages()
                PageCover {
                    id: pageCoverItem; objectName: "pageCover"
                    visible: !win.paged && !!win.pageCover
                    page: win; width: pageScroll.availableWidth; height: 200
                    onUploadRequested: coverDialog.open()
                }
                PaperSheets {
                    id: sheets; objectName: "paperSheets"
                    visible: win.paged
                    x: Math.max(win.deskMargin,Math.round((pageScroll.availableWidth-width-(pageScroll.withRail && pageScroll.railFits ? 332 : 0))/2))
                    y: win.deskMargin
                    count: win.sheetCount; gap: win.sheetGap; bottomMargin: win.marginY
                    paperWidth: win.paperWidth; paperHeight: win.paperHeight
                }
                ColumnLayout {
                    id: pageColumn
                    y: win.paged ? sheets.y+win.marginY : win.pageCover ? (win.pageIcon ? 156 : 200) : 0
                    x: win.paged ? sheets.x+win.marginX
                       : pageScroll.withRail && pageScroll.railFits ? Math.round((pageScroll.availableWidth-width-332)/2) : Math.round((pageScroll.availableWidth-width)/2)
                    width: win.paged ? win.paperWidth-2*win.marginX
                           : Math.min(win.pageWide ? 1600 : 780, pageScroll.availableWidth-pageScroll.gutter-(pageScroll.withRail && pageScroll.railFits ? 332 : 0))
                    spacing: 9
                    onHeightChanged: { rail.schedule(); win.schedulePages() }
                    onWidthChanged: { rail.schedule(); win.schedulePages() }
                    Item { Layout.preferredHeight: win.paged ? 0 : win.pageCover ? (win.pageIcon ? 0 : 20) : Math.min(94,win.height*0.1) }
                    PageHeader { id: pageHeader; Layout.fillWidth: true; page: win; picker: emojiPicker; titleHovered: titleArea.hovered || titleInput.activeFocus }
                    Label { visible: win.location !== "Biblioteca" && !win.deleted; text: win.location; color: Theme.muted; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                    TextArea {
                        id: titleInput; objectName: "titleInput"; Layout.fillWidth: true
                        wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText; font.pixelSize: (win.width >= 1150 ? 38 : 32)-(win.pageSmall ? 4 : 0); font.weight: Font.DemiBold; font.family: win.pageFamily
                        color: Theme.text; padding: 0; bottomPadding: 12; background: Item {}
                        placeholderText: "Sin título"; Accessible.name: "Título de la página"; placeholderTextColor: Theme.faint
                        selectByMouse: true; readOnly: win.locked; persistentSelection: true
                        onTextChanged: if (activeFocus && !win.loadingPage) win.markDirty()
                        onActiveFocusChanged: if (activeFocus) win.remember(titleInput,-1)
                        HoverHandler { id: titleArea }
                        Keys.onReturnPressed: function(event) {
                            if (win.locked) return
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
                            // Diseño de página: the room that takes this block to the next sheet.
                            readonly property real breakGap: win.paged && index < win.pageBreaks.length ? win.pageBreaks[index] : 0
                            Layout.topMargin: breakGap
                            Layout.fillWidth: true; total: blocks.count; editable: !win.locked
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
                            onDuplicateRequested: win.duplicateBlock(index)
                            pageFont: win.pageFont; smallText: win.pageSmall
                        }
                    }
                    UiButton { visible: win.deleted; primary: true; text: "Restaurar página"; onClicked: if (win.action("restore_page")) { win.trashMode = false; win.refreshNavigation() } }
                    Item { Layout.preferredHeight: win.paged ? 0 : 28 }
                }
                CommentRail {
                    id: rail; objectName: "commentRail"
                    floating: !pageScroll.railFits
                    width: 300
                    // Next to the text, or in Diseño de página next to the sheet (as Word's comment margin).
                    x: floating ? pageScroll.availableWidth-width-16 : win.paged ? sheets.x+sheets.width+24 : pageColumn.x+pageColumn.width+32
                    y: pageColumn.y; height: pageColumn.height; z: 5
                    // Modo lectura shows the text alone, as Word's reading view.
                    threads: win.reading ? [] : win.pageComments
                    draft: win.reading ? null : win.commentDraft
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
                visible: !win.settingsShown && !!win.currentId && !win.locked; Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height
                Layout.leftMargin: Math.max(22,pageColumn.x)
                Layout.rightMargin: 16; Layout.bottomMargin: 20; spacing: 6
                Repeater {
                    model: [{k:"paragraph",s:"text",t:"Párrafo"},{k:"heading",s:"heading",t:"Encabezado"},{k:"list",s:"list",t:"Lista"},{k:"task",s:"task",t:"Tarea"},{k:"image",s:"photo",t:"Foto"}]
                    delegate: UiButton { required property var modelData; text: modelData.t; symbol: modelData.s; hint: "Añadir " + modelData.t.toLowerCase(); onClicked: modelData.k === "image" ? win.choosePhoto() : win.add(modelData.k) }
                }
                UiButton { objectName: "composeButton"; symbol: "sparkles"; text: "Crear con IA"; hint: "Crear con IA (Ctrl+J)"; onClicked: win.openComposer(-2) }
            }
            // Modo lectura: in place of the tools, how to get back to writing.
            RowLayout {
                objectName: "readingBar"
                visible: !win.settingsShown && !!win.currentId && win.reading && !win.deleted
                Layout.alignment: Qt.AlignHCenter; Layout.bottomMargin: 16; spacing: 10
                Glyph { name: "book"; font.pixelSize: 13; color: Theme.muted }
                Label { text: "Modo lectura: la página no se puede cambiar."; color: Theme.muted; font.pixelSize: 13 }
                UiButton { objectName: "leaveReading"; symbol: "edit"; text: "Editar"; hint: "Volver a Edición (Ctrl+Shift+E)"; onClicked: win.setViewMode("edit") }
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
    Shortcut { sequence: "Ctrl+J"; enabled: !win.settingsShown && !!win.currentId && !win.locked; onActivated: win.openComposer(-2) }
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
        enabled: !win.settingsShown && !!win.currentId && !win.locked
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
    HelpDialog { id: helpDialog; objectName: "helpDialog" }
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
    AboutDialog { id: aboutDialog; objectName: "aboutDialog"; version: backend.version }
    Dialog {
        id: reloadDialog; title: "¿Descartar el borrador y recargar?"; anchors.centerIn: parent; modal: true
        standardButtons: Dialog.Yes | Dialog.Cancel
        onAccepted: { win.showPage(win.currentId); win.info("") }
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
        property string pageId: ""
        // The page itself and the pages inside it cannot hold it.
        readonly property var targets: {
            const own = moveDialog.pageId || win.currentId, inside = {}
            inside[own] = true
            let grew = true
            while (grew) { grew = false; for (const p of win.pages) if (!inside[p.id] && inside[p.parent_id]) { inside[p.id] = true; grew = true } }
            return [{id: null, title: "Raíz de la biblioteca"}].concat(win.pages.filter(p => !inside[p.id]))
        }
        onClosed: pageId = ""
        contentItem: ListView {
            model: moveDialog.targets
            clip: true; spacing: 3
            delegate: UiButton {
                required property var modelData; width: ListView.view.width; text: modelData.title; alignLeft: true; quiet: true
                symbol: modelData.id ? "page" : "home"
                onClicked: if (win.movePage(moveDialog.pageId || win.currentId,modelData.id)) moveDialog.close()
            }
        }
    }
    Native.FileDialog {
        id: coverDialog; title: "Elegir una foto de portada"; fileMode: Native.FileDialog.OpenFile
        nameFilters: ["Fotos (*.jpg *.jpeg *.png)"]; onAccepted: win.action("cover_photo",{url: selectedFile.toString()})
    }
    EmojiPicker { id: emojiPicker; objectName: "emojiPicker" }
    // The outline sits at the right edge of the page area and stays put while the page scrolls.
    PageOutline {
        objectName: "pageOutline"
        // The page area's corner in window coordinates (its column fills the window's row, right of the sidebar).
        readonly property real areaX: pageScroll.parent.x+pageScroll.x
        readonly property real areaY: pageScroll.parent.y+pageScroll.y
        // With comment cards on the right, it moves to the left edge so it never covers them.
        x: pageScroll.withRail ? areaX+14 : areaX+pageScroll.width-width-14; y: areaY+18; z: 25
        visible: !win.settingsShown && !!win.currentId && pageScroll.visible && win.headings.length >= 2
        headings: win.headings
        onChosen: function(index) { win.goToBlock(index) }
    }
    Dialog {
        id: renameDialog; objectName: "renameDialog"; title: "Cambiar nombre"; modal: true; anchors.centerIn: parent; width: 380
        property string pageId: ""
        standardButtons: Dialog.Save | Dialog.Cancel
        onAccepted: win.renamePage(pageId,renameField.text)
        onOpened: { renameField.forceActiveFocus(); renameField.selectAll() }
        contentItem: TextField { id: renameField; maximumLength: 240; selectByMouse: true; onAccepted: renameDialog.accept() }
    }
    Rectangle {
        id: toastBox; objectName: "toast"
        property string message: ""
        property string label: ""
        property var run: null
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 76
        width: toastRow.implicitWidth+28; height: 44; radius: Theme.radiusPanel; z: 60
        color: Theme.surface; border.color: Theme.line
        visible: opacity > 0; opacity: message ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 3; anchors.bottomMargin: -7; radius: Theme.radiusPanel+2; color: Theme.shadow }
        RowLayout {
            id: toastRow; anchors.centerIn: parent; spacing: 12
            Label { text: toastBox.message; color: Theme.text; font.pixelSize: 14 }
            UiButton {
                objectName: "toastAction"; visible: !!toastBox.label; text: toastBox.label; quiet: true
                onClicked: { const run = toastBox.run; toastBox.message = ""; if (run) run() }
            }
        }
        Timer { id: toastTimer; interval: 7000; onTriggered: toastBox.message = "" }
    }
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
            // A PDF comes out on the paper and with the margins of Diseño de página.
            const a = {id:win.currentId,url:selectedFile.toString(),paper:win.paper,margins:win.margins}
            if (win.fileAction === "draft") { a.title = titleInput.text; a.blocks = win.draft() }
            if (win.call(win.fileAction,a)) {
                if (!win.dirty) win.info("Archivo guardado.")
                else { win.notice = "Borrador exportado. Puedes descartar los cambios para recargar la página."; win.noticeError = false }
            }
        }
    }
}
