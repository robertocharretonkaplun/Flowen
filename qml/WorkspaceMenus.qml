import QtQuick
import QtQuick.Controls.Basic
import Lunqio

MenuBar {
    id: bar
    required property var workspace
    readonly property var target: workspace.settingsShown ? null : workspace.textTarget
    readonly property bool live: !workspace.settingsShown && !!workspace.currentId && !workspace.deleted
    // Modo lectura keeps the page as it is.
    readonly property bool writable: live && !workspace.reading
    implicitHeight: 30
    leftPadding: 7
    spacing: 0
    background: Rectangle { color: Theme.base; Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.hover } }
    delegate: MenuBarItem {
        id: item
        implicitHeight: 29; leftPadding: 11; rightPadding: 11
        contentItem: Text { text: item.text.replace("&",""); font.pixelSize: 13; color: Theme.textSoft; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 4; color: item.highlighted ? Theme.pressed : "transparent" }
    }
    UiMenu {
        title: "&Archivo"
        UiMenuItem { glyph: "newPage"; action: Action { text: "Nueva página"; shortcut: StandardKey.New; onTriggered: bar.workspace.newPage(null) } }
        UiMenuItem { glyph: "newPage"; text: "Nueva subpágina"; enabled: bar.live; onTriggered: bar.workspace.newPage(bar.workspace.currentId) }
        UiMenuItem { glyph: "save"; action: Action { text: "Guardar"; shortcut: StandardKey.Save; enabled: bar.live; onTriggered: bar.workspace.flush() } }
        UiMenuSeparator {}
        UiMenuItem { glyph: "download"; action: Action { text: "Guardar como…"; shortcut: StandardKey.SaveAs; enabled: bar.live; onTriggered: bar.workspace.requestFile("export") } }
        UiMenuItem { glyph: "archive"; text: "Copia de seguridad…"; onTriggered: bar.workspace.requestFile("backup") }
        UiMenuItem { glyph: "trash"; danger: true; text: "Enviar a la papelera"; enabled: bar.live; onTriggered: bar.workspace.openTrashConfirmation() }
        UiMenuSeparator {}
        UiMenuItem { glyph: "close"; text: "Salir"; onTriggered: bar.workspace.close() }
    }
    UiMenu {
        title: "&Edición"
        UiMenuItem { text: "Deshacer    Ctrl+Z"; enabled: !!bar.target && (bar.target.canUndo || (bar.workspace.editIndex >= 0 && bar.workspace.undoDepth > 0)) && !bar.target.readOnly; onTriggered: bar.workspace.textCommand("undo") }
        UiMenuItem { text: "Rehacer    Ctrl+Y"; enabled: !!bar.target && (bar.target.canRedo || (bar.workspace.editIndex >= 0 && bar.workspace.redoDepth > 0)) && !bar.target.readOnly; onTriggered: bar.workspace.textCommand("redo") }
        UiMenuSeparator {}
        UiMenuItem { text: "Cortar    Ctrl+X"; enabled: !!bar.target && !!bar.target.selectedText && !bar.target.readOnly; onTriggered: bar.workspace.textCommand("cut") }
        UiMenuItem { glyph: "copy"; text: "Copiar    Ctrl+C"; enabled: !!bar.target && !!bar.target.selectedText; onTriggered: bar.workspace.textCommand("copy") }
        UiMenuItem { text: "Pegar    Ctrl+V"; enabled: !!bar.target && (bar.target.canPaste || (backend.clipboardPhoto && bar.workspace.editIndex >= 0)) && !bar.target.readOnly; onTriggered: bar.workspace.textCommand("paste") }
        UiMenuItem { text: "Seleccionar todo    Ctrl+A"; enabled: !!bar.target; onTriggered: bar.workspace.textCommand("selectAll") }
        UiMenuSeparator {}
        // Labels only: the block editor handles these keys so they stay tied to the selection.
        UiMenu {
            title: "Formato"; glyph: "bold"
            enabled: bar.workspace.canFormat
            UiMenuItem { glyph: "bold"; text: "Negrita    Ctrl+B"; onTriggered: bar.workspace.format(InlineEditor.Bold) }
            UiMenuItem { glyph: "italic"; text: "Cursiva    Ctrl+I"; onTriggered: bar.workspace.format(InlineEditor.Italic) }
            UiMenuItem { glyph: "underline"; text: "Subrayado    Ctrl+U"; onTriggered: bar.workspace.format(InlineEditor.Underline) }
            UiMenuItem { glyph: "strike"; text: "Tachado    Ctrl+Shift+X"; onTriggered: bar.workspace.format(InlineEditor.Strike) }
            UiMenuItem { glyph: "code"; text: "Código en línea    Ctrl+E"; onTriggered: bar.workspace.format(InlineEditor.Code) }
            UiMenuItem { glyph: "highlight"; text: "Resaltar    Ctrl+Shift+H"; onTriggered: bar.workspace.format(InlineEditor.Highlight) }
            UiMenuItem { text: "Superíndice"; onTriggered: bar.workspace.format(InlineEditor.Superscript) }
            UiMenuSeparator {}
            UiMenuItem { glyph: "link"; text: "Enlace…    Ctrl+K"; onTriggered: bar.workspace.editLink() }
        }
        UiMenuSeparator {}
        UiMenuItem { glyph: "photo"; text: "Insertar foto…"; enabled: bar.writable; onTriggered: bar.workspace.choosePhoto() }
        UiMenuItem { glyph: "sparkles"; text: "Crear con IA…    Ctrl+J"; enabled: bar.writable; onTriggered: bar.workspace.openComposer(-2) }
        UiMenuItem { glyph: "sparkles"; action: Action { text: "Editar con IA…"; shortcut: "Ctrl+Shift+I"; enabled: bar.workspace.canEditSelection; onTriggered: bar.workspace.openWriting() } }
        UiMenuSeparator {}
        UiMenuItem { glyph: "plug"; action: Action { text: "Conectores"; shortcut: "Ctrl+,"; onTriggered: bar.workspace.openConnection() } }
    }
    UiMenu {
        title: "&Ver"
        UiMenuItem { glyph: "panel"; action: Action { text: "Barra lateral"; checkable: true; checked: bar.workspace.sidebarShown; shortcut: "Ctrl+\\";
                onTriggered: bar.workspace.sidebarShown = !bar.workspace.sidebarShown } }
        UiMenuItem { glyph: "search"; action: Action { text: "Buscar páginas"; shortcut: "Ctrl+K"; onTriggered: bar.workspace.focusSearch() } }
        UiMenuItem { glyph: "sparkles"; action: Action { text: "Preguntar a Lunqio"; shortcut: "Ctrl+Shift+P"; onTriggered: bar.workspace.openAsk() } }
        UiMenuItem { glyph: "history"; text: "Historial de revisiones…"; enabled: bar.live; onTriggered: bar.workspace.openHistory() }
        UiMenuItem { glyph: "trash"; text: "Papelera"; onTriggered: bar.workspace.browseTrash(true) }
        UiMenuSeparator {}
        // How the page is shown, as the view buttons of the top bar.
        UiMenuItem { objectName: "menuViewEdit"; glyph: "edit"; marked: bar.workspace.viewMode === "edit"
            action: Action { text: "Edición"; shortcut: "Ctrl+Shift+E"; onTriggered: bar.workspace.setViewMode("edit") } }
        UiMenuItem { objectName: "menuViewRead"; glyph: "book"; marked: bar.workspace.viewMode === "read"
            action: Action { text: "Modo lectura"; shortcut: "Ctrl+Shift+R"; onTriggered: bar.workspace.setViewMode("read") } }
        UiMenuItem { objectName: "menuViewPage"; glyph: "page"; marked: bar.workspace.viewMode === "page"
            action: Action { text: "Diseño de página"; shortcut: "Ctrl+Shift+D"; onTriggered: bar.workspace.setViewMode("page") } }
        PaperMenu { workspace: bar.workspace }
        UiMenuSeparator {}
        // Lunqio's identity in its two versions, the usual Claro and Oscuro, or those as Windows is.
        // Ctrl+Shift+L flips between the light and dark version of the current look, as in Notion.
        UiMenu {
            title: "Tema"; glyph: "palette"
            ActionGroup { id: themes; exclusive: true }
            UiMenuItem { action: Action { text: "Lunqio oscuro"; checkable: true; checked: backend.theme === "dark"; ActionGroup.group: themes; onTriggered: backend.theme = "dark" } }
            UiMenuItem { action: Action { text: "Lunqio claro"; checkable: true; checked: backend.theme === "light"; ActionGroup.group: themes; onTriggered: backend.theme = "light" } }
            UiMenuSeparator {}
            UiMenuItem { action: Action { text: "Claro"; checkable: true; checked: backend.theme === "white"; ActionGroup.group: themes; onTriggered: backend.theme = "white" } }
            UiMenuItem { action: Action { text: "Oscuro"; checkable: true; checked: backend.theme === "black"; ActionGroup.group: themes; onTriggered: backend.theme = "black" } }
            UiMenuItem { action: Action { text: "Según Windows"; checkable: true; checked: backend.theme === "system"; ActionGroup.group: themes; onTriggered: backend.theme = "system" } }
        }
        UiMenuItem { action: Action {
                readonly property var flip: ({dark: "light", light: "dark", white: "black", black: "white"})
                readonly property var names: ({dark: "Lunqio oscuro", light: "Lunqio claro", white: "Claro", black: "Oscuro"})
                text: "Cambiar a " + names[flip[Theme.scheme]]; shortcut: "Ctrl+Shift+L"
                onTriggered: backend.theme = flip[Theme.scheme] } }
        UiMenuSeparator {}
        UiMenuItem { glyph: "plug"; text: "Conectores"; onTriggered: bar.workspace.openConnection() }
    }
    UiMenu {
        title: "Ay&uda"
        UiMenuItem { glyph: "help"; text: "Guía y atajos…"; onTriggered: bar.workspace.openHelp() }
        UiMenuItem { glyph: "plug"; text: "Conectores…"; onTriggered: bar.workspace.openConnection() }
        UiMenuSeparator {}
        UiMenuItem { glyph: "book"; text: "Documentación"; onTriggered: Qt.openUrlExternally("https://robertocharretonkaplun.github.io/lunqio-/") }
        UiMenuItem { glyph: "code"; text: "Código en GitHub"; onTriggered: Qt.openUrlExternally("https://github.com/robertocharretonkaplun/lunqio-") }
        UiMenuItem { glyph: "globe"; text: "Attribute Overload"; onTriggered: Qt.openUrlExternally("https://www.attributeoverload.com") }
        UiMenuSeparator {}
        UiMenuItem { glyph: "bulb"; text: "Acerca de Lunqio"; onTriggered: bar.workspace.openAbout() }
    }
}
