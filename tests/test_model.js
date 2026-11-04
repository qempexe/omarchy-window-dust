// Run with: node tests/test_model.js
// Loads the .pragma libraries the way the shell does (each file's top level is shared),
// then checks the settings and the dust.
const fs = require("fs"), path = require("path"), assert = require("assert")

function lib(name, imports) {
  const src = fs.readFileSync(path.join(__dirname, "..", "qml", "js", name), "utf8")
    .replace(/^\.pragma library.*$/m, "").replace(/^\.import .*$/mg, "")
  const names = Array.from(src.matchAll(/^(?:var|let|const|function)\s+([A-Za-z_]\w*)/mg), m => m[1])
  const args = Object.keys(imports || {})
  return new Function(...args, src + "\nreturn {" + names.join(",") + "}")(...args.map(a => imports[a]))
}
const Util = lib("Util.js")
const Schema = lib("Schema.js", { Util })
const Model = lib("Model.js")

let n = 0
function ok(what, cond) { assert.ok(cond, what); n++ }
function eq(what, a, b) { assert.deepStrictEqual(a, b, what); n++ }

// ---- settings ----------------------------------------------------------------
const d = Schema.resolve({})
for (const k of Schema.settingKeys) ok("default for " + k, d[k] !== undefined)
for (const g of Schema.groups) for (const it of g.items) {
  if (it.kind === "steps") {
    ok("steps options for " + it.key, Array.isArray(it.options) && it.options.length > 1)
    ok("default in range " + it.key, it.fallback >= it.min && it.fallback <= it.max)
    ok("format " + it.key, Schema.format(it.fmt, it.fallback) !== "?")
  }
  if (it.kind === "enum") ok("enum default " + it.key, it.options.indexOf(it.fallback) !== -1)
}
eq("every preset key is a setting", Schema.presets.every(p => Object.keys(p.set).every(k => Schema.isSetting(k))), true)
eq("presets are valid", Schema.presets.every(p => Object.keys(p.set).every(k => Schema.clean(k, p.set[k]) === p.set[k])), true)
eq("Normal is the default speed", Schema.presetActive(d, Schema.presetFor("normal")), true)

// odd values give the default (or the nearest end) back
eq("bad number", Schema.clean("stages", "lots"), 8)
eq("clamped", Schema.clean("minOpacity", 7), 1)
eq("rounded steps", Schema.clean("spiderMax", 2.6), 3)
eq("enum", Schema.clean("curve", "zigzag"), "smooth")
eq("bool", Schema.clean("particles", "nope"), true)
eq("color with #", Schema.clean("dustColor", "#AABBCC"), "#aabbcc")
eq("1.x color", Schema.clean("dustColor", "8b8378"), "#8b8378")
eq("bad color", Schema.clean("dustColor", "red"), "#8b8378")
eq("tags cleaned", Schema.clean("exempt", [" Firefox ", "firefox", "<b>x</b>", 3, ""]), ["firefox", "bx/b", "3"])
eq("tags not a list", Schema.clean("exempt", "mpv"), ["mpv", "vlc", "spotify"])
eq("icon never empty", Schema.clean("barIcon", "   "), Schema.defaults.barIcon)
eq("text without < >", Schema.clean("barIcon", "<i>"), "i")
eq("unknown key", Schema.clean("__proto__", 1), undefined)
eq("int step", Schema.clean("windowWidth", 571), 580)

// 1.x files keep working
const old = Schema.resolve({ theme: "brown", customBackground: "#112233", dustColor: "55504a", stages: "12" })
eq("brown is custom", old.colorMode, "custom")
eq("custom bg kept", old.customBackground, "#112233")
eq("old color", old.dustColor, "#55504a")
eq("string number", old.stages, 12)
eq("mono", Schema.resolve({ theme: "mono" }).colorMode, "monochrome")
eq("follow", Schema.resolve({ theme: "follow" }).colorMode, "theme")
eq("start never below the floor", Schema.resolve({ startOpacity: 0.2, minOpacity: 0.6 }).startOpacity, 0.6)

// the engine only restarts for engine settings
eq("panel key ignored", Schema.engineKey(d) === Schema.engineKey(Schema.resolve({ cornerRadius: 12, colorMode: "custom" })), true)
eq("engine key seen", Schema.engineKey(d) === Schema.engineKey(Schema.resolve({ stages: 12 })), false)

// steps and words
eq("step up between values", Schema.stepFrom([1, 5, 10], 3, 1), 5)
eq("step down between values", Schema.stepFrom([1, 5, 10], 3, -1), 1)
eq("step at the end", Schema.stepFrom([1, 5, 10], 10, 1), 10)
eq("minutes", Schema.format("minutes", 0.25), "15s")
eq("hours", Schema.format("minutes", 90), "1h 30m")
eq("days", Schema.format("minutes", 2880), "2d")
eq("percent", Schema.format("percent", 0.55), "55%")
eq("short", Schema.format("density", 0.22, true), "0.22")

// ---- the dust -----------------------------------------------------------------
eq("smooth ends", [Model.dustLevel(0, 0, 1, "smooth"), Model.dustLevel(1, 0, 1, "smooth")], [0, 1])
ok("early is ahead", Model.dustLevel(0.3, 0, 1, "early") > Model.dustLevel(0.3, 0, 1, "late"))
ok("grace", Model.dustLevel(50, 60, 100, "linear") === 0)

