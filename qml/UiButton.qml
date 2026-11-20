import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// The identity's control: 8 px corners, 14 px semibold labels, the coral accent for the main action
// with ink text on it, and symbols in ivory and coral.
Button {
    id: control
    property bool primary: false
    property bool quiet: false
    property string hint: ""
    property string symbol: ""
    property bool alignLeft: false
    property color symbolColor: primary ? Theme.accentInk : Theme.glyph
    implicitHeight: 32
    implicitWidth: Math.max(32, group.implicitWidth + (text ? 20 : 8))
    padding: 0
    opacity: enabled ? 1 : 0.4
    hoverEnabled: true
    font.family: Theme.family
    font.pixelSize: 14
    font.weight: quiet ? Font.Normal : Font.DemiBold
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
            Glyph { visible: !!control.symbol; name: control.symbol; color: control.symbolColor }
            Text {
                visible: !!control.text; text: control.text; font: control.font
                color: control.primary ? Theme.accentInk : Theme.textSoft
            }
        }
    }
    background: Rectangle {
        radius: Theme.radiusButton
        color: control.primary ? (control.down ? Theme.accentPressed : control.hovered ? Theme.accentHover : Theme.accent)
               : control.down ? Theme.pressed : control.hovered ? Theme.hover : control.quiet ? "transparent" : Theme.surface
        border.width: control.visualFocus || (!control.quiet && !control.primary) ? 1 : 0
        border.color: control.visualFocus ? Theme.focus : Theme.line
    }
}
