import QtQuick

// The rhombus in the assistant's colour (Claude orange, Codex violet). Drawn as a path on an even
// box, so its centre lands on a whole pixel and lines up with the ring and the text beside it.
Canvas {
    id: mark
    property color color: "#d4714f"
    property real size: 10              // tip to tip
    implicitWidth: Math.ceil(size/2)*2; implicitHeight: implicitWidth
    onColorChanged: requestPaint()
    onSizeChanged: requestPaint()
    onPaint: {
        const g = getContext("2d"), cx = width/2, cy = height/2, h = size/2
        g.reset()
        g.fillStyle = color
        g.beginPath()
        g.moveTo(cx,cy-h); g.lineTo(cx+h,cy); g.lineTo(cx,cy+h); g.lineTo(cx-h,cy)
        g.closePath(); g.fill()
    }
}
