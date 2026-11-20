import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The sidebar: search, Inicio, Preguntar, Favoritos, Recientes, the page tree with its right-click menu,
// the trash and the workspace footer (MCP state, usage, settings). It reads and changes the window through
// `workspace` (Main.qml), as the other panels do.
Rectangle {
    id: sidebar
    required property var workspace
    // For the window: its search field and the MCP state shown when the sidebar is hidden.
    property alias searchField: search
    readonly property alias mcpLabel: mcpText.text
    // The page menu of the right click (the window's tests open it directly).
    property alias rowMenu: pageRowMenu
    visible: workspace.sidebarShown
    Layout.preferredWidth: Math.max(200,Math.min(workspace.width-525,workspace.sidebarPreferredWidth || Math.min(320,Math.round(workspace.width*0.225))))
    Layout.fillHeight: true
    color: Theme.sidebar
    ColumnLayout {
        anchors.fill: parent; spacing: 0
        RowLayout {
            Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.preferredHeight: 45
            UiButton { symbol: "panel"; hint: "Ocultar barra lateral"; quiet: true; onClicked: workspace.sidebarShown = false }
            Item { Layout.fillWidth: true }
            UiButton { symbol: "history"; hint: "Historial de esta página"; enabled: !workspace.settingsShown && !!workspace.currentId && !workspace.deleted; quiet: true; onClicked: workspace.openHistory() }
            UiButton { symbol: "newPage"; hint: "Nueva página (Ctrl+N)"; quiet: true; onClicked: workspace.newPage(null) }
        }
        TextField {
            id: search; Layout.fillWidth: true; Layout.leftMargin: 9; Layout.rightMargin: 11; Layout.preferredHeight: 36
            placeholderText: "Buscar páginas"; Accessible.name: "Buscar páginas"; maximumLength: 240
            leftPadding: 32; rightPadding: 48; selectByMouse: true
            onActiveFocusChanged: if (activeFocus) workspace.remember(search,-1)
            background: Rectangle {
                radius: Theme.radiusButton; border.color: search.activeFocus ? Theme.accent : Theme.line; color: Theme.surface
                Glyph { name: "search"; anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 14 }
                Rectangle { width: 39; height: 19; radius: 4; color: Theme.hover; anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter; visible: !search.text
                    Label { anchors.centerIn: parent; text: "Ctrl+K"; font.pixelSize: 10; color: Theme.secondary } }
            }
            onTextChanged: if (workspace.initialized) { if (text) { workspace.trashMode = false; workspace.pagesExpanded = true } workspace.refreshNavigation() }
        }
        UiButton { Layout.topMargin: 12; Layout.leftMargin: 9
            alignLeft: true; quiet: workspace.settingsShown || !!workspace.currentId || workspace.trashMode; symbol: "home"; text: "Inicio"
            onClicked: workspace.browseTrash(false) }
        UiButton { objectName: "askEntry"; Layout.leftMargin: 9
            alignLeft: true; quiet: !workspace.askOpen; symbol: "sparkles"; text: "Preguntar a Flowen"
            hint: "Preguntar sobre tus notas (Ctrl+Shift+P)"; onClicked: workspace.openAsk() }
        ListView {
            id: navList; Layout.fillWidth: true; Layout.fillHeight: true; Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.topMargin: 4
            clip: true; spacing: 2; model: workspace.pagesExpanded ? workspace.navigationRows : []
            ScrollBar.vertical: ScrollBar {}
            // Favoritos and Recientes scroll with the page tree; searching or the trash hides them.
            readonly property bool shortcuts: !workspace.trashMode && !search.text.trim()
            header: ColumnLayout {
                width: navList.width; spacing: 0
                SidebarSection {
                    objectName: "favorites"; Layout.fillWidth: true
                    visible: navList.shortcuts && workspace.favoriteRows.length > 0
                    title: "Favoritos"; favorites: true; rows: workspace.favoriteRows
                    currentId: workspace.settingsShown ? "" : workspace.currentId
                    onChosen: function(id) { workspace.selectPage(id) }
                    onUnfavorite: function(id) { workspace.setFavorite(id,false) }
                    onMoved: function(id, index) { workspace.setFavorite(id,true,index) }
                    onMenuRequested: function(id) { pageRowMenu.show(id) }
                }
                SidebarSection {
                    objectName: "recent"; Layout.fillWidth: true
                    visible: navList.shortcuts && workspace.recentRows.length > 0
                    title: "Recientes"; rows: workspace.recentRows.slice(0,5)
                    currentId: workspace.settingsShown ? "" : workspace.currentId
                    onChosen: function(id) { workspace.selectPage(id) }
                    onMenuRequested: function(id) { pageRowMenu.show(id) }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: 8; Layout.bottomMargin: 2
                    UiButton { text: workspace.trashMode ? "Papelera" : search.text.trim() ? "Resultados" : "Privado"
                        quiet: true; alignLeft: true; symbol: workspace.pagesExpanded ? "down" : "right"; hint: "Mostrar u ocultar las páginas"
                        onClicked: workspace.pagesExpanded = !workspace.pagesExpanded }
                    Item { Layout.fillWidth: true }
                    UiButton { symbol: "add"; quiet: true; hint: "Crear página en la raíz"; onClicked: workspace.newPage(null) }
                }
            }
            UiMenu {
                id: pageRowMenu; objectName: "pageRowMenu"
                property string pageId: ""
                readonly property bool favorite: workspace.favoriteIds.indexOf(pageId) >= 0
                readonly property bool trashed: workspace.trashMode
                function show(id) { pageId = id; popup() }
                UiMenuItem { glyph: "page"; text: "Abrir"; onTriggered: workspace.selectPage(pageRowMenu.pageId) }
                UiMenuItem { visible: !pageRowMenu.trashed; glyph: pageRowMenu.favorite ? "starFilled" : "star"
                    text: pageRowMenu.favorite ? "Quitar de favoritos" : "Añadir a favoritos"
                    onTriggered: workspace.setFavorite(pageRowMenu.pageId,!pageRowMenu.favorite) }
                UiMenuSeparator { visible: !pageRowMenu.trashed }
                UiMenuItem { visible: !pageRowMenu.trashed; glyph: "newPage"; text: "Nueva subpágina"; onTriggered: workspace.newPage(pageRowMenu.pageId) }
                UiMenuItem { visible: !pageRowMenu.trashed; glyph: "copy"; text: "Duplicar"; onTriggered: workspace.duplicatePage(pageRowMenu.pageId) }
                UiMenuItem { visible: !pageRowMenu.trashed; glyph: "edit"; text: "Cambiar nombre…"; onTriggered: workspace.openRename(pageRowMenu.pageId) }
                UiMenuItem { visible: !pageRowMenu.trashed; glyph: "move"; text: "Mover a…"; onTriggered: workspace.openMove(pageRowMenu.pageId) }
                UiMenuSeparator {}
                UiMenuItem { visible: !pageRowMenu.trashed; objectName: "rowTrash"; glyph: "trash"; danger: true; text: "Enviar a la papelera"
                    onTriggered: workspace.trashPage(pageRowMenu.pageId) }
                UiMenuItem { visible: pageRowMenu.trashed; glyph: "sync"; text: "Restaurar"; onTriggered: workspace.restorePage(pageRowMenu.pageId) }
            }
            delegate: Rectangle {
                id: navRow
                required property var modelData
                HoverHandler { id: rowHover }
                TapHandler { acceptedButtons: Qt.RightButton; onTapped: pageRowMenu.show(navRow.modelData.page.id) }
                width: navList.width; height: 34; radius: 5
                color: !workspace.settingsShown && modelData.page.id === workspace.currentId ? Theme.hover : rowHover.hovered ? Theme.raised : "transparent"
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 8 + Math.min(6,navRow.modelData.depth)*12; anchors.rightMargin: 6; spacing: 3
                    UiButton {
                        visible: navRow.modelData.branch; Layout.preferredWidth: 19; quiet: true; hint: "Mostrar u ocultar subpáginas"
                        symbol: workspace.collapsed[navRow.modelData.page.id] ? "right" : "down"
                        onClicked: { workspace.collapsed[navRow.modelData.page.id] = !workspace.collapsed[navRow.modelData.page.id]; workspace.refreshNavigation() }
                    }
                    Button {
                        id: navButton; flat: true; Layout.fillWidth: true; Layout.fillHeight: true; padding: 3
                        background: Rectangle { color: "transparent"; radius: 4; border.width: navButton.visualFocus ? 1 : 0; border.color: Theme.focus }
                        contentItem: RowLayout {
                            spacing: 9
                            PageIcon { icon: navRow.modelData.page.icon || ""; size: 15 }
                            Label { text: navRow.modelData.page.title; color: navRow.modelData.page.id === workspace.currentId ? Theme.text : Theme.secondary; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                        Accessible.name: navRow.modelData.page.title; onClicked: workspace.selectPage(navRow.modelData.page.id)
                        ToolTip.visible: hovered && !!navRow.modelData.page.snippet
                        ToolTip.text: navRow.modelData.page.snippet || ""
                    }
                    UiButton { visible: (rowHover.hovered || visualFocus) && !workspace.trashMode
                        symbol: "add"; quiet: true; hint: "Crear subpágina"; Layout.preferredWidth: 26
                        onClicked: workspace.newPage(navRow.modelData.page.id) }
                }
            }
            Label { visible: workspace.pagesExpanded && !navList.count; anchors.left: parent.left; anchors.leftMargin: 12; text: workspace.trashMode ? "Papelera vacía" : search.text ? "Sin coincidencias" : "Aún no hay páginas"; color: Theme.muted; font.pixelSize: 13 }
        }
        UiButton { Layout.fillWidth: true; Layout.margins: 9; quiet: !workspace.trashMode; alignLeft: true; text: "Papelera"; symbol: "trash"; onClicked: workspace.browseTrash(!workspace.trashMode) }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hover }
        RowLayout {
            Layout.fillWidth: true; Layout.margins: 10; spacing: 3
            Image { objectName: "appLogo"; source: "../assets/flowen-64.png"; sourceSize: Qt.size(64,64)
                Layout.preferredWidth: 29; Layout.preferredHeight: 29; smooth: true; mipmap: true; Accessible.ignored: true }
            Button {
                id: mcpBadge; flat: true; Layout.fillWidth: true; implicitHeight: 39
                Accessible.name: mcpText.text + ". Ajustes de conexión"; onClicked: workspace.openConnection()
                background: Rectangle { radius: 5; color: mcpBadge.hovered ? Theme.hover : "transparent"; border.width: mcpBadge.visualFocus ? 1 : 0; border.color: Theme.focus }
                contentItem: ColumnLayout {
                    spacing: 1
                    Label { text: "Flowen"; font.weight: Font.DemiBold; font.pixelSize: 14 }
                    RowLayout { spacing: 5
                        Rectangle { width: 6; height: 6; radius: 3; color: workspace.assistant.link.state === "connected" ? Theme.success : workspace.assistant.link.state === "connecting" ? Theme.warning : Theme.muted }
                        Label { id: mcpText; font.pixelSize: 11; color: Theme.secondary; text: workspace.assistant.link.state === "connected" ? "MCP conectado" : workspace.assistant.link.state === "connecting" ? "Conectando MCP…" : "MCP desconectado" }
                    }
                }
            }
            UsageButton { objectName: "usageButton"; assistant: workspace.assistant; onOpenUsage: workspace.openUsage() }
            UiButton { symbol: "settings"; quiet: true; hint: "Conectores"; onClicked: workspace.openConnection() }
        }
    }
}
