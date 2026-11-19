import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Above the title, as in Notion: the page's big emoji, and on hover "Añadir icono" / "Añadir portada".
ColumnLayout {
    id: header
    required property var page          // the window: pageIcon, pageCover, setPageIcon(), setPageCover()
    property var picker: null
    property bool titleHovered: false
    readonly property bool editable: !page.deleted
    spacing: 2
    HoverHandler { id: zone }
    AbstractButton {
        id: bigIcon; objectName: "pageIcon"
        visible: !!header.page.pageIcon
        implicitWidth: 80; implicitHeight: 80; hoverEnabled: true; focusPolicy: Qt.NoFocus; enabled: header.editable
        Accessible.name: "Cambiar el icono de la página"
        onClicked: header.picker.pick(bigIcon,function(emoji) { header.page.setPageIcon(emoji) },true)
        background: Rectangle { radius: 8; color: bigIcon.hovered ? "#2a2a2c" : "transparent" }
        contentItem: Text {
            text: header.page.pageIcon; font.family: "Segoe UI Emoji"; font.pixelSize: 62
            renderType: Text.NativeRendering; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
    }
    RowLayout {
        spacing: 2; Layout.preferredHeight: 30
        opacity: header.editable && (zone.hovered || header.titleHovered) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        UiButton {
            id: addIcon; objectName: "addIcon"
            visible: !header.page.pageIcon; quiet: true; text: "☺  Añadir icono"; enabled: header.editable
            onClicked: header.picker.pick(addIcon,function(emoji) { if (emoji) header.page.setPageIcon(emoji) },false)
        }
        UiButton {
            objectName: "addCover"
            visible: !header.page.pageCover; quiet: true; symbol: "photo"; text: "Añadir portada"; enabled: header.editable
            // Like Notion, a cover appears right away; it can be changed afterwards.
            onClicked: {
                const names = Object.keys(header.page.covers)
                header.page.setPageCover("gradient:" + names[Math.floor(Math.random()*names.length)])
            }
        }
    }
}
