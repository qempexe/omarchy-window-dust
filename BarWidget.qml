import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Window Dust: windows you have not touched slowly fade and gather dust.
// Click the bar icon for the panel; right-click dusts everything off; middle-click pauses.
BarWidget {
  id: root
  moduleName: "io.github.qempexe.window-dust"

  // ---- Settings ---------------------------------------------------------
  // Kept in memory (instant) and saved to window-dust.json, which is also watched,
  // so a hand edit applies live. Nothing is sent to `omarchy bar set`.
  SettingsStore { id: settingsStore }

  readonly property var dustConfig: Model.normalizeConfig(settingsStore.values)
  readonly property var cfg: dustConfig

  function setValue(key, value) { settingsStore.set(key, value) }
  function setValues(patch) { settingsStore.setMany(patch) }
  function resetAll() { settingsStore.reset() }
  function toggleExempt(cls) { setValue("exempt", Model.toggleExempt(cfg.exempt, cls)) }

  // The engine restarts (particles respawn, Hyprland props are re-applied) only when a
  // setting that affects it changed, never for a theme or bar-icon change.
  property string engineSig: ""
  onDustConfigChanged: {
    var sig = Model.engineKey(dustConfig)
    if (sig === engineSig) return
    engineSig = sig
    if (loaded) applyEngine()
  }
  function applyEngine() {
    applied = ({})
    particleSets = ({})
    recompute()
  }

  // ---- Colours ----------------------------------------------------------
  property string themeAccent: ""             // accent of the active Omarchy theme, or ""
  readonly property var colors: Model.resolveColors(cfg, themeAccent)

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string omarchyConfig: configHome + "/omarchy"

  FileView {
    id: themeColors
    path: root.omarchyConfig + "/current/theme/colors.toml"
    onLoaded: root.themeAccent = Model.parseAccent(text())
    onLoadFailed: root.themeAccent = ""
  }
  // A theme switch is not atomic, so read again shortly after the name changes.
  FileView {
    id: themeNameFile
    path: root.omarchyConfig + "/current/theme.name"
    watchChanges: true
    onFileChanged: { reload(); themeColors.reload(); themeSettle.restart() }
  }
  Timer { id: themeSettle; interval: 600; onTriggered: themeColors.reload() }

  // ---- Dust state -------------------------------------------------------
  property real dustClock: 0
  property real lastTick: Date.now()
  property real lastPersist: 0
  property var lastTouched: ({})
  property var applied: ({})
  property var dustClients: []
  property var dustEntries: []
  property int dustyCount: 0
  property bool loaded: false
  property bool stateLoaded: false

  // ---- Particle layer ---------------------------------------------------
  property var particleSets: ({})
  property var windowGeom: ({})

  // Workspace + multi-monitor awareness
  property var activeWorkspaceByMonitor: ({})
  property var visibleAddresses: ({})
  property var monitorInfoByOutput: ({})   // output name -> Hyprland monitor record
  property var fullscreenMonitors: ({})    // Hyprland monitor id -> true while a window is fullscreen there
  property var dustLevels: ({})            // window address -> dust level 0..1

  readonly property real dustyThreshold: 0.25

  readonly property string signature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
  readonly property string stateFile:
    (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state"))
    + "/omarchy-window-dust/state.json"

  // ---- Panel plumbing ---------------------------------------------------
  // Panel.qml is its own popup window; Foreground.qml only exposes the bar's colours to it.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { openTab("windows") }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function openTab(tab) {
    if (!panelLoader.item) return
    panelLoader.item.currentTab = tab
    // If the compositor dismissed the popup on click-outside, Panel's controller can still
    // think it is showing. Closing first gives a clean "hidden" state before opening.
    if (panelLoader.item.opened) panelLoader.item.close()
    Qt.callLater(function () { if (panelLoader.item) panelLoader.item.open() })
  }

  readonly property bool isVertical: {
    var b = root.bar
    if (!b) return false
    try { return b.vertical === true || b.isVertical === true } catch (e) { return false }
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.widget = root
    panelLoader.item.vertical = root.isVertical
    if (fgProbe.item) fgProbe.item.bar = root.bar
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  // ---- Hyprland dispatch ------------------------------------------------
  function dispatch(luaExpr) { Hyprland.dispatch(luaExpr) }

  // ---- Dust engine ------------------------------------------------------
  function recompute() {
    dustEntries = Model.compute(lastTouched, dustClients, dustClock, dustConfig)
    dustyCount = dustEntries.filter(function (e) { return e.level >= dustyThreshold }).length
    var lv = {}
    for (var q = 0; q < dustEntries.length; q++) lv[dustEntries[q].address] = dustEntries[q].level
    dustLevels = lv

    var next = {}
    for (var i = 0; i < dustEntries.length; i++) {
      var e = dustEntries[i]
      next[e.address] = e.step
      if (applied[e.address] === e.step) continue
      var cmds = Model.commands(e.address, e.step, dustConfig)
      for (var j = 0; j < cmds.length; j++) root.dispatch(cmds[j])
    }
    applied = next

    syncParticles()
    refreshVisibility()
  }

  function onClients(text) {
    var list
    try { list = JSON.parse(text) } catch (err) { return }
    dustClients = list.filter(function (c) { return c.mapped !== false })
    lastTouched = Model.reconcile(lastTouched, dustClients, dustClock)
    recompute()
  }

  function onMonitors(text) {
    var list
    try { list = JSON.parse(text) } catch (err) { return }
    var byId = {}
    var byName = {}
    for (var i = 0; i < list.length; i++) {
      var mon = list[i]
      var ws = (mon.activeWorkspace && typeof mon.activeWorkspace.id === "number")
        ? mon.activeWorkspace.id : -1
      byId[mon.id] = ws
      byName[mon.name] = {
        id: mon.id,
        x: mon.x,
        y: mon.y,
        w: mon.width,
        h: mon.height,
        scale: mon.scale,
        activeWorkspace: ws
      }
    }
    activeWorkspaceByMonitor = byId
    monitorInfoByOutput = byName
    refreshVisibility()
  }

  // A window is drawn on when it is on its monitor's active workspace and that
  // monitor has no fullscreen window (the overlay would sit on top of it).
  function refreshVisibility() {
    var fs = {}
    if (dustConfig.hideOnFullscreen) {
      for (var j = 0; j < dustEntries.length; j++) {
        var f = dustEntries[j]
        if (f.fullscreen && activeWorkspaceByMonitor[f.monitor] === f.workspace) fs[f.monitor] = true
      }
    }
    var v = {}
    for (var i = 0; i < dustEntries.length; i++) {
      var e = dustEntries[i]
      var activeWs = activeWorkspaceByMonitor[e.monitor]
      v[e.address] = (activeWs !== undefined && e.workspace === activeWs && fs[e.monitor] !== true)
    }
    visibleAddresses = v
    if (JSON.stringify(fs) !== JSON.stringify(fullscreenMonitors)) fullscreenMonitors = fs
  }

  function touch(address) {
    var t = Object.assign({}, lastTouched)
    t[address] = dustClock
    lastTouched = t
    recompute()
  }

  function wipeAll() {
    var t = {}
    for (var i = 0; i < dustClients.length; i++) t[dustClients[i].address] = dustClock
    lastTouched = t
    recompute()
  }

  function focusWindow(address) {
    root.dispatch(Model.focusCommand(address))
  }

  function tick() {
    var now = Date.now()
    var dt = Math.min((now - lastTick) / 1000, 90)
    lastTick = now
    var away = dustConfig.pauseWhenAway && idle.isIdle
    if (!away) dustClock += dt
    recompute()
    if (now - lastPersist > 30000) {
      lastPersist = now
      persist()
    }
  }

  // ---- Particle lifecycle ----------------------------------------------
  function syncParticles() {
    var nextSets = {}
    var nextGeom = {}
    for (var i = 0; i < dustEntries.length; i++) {
      var e = dustEntries[i]
      var oldG = windowGeom[e.address]
      var newG = { x: e.x, y: e.y, w: e.w, h: e.h,
                   monitor: e.monitor, workspace: e.workspace }

      var set = particleSets[e.address]
      var wantDust = Model.particleCount(e.w, e.h, dustConfig)
      var wantSpiders = Model.spiderCount(e.w, e.h, dustConfig)

      if (!set) {
        set = Model.resizeSet([], wantDust, wantSpiders, e.x, e.y, e.w, e.h, dustConfig)
      } else {
        // If the window moved or resized since last frame, remap particles
        // proportionally into the new rect before growing/trimming.
        if (oldG && (oldG.x !== e.x || oldG.y !== e.y
                     || oldG.w !== e.w || oldG.h !== e.h)) {
          Model.remapParticles(set, oldG.x, oldG.y, oldG.w, oldG.h,
                               e.x, e.y, e.w, e.h)
        }
        if (set.length !== wantDust + wantSpiders)
          set = Model.resizeSet(set, wantDust, wantSpiders, e.x, e.y, e.w, e.h, dustConfig)
      }
      nextSets[e.address] = set
      nextGeom[e.address] = newG
    }
    particleSets = nextSets
    windowGeom = nextGeom
  }

  function stepAllParticles(dt) {
    var next = {}
    for (var addr in particleSets) {
      var g = windowGeom[addr]
      if (!g) { next[addr] = particleSets[addr]; continue }

      if (visibleAddresses[addr] !== true) {
        next[addr] = particleSets[addr]
        continue
      }

      var level = 0
      for (var i = 0; i < dustEntries.length; i++) {
        if (dustEntries[i].address === addr) { level = dustEntries[i].level; break }
      }

      var set = particleSets[addr]
      Model.stepParticles(set, dt, g.x, g.y, g.w, g.h, level, dustConfig)
      next[addr] = set
    }
    particleSets = next
  }

  function scatterAt(address) {
    if (!dustConfig.scatterOnFocus) return
    var g = windowGeom[address]
    var set = particleSets[address]
    if (!g || !set || set.length === 0) return
    Model.scatterParticles(set, g.x + g.w / 2, g.y + g.h / 2, 1.0)
  }

  // ---- Persistence (dust clock + last-touched times; settings live in SettingsStore) ----
  function persist() {
    if (!loaded || stateWriter.running) return
    stateWriter.command = ["sh", "-c",
      'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", stateFile,
      JSON.stringify({ sig: signature, clock: dustClock, last: lastTouched })]
    stateWriter.running = true
  }

  function onBoot(text) {
    if (stateLoaded) return
    try {
      var s = JSON.parse(text)
      if (s && s.sig === signature && typeof s.clock === "number") {
        dustClock = s.clock
        lastTouched = s.last || {}
      }
    } catch (err) { }
    stateLoaded = true
    maybeStart()
  }

  // Start once both the saved dust state and the saved settings have been read, so the
  // first pass already uses the real settings and nothing flickers.
  function maybeStart() { if (stateLoaded && settingsStore.loaded) start() }

  function start() {
    if (loaded) return
    loaded = true
    engineSig = Model.engineKey(dustConfig)
    lastTick = Date.now()
    clientsProc.running = true
    monitorsProc.running = true
    tickTimer.start()
    particleTimer.start()
    heartbeatTimer.start()
  }

  Connections {
    target: settingsStore
    function onLoadedChanged() { root.maybeStart() }
  }

  Process { id: stateWriter }

  Process {
    id: bootRead
    command: ["sh", "-c", 'cat "$1" 2>/dev/null', "sh", root.stateFile]
    stdout: StdioCollector { onStreamFinished: root.onBoot(text) }
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector { onStreamFinished: root.onClients(text) }
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector { onStreamFinished: root.onMonitors(text) }
  }

  IdleMonitor {
    id: idle
    enabled: root.dustConfig.pauseWhenAway
    timeout: root.dustConfig.awayMinutes * 60
  }

  Timer {
    id: tickTimer
    interval: Model.tickMs(root.dustConfig)
    repeat: true
    onTriggered: root.tick()
  }

  Timer {
    id: particleTimer
    interval: 33
    repeat: true
    running: false
    onTriggered: root.stepAllParticles(0.033)
  }

  // Fast, debounced refresh after any relevant Hyprland event.
  Timer {
    id: refreshTimer
    interval: 200
    onTriggered: {
      if (!clientsProc.running) clientsProc.running = true
      if (!monitorsProc.running) monitorsProc.running = true
    }
  }

  // Fallback poll: catches geometry changes that don't emit an event (e.g.
  // a resize from the bottom or right edge, where the position is unchanged).
  Timer {
    id: heartbeatTimer
    interval: 1500
    running: false
    repeat: true
    onTriggered: {
      if (!clientsProc.running) clientsProc.running = true
      if (!monitorsProc.running) monitorsProc.running = true
    }
  }

  Timer { id: fallbackStart; interval: 2000; onTriggered: root.start() }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var data = String(event.data || "").trim()
      switch (event.name) {
      case "activewindowv2":
        if (data.length > 0) {
          var addr = "0x" + data
          root.scatterAt(addr)
          root.touch(addr)
        }
        break
      case "fullscreen":
        // read the clients straight away so the dust vanishes (or returns) at once
        if (!clientsProc.running) clientsProc.running = true
        refreshTimer.restart()
        break
      case "openwindow":
      case "closewindow":
      case "movewindow":
      case "movewindowv2":
      case "changefloatingmode":
      case "minimize":
        refreshTimer.restart()
        break
      case "workspace":
      case "workspacev2":
      case "focusedmon":
      case "focusedmonv2":
      case "moveworkspace":
      case "moveworkspacev2":
        if (!monitorsProc.running) monitorsProc.running = true
        if (!clientsProc.running) clientsProc.running = true
        break
      case "monitoradded":
      case "monitoraddedv2":
      case "monitorremoved":
        refreshTimer.restart()
        if (!monitorsProc.running) monitorsProc.running = true
        break
      case "configreloaded":
        root.applied = ({})
        root.recompute()
        break
      }
    }
  }

  Component.onCompleted: {
    bootRead.running = true
    fallbackStart.start()
  }

  Component.onDestruction: {
    for (var addr in applied) {
      root.dispatch(Model.setProp("opacity_inactive", 1.0, addr))
      root.dispatch(Model.setProp("inactive_border_color", -1, addr))
    }
  }

  Variants {
    model: Quickshell.screens
    delegate: Overlay {
      required property var modelData
      monitor: modelData
      hostWidget: root
    }
  }

  // Exposes the bar's own colours to the popup (see Foreground.qml).
  Loader {
    id: fgProbe
    active: true
    source: Qt.resolvedUrl("Foreground.qml")
    visible: false
    onLoaded: root.injectPanel()
  }
  Binding { target: panelLoader.item; property: "probeFg"; value: fgProbe.item ? fgProbe.item.barForeground : undefined; when: !!panelLoader.item && !!fgProbe.item }
  Binding { target: panelLoader.item; property: "probeBg"; value: fgProbe.item ? fgProbe.item.barBackground : undefined; when: !!panelLoader.item && !!fgProbe.item }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.cfg.barIcon + (!root.cfg.enabled ? " off"
      : (root.cfg.barShowCount && root.dustyCount > 0 ? " " + root.dustyCount : ""))
    tooltipText: !root.cfg.enabled
      ? "Window Dust is paused (middle-click to resume)"
      : (root.dustyCount === 0 ? "No dusty windows"
        : root.dustyCount + (root.dustyCount === 1 ? " dusty window" : " dusty windows"))
        + "\nLeft click: panel. Middle click: pause. Right click: dust everything off."
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.RightButton) root.wipeAll()
      else if (buttonCode === Qt.MiddleButton) root.setValue("enabled", !root.cfg.enabled)
    }
  }
}
