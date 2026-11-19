import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Button {
    id: control
    property bool primary: false
    property bool quiet: false
    property string hint: ""
    property string symbol: ""
    property bool alignLeft: false
    implicitHeight: 32
    implicitWidth: Math.max(30, group.implicitWidth + (text ? 20 : 8))
    padding: 0
    opacity: enabled ? 1 : 0.4
    hoverEnabled: true
    Accessible.name: hint || text
    ToolTip.visible: hovered && !!hint
    ToolTip.text: hint
    ToolTip.delay: 500
    contentItem: Item {
        RowLayout {
            id: group
            anchors.verticalCenter: parent.verticalCenter
            x: control.alignLeft ? 9 : Math.round((parent.width-width)/2)
            spacing: 7
            Glyph { visible: !!control.symbol; name: control.symbol; color: control.primary ? "#18171a" : "#c8c7ca" }
            Text {
                visible: !!control.text; text: control.text; font: control.font
                color: control.primary ? "#18171a" : "#e4e3e5"
            }
        }
    }
    background: Rectangle {
        radius: 6
        color: control.primary ? (control.down ? "#cccad4" : "#eeedf1")
               : control.down ? "#414044" : control.hovered ? "#333335" : control.quiet ? "transparent" : "#272729"
        border.width: control.visualFocus || (!control.quiet && !control.primary) ? 1 : 0
        border.color: control.visualFocus ? "#8db3ff" : "#404043"
    }
}
