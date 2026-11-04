import QtQuick
import Quickshell
import Quickshell.Wayland
import "Model.js" as Model

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

  // While a window on this monitor is fullscreen the overlay is hidden altogether (not just
  // blank), so it can't sit on top of the fullscreen window or block direct scanout.
  readonly property bool covered: overlay.hostWidget
    ? overlay.hostWidget.fullscreenMonitors[overlay.hyprMonitorId] === true : false
  visible: !covered

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

  // Dust layer: fine powder, haze and corner build-up. Drawn only when something changes
  // (a window moved, its dust stepped up, a setting changed), not every frame.
  Canvas {
    id: powder
    anchors.fill: parent
    renderStrategy: Canvas.Immediate

    property string sig: ""

    function signature() {
      var host = overlay.hostWidget
      if (!host || overlay.hyprMonitorId < 0 || overlay.covered) return "off"
      var cfg = host.dustConfig
      if (!cfg.particles || !cfg.effectPowder) return "off"
      var parts = [cfg.powderDensity, cfg.dustColor, cfg.particleOpacity, overlay.hyprMonitorId]
      var geom = host.windowGeom, vis = host.visibleAddresses, levels = host.dustLevels
      for (var addr in geom) {
        var g = geom[addr]
        if (vis[addr] !== true || !g || g.monitor !== overlay.hyprMonitorId) continue
        parts.push(addr, g.x, g.y, g.w, g.h, Math.round((levels[addr] || 0) * 100))
      }
      return parts.join("|")
    }
    function check() {
      var s = signature()
      if (s !== sig) { sig = s; requestPaint() }
    }
    Timer { interval: 250; running: true; repeat: true; onTriggered: powder.check() }

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var host = overlay.hostWidget
      if (!host || overlay.hyprMonitorId < 0 || overlay.covered) return
      var cfg = host.dustConfig
      if (!cfg.particles || !cfg.effectPowder) return

      var col = overlay.dustRgb
      var op = cfg.particleOpacity
      var geom = host.windowGeom, vis = host.visibleAddresses, levels = host.dustLevels
      var rgba = function (a) {
        return "rgba(" + col.r + "," + col.g + "," + col.b + "," + a + ")"
      }
      var alphas = [0.35, 0.6, 0.9]
      var sizes = [0.9, 1.3, 1.9]

      for (var addr in geom) {
        if (vis[addr] !== true) continue
        var g = geom[addr]
        if (!g || g.monitor !== overlay.hyprMonitorId) continue
        var level = levels[addr] || 0
        if (level < 0.03) continue

        var wx = g.x - overlay.screenX
        var wy = g.y - overlay.screenY

        ctx.save()
        ctx.beginPath()
        ctx.rect(wx, wy, g.w, g.h)
        ctx.clip()

        // haze: dust settles, so it is thicker toward the bottom
        var haze = ctx.createLinearGradient(0, wy, 0, wy + g.h)
        haze.addColorStop(0, rgba(level * 0.025 * op))
        haze.addColorStop(1, rgba(level * 0.14 * op))
        ctx.fillStyle = haze
        ctx.fillRect(wx, wy, g.w, g.h)

        // and it piles up in the corners
        var cr = Math.min(g.w, g.h) * 0.4
        var corners = [[wx, wy], [wx + g.w, wy], [wx, wy + g.h], [wx + g.w, wy + g.h]]
        for (var c = 0; c < 4; c++) {
          var rg = ctx.createRadialGradient(corners[c][0], corners[c][1], 0, corners[c][0], corners[c][1], cr)
          rg.addColorStop(0, rgba(level * 0.12 * op))
          rg.addColorStop(1, rgba(0))
          ctx.fillStyle = rg
          ctx.fillRect(corners[c][0] - cr, corners[c][1] - cr, cr * 2, cr * 2)
        }

        // powder: three batches (size and brightness), one path and one fill each
        var total = Model.powderCount(g.w, g.h, cfg)
        var n = Math.round(total * level)
        var seed = Model.hashStr(addr)
        var strength = Math.min(1, 0.4 + level * 0.6) * op
        for (var b = 0; b < 3; b++) {
          ctx.fillStyle = rgba(alphas[b] * strength)
          ctx.beginPath()
          for (var i = b; i < n; i += 3) {
            var u = Model.rand01(seed, i, 0)
            var v = 1 - Math.pow(Model.rand01(seed, i, 1), 1.6)    // more toward the bottom
            ctx.rect(wx + u * g.w, wy + v * g.h, sizes[b], sizes[b])
          }
          ctx.fill()
        }
        ctx.restore()
      }
    }
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
          if (set[i].kind === "spider") {
            ctx.globalCompositeOperation = "source-over"
            drawSpider(ctx, set[i], col)
            ctx.globalCompositeOperation = "lighter"
          } else {
            drawParticle(ctx, set[i], col)
          }
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

      } else if (p.kind === "fiber") {
        // a curved strand of lint
        var fdx = Math.cos(p.ang) * p.len / 2
        var fdy = Math.sin(p.ang) * p.len / 2
        ctx.strokeStyle = rgba(alpha * 0.8)
        ctx.lineWidth = 0.7
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.moveTo(px - fdx, py - fdy)
        ctx.quadraticCurveTo(px - Math.sin(p.ang) * p.curve, py + Math.cos(p.ang) * p.curve,
                             px + fdx, py + fdy)
        ctx.stroke()

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

    // A small spider: two body parts, eight jointed legs that step in alternation.
    // Dark with a light rim, so it shows up on both dark and light windows.
    function drawSpider(ctx, p, col) {
      var a = p.alpha
      if (a <= 0.01) return
      var s = p.size
      var light = "rgba(" + col.r + "," + col.g + "," + col.b + "," + (a * 0.55) + ")"
      var dark = "rgba(16,14,12," + a + ")"

      ctx.save()
      ctx.translate(p.x - overlay.screenX, p.y - overlay.screenY)
      ctx.rotate(p.ang)
      ctx.lineCap = "round"
      ctx.lineJoin = "round"

      // legs: four pairs, fanned out, each swinging in its own phase
      var feet = []
      for (var side = -1; side <= 1; side += 2) {
        for (var k = 0; k < 4; k++) {
          var ax = s * (0.55 - k * 0.38)
          var dir = side * (Math.PI / 2 + (k - 1.5) * 0.47)
          var swing = Math.sin(p.legPhase + k * 1.57 + (side > 0 ? 0 : 3.14159)) * 0.38
          var d2 = dir + swing
          var kx = ax + Math.cos(d2) * s * 1.7
          var ky = Math.sin(d2) * s * 1.7
          var fx = kx + Math.cos(d2 + side * 0.7) * s * 2.1
          var fy = ky + Math.sin(d2 + side * 0.7) * s * 2.1
          feet.push([ax, kx, ky, fx, fy])
        }
      }
      for (var pass = 0; pass < 2; pass++) {
        ctx.strokeStyle = pass === 0 ? light : dark
        ctx.lineWidth = pass === 0 ? 2.2 : 1.0
        ctx.beginPath()
        for (var f = 0; f < feet.length; f++) {
          ctx.moveTo(feet[f][0], 0)
          ctx.lineTo(feet[f][1], feet[f][2])
          ctx.lineTo(feet[f][3], feet[f][4])
        }
        ctx.stroke()
      }

      // body: abdomen behind, head and thorax in front, a rim first and the dark fill on top
      for (var bp = 0; bp < 2; bp++) {
        var grow = bp === 0 ? 0.8 : 0
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

    Timer {
      interval: 33
      running: true
      repeat: true
      onTriggered: canvas.requestPaint()
    }
  }
}
