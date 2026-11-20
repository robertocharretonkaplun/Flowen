import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: photo
    required property string asset
    required property string caption
    required property int percent
    required property bool editable
    signal resized(int value)
    signal captionEdited(string value)
    signal focused(var field)
    function focusCaption() { captionField.forceActiveFocus() }
    spacing: 5
    Item {
        id: frame
        Layout.fillWidth: true
        Layout.preferredHeight: picture.height
        Image {
            id: picture; objectName: "pagePhoto"
            width: Math.round(frame.width*photo.percent/100)
            height: implicitWidth > 0 ? Math.max(1,Math.round(width*implicitHeight/implicitWidth)) : 92
            source: photo.asset ? backend.photoUrl(photo.asset) : ""
            sourceSize.width: 1440
            fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
            Accessible.role: Accessible.Graphic
            Accessible.name: photo.caption || "Foto"
        }
        Label { anchors.centerIn: picture; visible: picture.status === Image.Error || picture.status === Image.Null; text: "No se pudo mostrar la foto." }
        Rectangle {
            visible: photo.editable && picture.status === Image.Ready
            anchors.right: picture.right; anchors.bottom: picture.bottom; anchors.margins: 3
            width: 24; height: 24; radius: 5; color: dragger.containsMouse ? Theme.accentSoft : "#cc302523"; border.color: Theme.muted
            Label { anchors.centerIn: parent; text: "⤡"; color: "white"; font.pixelSize: 15 }
            MouseArea {
                id: dragger; objectName: "photoResizeGrip"; anchors.fill: parent; hoverEnabled: true; preventStealing: true
                cursorShape: Qt.SizeFDiagCursor
                property real initialX
                property real initialWidth
                onPressed: function(mouse) { initialX = mapToItem(frame,mouse.x,mouse.y).x; initialWidth = picture.width }
                onPositionChanged: function(mouse) {
                    if (pressed && frame.width > 0) {
                        const w = initialWidth + mapToItem(frame,mouse.x,mouse.y).x - initialX
                        const value = Math.max(10,Math.min(100,Math.round(100*w/frame.width)))
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
