import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.qempexe.window-dust"

  property var dustConfig: Model.normalizeConfig({})

  property real dustClock: 0
  property real lastTick: Date.now()
  property real lastPersist: 0
  property var lastTouched: ({})
  property var applied: ({})
  property var dustClients: []
  property var dustEntries: []
  property int dustyCount: 0
  property bool loaded: false
  property bool pendingSave: false

  // ---- Particle layer ---------------------------------------------------
  property var particleSets: ({})
  property var windowGeom: ({})

  // Workspace awareness: which windows are actually on screen right now.
  property var activeWorkspaceByMonitor: ({})   // monitor id -> workspace id
  property var visibleAddresses: ({})           // address -> true if visible

  readonly property real dustyThreshold: 0.25

  readonly property string signature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configFile:
    (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/omarchy/window-dust.json"
  readonly property string stateFile:
    (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state"))
    + "/omarchy-window-dust/state.json"

  // ---- Panel plumbing ---------------------------------------------------
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
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
    var m = {}
    for (var i = 0; i < list.length; i++) {
      var mon = list[i]
      m[mon.id] = (mon.activeWorkspace && typeof mon.activeWorkspace.id === "number")
        ? mon.activeWorkspace.id : -1
    }
    activeWorkspaceByMonitor = m
    refreshVisibility()
  }

  // Mark which window addresses are on their monitor's active workspace.
  function refreshVisibility() {
    var v = {}
    for (var i = 0; i < dustEntries.length; i++) {
      var e = dustEntries[i]
      var activeWs = activeWorkspaceByMonitor[e.monitor]
      v[e.address] = (activeWs !== undefined && e.workspace === activeWs)
    }
    visibleAddresses = v
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
      nextGeom[e.address] = { x: e.x, y: e.y, w: e.w, h: e.h,
                              monitor: e.monitor, workspace: e.workspace }

      var set = particleSets[e.address]
      var want = Model.particleCount(e.w, e.h, dustConfig)

      if (!set) {
        set = want > 0
          ? Model.spawnParticles(want, e.x, e.y, e.w, e.h, dustConfig)
          : []
      } else if (set.length !== want) {
        if (want === 0) {
          set = []
        } else if (set.length < want) {
          var more = Model.spawnParticles(want - set.length, e.x, e.y, e.w, e.h, dustConfig)
          set = set.concat(more)
        } else {
          set = set.slice(0, want)
        }
      }
      nextSets[e.address] = set
    }
    particleSets = nextSets
    windowGeom = nextGeom
  }

  function stepAllParticles(dt) {
    var next = {}
    for (var addr in particleSets) {
      var g = windowGeom[addr]
      if (!g) { next[addr] = particleSets[addr]; continue }

      // Skip stepping for windows not on their monitor's active workspace.
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

  // ---- Settings ---------------------------------------------------------
  function applyConfig(cfg) {
    dustConfig = cfg
    applied = ({})
    particleSets = ({})
    recompute()
  }

  function setConfig(patch) {
    applyConfig(Model.normalizeConfig(Object.assign({}, dustConfig, patch)))
    saveConfig()
  }

  function toggleExempt(cls) {
    setConfig({ exempt: Model.toggleExempt(dustConfig.exempt, cls) })
  }

  function saveConfig() {
    if (cfgWriter.running) { pendingSave = true; return }
    pendingSave = false
    cfgWriter.command = ["sh", "-c",
      'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", configFile,
      JSON.stringify(dustConfig, null, 2) + "\n"]
    cfgWriter.running = true
  }

  function reloadConfig() {
    if (!loaded || cfgWriter.running || pendingSave || cfgReader.running) return
    cfgReader.running = true
  }

  function onConfigText(text) {
    if (String(text).trim() === "") return
    var raw
    try { raw = JSON.parse(text) } catch (err) { return }
    var cfg = Model.normalizeConfig(raw)
    if (JSON.stringify(cfg) !== JSON.stringify(dustConfig)) applyConfig(cfg)
  }

  // ---- Persistence ------------------------------------------------------
  function persist() {
    if (!loaded || stateWriter.running) return
    stateWriter.command = ["sh", "-c",
      'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", stateFile,
      JSON.stringify({ sig: signature, clock: dustClock, last: lastTouched })]
    stateWriter.running = true
  }

  readonly property string bootMarker: "\n@@STATE@@\n"

  function onBoot(text) {
    if (loaded) return
    var at = text.indexOf(bootMarker)
    var cfgText = at >= 0 ? text.slice(0, at) : text
    var stateText = at >= 0 ? text.slice(at + bootMarker.length) : ""

    var haveConfigFile = String(cfgText).trim() !== ""
    try { dustConfig = Model.normalizeConfig(JSON.parse(cfgText)) } catch (err) { }

    try {
      var s = JSON.parse(stateText)
      if (s && s.sig === signature && typeof s.clock === "number") {
        dustClock = s.clock
        lastTouched = s.last || {}
      }
    } catch (err2) { }

    start()
    if (!haveConfigFile) saveConfig()
  }

  function start() {
    if (loaded) return
    loaded = true
    lastTick = Date.now()
    clientsProc.running = true
    monitorsProc.running = true
    tickTimer.start()
    particleTimer.start()
  }

  Process { id: stateWriter }
  Process { id: cfgWriter; onExited: { if (root.pendingSave) root.saveConfig() } }

  Process {
    id: cfgReader
    command: ["cat", root.configFile]
    stdout: StdioCollector { onStreamFinished: root.onConfigText(text) }
  }

  Process {
    id: bootRead
    command: ["sh", "-c",
      'cat "$1" 2>/dev/null; printf "\\n@@STATE@@\\n"; cat "$2" 2>/dev/null',
      "sh", root.configFile, root.stateFile]
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

  Timer { id: fallbackStart; interval: 2000; onTriggered: root.start() }

  Timer {
    id: refreshTimer
    interval: 400
    onTriggered: {
      if (!clientsProc.running) clientsProc.running = true
      if (!monitorsProc.running) monitorsProc.running = true
    }
  }

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
      case "openwindow":
      case "closewindow":
      case "movewindowv2":
        refreshTimer.restart()
        break
      case "workspace":
      case "workspacev2":
      case "focusedmon":
      case "moveworkspace":
      case "moveworkspacev2":
        // Active workspace changed — refresh monitors so effects update fast.
        if (!monitorsProc.running) monitorsProc.running = true
        if (!clientsProc.running) clientsProc.running = true
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

  // ---- Overlays ---------------------------------------------------------
  Variants {
    model: Quickshell.screens
    delegate: Overlay {
      required property var modelData
      monitor: modelData
      hostWidget: root
    }
  }

  // ---- UI ---------------------------------------------------------------
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
    text: "\uDB80\uDCE2" + (!root.dustConfig.enabled ? " off"
      : (root.dustyCount > 0 ? " " + root.dustyCount : ""))
    tooltipText: !root.dustConfig.enabled
      ? "Window Dust is paused (middle-click to resume)"
      : (root.dustyCount === 0 ? "No dusty windows"
        : root.dustyCount + (root.dustyCount === 1 ? " dusty window" : " dusty windows"))
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.RightButton) root.wipeAll()
      else if (buttonCode === Qt.MiddleButton) root.setConfig({ enabled: !root.dustConfig.enabled })
    }
  }
}