const cfg = Schema.resolve({ exempt: ["mpv"] })
const clients = [
  { address: "0x1", class: "firefox", at: [0, 0], size: [1000, 800], workspace: { id: 1 }, monitor: 0, floating: false, focusHistoryID: 2 },
  { address: "0x2", class: "mpv", at: [0, 0], size: [500, 400], workspace: { id: 1 }, monitor: 0, floating: false, focusHistoryID: 3 },
  { address: "0x3", class: "calc", at: [200, 100], size: [300, 200], workspace: { id: 1 }, monitor: 0, floating: true, focusHistoryID: 1 },
  { address: "0x4", class: "term", at: [0, 0], size: [800, 600], workspace: { id: 1 }, monitor: 0, floating: false, fullscreen: 2, focusHistoryID: 0 }
]
const clock = 100000
const last = { "0x1": 0, "0x2": 0, "0x3": 0, "0x4": clock }
const e = Model.compute(last, clients, clock, cfg)
const by = {}; for (const x of e) by[x.address] = x
eq("fully dusty", by["0x1"].level, 1)
eq("exempt stays clean", [by["0x2"].level, by["0x2"].exempt], [0, true])
eq("just touched", by["0x4"].level, 0)
eq("fullscreen", by["0x4"].fullscreen, true)
eq("dustiest first", e[0].idleSec >= e[e.length - 1].idleSec, true)
eq("floating exempt", Model.compute(last, clients, clock, Schema.resolve({ exemptFloating: true })).find(x => x.address === "0x3").exempt, true)
eq("paused is clean", Model.compute(last, clients, clock, Schema.resolve({ enabled: false })).every(x => x.level === 0), true)

// windows in front keep their part of the window behind clean
const shown = { "0x1": true, "0x2": true, "0x3": true, "0x4": true }
eq("floating over tiled", Model.occluders(by["0x1"], e, shown).some(r => r[0] === 200 && r[1] === 100 && r[2] === 300 && r[3] === 200), true)
eq("tiled not over floating", Model.occluders(by["0x3"], e, shown).length, 0)
eq("hidden windows don't count", Model.occluders(by["0x1"], e, { "0x1": true }).length, 0)

// shell panels in front keep their part clean too, but not full-screen layers or our own
const mons = { "DP-1": { id: 0, x: 0, y: 0, w: 2000, h: 1000 } }
const tree = { "DP-1": { levels: {
  "0": [{ namespace: "wallpaper", x: 0, y: 0, w: 2000, h: 1000 }],
  "2": [{ namespace: "omarchy-bar", x: 0, y: 0, w: 2000, h: 1000 }, { namespace: "radio", x: 100, y: 50, w: 400, h: 300 }],
  "3": [{ namespace: "window-dust-overlay", x: 0, y: 0, w: 500, h: 500 }, { namespace: "osd", x: 900, y: 900, w: 200, h: 60 }] } },
  "gone": { levels: { "2": [{ namespace: "x", x: 0, y: 0, w: 10, h: 10 }] } } }
const fl = Model.frontLayers(tree, mons, "window-dust-overlay")
eq("front layers", fl.map(l => [l.x, l.y, l.w, l.h]), [[100, 50, 400, 300], [900, 900, 200, 60]])
eq("panel over a window", Model.layerCovers(by["0x1"], fl), [[100, 50, 400, 300]])
eq("bad layers", Model.frontLayers("nope", mons, "x"), [])

// what Hyprland is told
const cmds = Model.commands("0x1", 4, cfg)
ok("fade prop", /set_prop.*opacity_inactive.*address:0x1/.test(cmds[0]))
ok("border tint", /inactive_border_color.*rgba\(8b8378[0-9a-f]{2}\)/.test(cmds[1]))
eq("clean resets", Model.commands("0x1", 0, cfg).length, 2)
ok("addresses are quoted", Model.focusCommand('0x1" })').indexOf('"address:0x1\\" })"') !== -1)

// particles
const want = Model.particleCount(1000, 800, cfg), spiders = Model.spiderCount(1000, 800, cfg)
let set = Model.resizeSet([], want, spiders, 0, 0, 1000, 800, cfg)
eq("count", set.length, want + spiders)
eq("capped", Model.particleCount(4000, 3000, cfg), cfg.particleMax)
for (let i = 0; i < 60; i++) Model.stepParticles(set, 0.033, 0, 0, 1000, 800, 1, cfg)
ok("they stay near the window", set.every(p => p.x > -20 && p.x < 1020 && p.y > -20 && p.y < 820))
ok("they show", set.some(p => p.alpha > 0))
Model.remapParticles(set, 0, 0, 1000, 800, 100, 100, 500, 400)
ok("remapped", set.filter(p => p.kind !== "cobweb").every(p => p.x > 70 && p.x < 640))
Model.scatterParticles(set, 350, 300, 1)
ok("scattered", set.some(p => p.scatterTime > 0))
eq("no effects, no particles", Model.particleCount(1000, 800, Schema.resolve({ effectMotes: false, effectGrain: false, effectSmudges: false, effectStreaks: false, effectCobwebs: false, effectFibers: false })), 0)
eq("powder is the same every time", Model.rand01(Model.hashStr("0x1"), 5, 0), Model.rand01(Model.hashStr("0x1"), 5, 0))

console.log("ALL OK (" + n + ")")
