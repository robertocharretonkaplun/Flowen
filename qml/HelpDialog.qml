import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Ayuda → Guía y atajos (F1): how to start, then every shortcut in a table by topic, each key drawn
// as a key cap. A row with two combinations ("Tab / Shift+Tab") offers either.
Dialog {
    id: dialog
    title: "Guía y atajos"
    modal: true; anchors.centerIn: parent
    width: Math.min(640,parent.width-40)
    height: Math.min(700,parent.height-42)
    padding: 0
    readonly property var sections: [
        {title: "Formato del texto", note: "con texto seleccionado", glyph: "bold", rows: [
            ["Negrita", ["Ctrl+B"]], ["Cursiva", ["Ctrl+I"]], ["Subrayado", ["Ctrl+U"]], ["Tachado", ["Ctrl+Shift+X"]],
            ["Código en línea", ["Ctrl+E"]], ["Resaltar", ["Ctrl+Shift+H"]], ["Enlace", ["Ctrl+K"]]]},
        {title: "Escribir y bloques", note: "", glyph: "text", rows: [
            ["Menú de bloques", ["/"]], ["Enlazar otra página", ["@","[["]], ["Bloque nuevo", ["Enter"]],
            ["Unir con el bloque de arriba (al inicio)", ["Retroceso"]], ["Meter o sacar un nivel", ["Tab","Shift+Tab"]],
            ["Duplicar el bloque", ["Ctrl+D"]], ["Deshacer o rehacer", ["Ctrl+Z","Ctrl+Y"]]]},
        {title: "Inteligencia artificial", note: "", glyph: "sparkles", rows: [
            ["Crear con IA (Espacio en un párrafo vacío)", ["Ctrl+J","Espacio"]], ["Editar la selección con IA", ["Ctrl+Shift+I"]],
            ["Preguntar a Flowen sobre tus notas", ["Ctrl+Shift+P"]]]},
        {title: "Páginas y archivos", note: "", glyph: "pages", rows: [
            ["Nueva página", ["Ctrl+N"]], ["Buscar páginas (sin texto seleccionado)", ["Ctrl+K"]], ["Guardar", ["Ctrl+S"]],
            ["Guardar como…", ["Ctrl+Shift+S"]], ["Conectores", ["Ctrl+,"]]]},
        {title: "Vista", note: "", glyph: "book", rows: [
            ["Edición", ["Ctrl+Shift+E"]], ["Modo lectura", ["Ctrl+Shift+R"]], ["Diseño de página", ["Ctrl+Shift+D"]],
            ["Mostrar u ocultar la barra lateral", ["Ctrl+\\"]], ["Cambiar entre tema claro y oscuro", ["Ctrl+Shift+L"]],
            ["Esta guía", ["F1"]]]}]
    background: Rectangle {
        color: Theme.surface; radius: Theme.radiusPanel; border.color: Theme.line
        Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 4; anchors.bottomMargin: -10; radius: Theme.radiusPanel+2; color: Theme.shadow }
    }
    header: RowLayout {
        spacing: 10
        Glyph { name: "help"; font.pixelSize: 17; Layout.leftMargin: 22; Layout.topMargin: 16 }
        Label {
            text: dialog.title; Layout.fillWidth: true; Layout.topMargin: 16
            font.pixelSize: 19; font.weight: Font.DemiBold; color: Theme.text
        }
        UiButton { objectName: "helpClose"; symbol: "close"; quiet: true; hint: "Cerrar (Esc)"; onClicked: dialog.close(); Layout.rightMargin: 12; Layout.topMargin: 12 }
    }
    // One key, as on the keyboard.
    component KeyCap: Rectangle {
        required property string label
        implicitWidth: Math.max(24,name.implicitWidth+14); implicitHeight: 24
        radius: 5; color: Theme.base; border.color: Theme.line
        Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: parent.width-4; height: 2; radius: 1; color: Theme.hover }
        Text {
            id: name; anchors.centerIn: parent; anchors.verticalCenterOffset: -1
            text: parent.label; color: Theme.textSoft; font.family: Theme.family; font.pixelSize: 12; font.weight: Font.DemiBold
        }
    }
    contentItem: ScrollView {
        id: scroller
        clip: true; contentWidth: availableWidth
        ColumnLayout {
            width: scroller.availableWidth
            spacing: 18
            Label {
                Layout.fillWidth: true; Layout.leftMargin: 22; Layout.rightMargin: 22; Layout.topMargin: 6
                wrapMode: Text.Wrap; color: Theme.secondary; font.pixelSize: 14; lineHeight: 1.3
                text: "Selecciona texto dentro de un bloque para abrir el menú de formato: desde ahí conviertes el bloque, aplicas estilos y colores, " +
                      "añades un enlace o un comentario y editas con IA. Al inicio de un párrafo, «#», «-», «[]» o «>» seguidos de Espacio lo " +
                      "convierten en encabezado, lista, tarea o desplegable."
            }
            Repeater {
                model: dialog.sections
                delegate: ColumnLayout {
                    id: section
                    required property var modelData
                    Layout.fillWidth: true; Layout.leftMargin: 22; Layout.rightMargin: 22
                    spacing: 8
                    RowLayout {
                        spacing: 8
                        Glyph { name: section.modelData.glyph; font.pixelSize: 14 }
                        Label { text: section.modelData.title; color: Theme.text; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Label { visible: !!section.modelData.note; text: "· " + section.modelData.note; color: Theme.muted; font.pixelSize: 13 }
                    }
                    // The table: what it does on the left, the keys on the right; a line between rows.
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: rows.implicitHeight+2
                        radius: Theme.radiusButton; color: "transparent"; border.color: Theme.line
                        Accessible.role: Accessible.Table; Accessible.name: section.modelData.title
                        ColumnLayout {
                            id: rows
                            x: 1; y: 1; width: parent.width-2
                            spacing: 0
                            Repeater {
                                model: section.modelData.rows
                                delegate: Rectangle {
                                    id: line
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true; implicitHeight: 40
                                    color: index % 2 ? Theme.base : "transparent"
                                    radius: Theme.radiusButton
                                    // Square corners except at the top and bottom of the table.
                                    Rectangle { visible: line.index > 0; anchors.top: parent.top; width: parent.width; height: Theme.radiusButton; color: line.color }
                                    Rectangle { visible: line.index < section.modelData.rows.length-1; anchors.bottom: parent.bottom; width: parent.width; height: Theme.radiusButton; color: line.color }
                                    Rectangle { visible: line.index > 0; anchors.top: parent.top; x: 1; width: parent.width-2; height: 1; color: Theme.hover }
                                    Accessible.role: Accessible.Row
                                    Accessible.name: line.modelData[0] + ": " + line.modelData[1].join(" o ")
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 10
                                        spacing: 6
                                        Label { text: line.modelData[0]; color: Theme.textSoft; font.pixelSize: 14; elide: Text.ElideRight; Layout.fillWidth: true }
                                        Repeater {
                                            model: line.modelData[1]
                                            delegate: RowLayout {
                                                id: combo
                                                required property string modelData
                                                required property int index
                                                spacing: 4
                                                Label { visible: combo.index > 0; text: "o"; color: Theme.muted; font.pixelSize: 12; Layout.leftMargin: 2; Layout.rightMargin: 2 }
                                                Repeater {
                                                    model: combo.modelData.length > 1 ? combo.modelData.split("+") : [combo.modelData]
                                                    delegate: KeyCap { required property string modelData; label: modelData }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Item { Layout.preferredHeight: 10 }
        }
    }
}
