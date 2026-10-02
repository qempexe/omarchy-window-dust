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

  mask: Region {}

  // ---- Monitor identity -------------------------------------------------
  // The Wayland output name from Quickshell ("eDP-1", "HDMI-A-1", …). This is
  // the stable key we match against Hyprland's monitor list.
  readonly property string outputName: overlay.monitor ? overlay.monitor.name : ""

  // The Hyprland monitor record for this overlay, looked up by output name.
  // Gives us id, position, and size from a single authoritative source
  // (hyprctl monitors) instead of mixing Quickshell and Hyprland coordinates.
  readonly property var hyprMonitor: {
    var info = overlay.hostWidget ? overlay.hostWidget.monitorInfoByOutput : ({})
    return info[overlay.outputName] || null
  }

  // Hyprland monitor id, used to filter windows. -1 means "unknown monitor",
  // in which case nothing is drawn — safer than drawing on the wrong screen.
  readonly property int hyprMonitorId: overlay.hyprMonitor ? overlay.hyprMonitor.id : -1

  // Origin of this overlay in Hyprland's global coordinate space.
  readonly property real screenX: overlay.hyprMonitor ? overlay.hyprMonitor.x : 0
  readonly property real screenY: overlay.hyprMonitor ? overlay.hyprMonitor.y : 0

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

      // If we don't know our Hyprland monitor yet (e.g. right after hotplug
      // and before the next monitor poll), draw nothing. This is the safety
      // net against drawing windows that belong to another screen.
      if (overlay.hyprMonitorId < 0) return

      var col = overlay.dustRgb
      var addrs = Object.keys(particleSets)

      for (var a = 0; a < addrs.length; a++) {
        var addr = addrs[a]

        // Must be on the active workspace.
        if (visibleAddresses[addr] !== true) continue

        var g = windowGeom[addr]
        if (!g) continue

        // Must be on *this* overlay's monitor. We filter by Hyprland's
        // monitor id rather than relying on coordinate overlap, so a window
        // on another monitor never contributes particles here.
        if (g.monitor !== overlay.hyprMonitorId) continue

        var set = particleSets[addr]
        if (!set || set.length === 0) continue

        // Local coords for this overlay.
        var wx = g.x - overlay.screenX
        var wy = g.y - overlay.screenY

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
        var dirX = (p.corner === 0 || p.corner === 2) ? 1 : -1
        var dirY = (p.corner < 2) ? 1 : -1
        ctx.strokeStyle = rgba(alpha * 0.7)
        ctx.lineWidth = 0.6

        for (var s = 0; s < 4; s++) {
          var ang = (Math.PI / 2) * (s / 3)
          var ex = px + dirX * Math.cos(ang) * p.size
          var ey = py + dirY * Math.sin(ang) * p.size
          ctx.beginPath()
          ctx.moveTo(px, py)
          ctx.lineTo(ex, ey)
          ctx.stroke()
        }
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

    Timer {
      interval: 33
      running: true
      repeat: true
      onTriggered: canvas.requestPaint()
    }
  }
}
