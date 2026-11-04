import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "js/Schema.js" as Schema
import "js/Model.js" as Model
import "js/Theme.js" as Theme
import "js/Util.js" as Util
import "core"
import "overlay"

// The always-loaded part: the settings, the dust clock, what Hyprland is told, the
// particles and the overlays. It runs once, however many bars and screens there are;
// every bar button only shows what is here.
Item {
    id: root

    visible: false

    property var shell: null
    property var manifest: null

    readonly property string pluginId: "io.github.qempexe.window-dust"
    readonly property string version: manifest && manifest.version ? String(manifest.version) : "2.0.0"

    // ---- settings ----------------------------------------------------------------------
    SettingsStore { id: settingsStore }
    property alias store: settingsStore
    readonly property var cfg: Schema.resolve(settingsStore.values)

    function setValue(key, value) {
        const v = Schema.clean(key, value)
        if (v !== undefined) settingsStore.set(key, v)
    }
    function resetAll() { settingsStore.resetAll(Schema.defaults) }
    function applyPreset(key) {
        const p = Schema.presetFor(Util.toText(key))
        if (!p) return false
        const set = {}
        for (const k in p.set) set[k] = p.set[k]
        set.enabled = true
        settingsStore.setMany(set)
        return true
    }
    function toggleExempt(cls) {
        const c = Schema.className(cls)
        if (c === "") return
        const list = root.cfg.exempt.slice()
        const i = list.indexOf(c)
        if (i >= 0) list.splice(i, 1)
        else list.push(c)
        root.setValue("exempt", list)
    }

    UiState {
        id: ux
        cfg: root.cfg
        barFg: Color.bar.text
        barBg: Color.bar.background
        themeAccent: Color.accent
        themeUrgent: Color.urgent
        fontName: Style.font.family
        borderColors: root.borderColors
        borderAngle: root.borderAngle
    }
    property alias ui: ux

    // ---- the theme's window border, for the Window borders colors ------------------------
    property var luaBorder: ({ colors: [], angle: 0 })
    property var confBorder: ({ colors: [], angle: 0 })
    property bool luaMissing: false
    readonly property var borderColors: luaBorder.colors.length > 0 ? luaBorder.colors : confBorder.colors
    readonly property real borderAngle: luaBorder.colors.length > 0 ? luaBorder.angle : confBorder.angle
    readonly property string themeDir: {
        try { return Color.currentThemePath ? String(Color.currentThemePath) : "" } catch (e) { return "" }
    }
    function fileText(fv) {
        try { const t = typeof fv.text === "function" ? fv.text() : fv.text; return typeof t === "string" ? t : "" } catch (e) { return "" }
    }
    FileView {
        id: borderLua
        path: root.themeDir !== "" ? root.themeDir + "/hyprland.lua" : ""
        watchChanges: true
        printErrors: false                  // a theme switch removes it for a moment
        onFileChanged: reload()
        onLoaded: { root.luaMissing = false; root.luaBorder = Theme.parseBorder(root.fileText(borderLua)) }
        onLoadFailed: { root.luaBorder = ({ colors: [], angle: 0 }); root.luaMissing = true; root.retryTheme() }
    }
    FileView {
        id: borderConf
        path: root.themeDir !== "" && root.luaMissing ? root.themeDir + "/hyprland.conf" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onPathChanged: if (path === "") root.confBorder = ({ colors: [], angle: 0 })
        onLoaded: root.confBorder = Theme.parseBorder(root.fileText(borderConf))
        onLoadFailed: root.confBorder = ({ colors: [], angle: 0 })
    }
    property int themeTries: 0
    function retryTheme() { if (root.themeTries < 3) { root.themeTries++; themeRetry.restart() } }
    Timer { id: themeRetry; interval: 800; onTriggered: { borderLua.reload(); borderConf.reload() } }
    Connections {
        target: Color
        ignoreUnknownSignals: true
        function onAccentChanged() { root.themeTries = 0; themeRetry.restart() }
    }

    // ---- the dust ----------------------------------------------------------------------
    property real dustClock: 0                  // seconds you've been at the machine
    property double lastTick: Date.now()
    property double lastPersist: 0
    property var lastTouched: ({})              // address -> dustClock when last focused
    property var applied: ({})                  // address -> the stage Hyprland was last told
    property var clients: []
    property var entries: []                    // Model.compute(), the dustiest first
    property var byAddress: ({})                // address -> entry
    property var shown: ({})                    // address -> on screen now (its workspace, no fullscreen)
    property var fullscreenMonitors: ({})       // Hyprland monitor id -> true
    property var monitors: ({})                 // output name -> { id, x, y, w, h }
    property var activeWorkspace: ({})          // Hyprland monitor id -> workspace id
    property int dustyCount: 0
    property bool started: false
    property bool stateLoaded: false
    readonly property real dustyThreshold: 0.25

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string signature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (root.home + "/.local/state")) + "/omarchy-window-dust"

    // the engine starts over (particles respawn, the windows are told again) only when a
    // setting that matters to it changed, never for a panel or button setting
    property string engineSig: ""
    onCfgChanged: {
        const sig = Schema.engineKey(root.cfg)
        if (sig === root.engineSig) return
        root.engineSig = sig
        if (!root.started) return
        root.applied = ({})
        root.sets = ({})
        root.recompute()
    }

    function recompute() {
        const list = Model.compute(root.lastTouched, root.clients, root.dustClock, root.cfg)
        const by = {}
        let dusty = 0
        for (let i = 0; i < list.length; i++) {
            by[list[i].address] = list[i]
            if (list[i].level >= root.dustyThreshold) dusty++
        }
        root.entries = list
        root.byAddress = by
        root.dustyCount = dusty

        // Hyprland hears about a window only when it moves to another stage
        const next = {}
        for (let j = 0; j < list.length; j++) {
            const e = list[j]
            next[e.address] = e.step
            if (root.applied[e.address] === e.step) continue
            const cmds = Model.commands(e.address, e.step, root.cfg)
            for (let k = 0; k < cmds.length; k++) Hyprland.dispatch(cmds[k])
        }
        root.applied = next
        root.refreshShown()
        root.syncSets()
    }

    // A window is drawn on while it is on its monitor's active workspace and that
    // monitor has no fullscreen window (the overlay would sit over it).
    function refreshShown() {
        const fs = {}
        if (root.cfg.hideOnFullscreen) {
            for (let i = 0; i < root.entries.length; i++) {
                const f = root.entries[i]
                if (f.fullscreen && root.activeWorkspace[f.monitor] === f.workspace) fs[f.monitor] = true
            }
        }
        const now = Date.now()
        const v = {}
        for (let j = 0; j < root.entries.length; j++) {
            const e = root.entries[j]
            const ws = root.activeWorkspace[e.monitor]
            const sliding = (root.settling[e.monitor] || root.settling.all || 0) > now
            v[e.address] = ws !== undefined && (e.workspace === ws || e.pinned) && fs[e.monitor] !== true && !sliding
        }
        root.shown = v
        if (JSON.stringify(fs) !== JSON.stringify(root.fullscreenMonitors)) root.fullscreenMonitors = fs
        root.layoutRev++
    }

    function onClients(text) {
        let list
        try { list = JSON.parse(text) } catch (err) { return }
        if (!Array.isArray(list)) return
        root.clients = list.filter(c => c && typeof c.address === "string" && c.mapped !== false && c.hidden !== true)
        root.lastTouched = Model.reconcile(root.lastTouched, root.clients, root.dustClock)
        root.recompute()
    }

    // While a workspace slides in or out, the windows move without Hyprland saying where,
    // so their dust is hidden on that screen until the windows have arrived.
    property var settling: ({})                 // monitor id (or "all") -> time the slide ends
    property int focusedMonitor: -1
    readonly property int slideMs: 450
    function settle(monitor) {
        const next = {}
        for (const k in root.settling) next[k] = root.settling[k]
        next[monitor >= 0 ? monitor : "all"] = Date.now() + root.slideMs
        root.settling = next
        root.refreshShown()
        settleTimer.restart()
    }
    Timer {
        id: settleTimer
        interval: root.slideMs + 30
        onTriggered: { root.settling = ({}); root.poll() }
    }

    // Shell panels and popups (layers) in front of the windows: their rectangles are
    // kept clear of dust too, all but ones as big as their screen (those are
    // click-through layers like this one, or a bar that spans the screen).
    property var layers: []
    function onLayers(text) {
        let tree
        try { tree = JSON.parse(text) } catch (err) { return }
        const list = Model.frontLayers(tree, root.monitors, "window-dust-overlay")
        if (JSON.stringify(list) !== JSON.stringify(root.layers)) { root.layers = list; root.layoutRev++ }
    }

    function onMonitors(text) {
        let list
        try { list = JSON.parse(text) } catch (err) { return }
        if (!Array.isArray(list)) return
        const ws = {}, byName = {}
        for (let i = 0; i < list.length; i++) {
            const m = list[i]
            const id = m.activeWorkspace && typeof m.activeWorkspace.id === "number" ? m.activeWorkspace.id : -1
            ws[m.id] = id
            if (m.focused === true) root.focusedMonitor = m.id
            byName[m.name] = { id: m.id, x: m.x, y: m.y, w: m.width, h: m.height }
        }
        root.activeWorkspace = ws
        if (JSON.stringify(byName) !== JSON.stringify(root.monitors)) root.monitors = byName
        root.refreshShown()
    }

    function touch(address) {
        const t = Object.assign({}, root.lastTouched)
        t[address] = root.dustClock
        root.lastTouched = t
        root.recompute()
    }
    // every window clean
    function cleanAll() {
        const t = {}
        for (let i = 0; i < root.clients.length; i++) {
            t[root.clients[i].address] = root.dustClock
            root.scatter(root.clients[i].address)
        }
        root.lastTouched = t
        root.recompute()
    }
    function cleanWindow(address) {
        root.scatter(address)
        root.touch(address)
    }
    // as if the window had been left alone the whole time: fully dusty at once
    function dustWindow(address) {
        if (!root.byAddress[address]) return
        const t = Object.assign({}, root.lastTouched)
        t[address] = root.dustClock - (root.cfg.dustAfterMinutes + root.cfg.settleMinutes) * 60 - 1
        root.lastTouched = t
        root.recompute()
    }
    function focusWindow(address) {
        Hyprland.dispatch(Model.focusCommand(address))
    }
    function setEnabled(on) { root.setValue("enabled", on === true) }

    function tick() {
        const now = Date.now()
        const dt = Math.min((now - root.lastTick) / 1000, 90)
        root.lastTick = now
        const away = root.cfg.pauseWhenAway && root.idle !== null && root.idle.isIdle === true
        if (!away && root.cfg.enabled) root.dustClock += dt
        root.recompute()
        if (now - root.lastPersist > 30000) { root.lastPersist = now; root.persist() }
    }

    // ---- particles ---------------------------------------------------------------------
    // One set per dusty window, made the first time it gets dusty and kept while its
    // workspace is hidden, so the dust is where it was when you come back. `sets` is
    // changed in place every frame; `frame` tells the overlays to draw again, and
    // `layoutRev` that the windows, their dust or what is on screen changed.
    property var sets: ({})                    // address -> { list, level (as drawn), geom }
    property int frame: 0
    property int layoutRev: 0
    property bool moving: false                 // some dust on screen is being animated

    function syncSets() {
        const next = {}
        const cfg = root.cfg
        for (let i = 0; i < root.entries.length; i++) {
            const e = root.entries[i]
            let s = root.sets[e.address]
            if (!s) {
                if (e.level <= 0 || !cfg.particles) continue
                s = { list: [], level: 0, geom: null }
            }
            const old = s.geom
            if (old && (old.x !== e.x || old.y !== e.y || old.w !== e.w || old.h !== e.h))
                Model.remapParticles(s.list, old.x, old.y, old.w, old.h, e.x, e.y, e.w, e.h)
            s.geom = { x: e.x, y: e.y, w: e.w, h: e.h }
            const want = Model.particleCount(e.w, e.h, cfg)
            const spiders = Model.spiderCount(e.w, e.h, cfg)
            if (s.list.length !== want + spiders) s.list = Model.resizeSet(s.list, want, spiders, e.x, e.y, e.w, e.h, cfg)
            next[e.address] = s
        }
        root.sets = next
        root.updateMoving()
    }

    function updateMoving() {
        let any = false
        if (root.cfg.particles) {
            for (const a in root.sets) {
                if (root.shown[a] !== true) continue
                const e = root.byAddress[a]
                if ((e && e.level > 0) || root.sets[a].level > 0.003) { any = true; break }
            }
        }
        root.moving = any
    }

    function stepAll(dt) {
        const cfg = root.cfg
        let alive = false, finished = false
        for (const a in root.sets) {
            if (root.shown[a] !== true) continue
            const s = root.sets[a]
            const e = root.byAddress[a]
            if (!e || !s.geom) continue
            // the dust as drawn eases toward the real level, so a cleaned window's dust
            // can still be seen flying off
            const target = e.level
            const rate = target < s.level ? 1.6 : 0.8
            s.level += (target - s.level) * Math.min(1, dt * rate)
            if (Math.abs(target - s.level) < 0.002) s.level = target
            if (s.level <= 0.003 && target <= 0) { s.level = 0; finished = true; continue }
            Model.stepParticles(s.list, dt, s.geom.x, s.geom.y, s.geom.w, s.geom.h, s.level, cfg)
            alive = true
        }
        root.frame++
        // a wiped window's dust has gone: it needs no canvas any more
        if (finished) root.layoutRev++
        if (!alive) root.updateMoving()
    }

    function scatter(address) {
        if (!root.cfg.scatterOnFocus) return
        const s = root.sets[address]
        if (!s || !s.geom || s.list.length === 0) return
        Model.scatterParticles(s.list, s.geom.x + s.geom.w / 2, s.geom.y + s.geom.h / 2, 1.0)
    }

    // the time that really passed, so a late frame doesn't slow the dust down
    property double lastFrame: 0
    Timer {
        id: frameTimer
        interval: Math.round(1000 / Math.max(10, root.cfg.fps))
        repeat: true
        running: root.started && root.moving
        onRunningChanged: root.lastFrame = Date.now()
        onTriggered: {
            const now = Date.now()
            const dt = Math.min(0.25, Math.max(0.001, (now - root.lastFrame) / 1000))
            root.lastFrame = now
            root.stepAll(dt)
        }
    }

    // ---- reading Hyprland --------------------------------------------------------------
    function poll() {
        if (!clientsProc.running) clientsProc.running = true
        if (!monitorsProc.running) monitorsProc.running = true
        if (!layersProc.running && root.cfg.particles) layersProc.running = true
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
    Process {
        id: layersProc
        command: ["hyprctl", "-j", "layers"]
        stdout: StdioCollector { onStreamFinished: root.onLayers(text) }
    }
    // a burst of events is read once
    Timer { id: refreshSoon; interval: 150; onTriggered: root.poll() }
    // A resize from the bottom or right edge sends no event, so the windows are read
    // now and then: often while dust is moving on screen, rarely otherwise.
    Timer {
        interval: root.moving ? 1500 : 10000
        repeat: true
        running: root.started
        onTriggered: root.poll()
    }
    Timer {
        id: tickTimer
        interval: Model.tickMs(root.cfg)
        repeat: true
        running: root.started
        onTriggered: root.tick()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const data = Util.toText(event.data).trim()
            switch (event.name) {
            case "activewindowv2":
                if (/^[0-9a-fA-F]{1,16}$/.test(data)) {
                    const addr = "0x" + data
                    root.scatter(addr)
                    root.touch(addr)
                }
                break
            case "fullscreen":
                root.poll()
                break
            case "openwindow": case "closewindow": case "movewindow": case "movewindowv2":
            case "changefloatingmode": case "minimized": case "pin":
            case "monitoradded": case "monitoraddedv2": case "monitorremoved": case "monitorremovedv2":
            case "openlayer": case "closelayer":
                refreshSoon.restart()
                break
            case "focusedmonv2": {
                // "monitor name,workspace id": the next workspace event is about this one
                const mon = root.monitors[data.split(",")[0]]
                if (mon) root.focusedMonitor = mon.id
                root.poll()
                break
            }
            case "workspacev2":
                root.settle(root.focusedMonitor)
                root.poll()
                break
            case "moveworkspacev2": case "activespecialv2":
                root.settle(-1)
                root.poll()
                break
            case "workspace": case "focusedmon": case "moveworkspace":
                root.poll()
                break
            case "configreloaded":
                // a reload drops the props Hyprland was given, so give them again
                root.applied = ({})
                root.recompute()
                break
            }
        }
    }

    // away = idle for a while, made at runtime so a shell without it still works
    property var idle: null
    function makeIdle() {
        try {
            root.idle = Qt.createQmlObject('import Quickshell.Wayland\nIdleMonitor { }', root, "WindowDustIdle")
            root.idle.enabled = Qt.binding(() => root.cfg.pauseWhenAway)
            root.idle.timeout = Qt.binding(() => root.cfg.awayMinutes * 60)
        } catch (e) { root.idle = null }
    }

    // ---- the dust clock, kept across restarts ----------------------------------------
    // only for the same Hyprland session: a new login starts clean
    function persist() {
        if (!root.started || !root.stateLoaded) return
        stateFile.setText(JSON.stringify({ sig: root.signature, clock: root.dustClock, last: root.lastTouched }))
    }
    FileView {
        id: stateFile
        path: root.stateDir + "/state.json"
        printErrors: false
        onLoaded: root.absorbState(root.fileText(stateFile))
        onLoadFailed: root.absorbState("")
    }
    function absorbState(text) {
        if (root.stateLoaded) return
        try {
            const s = JSON.parse(text)
            if (s && s.sig === root.signature && typeof s.clock === "number" && isFinite(s.clock) && s.last && typeof s.last === "object") {
                const last = {}
                for (const k in s.last) if (/^0x[0-9a-fA-F]{1,16}$/.test(k) && typeof s.last[k] === "number") last[k] = s.last[k]
                root.dustClock = s.clock
                root.lastTouched = last
            }
        } catch (err) { }
        root.stateLoaded = true
        root.maybeStart()
    }
    Process {
        id: mkState
        command: ["sh", "-c", 'umask 077; mkdir -p "$1"', "sh", root.stateDir]
        onExited: stateFile.reload()
    }

    // Start once the saved dust and the saved settings are both read, so the first pass
    // already uses the real settings and nothing flickers.
    function maybeStart() {
        if (root.started || !root.stateLoaded || !settingsStore.loaded) return
        root.started = true
        root.engineSig = Schema.engineKey(root.cfg)
        root.lastTick = Date.now()
        root.makeIdle()
        root.poll()
    }
    Connections {
        target: settingsStore
        function onLoadedChanged() { root.maybeStart() }
    }
    Timer { interval: 3000; running: !root.started; onTriggered: { root.stateLoaded = true; root.maybeStart() } }

    Component.onCompleted: mkState.running = true
    Component.onDestruction: {
        root.persist()
        for (const addr in root.applied) {
            if (root.applied[addr] <= 0) continue
            const cmds = Model.commands(addr, 0, root.cfg)
            for (let i = 0; i < cmds.length; i++) Hyprland.dispatch(cmds[i])
        }
    }

    // one click-through layer per screen
    Variants {
        model: Quickshell.screens
        delegate: Overlay {
            required property var modelData
            screen: modelData
            svc: root
        }
    }

    // ---- ipc: omarchy-shell io.github.qempexe.window-dust <function> ----------------------
    IpcHandler {
        target: root.pluginId

        function settings(): string { root.ui.tabRequested("settings", true); return "ok" }
        function windows(): string { root.ui.tabRequested("windows", true); return "ok" }
        function clean(): string { root.cleanAll(); return "clean" }
        function pause(): string { root.setEnabled(false); return "paused" }
        function resume(): string { root.setEnabled(true); return "on" }
        function toggle(): string { root.setEnabled(!root.cfg.enabled); return root.cfg.enabled ? "on" : "paused" }
        function preset(name: string): string { return root.applyPreset(name) ? name : "unknown, try: gentle normal dramatic demo" }
        function status(): string {
            const list = []
            for (let i = 0; i < root.entries.length; i++) {
                const e = root.entries[i]
                list.push({ address: e.address, class: e.cls, level: Math.round(e.level * 100) / 100, idle: Math.round(e.idleSec), exempt: e.exempt })
            }
            return JSON.stringify({ enabled: root.cfg.enabled, dusty: root.dustyCount, windows: list })
        }
    }
}
