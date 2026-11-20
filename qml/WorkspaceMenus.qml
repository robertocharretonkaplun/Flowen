import QtQuick
import QtQuick.Controls.Basic
import Lunqio

MenuBar {
    id: bar
    required property var workspace
    readonly property var target: workspace.settingsShown ? null : workspace.textTarget
    readonly property bool live: !workspace.settingsShown && !!workspace.currentId && !workspace.deleted
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
    Menu {
        title: "&File"
        MenuItem { action: Action { text: "Nueva página"; shortcut: StandardKey.New; onTriggered: bar.workspace.newPage(null) } }
        MenuItem { text: "Nueva subpágina"; enabled: bar.live; onTriggered: bar.workspace.newPage(bar.workspace.currentId) }
        MenuItem { action: Action { text: "Guardar"; shortcut: StandardKey.Save; enabled: bar.live; onTriggered: bar.workspace.flush() } }
        MenuSeparator {}
        MenuItem { action: Action { text: "Guardar como…"; shortcut: StandardKey.SaveAs; enabled: bar.live; onTriggered: bar.workspace.requestFile("export") } }
        MenuItem { text: "Copia de seguridad…"; onTriggered: bar.workspace.requestFile("backup") }
        MenuItem { text: "Enviar a la papelera…"; enabled: bar.live; onTriggered: bar.workspace.openTrashConfirmation() }
        MenuSeparator {}
        MenuItem { text: "Salir"; onTriggered: bar.workspace.close() }
    }
    Menu {
        title: "&Edit"
        MenuItem { text: "Deshacer    Ctrl+Z"; enabled: !!bar.target && bar.target.canUndo && !bar.target.readOnly; onTriggered: bar.workspace.textCommand("undo") }
        MenuItem { text: "Rehacer    Ctrl+Y"; enabled: !!bar.target && bar.target.canRedo && !bar.target.readOnly; onTriggered: bar.workspace.textCommand("redo") }
        MenuSeparator {}
        MenuItem { text: "Cortar    Ctrl+X"; enabled: !!bar.target && !!bar.target.selectedText && !bar.target.readOnly; onTriggered: bar.workspace.textCommand("cut") }
        MenuItem { text: "Copiar    Ctrl+C"; enabled: !!bar.target && !!bar.target.selectedText; onTriggered: bar.workspace.textCommand("copy") }
        MenuItem { text: "Pegar    Ctrl+V"; enabled: !!bar.target && (bar.target.canPaste || (backend.clipboardPhoto && bar.workspace.editIndex >= 0)) && !bar.target.readOnly; onTriggered: bar.workspace.textCommand("paste") }
        MenuItem { text: "Seleccionar todo    Ctrl+A"; enabled: !!bar.target; onTriggered: bar.workspace.textCommand("selectAll") }
        MenuSeparator {}
        // Labels only: the block editor handles these keys so they stay tied to the selection.
        Menu {
            title: "Formato"
            enabled: bar.workspace.canFormat
            MenuItem { text: "Negrita    Ctrl+B"; onTriggered: bar.workspace.format(InlineEditor.Bold) }
            MenuItem { text: "Cursiva    Ctrl+I"; onTriggered: bar.workspace.format(InlineEditor.Italic) }
            MenuItem { text: "Subrayado    Ctrl+U"; onTriggered: bar.workspace.format(InlineEditor.Underline) }
            MenuItem { text: "Tachado    Ctrl+Shift+X"; onTriggered: bar.workspace.format(InlineEditor.Strike) }
            MenuItem { text: "Código en línea    Ctrl+E"; onTriggered: bar.workspace.format(InlineEditor.Code) }
            MenuItem { text: "Resaltar    Ctrl+Shift+H"; onTriggered: bar.workspace.format(InlineEditor.Highlight) }
            MenuItem { text: "Superíndice"; onTriggered: bar.workspace.format(InlineEditor.Superscript) }
            MenuSeparator {}
            MenuItem { text: "Enlace…    Ctrl+K"; onTriggered: bar.workspace.editLink() }
        }
        MenuSeparator {}
        MenuItem { text: "Insertar foto…"; enabled: bar.live; onTriggered: bar.workspace.choosePhoto() }
        MenuItem { text: "Crear con IA…    Ctrl+J"; enabled: bar.live; onTriggered: bar.workspace.openComposer(-2) }
        MenuItem { action: Action { text: "Editar con IA…"; shortcut: "Ctrl+Shift+I"; enabled: bar.workspace.canEditSelection; onTriggered: bar.workspace.openWriting() } }
        MenuSeparator {}
        MenuItem { action: Action { text: "Conectores"; shortcut: "Ctrl+,"; onTriggered: bar.workspace.openConnection() } }
    }
    Menu {
        title: "&View"
        MenuItem { action: Action { text: "Barra lateral"; checkable: true; checked: bar.workspace.sidebarShown; shortcut: "Ctrl+\\";
                onTriggered: bar.workspace.sidebarShown = !bar.workspace.sidebarShown } }
        MenuItem { action: Action { text: "Buscar páginas"; shortcut: "Ctrl+K"; onTriggered: bar.workspace.focusSearch() } }
        MenuItem { text: "Historial de revisiones…"; enabled: bar.live; onTriggered: bar.workspace.openHistory() }
        MenuItem { text: "Papelera"; onTriggered: bar.workspace.browseTrash(true) }
        MenuSeparator {}
        // Lunqio's identity in its two versions, the usual Claro and Oscuro, or those as Windows is.
        // Ctrl+Shift+L flips between the light and dark version of the current look, as in Notion.
        Menu {
            title: "Tema"
            ActionGroup { id: themes; exclusive: true }
            MenuItem { action: Action { text: "Lunqio oscuro"; checkable: true; checked: backend.theme === "dark"; ActionGroup.group: themes; onTriggered: backend.theme = "dark" } }
            MenuItem { action: Action { text: "Lunqio claro"; checkable: true; checked: backend.theme === "light"; ActionGroup.group: themes; onTriggered: backend.theme = "light" } }
            MenuSeparator {}
            MenuItem { action: Action { text: "Claro"; checkable: true; checked: backend.theme === "white"; ActionGroup.group: themes; onTriggered: backend.theme = "white" } }
            MenuItem { action: Action { text: "Oscuro"; checkable: true; checked: backend.theme === "black"; ActionGroup.group: themes; onTriggered: backend.theme = "black" } }
            MenuItem { action: Action { text: "Según Windows"; checkable: true; checked: backend.theme === "system"; ActionGroup.group: themes; onTriggered: backend.theme = "system" } }
        }
        MenuItem { action: Action {
                readonly property var flip: ({dark: "light", light: "dark", white: "black", black: "white"})
                readonly property var names: ({dark: "Lunqio oscuro", light: "Lunqio claro", white: "Claro", black: "Oscuro"})
                text: "Cambiar a " + names[flip[Theme.scheme]]; shortcut: "Ctrl+Shift+L"
                onTriggered: backend.theme = flip[Theme.scheme] } }
        MenuSeparator {}
        MenuItem { text: "Conectores"; onTriggered: bar.workspace.openConnection() }
    }
    Menu {
        title: "&Help"
        MenuItem { text: "Guía y atajos…"; onTriggered: bar.workspace.openHelp() }
        MenuItem { text: "Conectores…"; onTriggered: bar.workspace.openConnection() }
        MenuItem { text: "Acerca de Lunqio"; onTriggered: bar.workspace.openAbout() }
    }
}
