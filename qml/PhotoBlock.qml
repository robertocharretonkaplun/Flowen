import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Lunqio

// A photo of the page: width as a share of the column, where it sits (left, centre, right) and its
// style (rounded corners, a border or a shadow). A double click shows it at full size.
ColumnLayout {
    id: photo
    required property string asset
    required property string caption
    required property int percent
    required property bool editable
    property string align: ""          // "center", "right", or at the left
    property string frame: ""          // "rounded", "border", "shadow", or plain
    signal resized(int value)
    signal captionEdited(string value)
    signal focused(var field)
    signal viewRequested()
    function focusCaption() { captionField.forceActiveFocus() }
    readonly property int corner: frame === "rounded" || frame === "shadow" ? 12 : frame === "border" ? 6 : 0
    spacing: 5
    Item {
        id: holder
        Layout.fillWidth: true
        Layout.preferredHeight: picture.height+(photo.frame === "shadow" ? 10 : 0)
        // Where the photo starts in the column.
        readonly property real start: photo.align === "center" ? Math.round((width-picture.width)/2)
                                      : photo.align === "right" ? width-picture.width : 0
        Rectangle {
            // The shadow sits under the photo, slightly lower.
            visible: photo.frame === "shadow" && picture.status === 1
            x: picture.x-2; y: picture.y+4; width: picture.width+4; height: picture.height+4
            radius: photo.corner+2; color: Theme.shadow
        }
        // Draws the photo clipped to its corners (status: 1 when shown, 3 when it could not be read).
        PhotoView {
            id: picture
            objectName: "pagePhoto"
            x: holder.start
            width: Math.round(holder.width*photo.percent/100)
            height: implicitWidth > 0 ? Math.max(1,Math.round(width*implicitHeight/implicitWidth)) : 92
            source: photo.asset ? backend.photoUrl(photo.asset) : ""
            radius: photo.corner
            Accessible.role: Accessible.Graphic
            Accessible.name: photo.caption || "Foto"
        }
        Rectangle {
            visible: photo.frame === "border" && picture.status === 1
            x: picture.x; y: picture.y; width: picture.width; height: picture.height
            radius: photo.corner; color: "transparent"; border.width: 1; border.color: Theme.line
        }
        TapHandler { acceptedButtons: Qt.LeftButton; onDoubleTapped: photo.viewRequested() }
        Label { anchors.centerIn: picture; visible: picture.status === 3; text: "No se pudo mostrar la foto." }
        Rectangle {
            visible: photo.editable && picture.status === 1
            anchors.right: picture.right; anchors.bottom: picture.bottom; anchors.margins: 3+photo.corner/3
            width: 24; height: 24; radius: 5; color: dragger.containsMouse ? Theme.accentSoft : "#cc302523"; border.color: Theme.muted
            Label { anchors.centerIn: parent; text: "⤡"; color: "white"; font.pixelSize: 15 }
            MouseArea {
                id: dragger; objectName: "photoResizeGrip"; anchors.fill: parent; hoverEnabled: true; preventStealing: true
                cursorShape: Qt.SizeFDiagCursor
                property real initialX
                property real initialWidth
                onPressed: function(mouse) { initialX = mapToItem(holder,mouse.x,mouse.y).x; initialWidth = picture.width }
                onPositionChanged: function(mouse) {
                    if (pressed && holder.width > 0) {
                        // A centred photo grows on both sides, so the pointer moves half as far.
                        const moved = mapToItem(holder,mouse.x,mouse.y).x-initialX
                        const w = initialWidth+(photo.align === "center" ? 2 : photo.align === "right" ? -1 : 1)*moved
                        const value = Math.max(10,Math.min(100,Math.round(100*w/holder.width)))
                        if (value !== photo.percent) photo.resized(value)
                    }
                }
                ToolTip.visible: containsMouse && !pressed; ToolTip.text: "Arrastra para cambiar el tamaño"; ToolTip.delay: 450
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        TextField {
            id: captionField; Layout.fillWidth: true; text: photo.caption
            readOnly: !photo.editable; selectByMouse: true
            padding: 3; color: Theme.secondary; font.pixelSize: 13
            horizontalAlignment: photo.align === "right" ? Text.AlignRight : photo.align === "center" ? Text.AlignHCenter : Text.AlignLeft
            placeholderText: "Añadir pie de foto…"; maximumLength: 8192
            Accessible.name: "Pie de foto"; background: Item {}
            onTextEdited: photo.captionEdited(text)
            onActiveFocusChanged: if (activeFocus) photo.focused(captionField)
        }
        Label { visible: photo.editable; text: "Ancho (%)"; color: Theme.muted; font.pixelSize: 12 }
        SpinBox {
            visible: photo.editable; objectName: "photoWidth"
            from: 10; to: 100; stepSize: 5; value: photo.percent; editable: true
            implicitWidth: 132; implicitHeight: 31; Accessible.name: "Ancho de foto en porcentaje"
            onValueModified: photo.resized(value)
        }
    }
}
