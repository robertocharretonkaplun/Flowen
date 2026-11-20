import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// "Uso": tokens spent by Crear con IA and Editar con IA, as reported by each assistant.
ScrollView {
    id: page
    required property var assistant
    readonly property var usage: assistant.usage
    // Chart colours (validated for the dark card surface): one per assistant, one per token kind.
    readonly property var engineColor: ({claude: "#d4714f", codex: "#9085e9"})
    readonly property var partColor: ({input: "#199e70", cacheRead: "#c98500", cacheWrite: "#d55181", output: "#0ca30c"})
    readonly property var today: { usage.count; return usage.totals(1) }
    readonly property var week: { usage.count; return usage.totals(7) }
    readonly property var all: { usage.count; return usage.totals(-1) }
    readonly property var days: { usage.count; return usage.daily(14) }
    readonly property var last: usage.last
    clip: true
    contentWidth: availableWidth
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    onVisibleChanged: if (visible) assistant.limits.refreshIfStale(60)

    function tokens(n) {
        n = Number(n || 0)
        if (n >= 1e6) return (n/1e6).toLocaleString(Qt.locale(),'f',1) + " M"
        if (n >= 1000) return (n/1000).toLocaleString(Qt.locale(),'f',n >= 100000 ? 0 : 1) + " k"
        return Math.round(n).toLocaleString(Qt.locale(),'f',0)
    }
    function money(n) {
        if (n <= 0) return "US$ 0"
        if (n < 0.01) return "< US$ " + (0.01).toLocaleString(Qt.locale(),'f',2)
        return "US$ " + n.toLocaleString(Qt.locale(),'f',2)
    }
    function when(iso) {
        const d = new Date(iso)
        if (isNaN(d.getTime())) return ""
        const now = new Date()
        const days = Math.round((new Date(now.getFullYear(),now.getMonth(),now.getDate()) - new Date(d.getFullYear(),d.getMonth(),d.getDate()))/86400000)
        const time = Qt.formatTime(d,"HH:mm")
        return days === 0 ? time + " Hoy" : days === 1 ? time + " Ayer" : Qt.formatDate(d,"d MMM") + " " + time
    }
    function requests(n) { return n === 1 ? "1 petición" : n + " peticiones" }
    function niceMax(n) {
        if (n <= 0) return 1000
        const power = Math.pow(10,Math.floor(Math.log10(n)))
        for (const step of [1,2,2.5,5,10]) if (step*power >= n) return step*power
        return 10*power
    }

    component Detail: Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.muted; font.pixelSize: 13 }
    component Section: Label {
        Layout.fillWidth: true; Layout.topMargin: 30; Layout.bottomMargin: 10
        font.pixelSize: 15; font.weight: Font.DemiBold; color: Theme.text
    }
    component Card: Rectangle { Layout.fillWidth: true; radius: Theme.radiusPanel; color: Theme.sidebar; border.color: Theme.line }
    component Stat: Rectangle {
        property string label: ""
        property string value: ""
        property string note: ""
        Layout.fillWidth: true; Layout.preferredWidth: 1
        implicitHeight: 92; radius: Theme.radiusPanel; color: Theme.sidebar; border.color: Theme.line
        ColumnLayout {
            x: 16; y: 14; width: parent.width-32; spacing: 3
            Label { text: parent.parent.label; color: Theme.muted; font.pixelSize: 12 }
            Label { text: parent.parent.value; color: Theme.text; font.pixelSize: 24; font.weight: Font.DemiBold; font.features: {"tnum": 1} }
            Label { text: parent.parent.note; color: Theme.muted; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
        }
    }
    component Key: RowLayout {
        property color swatch: Theme.text
        property string label: ""
        property string value: ""
        spacing: 6
        Rectangle { width: 9; height: 9; radius: 2; color: parent.swatch }
        Label { text: parent.label; color: Theme.secondary; font.pixelSize: 12 }
        Label { text: parent.value; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold; visible: !!text; font.features: {"tnum": 1} }
    }

    ColumnLayout {
        width: Math.min(820,page.availableWidth-48)
        x: Math.round((page.availableWidth-width)/2)
        spacing: 0
        Item { Layout.preferredHeight: 30 }
        Label { text: "Uso"; font.pixelSize: 30; font.weight: Font.Bold; color: Theme.text }
        Detail {
            Layout.topMargin: 6; Layout.maximumWidth: 640; font.pixelSize: 14
            text: "Tokens que consumen «Crear con IA» y «Editar con IA» en este equipo, según los informa cada asistente."
        }

        GridLayout {
            Layout.fillWidth: true; Layout.topMargin: 24
            columns: width > 640 ? 4 : 2; columnSpacing: 12; rowSpacing: 12
            Stat { objectName: "usageToday"; label: "Hoy"; value: page.tokens(page.today.total); note: page.requests(page.today.requests) }
            Stat { label: "Últimos 7 días"; value: page.tokens(page.week.total); note: page.requests(page.week.requests) }
            Stat { label: "Total"; value: page.tokens(page.all.total); note: page.requests(page.all.requests) }
            Stat {
                label: "Costo estimado"; value: page.all.priced ? page.money(page.all.cost) : "Sin datos"
                note: page.all.priced ? "Claude, a precio de API" : "Codex no informa el costo"
            }
        }

        // The plans' own limits, which also count what you use outside Lunqio.
        Section { text: "Límites del plan" }
        GridLayout {
            Layout.fillWidth: true
            columns: width > 640 ? 2 : 1; columnSpacing: 12; rowSpacing: 12
            Repeater {
                model: ["claude","codex"]
                delegate: Card {
                    id: planCard
                    required property string modelData
                    readonly property var plan: modelData === "claude" ? page.assistant.limits.claude : page.assistant.limits.codex
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop
                    implicitHeight: planBody.implicitHeight+32
                    border.color: page.assistant.engine === modelData ? Theme.line : Theme.hover
                    ColumnLayout {
                        id: planBody
                        x: 16; y: 16; width: parent.width-32; spacing: 12
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            EngineMark { size: 11; color: page.engineColor[planCard.modelData]; Layout.alignment: Qt.AlignVCenter }
                            Label {
                                Layout.fillWidth: true; color: Theme.text; font.pixelSize: 15; font.weight: Font.DemiBold
                                text: (planCard.modelData === "claude" ? "Claude" : "Codex")
                                      + (planCard.plan.plan ? " · " + planCard.plan.plan.charAt(0).toUpperCase() + planCard.plan.plan.slice(1) : "")
                            }
                            Label { visible: page.assistant.engine === planCard.modelData; text: "En uso"; color: Theme.muted; font.pixelSize: 12 }
                        }
                        PlanLimitsView {
                            Layout.fillWidth: true; plan: planCard.plan; engine: planCard.modelData
                            checking: planCard.modelData === "codex" && page.assistant.limits.checking
                        }
                    }
                }
            }
        }

        Card {
            visible: page.usage.count === 0
            Layout.topMargin: 24; implicitHeight: empty.implicitHeight+36
            ColumnLayout {
                id: empty
                x: 18; y: 18; width: parent.width-36; spacing: 6
                Label { text: "Aún no hay peticiones"; font.pixelSize: 15; font.weight: Font.DemiBold; color: Theme.text }
                Detail { text: "Usa «Crear con IA» (Espacio en una línea vacía o Ctrl+J) o «Editar con IA» y aquí verás los tokens de cada petición." }
            }
        }

        Section { visible: page.usage.count > 0; text: "Última petición" }
        Card {
            visible: page.usage.count > 0
            implicitHeight: latest.implicitHeight+36
            RowLayout {
                id: latest
                x: 18; y: 18; width: parent.width-36; spacing: 22
                // Context ring: share of the model's context window this request filled.
                Item {
                    readonly property real share: page.last.window > 0 ? Math.min(1,page.last.total/page.last.window) : 0
                    visible: page.last.window > 0
                    implicitWidth: 104; implicitHeight: 104
                    Canvas {
                        id: ring
                        anchors.fill: parent
                        property real share: parent.share
                        property color track: Theme.hover
                        property color fill: Theme.accent
                        onShareChanged: requestPaint()
                        onTrackChanged: requestPaint()
                        onFillChanged: requestPaint()
                        onPaint: {
                            const g = getContext("2d"), c = width/2, r = c-7
                            g.reset(); g.lineWidth = 9; g.lineCap = "round"
                            g.strokeStyle = track; g.beginPath(); g.arc(c,c,r,0,2*Math.PI); g.stroke()
                            if (share > 0) {
                                g.strokeStyle = fill; g.beginPath()
                                g.arc(c,c,r,-Math.PI/2,-Math.PI/2+Math.max(0.04,share)*2*Math.PI); g.stroke()
                            }
                        }
                    }
                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 0
                        Label {
                            Layout.alignment: Qt.AlignHCenter; color: Theme.text; font.pixelSize: 20; font.weight: Font.DemiBold
                            text: (parent.parent.share*100 < 1 && parent.parent.share > 0 ? "<1" : Math.round(parent.parent.share*100)) + " %"
                        }
                        Label { Layout.alignment: Qt.AlignHCenter; text: "contexto"; color: Theme.muted; font.pixelSize: 11 }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    Label {
                        Layout.fillWidth: true; elide: Text.ElideRight; color: Theme.text; font.pixelSize: 15; font.weight: Font.DemiBold
                        text: (page.last.engine === "claude" ? "Claude" : "Codex") + (page.last.model ? " · " + page.last.model : "")
                    }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.secondary; font.pixelSize: 13
                        text: (page.last.kind === "create" ? "Crear con IA" : "Editar con IA") + ", " + page.when(page.last.at)
                              + (page.last.ms ? " · " + (page.last.ms/1000).toLocaleString(Qt.locale(),'f',1) + " s" : "")
                              + (page.last.ok === false ? " · sin resultado" : "")
                    }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.text; font.pixelSize: 13
                        text: page.tokens(page.last.total) + " tokens"
                              + (page.last.window > 0 ? " de " + page.tokens(page.last.window) + " de contexto" : "")
                              + (page.last.cost !== undefined ? " · " + page.money(page.last.cost) : "")
                    }
                    // Breakdown, as a single stacked bar with a 2 px gap between parts.
                    Row {
                        id: parts
                        Layout.fillWidth: true; Layout.preferredHeight: 10; spacing: 2
                        readonly property var keys: ["input","cacheRead","cacheWrite","output"].filter(k => (page.last[k] || 0) > 0)
                        Repeater {
                            model: parts.keys
                            delegate: Rectangle {
                                required property string modelData
                                required property int index
                                height: 10; radius: 2
                                width: Math.max(3,(parts.width-2*(parts.keys.length-1))*(page.last[modelData] || 0)/Math.max(1,page.last.total))
                                color: page.partColor[modelData]
                            }
                        }
                    }
                    Flow {
                        Layout.fillWidth: true; Layout.preferredHeight: childrenRect.height; spacing: 16
                        Key { swatch: page.partColor.input; label: "Entrada"; value: page.tokens(page.last.input) }
                        Key { swatch: page.partColor.cacheRead; label: "Caché leída"; value: page.tokens(page.last.cacheRead) }
                        Key { swatch: page.partColor.cacheWrite; label: "Caché escrita"; value: page.tokens(page.last.cacheWrite) }
                        Key { swatch: page.partColor.output; label: "Salida"; value: page.tokens(page.last.output) }
                    }
                }
            }
        }

        RowLayout {
            visible: page.usage.count > 0
            Layout.fillWidth: true; Layout.topMargin: 30; Layout.bottomMargin: 10
            Label { text: "Últimos 14 días"; font.pixelSize: 15; font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true }
            Key { swatch: page.engineColor.claude; label: "Claude" }
            Key { swatch: page.engineColor.codex; label: "Codex"; Layout.leftMargin: 10 }
        }
        Card {
            visible: page.usage.count > 0
            implicitHeight: 236
            Item {
                id: chart
                x: 16; y: 16; width: parent.width-32; height: parent.height-32
                readonly property real peak: page.niceMax(Math.max(...page.days.map(d => d.claude+d.codex)))
                readonly property int axis: 46
                readonly property real plotHeight: height-24
                property int hovered: -1
                // Recessive grid: zero, middle and top, labelled on the left.
                Repeater {
                    model: [0,0.5,1]
                    delegate: Item {
                        required property real modelData
                        width: chart.width; height: 1
                        y: chart.plotHeight - modelData*chart.plotHeight
                        Rectangle { x: chart.axis; width: parent.width-chart.axis; height: 1; color: modelData === 0 ? Theme.pressed : Theme.raised }
                        Label {
                            width: chart.axis-8; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                            text: page.tokens(chart.peak*modelData); color: Theme.muted; font.pixelSize: 11; font.features: {"tnum": 1}
                        }
                    }
                }
                Row {
                    id: bars
                    x: chart.axis; width: chart.width-chart.axis; height: chart.height
                    readonly property real slot: width/Math.max(1,page.days.length)
                    Repeater {
                        model: page.days
                        delegate: Item {
                            id: day
                            required property var modelData
                            required property int index
                            width: bars.slot; height: bars.height
                            readonly property real claudeHeight: chart.plotHeight*modelData.claude/chart.peak
                            readonly property real codexHeight: chart.plotHeight*modelData.codex/chart.peak
                            Rectangle { // hover column
                                anchors.fill: parent; anchors.bottomMargin: 20; radius: 5
                                color: chart.hovered === day.index ? Theme.raised : "transparent"
                            }
                            Rectangle { // Claude, at the baseline
                                visible: day.modelData.claude > 0
                                width: Math.min(22,bars.slot-8); x: (parent.width-width)/2
                                height: Math.max(2,day.claudeHeight); y: chart.plotHeight-height
                                radius: day.modelData.codex > 0 ? 0 : 4; color: page.engineColor.claude
                                Rectangle { visible: parent.radius > 0; width: parent.width; height: Math.min(4,parent.height); anchors.bottom: parent.bottom; color: parent.color }
                            }
                            Rectangle { // Codex, on top with a 2 px gap
                                visible: day.modelData.codex > 0
                                width: Math.min(22,bars.slot-8); x: (parent.width-width)/2
                                height: Math.max(2,day.codexHeight)
                                y: chart.plotHeight-(day.modelData.claude > 0 ? Math.max(2,day.claudeHeight)+2 : 0)-height
                                radius: 4; color: page.engineColor.codex
                                Rectangle { width: parent.width; height: Math.min(4,parent.height); anchors.bottom: parent.bottom; color: parent.color }
                            }
                            Label {
                                visible: day.modelData.today || day.index % 3 === 1
                                anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom
                                text: day.modelData.today ? "Hoy" : day.modelData.label; color: Theme.muted; font.pixelSize: 11
                            }
                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true
                                onContainsMouseChanged: chart.hovered = containsMouse ? day.index : (chart.hovered === day.index ? -1 : chart.hovered)
                            }
                            ToolTip {
                                visible: chart.hovered === day.index; delay: 0
                                text: (day.modelData.today ? "Hoy" : day.modelData.label) + "\nClaude: " + page.tokens(day.modelData.claude)
                                      + "\nCodex: " + page.tokens(day.modelData.codex) + "\n" + page.requests(day.modelData.requests)
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            visible: page.usage.count > 0
            Layout.fillWidth: true; Layout.topMargin: 30; Layout.bottomMargin: 10
            Label { text: "Peticiones recientes"; font.pixelSize: 15; font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true }
            UiButton { text: "Borrar historial"; quiet: true; onClicked: clearDialog.open() }
        }
        Card {
            visible: page.usage.count > 0
            implicitHeight: table.implicitHeight+16
            ColumnLayout {
                id: table
                x: 16; y: 8; width: parent.width-32; spacing: 0
                component Cell: Label {
                    property bool number: false
                    Layout.preferredWidth: number ? 78 : 1; Layout.fillWidth: !number
                    horizontalAlignment: number ? Text.AlignRight : Text.AlignLeft
                    elide: Text.ElideRight; font.pixelSize: 13; color: Theme.textSoft; font.features: {"tnum": 1}
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: 34; spacing: 12
                    Cell { text: "Cuándo"; color: Theme.muted; font.pixelSize: 12 }
                    Cell { text: "Asistente"; color: Theme.muted; font.pixelSize: 12 }
                    Cell { text: "Tipo"; color: Theme.muted; font.pixelSize: 12 }
                    Cell { number: true; text: "Entrada"; color: Theme.muted; font.pixelSize: 12 }
                    Cell { number: true; text: "Salida"; color: Theme.muted; font.pixelSize: 12 }
                    Cell { number: true; text: "Total"; color: Theme.muted; font.pixelSize: 12 }
                    Cell { number: true; text: "Costo"; color: Theme.muted; font.pixelSize: 12 }
                }
                Repeater {
                    model: page.usage.recent.slice(0,20)
                    delegate: ColumnLayout {
                        id: entry
                        required property var modelData
                        Layout.fillWidth: true; spacing: 0
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.raised }
                        RowLayout {
                            Layout.fillWidth: true; Layout.preferredHeight: 36; spacing: 12
                            Cell { text: page.when(entry.modelData.at) }
                            RowLayout {
                                Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 7
                                Rectangle { width: 8; height: 8; radius: 4; color: page.engineColor[entry.modelData.engine] || Theme.muted }
                                Cell { text: entry.modelData.engine === "claude" ? "Claude" : "Codex" }
                            }
                            Cell { text: (entry.modelData.kind === "create" ? "Crear" : "Editar") + (entry.modelData.ok === false ? " · sin resultado" : "") }
                            Cell { number: true; text: page.tokens((entry.modelData.input || 0)+(entry.modelData.cacheRead || 0)+(entry.modelData.cacheWrite || 0)) }
                            Cell { number: true; text: page.tokens(entry.modelData.output) }
                            Cell { number: true; text: page.tokens(entry.modelData.total); color: Theme.text; font.weight: Font.DemiBold }
                            Cell { number: true; text: entry.modelData.cost !== undefined ? page.money(entry.modelData.cost) : "–" ; color: Theme.muted }
                        }
                    }
                }
            }
        }
        Item { Layout.preferredHeight: 30 }
    }
    Dialog {
        id: clearDialog; title: "¿Borrar el historial de uso?"; modal: true; anchors.centerIn: parent; width: 400
        standardButtons: Dialog.Yes | Dialog.Cancel
        contentItem: Label { text: "Se borran las cifras guardadas en este equipo. No afecta a tus páginas."; wrapMode: Text.Wrap; color: Theme.secondary }
        onAccepted: page.usage.clear()
    }
}
