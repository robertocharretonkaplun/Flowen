import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// One assistant's plan limits: the 5-hour and weekly windows with their reset time.
ColumnLayout {
    id: view
    property var plan: ({})
    property string engine: "claude"
    property bool checking: false
    readonly property string name: engine === "claude" ? "Claude" : "Codex"
    readonly property bool known: !!plan.fiveHour || !!plan.weekly
    spacing: 12

    function resets(ms) {
        if (!ms) return ""
        const d = new Date(ms), now = new Date()
        const time = d.toLocaleTimeString(Qt.locale(),Locale.ShortFormat)
        if (d.toDateString() === now.toDateString()) return "Se restablece a las " + time
        return "Se restablece el " + d.toLocaleDateString(Qt.locale(),"ddd") + ", " + time
    }

    component Limit: ColumnLayout {
        id: limit
        property string title: ""
        property var window: null
        visible: !!window
        Layout.fillWidth: true; spacing: 7
        // Title and reset time share a line when they fit, as in Claude's own menu; otherwise the time goes below.
        GridLayout {
            id: heading
            Layout.fillWidth: true
            readonly property bool fits: titleText.implicitWidth+resetText.implicitWidth+16 <= view.width
            columns: fits ? 2 : 1; columnSpacing: 8; rowSpacing: 2
            Label { id: titleText; text: limit.title; color: "#efedf0"; font.pixelSize: 14; Layout.fillWidth: heading.fits }
            Label {
                id: resetText; Layout.alignment: Qt.AlignRight
                Layout.fillWidth: !heading.fits; horizontalAlignment: Text.AlignRight
                text: (limit.window && limit.window.resetsAt ? view.resets(limit.window.resetsAt) + "   " : "") + (limit.window ? limit.window.used + "%" : "")
                color: "#a9a6ae"; font.pixelSize: 13; font.features: {"tnum": 1}
            }
        }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 6; radius: 3; color: "#3a3a3d"
            Rectangle {
                width: limit.window ? Math.max(limit.window.used > 0 ? 6 : 0,parent.width*Math.min(100,limit.window.used)/100) : 0
                height: parent.height; radius: 3; color: "#3b8beb"
            }
        }
    }

    Limit { title: "Límite de 5 horas"; window: view.plan.fiveHour || null }
    Limit { title: "Semanal · todos los modelos"; window: view.plan.weekly || null }
    RowLayout {
        visible: !!view.plan.credits
        Layout.fillWidth: true
        Label { text: "Créditos"; color: "#efedf0"; font.pixelSize: 14; Layout.fillWidth: true }
        Label {
            color: "#a9a6ae"; font.pixelSize: 13
            text: !view.plan.credits ? "" : view.plan.credits.unlimited ? "Ilimitados" : (view.plan.credits.balance || "0") + " créditos"
        }
    }
    Label {
        Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 12
        color: view.plan.error && !view.known ? "#efb69c" : "#8e8c92"
        text: view.checking && !view.known ? "Consultando a " + view.name + "…"
              : view.known ? (view.engine === "claude" ? "Según tu última petición con Claude, " : "Actualizado ")
                             + new Date(view.plan.updatedAt).toLocaleTimeString(Qt.locale(),Locale.ShortFormat)
              : view.plan.error ? view.plan.error
              : view.engine === "claude" ? "Claude informa sus límites con cada petición; aparecerán tras la próxima."
              : "Sin datos de Codex todavía."
    }
}
