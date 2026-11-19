import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Sidebar usage indicator: a blue ring with the active assistant's plan use and a diamond in
// that assistant's colour. Hovering shows the plan limits; clicking opens the Uso tab.
AbstractButton {
    id: button
    required property var assistant
    signal openUsage()
    readonly property var colors: ({claude: "#d4714f", codex: "#9085e9"})
    readonly property string engine: assistant.engine
    readonly property string engineName: engine === "claude" ? "Claude" : "Codex"
    readonly property var plan: engine === "claude" ? assistant.limits.claude : assistant.limits.codex
    readonly property var lead: plan.fiveHour || plan.weekly || null
    readonly property real share: lead ? lead.used/100 : 0
    readonly property var today: { assistant.usage.count; return assistant.usage.totals(1) }
    implicitWidth: 30; implicitHeight: 30
    hoverEnabled: true
    Accessible.name: "Uso de " + engineName + (lead ? ", " + lead.used + " por ciento del límite" : "") + ". Abrir la pestaña Uso"
    onClicked: { card.close(); openUsage() }
    onHoveredChanged: hovered ? opener.restart() : closer.restart()
    Timer { id: opener; interval: 220; onTriggered: if (button.hovered) { button.assistant.limits.refreshIfStale(90); card.open() } }
    Timer { id: closer; interval: 260; onTriggered: if (!button.hovered && !cardHover.hovered) card.close() }
    background: Rectangle {
        radius: 15; color: button.down ? "#3a3a3d" : button.hovered || card.opened ? "#313133" : "transparent"
        border.width: button.visualFocus ? 1 : 0; border.color: "#8db3ff"
    }
    contentItem: Item {
        Canvas {
            id: ring
            anchors.centerIn: parent; width: 22; height: 22
            property real share: button.share
            onShareChanged: requestPaint()
            onPaint: {
                const g = getContext("2d"), c = width/2, r = c-2
                g.reset(); g.lineWidth = 2.5; g.lineCap = "round"
                g.strokeStyle = "#3e3e42"; g.beginPath(); g.arc(c,c,r,0,2*Math.PI); g.stroke()
                if (share > 0) {
                    g.strokeStyle = "#3b8beb"; g.beginPath()
                    g.arc(c,c,r,-Math.PI/2,-Math.PI/2+Math.max(0.05,share)*2*Math.PI); g.stroke()
                }
            }
        }
        Rectangle {
            objectName: "usageDiamond"
            anchors.centerIn: parent; width: 7; height: 7; radius: 1; rotation: 45
            color: button.colors[button.engine] || "#c9c7cc"
        }
    }
    Popup {
        id: card; objectName: "usageCard"
        width: 384; padding: 18
        y: -height-10
        onAboutToShow: x = Math.max(8-button.mapToItem(null,0,0).x,button.width-width+40)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 14; color: "#262628"; border.color: "#3e3d41"
            Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 3; anchors.bottomMargin: -6; radius: 16; color: "#40000000" }
        }
        HoverHandler { id: cardHover; onHoveredChanged: if (!hovered) closer.restart() }
        contentItem: ColumnLayout {
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true; elide: Text.ElideRight; color: "#a9a6ae"; font.pixelSize: 13
                    text: "Límites de uso del plan · " + button.engineName
                          + (button.plan.plan ? " " + button.plan.plan.charAt(0).toUpperCase() + button.plan.plan.slice(1) : "")
                }
                AbstractButton {
                    objectName: "usageSeeAll"; hoverEnabled: true; focusPolicy: Qt.NoFocus
                    onClicked: { card.close(); button.openUsage() }
                    contentItem: Label { text: "Ver todo  →"; color: parent.hovered ? "#ffffff" : "#e6e5e8"; font.pixelSize: 13; font.weight: Font.DemiBold }
                    background: Item {}
                }
            }
            PlanLimitsView {
                Layout.fillWidth: true
                plan: button.plan; engine: button.engine; checking: button.assistant.limits.checking
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#37363a" }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Rectangle { width: 7; height: 7; radius: 1; rotation: 45; color: button.colors[button.engine] }
                Label { text: "Lunqio hoy"; color: "#c9c6cd"; font.pixelSize: 13; Layout.fillWidth: true }
                Label {
                    color: "#efedf0"; font.pixelSize: 13; font.features: {"tnum": 1}
                    text: (button.today.total >= 1000 ? (button.today.total/1000).toLocaleString(Qt.locale(),'f',1) + " k" : button.today.total)
                          + " tokens · " + button.today.requests + (button.today.requests === 1 ? " petición" : " peticiones")
                }
            }
        }
    }
}
