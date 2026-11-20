import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// Ayuda → Acerca de Lunqio: the app and its version, and Attribute Overload, the studio that makes it,
// with its site, the project's code and its documentation. The studio's lockup has a white name on
// dark themes and an ink one on light themes.
Dialog {
    id: dialog
    required property string version
    readonly property string site: "https://www.attributeoverload.com"
    readonly property string repository: "https://github.com/robertocharretonkaplun/lunqio-"
    readonly property string documentation: "https://robertocharretonkaplun.github.io/lunqio-/"
    title: "Acerca de Lunqio"
    modal: true; anchors.centerIn: parent
    width: Math.min(520,parent.width-40)
    padding: 24; topPadding: 4
    background: Rectangle {
        color: Theme.surface; radius: Theme.radiusPanel; border.color: Theme.line
        Rectangle { z: -1; anchors.fill: parent; anchors.margins: -1; anchors.topMargin: 4; anchors.bottomMargin: -10; radius: Theme.radiusPanel+2; color: Theme.shadow }
    }
    header: RowLayout {
        Item { Layout.fillWidth: true }
        UiButton { objectName: "aboutClose"; symbol: "close"; quiet: true; hint: "Cerrar (Esc)"; onClicked: dialog.close(); Layout.rightMargin: 12; Layout.topMargin: 12 }
    }
    contentItem: ColumnLayout {
        spacing: 16
        RowLayout {
            spacing: 16
            Image { source: "../assets/lunqio-256.png"; sourceSize: Qt.size(128,128); Layout.preferredWidth: 64; Layout.preferredHeight: 64; smooth: true; mipmap: true }
            ColumnLayout {
                spacing: 2
                Label { text: "Lunqio"; color: Theme.text; font.pixelSize: 26; font.weight: Font.DemiBold }
                Label { objectName: "aboutVersion"; text: "Versión " + dialog.version; color: Theme.muted; font.pixelSize: 13 }
            }
        }
        Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.secondary; font.pixelSize: 14; lineHeight: 1.3
            text: "Editor local de páginas, fotos y tareas para Windows, con IA y conexión MCP para Claude y Codex. Tus notas se quedan en tu equipo."
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hover }
        Label { text: "Una aplicación creada por"; color: Theme.muted; font.pixelSize: 12 }
        // The studio's lockup opens its site.
        AbstractButton {
            id: studio; objectName: "studioLogo"
            Layout.preferredWidth: 236; Layout.preferredHeight: 56
            hoverEnabled: true
            Accessible.name: "Attribute Overload: abrir attributeoverload.com"
            ToolTip.visible: hovered; ToolTip.delay: 450; ToolTip.text: "attributeoverload.com"
            onClicked: Qt.openUrlExternally(dialog.site)
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            background: Rectangle { radius: Theme.radiusButton; color: studio.hovered ? Theme.raised : "transparent"; border.width: studio.visualFocus ? 1 : 0; border.color: Theme.focus }
            contentItem: Image {
                objectName: "studioImage"
                source: Theme.dark ? "../assets/brand/ao-lockup-white.png" : "../assets/brand/ao-lockup-ink.png"
                fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
                sourceSize.width: 560
            }
        }
        Flow {
            Layout.fillWidth: true; spacing: 8
            UiButton { objectName: "aboutSite"; symbol: "globe"; text: "attributeoverload.com"; hint: dialog.site; onClicked: Qt.openUrlExternally(dialog.site) }
            UiButton { objectName: "aboutCode"; symbol: "code"; text: "GitHub"; hint: dialog.repository; onClicked: Qt.openUrlExternally(dialog.repository) }
            UiButton { objectName: "aboutDocs"; symbol: "book"; text: "Documentación"; hint: dialog.documentation; onClicked: Qt.openUrlExternally(dialog.documentation) }
        }
        Label { text: "© 2026 Attribute Overload"; color: Theme.faint; font.pixelSize: 12 }
    }
}
