import QtQuick
import Quickshell
import Quickshell.Wayland
import "../js/Model.js" as Model

// One click-through layer per screen, over the windows. Each dusty window on this
// screen's workspace gets two canvases of its own size: the dust layer, drawn when the
// dust changes, and the moving specks, drawn every frame while there are any. Small
// canvases are fast to draw, and with nothing to draw the layer is not on screen at all.
PanelWindow {
    id: overlay

    property var svc: null
    readonly property var cfg: svc ? svc.cfg : null

    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "window-dust-overlay"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    surfaceFormat.opaque: false
    mask: Region {}

    // this screen in Hyprland's terms, found by its output name ("eDP-1", "HDMI-A-1", …)
    readonly property string outputName: screen ? screen.name : ""
    readonly property var mon: svc && svc.monitors[outputName] ? svc.monitors[outputName] : null
    // -1 until Hyprland has told us: nothing is drawn rather than the wrong screen's dust
    readonly property int monId: mon ? mon.id : -1
    readonly property real originX: mon ? mon.x : 0
    readonly property real originY: mon ? mon.y : 0
    // a fullscreen window here: the layer goes away, so it can't cover it
    readonly property bool covered: svc ? svc.fullscreenMonitors[monId] === true : false

    readonly property var col: Model.rgbOf(cfg ? cfg.dustColor : "")
    function rgba(c, a) { return "rgba(" + c.r + "," + c.g + "," + c.b + "," + a + ")" }

    // What there is to draw here, worked out when the windows or their dust change
    // (svc.layoutRev), not every frame. `addrs` only changes when windows come or go,
    // so their canvases stay; `geo` has each one's place on this screen, its dust, and
    // the parts that windows in front cover (in the window's own coordinates).
    property var addrs: []
    property var geo: ({})
    property bool anyMoving: false
    function relayout() {
        const list = [], g = {}
        let moving = false
        if (svc && monId >= 0 && !covered && cfg.particles) {
            const entries = svc.entries
            for (let i = 0; i < entries.length; i++) {
                const e = entries[i]
                if (e.monitor !== monId || svc.shown[e.address] !== true || e.w <= 0 || e.h <= 0) continue
                const s = svc.sets[e.address]
                const drawn = s ? s.level : 0
                if (e.level <= 0 && drawn <= 0.003) continue
                const occ = cfg.occlude ? Model.occluders(e, entries, svc.shown) : []
                for (let k = 0; k < occ.length; k++) { occ[k][0] -= e.x; occ[k][1] -= e.y }
                list.push(e.address)
                g[e.address] = { level: e.level, x: e.x - originX, y: e.y - originY, w: e.w, h: e.h,
                                 gx: e.x, gy: e.y, occ: occ }
                if (s && s.list.length > 0) moving = true
            }
        }
        geo = g
        if (JSON.stringify(list) !== JSON.stringify(addrs)) addrs = list
        anyMoving = moving
    }
    Connections {
        target: overlay.svc
        function onLayoutRevChanged() { overlay.relayout() }
        function onCfgChanged() { overlay.relayout() }
    }
    onMonIdChanged: relayout()
    onCoveredChanged: relayout()

    visible: addrs.length > 0 && !covered

    // keep a window's dust inside it, and off the windows in front of it
    function clipTo(ctx, w, h, occ) {
        ctx.beginPath()
        ctx.rect(0, 0, w, h)
        for (let k = 0; k < occ.length; k++) {
            const o = occ[k]
            // the other way round, so the even-odd rule leaves a hole
            ctx.moveTo(o[0], o[1]); ctx.lineTo(o[0], o[1] + o[3]); ctx.lineTo(o[0] + o[2], o[1] + o[3]); ctx.lineTo(o[0] + o[2], o[1]); ctx.closePath()
        }
        ctx.fillRule = Qt.OddEvenFill
        ctx.clip()
        ctx.fillRule = Qt.WindingFill
    }

    // The dust layer: a fine powder, a haze thicker toward the bottom, and more in the
    // corners. Every speck comes from the window's address, so it stays put.
    function paintPowder(ctx, address, it) {
        const cfg = overlay.cfg
        const level = it.level
        if (!cfg.effectPowder || level < 0.03) return
        const op = cfg.particleOpacity
        const col = overlay.col
        const rgba = a => overlay.rgba(col, a)
        const w = it.w, h = it.h
        ctx.save()
        overlay.clipTo(ctx, w, h, it.occ)

        const haze = ctx.createLinearGradient(0, 0, 0, h)
        haze.addColorStop(0, rgba(level * 0.025 * op))
        haze.addColorStop(1, rgba(level * 0.14 * op))
        ctx.fillStyle = haze
        ctx.fillRect(0, 0, w, h)

        const cr = Math.min(w, h) * 0.4
        const corners = [[0, 0], [w, 0], [0, h], [w, h]]
        for (let c = 0; c < 4; c++) {
            const rg = ctx.createRadialGradient(corners[c][0], corners[c][1], 0, corners[c][0], corners[c][1], cr)
            rg.addColorStop(0, rgba(level * 0.12 * op))
            rg.addColorStop(1, rgba(0))
            ctx.fillStyle = rg
            ctx.fillRect(corners[c][0] - cr, corners[c][1] - cr, cr * 2, cr * 2)
        }

        // three batches (size and brightness), one path and one fill each
        const alphas = [0.35, 0.6, 0.9]
        const sizes = [0.9, 1.3, 1.9]
        const n = Math.round(Model.powderCount(w, h, cfg) * level)
        const seed = Model.hashStr(address)
        const strength = Math.min(1, 0.4 + level * 0.6) * op
        for (let b = 0; b < 3; b++) {
            ctx.fillStyle = rgba(alphas[b] * strength)
            ctx.beginPath()
            for (let i = b; i < n; i += 3) {
                const u = Model.rand01(seed, i, 0)
                const v = 1 - Math.pow(Model.rand01(seed, i, 1), 1.6)    // more toward the bottom
                ctx.rect(u * w, v * h, sizes[b], sizes[b])
            }
            ctx.fill()
        }
        ctx.restore()
    }

    // The moving dust: motes, grain, smudges, streaks, fibres, cobwebs and spiders.
    function paintSpecks(ctx, address, it) {
        const s = overlay.svc ? overlay.svc.sets[address] : null
        if (!s || s.list.length === 0 || s.level <= 0.003) return
        const col = overlay.col
        ctx.save()
        overlay.clipTo(ctx, it.w, it.h, it.occ)
        ctx.globalCompositeOperation = "lighter"
        const list = s.list
        for (let i = 0; i < list.length; i++) {
            if (list[i].kind === "spider") {
                ctx.globalCompositeOperation = "source-over"
                overlay.drawSpider(ctx, list[i], col, it.gx, it.gy)
                ctx.globalCompositeOperation = "lighter"
            } else {
                overlay.drawParticle(ctx, list[i], col, it.gx, it.gy)
            }
        }
        ctx.restore()
    }

    Repeater {
        model: overlay.addrs
        delegate: Item {
            id: win
            required property var modelData
            readonly property var it: overlay.geo[modelData] || ({ level: 0, x: 0, y: 0, w: 1, h: 1, gx: 0, gy: 0, occ: [] })
            x: it.x
            y: it.y
            width: it.w
            height: it.h

            Canvas {
                id: powder
                anchors.fill: parent
                renderStrategy: Canvas.Cooperative
                // drawn again only when it would look different
                readonly property string sig: [overlay.cfg ? overlay.cfg.effectPowder : false, overlay.cfg ? overlay.cfg.powderDensity : 0,
                    overlay.cfg ? overlay.cfg.dustColor : "", overlay.cfg ? overlay.cfg.particleOpacity : 0,
                    win.it.w, win.it.h, Math.round(win.it.level * 100), JSON.stringify(win.it.occ)].join("|")
                onSigChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    overlay.paintPowder(ctx, win.modelData, win.it)
                }
            }
            Canvas {
                id: specks
                anchors.fill: parent
                renderStrategy: Canvas.Cooperative
                antialiasing: true
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    overlay.paintSpecks(ctx, win.modelData, win.it)
                }
                Connections {
                    target: overlay.svc
                    function onFrameChanged() { if (overlay.visible) specks.requestPaint() }
                }
            }
        }
    }

    function drawParticle(ctx, p, col, ox, oy) {
        let px = p.x - ox
        let py = p.y - oy
        let tw = 0.75 + 0.25 * Math.sin(p.twinklePhase)
        let alpha = p.alpha * tw
        if (alpha <= 0.006) return

        const rgba = a => overlay.rgba(col, a)

        if (p.kind === "cobweb") {
            let dirX = (p.corner === 0 || p.corner === 2) ? 1 : -1
            let dirY = (p.corner < 2) ? 1 : -1
            ctx.strokeStyle = rgba(alpha * 0.7)
            ctx.lineWidth = 0.6

            for (let s = 0; s < 4; s++) {
                let ang = (Math.PI / 2) * (s / 3)
                let ex = px + dirX * Math.cos(ang) * p.size
                let ey = py + dirY * Math.sin(ang) * p.size
                ctx.beginPath()
                ctx.moveTo(px, py)
                ctx.lineTo(ex, ey)
                ctx.stroke()
            }
            for (let rr = 0.45; rr <= 1.001; rr += 0.28) {
                let r = p.size * rr
                let a0, a1
                if (dirX > 0 && dirY > 0) { a0 = 0; a1 = Math.PI / 2 }
                else if (dirX < 0 && dirY > 0) { a0 = Math.PI / 2; a1 = Math.PI }
                else if (dirX < 0 && dirY < 0) { a0 = Math.PI; a1 = Math.PI * 1.5 }
                else { a0 = Math.PI * 1.5; a1 = Math.PI * 2 }
                ctx.beginPath()
                ctx.arc(px, py, r, a0, a1)
                ctx.stroke()
            }

        } else if (p.kind === "fiber") {
            // a curved strand of lint
            let fdx = Math.cos(p.ang) * p.len / 2
            let fdy = Math.sin(p.ang) * p.len / 2
            ctx.strokeStyle = rgba(alpha * 0.8)
            ctx.lineWidth = 0.7
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.moveTo(px - fdx, py - fdy)
            ctx.quadraticCurveTo(px - Math.sin(p.ang) * p.curve, py + Math.cos(p.ang) * p.curve,
                                                      px + fdx, py + fdy)
            ctx.stroke()

        } else if (p.kind === "smudge") {
            let grad = ctx.createRadialGradient(px, py, 0, px, py, p.size)
            grad.addColorStop(0, rgba(alpha * 0.6))
            grad.addColorStop(1, rgba(0))
            ctx.fillStyle = grad
            ctx.beginPath()
            ctx.arc(px, py, p.size, 0, Math.PI * 2)
            ctx.fill()

        } else if (p.kind === "streak") {
            ctx.strokeStyle = rgba(alpha)
            ctx.lineWidth = p.size
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.moveTo(px, py)
            ctx.lineTo(px + p.vx * 1.2, py + p.len)
            ctx.stroke()

        } else if (p.kind === "grain") {
            ctx.fillStyle = rgba(alpha)
            ctx.beginPath()
            ctx.arc(px, py, p.size, 0, Math.PI * 2)
            ctx.fill()

        } else {
            // mote
            ctx.fillStyle = rgba(alpha)
            ctx.beginPath()
            ctx.arc(px, py, p.size, 0, Math.PI * 2)
            ctx.fill()

            ctx.beginPath()
            ctx.arc(px, py, p.size * 2.2, 0, Math.PI * 2)
            ctx.fillStyle = rgba(alpha * 0.18)
            ctx.fill()
        }
    }

    // A small spider: two body parts, eight jointed legs that step in alternation.
    // Dark with a light rim, so it shows up on both dark and light windows.
    function drawSpider(ctx, p, col, ox, oy) {
        let a = p.alpha
        if (a <= 0.01) return
        let s = p.size
        let light = "rgba(" + col.r + "," + col.g + "," + col.b + "," + (a * 0.55) + ")"
        let dark = "rgba(16,14,12," + a + ")"

        ctx.save()
        ctx.translate(p.x - ox, p.y - oy)
        ctx.rotate(p.ang)
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        // legs: four pairs, fanned out, each swinging in its own phase
        let feet = []
        for (let side = -1; side <= 1; side += 2) {
            for (let k = 0; k < 4; k++) {
                let ax = s * (0.55 - k * 0.38)
                let dir = side * (Math.PI / 2 + (k - 1.5) * 0.47)
                let swing = Math.sin(p.legPhase + k * 1.57 + (side > 0 ? 0 : 3.14159)) * 0.38
                let d2 = dir + swing
                let kx = ax + Math.cos(d2) * s * 1.7
                let ky = Math.sin(d2) * s * 1.7
                let fx = kx + Math.cos(d2 + side * 0.7) * s * 2.1
                let fy = ky + Math.sin(d2 + side * 0.7) * s * 2.1
                feet.push([ax, kx, ky, fx, fy])
            }
        }
        for (let pass = 0; pass < 2; pass++) {
            ctx.strokeStyle = pass === 0 ? light : dark
            ctx.lineWidth = pass === 0 ? 2.2 : 1.0
            ctx.beginPath()
            for (let f = 0; f < feet.length; f++) {
                ctx.moveTo(feet[f][0], 0)
                ctx.lineTo(feet[f][1], feet[f][2])
                ctx.lineTo(feet[f][3], feet[f][4])
            }
            ctx.stroke()
        }

        // body: abdomen behind, head and thorax in front, a rim first and the dark fill on top
        for (let bp = 0; bp < 2; bp++) {
            let grow = bp === 0 ? 0.8 : 0
            ctx.fillStyle = bp === 0 ? light : dark
            ctx.beginPath()
            ctx.save()
            ctx.translate(-s * 0.9, 0)
            ctx.scale(1.15, 0.85)
            ctx.arc(0, 0, s + grow, 0, Math.PI * 2)
            ctx.restore()
            ctx.fill()
            ctx.beginPath()
            ctx.arc(s * 0.45, 0, s * 0.62 + grow, 0, Math.PI * 2)
            ctx.fill()
        }
        ctx.fillStyle = light
        ctx.beginPath()
        ctx.arc(s * 0.9, -s * 0.2, s * 0.13, 0, Math.PI * 2)
        ctx.arc(s * 0.9, s * 0.2, s * 0.13, 0, Math.PI * 2)
        ctx.fill()
        ctx.restore()
    }
}
