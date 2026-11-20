import QtQuick

// Diseño de página: the sheets the page is laid out on, as in Word's print layout. Each sheet has the
// page's colour and a soft shadow on the desk around it; its number sits in the bottom margin.
// The text itself is the page's column, placed over the sheets by the window.
Item {
    id: sheets
    property int count: 1
    property real paperWidth: 816
    property real paperHeight: 1056
    property real gap: 24
    property real bottomMargin: 96
    readonly property real stride: paperHeight+gap
    implicitWidth: paperWidth
    implicitHeight: count*paperHeight+Math.max(0,count-1)*gap
    width: implicitWidth; height: implicitHeight
    Repeater {
        model: sheets.count
        delegate: Item {
            id: sheet
            required property int index
            objectName: "sheet-" + index
            y: index*sheets.stride; width: sheets.paperWidth; height: sheets.paperHeight
            Rectangle { x: -2; y: 1; width: parent.width+4; height: parent.height+5; radius: 4; color: Theme.shadowSoft }
            Rectangle { x: 0; y: 2; width: parent.width; height: parent.height; radius: 3; color: Theme.shadow }
            Rectangle {
                anchors.fill: parent; radius: 2; color: Theme.canvas
                border.width: Theme.dark ? 1 : 0; border.color: Theme.raised
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height-Math.round(sheets.bottomMargin/2)-Math.round(height/2)
                text: sheet.index+1; color: Theme.faint
                font.family: Theme.family; font.pixelSize: 11; font.features: {"tnum": 1}
                Accessible.name: "Página " + (sheet.index+1)
            }
        }
    }
}
