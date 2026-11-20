import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// "@" or "[[": pick a page to mention, or create one with what you typed.
Rectangle {
    id: menu
    property string query: ""
    property int highlighted: 0
    property var pages: []
    property string currentId: ""
    signal chosen(var entry)
    function fold(text) {
        return (text || "").toLowerCase().replace(/[áàä]/g,"a").replace(/[éèë]/g,"e").replace(/[íìï]/g,"i")
                   .replace(/[óòö]/g,"o").replace(/[úùü]/g,"u").replace(/ñ/g,"n")
    }
    readonly property var titles: {
        const map = {}
        for (const p of pages) map[p.id] = p.title
        return map
    }
    readonly property var matches: {
        const q = fold(query.trim())
        const found = pages.filter(p => p.id !== currentId && (!q || fold(p.title).indexOf(q) >= 0))
        found.sort((a,b) => (fold(b.title).indexOf(q) === 0) - (fold(a.title).indexOf(q) === 0) || a.title.localeCompare(b.title))
        const list = found.slice(0,8).map(p => ({id: p.id, title: p.title, icon: p.icon || "", parent: titles[p.parent_id] || ""}))
        if (q && !pages.some(p => fold(p.title) === q)) list.push({create: true, title: query.trim()})
        return list
    }
    function move(step) { if (matches.length) highlighted = (highlighted+step+matches.length) % matches.length }
    function current() { return matches.length ? matches[Math.min(highlighted,matches.length-1)] : null }
    onQueryChanged: highlighted = 0

    width: 340; height: list.implicitHeight+12
    radius: Theme.radiusPanel; color: Theme.surface; border.color: Theme.line; z: 30
    Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 2; anchors.bottomMargin: -5; radius: Theme.radiusPanel+1; color: Theme.shadow }
    MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons; onWheel: function(wheel) { wheel.accepted = true } }
    ColumnLayout {
        id: list
        x: 6; y: 6; width: parent.width-12; spacing: 0
        Text { text: "Enlazar a una página"; color: Theme.muted; font.pixelSize: 12; Layout.leftMargin: 8; Layout.topMargin: 2; Layout.bottomMargin: 4 }
        Repeater {
            model: menu.matches
            delegate: AbstractButton {
                id: option
                required property var modelData
                required property int index
                objectName: modelData.create ? "mentionCreate" : "mention-" + index
                Layout.fillWidth: true; implicitHeight: 36; leftPadding: 8; rightPadding: 8
                focusPolicy: Qt.NoFocus; hoverEnabled: true
                Accessible.name: modelData.create ? "Nueva página " + modelData.title : modelData.title
                onHoveredChanged: if (hovered) menu.highlighted = index
                onClicked: menu.chosen(modelData)
                background: Rectangle { radius: Theme.radiusButton; color: menu.highlighted === option.index ? Theme.raised : "transparent" }
                contentItem: RowLayout {
                    spacing: 9
                    Item {
                        implicitWidth: 20; implicitHeight: 20
                        Glyph { anchors.centerIn: parent; visible: !!option.modelData.create; name: "add"; font.pixelSize: 13; color: Theme.accent }
                        PageIcon { anchors.centerIn: parent; visible: !option.modelData.create; icon: option.modelData.icon || ""; size: 15 }
                    }
                    Text {
                        Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 14; color: Theme.text
                        text: option.modelData.create ? "Nueva página «" + option.modelData.title + "»" : option.modelData.title
                    }
                    Text { visible: !!option.modelData.parent; text: option.modelData.parent || ""; color: Theme.muted; font.pixelSize: 12; elide: Text.ElideRight; Layout.maximumWidth: 110 }
                }
            }
        }
        Text {
            visible: !menu.matches.length
            text: "Escribe el nombre de una página"; color: Theme.muted; font.pixelSize: 13
            Layout.leftMargin: 8; Layout.topMargin: 6; Layout.bottomMargin: 8
        }
    }
}
