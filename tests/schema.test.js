// Run with: node tests/schema.test.js
const fs = require("fs"), path = require("path"), assert = require("assert")
function load(name) {
  const src = fs.readFileSync(path.join(__dirname, "..", name), "utf8").replace(/^\.pragma library.*$/m, "")
  return new Function(src + "\nreturn typeof SCHEMA !== 'undefined' ? {SCHEMA, PALETTE} : {Model: {DEFAULTS, OPTIONS, PRESETS, normalizeConfig, stepOption, presetActive, toggleExempt, addExempt, engineKey, resolveColors, parseAccent, formatSetting, statusText, isHex, THEMES, LOOK_KEYS, compute, spawnParticles, spawnSpiders, spiderCount, resizeSet, stepParticles, scatterParticles, powderCount, hashStr, rand01, particleCount}}")()
}
const { SCHEMA, PALETTE } = load("Settings.js")
const { Model } = load("Model.js")

// 1. every schema default equals Model.DEFAULTS; every stored default key has a row
const keys = new Set()
for (const d of SCHEMA) {
  if (d.virtual) continue
  keys.add(d.key)
  assert.ok(d.key in Model.DEFAULTS, "no Model default for " + d.key)
  assert.deepStrictEqual(d.defaultValue, Model.DEFAULTS[d.key], "default drift: " + d.key)
}
for (const k in Model.DEFAULTS) assert.ok(keys.has(k), "no schema row for " + k)

// 2. steppers have option lists and a known format
for (const d of SCHEMA.filter(d => d.type === "stepper")) {
  assert.ok(Array.isArray(Model.OPTIONS[d.key]) && Model.OPTIONS[d.key].length > 1, "no OPTIONS for " + d.key)
  assert.ok(Model.OPTIONS[d.key].includes(Model.DEFAULTS[d.key]), "default not in OPTIONS: " + d.key)
  assert.ok(Model.formatSetting(d.fmt, Model.DEFAULTS[d.key]).length > 0)
}
// 3. enums: labels line up, default is an option
for (const d of SCHEMA.filter(d => d.type === "enum")) {
  assert.strictEqual(d.options.length, d.labels.length)
  assert.ok(d.options.includes(d.defaultValue))
}
// 4. normalisation clamps and rejects junk
const n = Model.normalizeConfig({ theme: "nope", customAccent: "red", barIcon: "  ", stages: "999", exempt: ["MPV", "mpv", 3] })
assert.strictEqual(n.theme, "follow"); assert.strictEqual(n.customAccent, "#c8905a")
assert.strictEqual(n.barIcon, Model.DEFAULTS.barIcon); assert.strictEqual(n.stages, 32)
assert.deepStrictEqual(n.exempt, ["mpv"])
assert.deepStrictEqual(Model.normalizeConfig({}), Model.normalizeConfig(Model.normalizeConfig({})))
// 5. presets only use keys that exist
for (const p of Model.PRESETS) for (const k in p.values) assert.ok(k in Model.DEFAULTS)
// 6. engine key ignores look-only keys, notices real ones
const a = Model.normalizeConfig({}), b = Model.normalizeConfig({ theme: "mono", barIcon: "X" }), c = Model.normalizeConfig({ stages: 12 })
assert.strictEqual(Model.engineKey(a), Model.engineKey(b)); assert.notStrictEqual(Model.engineKey(a), Model.engineKey(c))
// 7. theme helpers
assert.strictEqual(Model.parseAccent('foreground = "#fff"\naccent = "#7AA2F7"\n'), "#7aa2f7")
assert.strictEqual(Model.parseAccent("nothing"), "")
assert.strictEqual(Model.resolveColors(a, "#112233").accent, "#112233")
// the old "brown" theme becomes Custom, whose defaults are the same brown
const br = Model.normalizeConfig({ theme: "brown" })
assert.strictEqual(br.theme, "custom"); assert.strictEqual(Model.resolveColors(br, "").accent, "#c8905a")
assert.ok(!SCHEMA.find(d => d.key === "theme").options.includes("brown"))
assert.ok(PALETTE.every(Model.isHex))
// 8. exempt helpers
assert.deepStrictEqual(Model.addExempt(["a"], " B "), ["a", "b"]); assert.deepStrictEqual(Model.addExempt(["a"], "A"), ["a"])
assert.strictEqual(Model.statusText(false, 0, 3), "Paused")

