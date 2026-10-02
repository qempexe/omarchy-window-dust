import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: overlay

  required property var monitor
  required property var hostWidget

  screen: monitor

  anchors { top: true; bottom: true; left: true; right: true }
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "window-dust-overlay"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.exclusiveZone: -1
  color: "transparent"

  // Fully click-through.
  mask: Region {}

  readonly property real screenX: overlay.monitor ? overlay.monitor.x : 0
  readonly property real screenY: overlay.monitor ? overlay.monitor.y : 0

  readonly property var dustRgb: {
    var c = overlay.hostWidget ? overlay.hostWidget.dustConfig.dustColor : "8b8378";
    return {
      r: parseInt(c.substr(0, 2), 16),
      g: parseInt(c.substr(2, 2), 16),
      b: parseInt(c.substr(4, 2), 16)
    };
  }

  Canvas {
    id: canvas
    anchors.fill: parent
    renderStrategy: Canvas.Immediate
    antialiasing: true

    property var particleSets: overlay.hostWidget ? overlay.hostWidget.particleSets : ({})
    property var windowGeom: overlay.hostWidget ? overlay.hostWidget.windowGeom : ({})
    property var visibleAddresses: overlay.hostWidget ? overlay.hostWidget.visibleAddresses : ({})

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)

      var col = overlay.dustRgb
      var addrs = Object.keys(particleSets)

      for (var a = 0; a < addrs.length; a++) {
        var addr = addrs[a]

        // Skip windows that aren't on the currently active workspace of their
        // monitor. This is what makes effects disappear when you switch.
        if (visibleAddresses[addr] !== true) continue

        var g = windowGeom[addr]
        if (!g) continue
        var set = particleSets[addr]
        if (!set || set.length === 0) continue

        // Convert window rect to local overlay coords.
        var wx = g.x - overlay.screenX
        var wy = g.y - overlay.screenY

        // Quick reject if the window is entirely off this overlay.
        if (wx > width + 4 || wy > height + 4) continue
        if (wx + g.w < -4 || wy + g.h < -4) continue

        // Clip everything to the window rect.
        ctx.save()
        ctx.beginPath()
        ctx.rect(wx, wy, g.w, g.h)
        ctx.clip()

        ctx.globalCompositeOperation = "lighter"

        for (var i = 0; i < set.length; i++) {
          drawParticle(ctx, set[i], col)
        }

        ctx.restore()
      }
    }

    function drawParticle(ctx, p, col) {
      var px = p.x - overlay.screenX
      var py = p.y - overlay.screenY
      var tw = 0.75 + 0.25 * Math.sin(p.twinklePhase)
      var alpha = p.alpha * tw
      if (alpha <= 0.006) return

      var rgba = function (a) {
        return "rgba(" + col.r + "," + col.g + "," + col.b + "," + a + ")"
      }

      if (p.kind === "cobweb") {
        // Thin arcs + radial spokes anchored at the corner.
        var dirX = (p.corner === 0 || p.corner === 2) ? 1 : -1
        var dirY = (p.corner < 2) ? 1 : -1
        ctx.strokeStyle = rgba(alpha * 0.7)
        ctx.lineWidth = 0.6

        // Spokes
        for (var s = 0; s < 4; s++) {
          var ang = (Math.PI / 2) * (s / 3)
          var ex = px + dirX * Math.cos(ang) * p.size
          var ey = py + dirY * Math.sin(ang) * p.size
          ctx.beginPath()
          ctx.moveTo(px, py)
          ctx.lineTo(ex, ey)
          ctx.stroke()
        }
        // Concentric arcs
        for (var rr = 0.45; rr <= 1.001; rr += 0.28) {
          var r = p.size * rr
          var a0, a1
          if (dirX > 0 && dirY > 0) { a0 = 0; a1 = Math.PI / 2 }
          else if (dirX < 0 && dirY > 0) { a0 = Math.PI / 2; a1 = Math.PI }
          else if (dirX < 0 && dirY < 0) { a0 = Math.PI; a1 = Math.PI * 1.5 }
          else { a0 = Math.PI * 1.5; a1 = Math.PI * 2 }
          ctx.beginPath()
          ctx.arc(px, py, r, a0, a1)
          ctx.stroke()
        }

      } else if (p.kind === "smudge") {
        // Soft radial blob.
        var grad = ctx.createRadialGradient(px, py, 0, px, py, p.size)
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
        // Sharp tiny dot, no halo.
        ctx.fillStyle = rgba(alpha)
        ctx.beginPath()
        ctx.arc(px, py, p.size, 0, Math.PI * 2)
        ctx.fill()

      } else { // mote
        ctx.fillStyle = rgba(alpha)
        ctx.beginPath()
        ctx.arc(px, py, p.size, 0, Math.PI * 2)
        ctx.fill()

        // Halo
        ctx.beginPath()
        ctx.arc(px, py, p.size * 2.2, 0, Math.PI * 2)
        ctx.fillStyle = rgba(alpha * 0.18)
        ctx.fill()
      }
    }

    Timer {
      interval: 33
      running: true
      repeat: true
      onTriggered: canvas.requestPaint()
    }
  }
}
