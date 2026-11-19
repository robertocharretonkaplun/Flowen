import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The "/" block menu, as in Notion: typing after the slash filters it, arrows move, Enter picks.
Rectangle {
    id: menu
    property string query: ""
    property int highlighted: 0
    signal chosen(var command)
    readonly property var commands: [
        {key: "paragraph", title: "Texto", hint: "Escribe texto normal.", glyph: "text", words: "texto parrafo normal paragraph text"},
        {key: "heading1", title: "Encabezado 1", hint: "Título grande de sección.", mark: "H1", words: "encabezado titulo seccion heading h1 1"},
        {key: "heading2", title: "Encabezado 2", hint: "Título mediano de sección.", mark: "H2", words: "encabezado titulo subtitulo heading h2 2"},
        {key: "heading3", title: "Encabezado 3", hint: "Título pequeño de sección.", mark: "H3", words: "encabezado titulo heading h3 3"},
        {key: "list", title: "Lista con viñetas", hint: "Una lista sencilla de puntos.", glyph: "list", words: "lista vinetas puntos bullet list"},
        {key: "numbered", title: "Lista numerada", hint: "Una lista con números.", mark: "1.", words: "lista numerada numeros ordenada numbered 1"},
        {key: "task", title: "Tarea", hint: "Una casilla para marcar lo hecho.", glyph: "task", words: "tarea pendiente todo checkbox casilla"},
        {key: "toggle", title: "Desplegable", hint: "Oculta o muestra lo que va dentro.", glyph: "right", words: "desplegable plegable toggle ocultar"},
        {key: "quote", title: "Cita", hint: "Destaca una cita.", mark: "❝", words: "cita quote frase"},
        {key: "callout", title: "Nota destacada", hint: "Un recuadro con icono para resaltar.", mark: "💡", words: "nota destacada callout aviso recuadro"},
        {key: "code", title: "Código", hint: "Un bloque de código.", mark: "</>", words: "codigo code programa snippet"},
        {key: "divider", title: "Separador", hint: "Una línea para dividir secciones.", mark: "─", words: "separador divisor linea divider"},
        {key: "image", title: "Foto", hint: "Una imagen PNG o JPEG de tu equipo.", glyph: "photo", words: "foto imagen image picture"},
        {key: "ai", title: "Crear con IA", hint: "Pide a Claude o Codex que escriba aquí.", mark: "✦", words: "ia ai crear escribir claude codex inteligencia"}
    ]
    function fold(text) {
        return text.toLowerCase().replace(/[áàä]/g,"a").replace(/[éèë]/g,"e").replace(/[íìï]/g,"i")
                   .replace(/[óòö]/g,"o").replace(/[úùü]/g,"u").replace(/ñ/g,"n")
    }
    readonly property var matches: {
        const q = fold(query.trim())
        if (!q) return commands
        return commands.filter(c => fold(c.title).indexOf(q) >= 0 || c.words.split(" ").some(w => w.indexOf(q) === 0))
    }
    function move(step) { if (matches.length) highlighted = (highlighted+step+matches.length) % matches.length }
    function current() { return matches.length ? matches[Math.min(highlighted,matches.length-1)] : null }
    onQueryChanged: highlighted = 0

    width: 320; height: list.implicitHeight+12
    radius: 10; color: "#252526"; border.color: "#3e3d41"; z: 30
    Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 2; anchors.bottomMargin: -5; radius: 12; color: "#38000000" }
    MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons; onWheel: function(wheel) { wheel.accepted = true } }
    ColumnLayout {
        id: list
        x: 6; y: 6; width: parent.width-12; spacing: 0
        Text {
            text: menu.query ? "Resultados" : "Bloques básicos"; color: "#8e8c92"; font.pixelSize: 12
            Layout.leftMargin: 8; Layout.topMargin: 2; Layout.bottomMargin: 4
        }
        ListView {
            id: options
            Layout.fillWidth: true; Layout.preferredHeight: Math.min(contentHeight,336)
            clip: true; model: menu.matches; currentIndex: menu.highlighted
            highlightMoveDuration: 0; boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: options.contentHeight > options.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
            delegate: AbstractButton {
                id: option
                required property var modelData
                required property int index
                objectName: "slash-" + modelData.key
                width: options.width; implicitHeight: 48; leftPadding: 6; rightPadding: 8
                focusPolicy: Qt.NoFocus; hoverEnabled: true
                Accessible.name: modelData.title
                onHoveredChanged: if (hovered) menu.highlighted = index
                onClicked: menu.chosen(modelData)
                background: Rectangle { radius: 6; color: menu.highlighted === option.index ? "#2f2f32" : "transparent" }
                contentItem: RowLayout {
                    spacing: 10
                    Rectangle {
                        implicitWidth: 36; implicitHeight: 36; radius: 6; color: "#1e1e20"; border.color: "#3a3a3e"
                        Glyph { anchors.centerIn: parent; visible: !!option.modelData.glyph; name: option.modelData.glyph || "text"; font.pixelSize: 16; color: "#d6d4da" }
                        Text {
                            anchors.centerIn: parent; visible: !option.modelData.glyph; text: option.modelData.mark || ""
                            font.pixelSize: option.modelData.mark === "</>" ? 12 : 15; font.weight: Font.DemiBold
                            font.family: option.modelData.key === "callout" ? "Segoe UI Emoji" : "Segoe UI"
                            renderType: option.modelData.key === "callout" ? Text.NativeRendering : Text.QtRendering
                            color: option.modelData.key === "ai" ? "#a4bfe5" : "#d6d4da"
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 1
                        Text { text: option.modelData.title; color: "#efedf0"; font.pixelSize: 14; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: option.modelData.hint; color: "#8e8c92"; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }
            }
        }
        Text {
            visible: !menu.matches.length
            text: "Sin resultados"; color: "#8e8c92"; font.pixelSize: 13
            Layout.leftMargin: 8; Layout.topMargin: 6; Layout.bottomMargin: 8
        }
    }
}