// 9. spiders: counted separately from dust, kept inside the window, run when scattered
const cfg = Model.normalizeConfig({})
assert.strictEqual(Model.spiderCount(100, 100, cfg), 0)
assert.ok(Model.spiderCount(1920, 1080, cfg) >= 1 && Model.spiderCount(1920, 1080, cfg) <= cfg.spiderMax)
assert.strictEqual(Model.spiderCount(1920, 1080, Model.normalizeConfig({ effectSpiders: false })), 0)
let set = Model.resizeSet([], 20, 2, 100, 100, 800, 600, cfg)
assert.strictEqual(set.filter(p => p.kind === "spider").length, 2); assert.strictEqual(set.length, 22)
set = Model.resizeSet(set, 5, 1, 100, 100, 800, 600, cfg)
assert.strictEqual(set.length, 6); assert.strictEqual(set.filter(p => p.kind === "spider").length, 1)
const sp = Model.spawnSpiders(3, 100, 100, 800, 600, cfg)
for (let i = 0; i < 3000; i++) Model.stepParticles(sp, 0.033, 100, 100, 800, 600, 1, cfg)
for (const p of sp) { assert.ok(p.x >= 100 && p.x <= 900 && p.y >= 100 && p.y <= 700, "spider left the window"); assert.ok(p.alpha > 0.3) }
const before = sp.map(p => p.legPhase); for (let i = 0; i < 30; i++) Model.stepParticles(sp, 0.033, 100, 100, 800, 600, 1, cfg)
assert.ok(sp.some((p, i) => p.legPhase !== before[i]) || sp.every(p => p.state === "pause"), "no spider moved")
Model.scatterParticles(sp, 500, 400, 1); assert.ok(sp.every(p => p.run > 1))
const young = Model.spawnSpiders(1, 0, 0, 800, 600, cfg); Model.stepParticles(young, 0.033, 0, 0, 800, 600, 0.1, cfg)
assert.strictEqual(young[0].alpha, 0)                       // too clean for spiders
// 10. fibres and the rest of the dust still spawn and step
const dust = Model.spawnParticles(200, 0, 0, 800, 600, Model.normalizeConfig({ effectMotes: false, effectGrain: false, effectSmudges: false, effectStreaks: false, effectCobwebs: false }))
assert.ok(dust.length === 200 && dust.every(p => p.kind === "fiber" && p.len > 0))
for (let i = 0; i < 200; i++) Model.stepParticles(dust, 0.033, 0, 0, 800, 600, 0.8, cfg)
assert.ok(dust.every(p => Number.isFinite(p.x) && Number.isFinite(p.ang)))
// 11. powder: capped, scaled, stable per window, in range
assert.strictEqual(Model.powderCount(1920, 1080, Model.normalizeConfig({ effectPowder: false })), 0)
assert.strictEqual(Model.powderCount(1920, 1080, Model.normalizeConfig({ powderDensity: 30 })), 7000)
assert.ok(Model.powderCount(400, 300, cfg) > 0 && Model.powderCount(400, 300, cfg) < Model.powderCount(1920, 1080, cfg))
const seed = Model.hashStr("0xabc")
for (let i = 0; i < 500; i++) { const r = Model.rand01(seed, i, 0); assert.ok(r >= 0 && r < 1) }
assert.strictEqual(Model.rand01(seed, 7, 1), Model.rand01(seed, 7, 1)); assert.notStrictEqual(Model.hashStr("a"), Model.hashStr("b"))
// 12. compute flags real fullscreen only
const cl = a => ({ address: a.addr, mapped: true, class: "x", title: "t", at: [0, 0], size: [800, 600], workspace: { id: 1 }, monitor: 0, fullscreen: a.fs })
const ent = Model.compute({}, [cl({ addr: "0x1", fs: 2 }), cl({ addr: "0x2", fs: 1 }), cl({ addr: "0x3", fs: 0 }), cl({ addr: "0x4", fs: true })], 0, cfg)
assert.deepStrictEqual(ent.map(e => e.fullscreen), [true, false, false, true])
console.log("schema tests passed")
