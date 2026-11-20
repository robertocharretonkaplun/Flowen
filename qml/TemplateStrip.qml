import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// On an empty page, as in Notion: start from a template. Lunqio's own come first, then yours
// (saved with ⋯ → Guardar como plantilla…, removable with ×). "{fecha}" becomes today's date.
ColumnLayout {
    id: strip
    property var saved: []                     // [{id, name, icon, page}]
    signal chosen(var page)
    signal removeRequested(string id)
    spacing: 8
    readonly property var builtIn: [
        {name: "Reunión", icon: "📋", page: {title: "Reunión · {fecha}", icon: "📋", blocks: [
            {type: "heading", level: 2, text: "Asistentes"}, {type: "list", text: ""},
            {type: "heading", level: 2, text: "Temas"}, {type: "numbered", text: ""},
            {type: "heading", level: 2, text: "Acuerdos"}, {type: "list", text: ""},
            {type: "heading", level: 2, text: "Próximos pasos"}, {type: "task", text: "", checked: false}]}},
        {name: "Diario", icon: "📔", page: {title: "{fecha}", icon: "📔", blocks: [
            {type: "callout", icon: "🌤️", text: "¿Cómo te sientes hoy?"},
            {type: "heading", level: 2, text: "Lo más importante"}, {type: "task", text: "", checked: false}, {type: "task", text: "", checked: false},
            {type: "heading", level: 2, text: "Notas"}, {type: "paragraph", text: ""},
            {type: "heading", level: 2, text: "Agradezco"}, {type: "list", text: ""}]}},
        {name: "Proyecto", icon: "🚀", page: {title: "Proyecto", icon: "🚀", blocks: [
            {type: "callout", icon: "🎯", text: "Objetivo: "},
            {type: "heading", level: 2, text: "Contexto"}, {type: "paragraph", text: ""},
            {type: "heading", level: 2, text: "Tareas"}, {type: "task", text: "", checked: false}, {type: "task", text: "", checked: false},
            {type: "heading", level: 2, text: "Fechas clave"}, {type: "list", text: ""},
            {type: "heading", level: 2, text: "Recursos"}, {type: "list", text: ""}]}},
        {name: "Clase", icon: "🎓", page: {title: "Clase · {fecha}", icon: "🎓", blocks: [
            {type: "heading", level: 2, text: "Tema"}, {type: "paragraph", text: ""},
            {type: "heading", level: 2, text: "Ideas clave"}, {type: "list", text: ""},
            {type: "heading", level: 2, text: "Ejemplos"}, {type: "paragraph", text: ""},
            {type: "heading", level: 2, text: "Ejercicio"}, {type: "task", text: "", checked: false},
            {type: "toggle", text: "Preguntas para la próxima clase"}]}},
        {name: "Lista de tareas", icon: "✅", page: {title: "Tareas", icon: "✅", blocks: [
            {type: "heading", level: 2, text: "Hoy"}, {type: "task", text: "", checked: false}, {type: "task", text: "", checked: false},
            {type: "heading", level: 2, text: "Esta semana"}, {type: "task", text: "", checked: false},
            {type: "heading", level: 2, text: "Más adelante"}, {type: "task", text: "", checked: false}]}},
        {name: "Documento de diseño", icon: "🎮", page: {title: "Documento de diseño", icon: "🎮", blocks: [
            {type: "callout", icon: "💡", text: "El juego en una frase: "},
            {type: "heading", level: 2, text: "Concepto"}, {type: "paragraph", text: ""},
            {type: "heading", level: 2, text: "Mecánicas"}, {type: "list", text: ""},
            {type: "heading", level: 2, text: "Público"}, {type: "paragraph", text: ""},
            {type: "heading", level: 2, text: "Estética"}, {type: "paragraph", text: ""},
            {type: "heading", level: 2, text: "Alcance"}, {type: "task", text: "", checked: false}]}}
    ]
    readonly property var all: builtIn.concat(saved.map(t => ({id: t.id, name: t.name, icon: t.icon || "", page: t.page})))

    Text { text: "Empieza con una plantilla"; color: Theme.muted; font.pixelSize: 13 }
    Flow {
        Layout.fillWidth: true; spacing: 6
        Repeater {
            model: strip.all
            delegate: AbstractButton {
                id: option
                required property var modelData
                required property int index
                objectName: "template-" + index
                hoverEnabled: true; focusPolicy: Qt.NoFocus
                implicitHeight: 34; leftPadding: 10; rightPadding: option.modelData.id ? 30 : 12
                Accessible.name: "Plantilla " + modelData.name
                onClicked: strip.chosen(modelData.page)
                background: Rectangle {
                    radius: Theme.radiusButton; color: option.hovered ? Theme.hover : Theme.raised
                    border.color: option.modelData.id ? Theme.accentLine : Theme.line
                }
                contentItem: RowLayout {
                    spacing: 7
                    PageIcon { icon: option.modelData.icon || ""; size: 14 }
                    Text { text: option.modelData.name; color: Theme.textSoft; font.pixelSize: 14 }
                }
                UiButton {
                    visible: !!option.modelData.id && (option.hovered || hovered)
                    anchors.right: parent.right; anchors.rightMargin: 3; anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; quiet: true; symbol: "close"; hint: "Eliminar la plantilla"
                    onClicked: strip.removeRequested(option.modelData.id)
                }
            }
        }
    }
}
