import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// "Conectores": the library's MCP server and the AI clients allowed to start it.
ScrollView {
    id: page
    required property var assistant
    readonly property var link: assistant.link
    readonly property var hub: assistant.connectors
    readonly property bool connected: link.state === "connected"
    readonly property bool connecting: link.state === "connecting"
    readonly property bool checking: hub.claudeDesktop.busy || hub.claudeCode.busy || hub.codex.busy
    signal chooseCodex()
    signal chooseClaude()
    clip: true
    contentWidth: availableWidth
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    onVisibleChanged: if (visible) { hub.inspectAll(); if (assistant.engine === "claude") assistant.checkClaude() }
    Connections {
        target: page.assistant
        function onExecutableChanged() { if (page.visible) page.hub.codex.inspect() }
    }

    component Detail: Label {
        Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: 13; lineHeight: 1.15
    }
    component Section: Label {
        Layout.fillWidth: true; Layout.topMargin: 30; Layout.bottomMargin: 10
        font.pixelSize: 15; font.weight: Font.DemiBold; color: Theme.text
    }
    component Card: Rectangle {
        Layout.fillWidth: true; radius: Theme.radiusPanel; color: Theme.sidebar; border.color: Theme.line
    }
    component Tile: Rectangle {
        property string glyph: ""
        property string letter: ""
        property bool light: false
        implicitWidth: 38; implicitHeight: 38; radius: 9
        color: light ? Theme.ivory : Theme.raised; border.color: light ? Theme.ivory : Theme.pressed
        Glyph { anchors.centerIn: parent; visible: !!parent.glyph; name: parent.glyph; font.pixelSize: 17; color: Theme.textSoft }
        Label { anchors.centerIn: parent; visible: !parent.glyph; text: parent.letter; font.pixelSize: 18; font.weight: Font.Bold; color: parent.light ? Theme.ink : Theme.textSoft }
    }
    component Toggle: Switch {
        id: toggle
        padding: 0; implicitWidth: 40; implicitHeight: 24
        indicator: Rectangle {
            x: toggle.leftPadding; y: Math.round((toggle.height-height)/2)
            implicitWidth: 40; implicitHeight: 22; radius: 11
            opacity: toggle.enabled ? 1 : 0.45
            color: toggle.checked ? Theme.accent : Theme.pressed
            border.color: toggle.visualFocus ? Theme.focus : toggle.checked ? Theme.accent : Theme.line
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle {
                width: 16; height: 16; radius: 8; y: 3
                x: toggle.checked ? parent.width-width-3 : 3
                color: toggle.checked ? Theme.accentInk : Theme.secondary
                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
        }
        contentItem: Item {}
    }
    component Chip: Rectangle {
        property string tone: "idle"
        property alias text: chipLabel.text
        implicitWidth: chipLabel.implicitWidth+16; implicitHeight: 20; radius: 10
        color: ({on: Theme.successSoft, warn: Theme.warningSoft, error: Theme.dangerSoft})[tone] || Theme.raised
        Label {
            id: chipLabel; anchors.centerIn: parent; font.pixelSize: 11; font.weight: Font.DemiBold
            color: ({on: Theme.success, warn: Theme.warning, error: Theme.danger})[parent.tone] || Theme.muted
        }
    }
    component ClientRow: Item {
        id: client
        required property var connector
        required property int index
        readonly property var labels: ({
            on: ["Activo","on"], paused: ["Inactivo","idle"], off: ["Inactivo","idle"], outdated: ["Ruta antigua","warn"],
            restart: ["Reinicia Claude","warn"],
            missing: ["No encontrado","idle"], error: ["Error","error"], checking: ["Comprobando…","idle"],
            applying: [connector.enabled ? "Activando…" : "Desactivando…","idle"], idle: ["Sin comprobar","idle"]
        })[connector.state] || ["", "idle"]
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight+30
        Rectangle { visible: client.index > 0; x: 16; width: parent.width-32; height: 1; color: Theme.raised }
        RowLayout {
            id: body
            x: 16; width: parent.width-32; y: 15
            spacing: 14
            Tile { glyph: client.connector.icon; Layout.alignment: Qt.AlignTop }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                RowLayout {
                    spacing: 8
                    Label { text: client.connector.title; font.pixelSize: 15; font.weight: Font.DemiBold; color: Theme.text }
                    Chip { text: client.labels[0]; tone: client.labels[1]; visible: !!text }
                }
                Label { text: client.connector.summary; font.pixelSize: 12; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                Detail { text: client.connector.detail; Layout.topMargin: 6; color: client.connector.state === "error" ? Theme.danger : Theme.secondary }
                Label {
                    visible: !!client.connector.location; Layout.fillWidth: true; Layout.topMargin: 2
                    text: client.connector.location; elide: Text.ElideMiddle
                    font.family: "Consolas"; font.pixelSize: 11; color: Theme.faint
                }
            }
            Toggle {
                objectName: "toggle-" + client.connector.key
                Layout.alignment: Qt.AlignTop; Layout.topMargin: 6
                checked: client.connector.enabled
                enabled: client.connector.ready && !client.connector.busy
                Accessible.name: "Activar " + client.connector.title
                onToggled: client.connector.setEnabled(checked)
            }
            UiButton {
                symbol: "more"; quiet: true; hint: "Más opciones de " + client.connector.title
                Layout.alignment: Qt.AlignTop; Layout.topMargin: 2
                onClicked: options.popup()
                UiMenu {
                    id: options
                    UiMenuItem { text: "Comprobar de nuevo"; enabled: !client.connector.busy; onTriggered: client.connector.inspect() }
                    UiMenuItem {
                        visible: client.connector.usesProgram; height: visible ? implicitHeight : 0
                        text: client.connector.key === "codex" ? "Elegir codex.exe…" : "Elegir claude.exe…"
                        enabled: !client.connector.busy
                        onTriggered: client.connector.key === "codex" ? page.chooseCodex() : page.chooseClaude()
                    }
                    UiMenuItem { text: "Mostrar archivo de configuración"; enabled: !!client.connector.location; onTriggered: client.connector.reveal() }
                    UiMenuSeparator {}
                    UiMenuItem {
                        text: "Quitar registro"
                        enabled: client.connector.registered && client.connector.ready && !client.connector.busy
                        onTriggered: client.connector.remove()
                    }
                }
            }
        }
    }

    ColumnLayout {
        width: Math.min(760,page.availableWidth-48)
        x: Math.round((page.availableWidth-width)/2)
        spacing: 0
        Item { Layout.preferredHeight: 30 }
        Label { text: "Conectores"; font.pixelSize: 30; font.weight: Font.Bold; color: Theme.text }
        Detail {
            Layout.topMargin: 6; Layout.maximumWidth: 620; font.pixelSize: 14
            text: "Conecta esta biblioteca con tus asistentes de IA mediante MCP. Activa un cliente para que pueda buscar, leer y editar tus páginas."
        }

        Section { text: "Servidor de la biblioteca" }
        Card {
            implicitHeight: server.implicitHeight+32
            ColumnLayout {
                id: server
                x: 16; y: 16; width: parent.width-32
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true; spacing: 14
                    Tile { letter: "L"; light: true }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 3
                        Label { text: "Conexión del editor"; font.pixelSize: 15; font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true }
                        RowLayout {
                            spacing: 6
                            Rectangle { width: 7; height: 7; radius: 4; color: page.connected ? Theme.success : page.connecting ? Theme.warning : Theme.faint }
                            Label {
                                font.pixelSize: 13; color: Theme.secondary
                                text: page.connected ? "Conectada · " + page.link.tools.length + " herramientas"
                                      : page.connecting ? "Conectando…" : "Desconectada"
                            }
                        }
                    }
                    Toggle {
                        objectName: "toggleLocalMcp"
                        checked: page.connected || page.connecting
                        enabled: !page.connecting && page.assistant.phase !== "applying" && page.assistant.phase !== "generating"
                        Accessible.name: "Conexión del editor"
                        onToggled: checked ? page.link.open() : page.link.close()
                    }
                    Item { Layout.preferredWidth: 30 }   // lines up with the client switches

                }
                Detail {
                    text: page.connected || page.connecting
                          ? "La usa «Editar con IA» dentro de Lunqio. Cada cliente abre su propia conexión, incluso con Lunqio cerrado."
                          : (page.link.detail || "Actívala para usar «Editar con IA». Los clientes conectados siguen funcionando aunque esté apagada.")
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.raised }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    CheckBox { checked: page.link.autoConnect; text: "Conectar al abrir Lunqio"; onToggled: page.link.autoConnect = checked }
                    Item { Layout.fillWidth: true }
                    Label {
                        Layout.maximumWidth: 330; text: page.link.databasePath.replace(/\//g,"\\"); elide: Text.ElideMiddle
                        font.family: "Consolas"; font.pixelSize: 11; color: Theme.faint
                    }
                }
            }
        }

        Section { text: "IA dentro de Lunqio" }
        Card {
            implicitHeight: writer.implicitHeight+32
            ColumnLayout {
                id: writer
                x: 16; y: 16; width: parent.width-32
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true; spacing: 14
                    Tile { letter: "✦" }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 3
                        Label { text: "Crear y editar con IA"; font.pixelSize: 15; font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true }
                        Label {
                            Layout.fillWidth: true; font.pixelSize: 13; color: Theme.secondary; elide: Text.ElideRight
                            text: page.assistant.engine === "codex"
                                  ? (page.assistant.engineReady ? "Escribe con Codex" : "Codex no está instalado")
                                  : !page.assistant.engineReady ? "Claude Code no está instalado"
                                  : ({in: "Escribe con Claude · sesión iniciada", out: "Claude Code: falta iniciar sesión",
                                      checking: "Comprobando la sesión de Claude…"})[page.assistant.claudeAccount] || "Escribe con Claude"
                        }
                    }
                    EngineSwitch { objectName: "connectorsEngine"; assistant: page.assistant }
                    Item { Layout.preferredWidth: 30 }
                }
                Detail { text: "Elige quién escribe en «Crear con IA» (Espacio en una línea vacía o Ctrl+J) y en «Editar con IA». Usa tu propia cuenta de ese servicio." }
                RowLayout {
                    visible: page.assistant.engine === "claude" && page.assistant.engineReady && page.assistant.claudeAccount === "out"
                    Layout.fillWidth: true; spacing: 10
                    Detail { text: "La copia de Claude Code que usa Lunqio necesita que inicies sesión una vez. Se abrirá una ventana para hacerlo con tu cuenta de Claude."; color: Theme.warning }
                    UiButton { text: "Iniciar sesión"; primary: true; onClicked: page.assistant.signInClaude() }
                    UiButton { text: "Comprobar"; quiet: true; onClicked: page.assistant.checkClaude() }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true; Layout.topMargin: 30; Layout.bottomMargin: 10
            Label { text: "Clientes"; font.pixelSize: 15; font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true }
            UiButton { objectName: "inspectConnectors"; text: "Comprobar"; quiet: true; enabled: !page.checking; onClicked: page.hub.inspectAll() }
        }
        Card {
            implicitHeight: clients.implicitHeight
            ColumnLayout {
                id: clients
                width: parent.width; spacing: 0
                Repeater {
                    model: page.hub.clients
                    delegate: ClientRow { required property var modelData; connector: modelData }
                }
            }
        }
        Card {
            Layout.topMargin: 12
            implicitHeight: other.implicitHeight+28
            RowLayout {
                id: other
                x: 16; y: 14; width: parent.width-32; spacing: 14
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label { text: "Otro cliente MCP"; font.pixelSize: 14; font.weight: Font.DemiBold; color: Theme.text }
                    Detail { text: "Copia la configuración para clientes que usan mcpServers, como Cursor, Windsurf o VS Code." }
                }
                UiButton {
                    text: copied.running ? "Copiada" : "Copiar JSON"; symbol: copied.running ? "check" : "copy"
                    onClicked: { page.hub.copyConfiguration(); copied.restart() }
                    Timer { id: copied; interval: 2200 }
                }
            }
        }

        Section { text: "Herramientas" + (page.connected ? " (" + page.link.tools.length + ")" : "") }
        Card {
            implicitHeight: toolList.implicitHeight+(toolList.visible ? 20 : 0)+(toolHint.visible ? toolHint.implicitHeight+28 : 0)
            Detail {
                id: toolHint; visible: !page.connected
                x: 16; y: 14; width: parent.width-32
                text: "Activa la conexión del editor para ver las herramientas que ofrece esta biblioteca."
            }
            GridLayout {
                id: toolList
                visible: page.connected
                x: 16; y: 10; width: parent.width-32
                columns: width > 560 ? 2 : 1; columnSpacing: 24; rowSpacing: 0
                readonly property var descriptions: ({
                    list_pages: "Listar páginas, subpáginas o papelera", search_notes: "Buscar en títulos y contenido",
                    get_page: "Leer una página y sus bloques", create_page: "Crear páginas y subpáginas",
                    update_page: "Renombrar o mover una página", apply_block_changes: "Editar texto, tareas y bloques",
                    trash_page: "Enviar páginas a la papelera", restore_page: "Recuperar páginas de la papelera"
                })
                Repeater {
                    model: page.connected ? page.link.tools : []
                    delegate: ColumnLayout {
                        required property string modelData
                        Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.topMargin: 8; Layout.bottomMargin: 8; spacing: 2
                        Label { Layout.fillWidth: true; text: toolList.descriptions[modelData] || modelData; color: Theme.textSoft; font.pixelSize: 13; elide: Text.ElideRight }
                        Label { text: modelData; font.family: "Consolas"; font.pixelSize: 11; color: Theme.secondary }
                    }
                }
            }
        }
        Item { Layout.preferredHeight: 30 }
    }
}
