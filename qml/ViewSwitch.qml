import QtQuick
import QtQuick.Controls.Basic

// How the open page is shown, as the view buttons on Word's status bar: Edición (the usual editor),
// Lectura (the page can be read, not changed) and Diseño de página (sheets of paper with margins).
// The current one is raised; a click or its shortcut picks another.
Rectangle {
    id: views
    property string mode: "edit"
    signal chosen(string mode)
    readonly property var choices: [
        {mode: "edit", glyph: "edit", label: "Edición", keys: "Ctrl+Shift+E"},
        {mode: "read", glyph: "book", label: "Modo lectura", keys: "Ctrl+Shift+R"},
        {mode: "page", glyph: "page", label: "Diseño de página", keys: "Ctrl+Shift+D"}]
    implicitWidth: buttons.implicitWidth+6; implicitHeight: 30
    radius: Theme.radiusButton
    color: Theme.base
    border.color: Theme.hover
    Accessible.role: Accessible.Grouping
    Accessible.name: "Vista de la página"
    Row {
        id: buttons
        anchors.centerIn: parent
        spacing: 2
        Repeater {
            model: views.choices
            delegate: AbstractButton {
                id: choice
                required property var modelData
                readonly property bool current: views.mode === modelData.mode
                objectName: "view-" + modelData.mode
                width: 30; height: 24
                hoverEnabled: true; focusPolicy: Qt.TabFocus
                checkable: true; checked: current
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.label
                onClicked: { checked = Qt.binding(function() { return choice.current }); views.chosen(modelData.mode) }
                ToolTip.visible: hovered
                ToolTip.delay: 450
                ToolTip.text: modelData.label + " (" + modelData.keys + ")"
                background: Rectangle {
                    radius: 6
                    color: choice.current ? Theme.surface : choice.down ? Theme.pressed : choice.hovered ? Theme.hover : "transparent"
                    border.width: choice.current || choice.visualFocus ? 1 : 0
                    border.color: choice.visualFocus ? Theme.focus : Theme.line
                }
                contentItem: Item {
                    Glyph {
                        anchors.centerIn: parent
                        name: choice.modelData.glyph; font.pixelSize: 13
                        color: choice.current ? Theme.glyph : Theme.muted
                    }
                }
            }
        }
    }
}
