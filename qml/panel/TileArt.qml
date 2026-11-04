import QtQuick
import "../js/Model.js" as Model

// The little picture on a tile: for "How dust settles", the build-up over time.
Canvas {
    id: art

    property var ui: null
    property string key: ""
    property string opt: ""
    property bool on: false

    width: 64
    height: 40
    readonly property color ink: ui ? ui.fg : "white"
    readonly property color ac: ui ? ui.accent : "white"
    onOnChanged: requestPaint()
    onInkChanged: requestPaint()
    onAcChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        // the axes: time along, dust up
        ctx.strokeStyle = Qt.rgba(ink.r, ink.g, ink.b, 0.18)
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(4.5, 2); ctx.lineTo(4.5, height - 4.5); ctx.lineTo(width - 2, height - 4.5)
        ctx.stroke()
        if (key !== "curve") return
        const c = on ? ac : Qt.rgba(ink.r, ink.g, ink.b, 0.75)
        const x0 = 6, x1 = width - 4, y0 = height - 6, y1 = 4
        // the dust under the curve
        ctx.beginPath()
        ctx.moveTo(x0, y0)
        for (let i = 0; i <= 32; i++) {
            const t = i / 32
            ctx.lineTo(x0 + (x1 - x0) * t, y0 - (y0 - y1) * Model.dustLevel(t, 0, 1, opt))
        }
        ctx.lineTo(x1, y0)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.18)
        ctx.fill()
        ctx.beginPath()
        for (let j = 0; j <= 32; j++) {
            const t = j / 32
            const x = x0 + (x1 - x0) * t, y = y0 - (y0 - y1) * Model.dustLevel(t, 0, 1, opt)
            if (j === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
        }
        ctx.strokeStyle = c
        ctx.lineWidth = 1.6
        ctx.stroke()
    }
}
