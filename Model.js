.pragma library

// Pure logic for Window Dust. No QML, no I/O, so it can be tested with node.

function clamp(x, lo, hi) { return Math.min(hi, Math.max(lo, x)); }
function lerp(a, b, t) { return a + (b - a) * t; }
function randRange(lo, hi) { return lo + Math.random() * (hi - lo); }

function hex2(n) {
  var s = Math.round(clamp(n, 0, 255)).toString(16);
  return s.length < 2 ? "0" + s : s;
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

var DEFAULTS = {
  enabled: true,
  dustAfterMinutes: 20,
  settleMinutes: 180,
  startOpacity: 0.95,
  minOpacity: 0.55,
  stages: 8,
  curve: "smooth",
  tintBorder: true,
  dustColor: "8b8378",
  pauseWhenAway: true,
  awayMinutes: 5,
  exempt: ["mpv", "vlc", "spotify"],

  particles: true,
  particleDensity: 0.22,
  particleMax: 240,
  particleSizeMin: 0.8,
  particleSizeMax: 2.6,
  particleDrift: 4,
  particleOpacity: 0.75,
  particleTwinkle: true,
  scatterOnFocus: true,

  effectMotes: true,
  effectGrain: true,
  effectSmudges: true,
  effectStreaks: true,
  effectCobwebs: true,

  theme: "follow",
  customBackground: "#1c1210",
  customText: "#e9dcc8",
  customAccent: "#c8905a",
  barIcon: "\uDB80\uDCE2",
  barShowCount: true,

  hideOnFullscreen: true,
  effectPowder: true,
  effectSpiders: true,
  effectFibers: true,
  powderDensity: 8,
  spiderMax: 2
};

var THEMES = ["follow", "custom", "mono"];

// Keys that only change how the panel and bar look. A change to one of them
// never needs the dust engine (particles, Hyprland props) to restart.
var LOOK_KEYS = ["theme", "customBackground", "customText", "customAccent", "barIcon", "barShowCount"];

var OPTIONS = {
  dustAfterMinutes: [0.25, 1, 5, 10, 20, 30, 45, 60, 90, 120, 180, 240, 480, 720],
  settleMinutes: [1.5, 5, 15, 30, 60, 120, 180, 360, 720, 1440],
  minOpacity: [0.2, 0.3, 0.4, 0.5, 0.55, 0.6, 0.7, 0.8, 0.9],
  stages: [4, 6, 8, 12, 16, 24],
  awayMinutes: [1, 2, 5, 10, 15, 30],
  particleDensity: [0.1, 0.15, 0.22, 0.35, 0.5, 0.75, 1.0],
  particleMax: [80, 140, 200, 240, 360, 500],
  particleSizeMax: [1.5, 2.0, 2.6, 3.5, 5.0],
  particleDrift: [1, 2, 4, 7, 12, 20],
  particleOpacity: [0.4, 0.55, 0.75, 0.9, 1.0],
  powderDensity: [2, 4, 8, 12, 20, 30],
  spiderMax: [1, 2, 3, 5, 8]
};

var CURVES = [
  { id: "smooth", label: "Smooth" },
  { id: "linear", label: "Linear" },
  { id: "early", label: "Early" },
  { id: "late", label: "Late" }
];

var COLORS = [
  { id: "8b8378", label: "Dust" },
  { id: "b5a07a", label: "Sand" },
  { id: "7d8590", label: "Ash" },
  { id: "55504a", label: "Soot" },
  { id: "e8dcc0", label: "Mote" }
];

var PRESETS = [
  { id: "gentle", label: "Gentle",
    values: { dustAfterMinutes: 60, settleMinutes: 720, minOpacity: 0.7, stages: 8, curve: "smooth",
              particleDensity: 0.15, particleOpacity: 0.55, powderDensity: 4, spiderMax: 1 } },
  { id: "normal", label: "Normal",
    values: { dustAfterMinutes: 20, settleMinutes: 180, minOpacity: 0.55, stages: 8, curve: "smooth",
              particleDensity: 0.22, particleOpacity: 0.75, powderDensity: 8, spiderMax: 2 } },
  { id: "dramatic", label: "Dramatic",
    values: { dustAfterMinutes: 10, settleMinutes: 60, minOpacity: 0.35, stages: 12, curve: "early",
              particleDensity: 0.5, particleOpacity: 0.9, powderDensity: 20, spiderMax: 3 } },
  { id: "demo", label: "Demo (2 min)",
    values: { dustAfterMinutes: 0.25, settleMinutes: 1.5, minOpacity: 0.4, stages: 12, curve: "linear",
              particleDensity: 0.4, particleOpacity: 0.85, powderDensity: 14, spiderMax: 3 } }
];

function num(v, lo, hi, d) {
  if (typeof v === "string" && v.trim() !== "") v = Number(v);
  if (typeof v !== "number" || !isFinite(v)) return d;
  return clamp(v, lo, hi);
}
function bool(v, d) { return typeof v === "boolean" ? v : d; }

function normalizeExempt(v, d) {
  if (!Array.isArray(v)) return d.slice();
  var out = [];
  for (var i = 0; i < v.length && out.length < 64; i++) {
    if (typeof v[i] !== "string") continue;
    var s = v[i].trim().toLowerCase();
    if (s !== "" && out.indexOf(s) < 0) out.push(s);
  }
  return out;
}

function normalizeConfig(raw) {
  var r = (raw && typeof raw === "object" && !Array.isArray(raw)) ? raw : {};
  var d = DEFAULTS;
  var out = {};
  out.enabled = bool(r.enabled, d.enabled);
  out.dustAfterMinutes = num(r.dustAfterMinutes, 0.05, 7 * 24 * 60, d.dustAfterMinutes);
  out.settleMinutes = num(r.settleMinutes, 0.25, 7 * 24 * 60, d.settleMinutes);
  out.minOpacity = num(r.minOpacity, 0.1, 1, d.minOpacity);
  out.startOpacity = Math.max(num(r.startOpacity, 0.1, 1, d.startOpacity), out.minOpacity);
  out.stages = Math.round(num(r.stages, 2, 32, d.stages));
  var curveOk = false;
  for (var i = 0; i < CURVES.length; i++) if (CURVES[i].id === r.curve) curveOk = true;
  out.curve = curveOk ? r.curve : d.curve;
  out.tintBorder = bool(r.tintBorder, d.tintBorder);
  out.dustColor = (typeof r.dustColor === "string" && /^[0-9a-fA-F]{6}$/.test(r.dustColor))
    ? r.dustColor.toLowerCase() : d.dustColor;
  out.pauseWhenAway = bool(r.pauseWhenAway, d.pauseWhenAway);
  out.awayMinutes = num(r.awayMinutes, 1, 240, d.awayMinutes);
  out.exempt = normalizeExempt(r.exempt, d.exempt);

  out.particles = bool(r.particles, d.particles);
  out.particleDensity = num(r.particleDensity, 0.01, 3, d.particleDensity);
  out.particleMax = Math.round(num(r.particleMax, 20, 1500, d.particleMax));
  out.particleSizeMin = num(r.particleSizeMin, 0.3, 6, d.particleSizeMin);
  out.particleSizeMax = Math.max(num(r.particleSizeMax, 0.5, 12, d.particleSizeMax),
                                 out.particleSizeMin);
  out.particleDrift = num(r.particleDrift, 0, 60, d.particleDrift);
  out.particleOpacity = num(r.particleOpacity, 0.05, 1, d.particleOpacity);
  out.particleTwinkle = bool(r.particleTwinkle, d.particleTwinkle);
  out.scatterOnFocus = bool(r.scatterOnFocus, d.scatterOnFocus);

  out.effectMotes = bool(r.effectMotes, d.effectMotes);
  out.effectGrain = bool(r.effectGrain, d.effectGrain);
  out.effectSmudges = bool(r.effectSmudges, d.effectSmudges);
  out.effectStreaks = bool(r.effectStreaks, d.effectStreaks);
  out.effectCobwebs = bool(r.effectCobwebs, d.effectCobwebs);

  // "brown" used to be its own choice; Custom now starts from the same brown colours.
  var themeIn = r.theme === "brown" ? "custom" : r.theme;
  out.theme = THEMES.indexOf(themeIn) >= 0 ? themeIn : d.theme;
  out.customBackground = hexOr(r.customBackground, d.customBackground);
  out.customText = hexOr(r.customText, d.customText);
  out.customAccent = hexOr(r.customAccent, d.customAccent);
  out.barIcon = (typeof r.barIcon === "string" && r.barIcon.trim() !== "")
    ? r.barIcon.trim().slice(0, 8) : d.barIcon;
  out.barShowCount = bool(r.barShowCount, d.barShowCount);

  out.hideOnFullscreen = bool(r.hideOnFullscreen, d.hideOnFullscreen);
  out.effectPowder = bool(r.effectPowder, d.effectPowder);
  out.effectSpiders = bool(r.effectSpiders, d.effectSpiders);
  out.effectFibers = bool(r.effectFibers, d.effectFibers);
  out.powderDensity = num(r.powderDensity, 0.5, 60, d.powderDensity);
  out.spiderMax = Math.round(num(r.spiderMax, 1, 12, d.spiderMax));
  return out;
}

function isHex(s) { return typeof s === "string" && /^#[0-9a-fA-F]{6}$/.test(s); }
function hexOr(v, d) { return isHex(v) ? v.toLowerCase() : d; }

// The accent colour of the active Omarchy theme (colors.toml), or "".
function parseAccent(text) {
  var m = /^\s*accent\s*=\s*["']?(#[0-9a-fA-F]{6})/m.exec(String(text || ""));
  return m ? m[1].toLowerCase() : "";
}

// Panel colours when the shell's own bar colours are not used (Custom, Brown,
// Monochrome, or Follow before the bar colours are known).
function resolveColors(cfg, accent) {
  switch (cfg.theme) {
  case "custom":
    return { background: cfg.customBackground, text: cfg.customText, accent: cfg.customAccent };
  case "mono":
    return { background: "#141414", text: "#e0e0e0", accent: "#aaaaaa" };
  default:
    return { background: "#141414", text: "#e0e0e0", accent: isHex(accent) ? accent : "#aaaaaa" };
  }
}

// Settings that matter to the dust engine, as a string, to tell real engine
// changes from look-only ones.
function engineKey(cfg) {
  var o = {};
  for (var k in cfg) if (LOOK_KEYS.indexOf(k) < 0) o[k] = cfg[k];
  return JSON.stringify(o);
}

function addExempt(exempt, cls) {
  var c = String(cls || "").trim().toLowerCase();
  if (c === "" || exempt.indexOf(c) >= 0) return exempt.slice();
  return exempt.concat([c]);
}

function stepOption(list, value, dir) {
  var best = 0;
  for (var i = 1; i < list.length; i++)
    if (Math.abs(list[i] - value) < Math.abs(list[best] - value)) best = i;
  return list[clamp(best + dir, 0, list.length - 1)];
}

function presetActive(cfg, preset) {
  for (var k in preset.values)
    if (cfg[k] !== preset.values[k]) return false;
  return true;
}

function toggleExempt(exempt, cls) {
  var c = String(cls || "").trim().toLowerCase();
  if (c === "") return exempt.slice();
  var i = exempt.indexOf(c);
  if (i >= 0) return exempt.filter(function (x) { return x !== c; });
  return exempt.concat([c]);
}

// ---------------------------------------------------------------------------
// Dust maths
// ---------------------------------------------------------------------------

function dustLevel(idleSec, graceSec, rampSec, curve) {
  var t = clamp((idleSec - graceSec) / rampSec, 0, 1);
  switch (curve) {
  case "linear": return t;
  case "early": return 1 - (1 - t) * (1 - t);
  case "late": return t * t;
  default: return t * t * (3 - 2 * t);
  }
}

function toStep(level, stages) { return Math.round(level * stages); }

function effects(step, cfg) {
  var level = step / cfg.stages;
  var alpha = Math.round(lerp(cfg.startOpacity, cfg.minOpacity, level) * 1000) / 1000;
  var borderAlpha = lerp(0.35, 0.95, level);
  return {
    alpha: alpha,
    border: "rgba(" + cfg.dustColor + hex2(borderAlpha * 255) + ")"
  };
}

// ---------------------------------------------------------------------------
// Lua dispatcher builders (Hyprland set_prop API)
// ---------------------------------------------------------------------------

function setProp(prop, value, address) {
  var v = (typeof value === "number") ? String(value) : JSON.stringify(String(value));
  return 'hl.dsp.window.set_prop({ prop = ' + JSON.stringify(prop)
    + ', value = ' + v
    + ', window = ' + JSON.stringify("address:" + address) + ' })';
}

function focusCommand(address) {
  return 'hl.dsp.focus({ window = ' + JSON.stringify("address:" + address) + ' })';
}

function commands(address, step, cfg) {
  if (step <= 0) {
    return [
      setProp("opacity_inactive", 1.0, address),
      setProp("inactive_border_color", -1, address)
    ];
  }
  var fx = effects(step, cfg);
  var out = [setProp("opacity_inactive", fx.alpha, address)];
  if (cfg.tintBorder)
    out.push(setProp("inactive_border_color", fx.border, address));
  return out;
}

function tickMs(cfg) {
  return Math.round(clamp(cfg.settleMinutes * 60 * 1000 / cfg.stages / 2, 2000, 30000));
}

function reconcile(last, clients, clock) {
  var next = {};
  for (var i = 0; i < clients.length; i++) {
    var c = clients[i];
    var prev = last[c.address];
    var v = (typeof prev === "number" && prev <= clock) ? prev : clock;
    if (c.focusHistoryID === 0) v = clock;
    next[c.address] = v;
  }
  return next;
}

function isExempt(client, exempt) {
  var cls = String(client["class"] || "").toLowerCase();
  return exempt.indexOf(cls) >= 0;
}

function compute(last, clients, clock, cfg) {
  var graceSec = cfg.dustAfterMinutes * 60;
  var rampSec = cfg.settleMinutes * 60;
  var out = [];
  for (var i = 0; i < clients.length; i++) {
    var c = clients[i];
    var idle = Math.max(0, clock - (typeof last[c.address] === "number" ? last[c.address] : clock));
    var exempt = isExempt(c, cfg.exempt);
    var step = (!cfg.enabled || exempt) ? 0
      : toStep(dustLevel(idle, graceSec, rampSec, cfg.curve), cfg.stages);
    var at = c.at || [0, 0];
    var size = c.size || [0, 0];
    // real fullscreen only (2); "maximised" (1) keeps the bar and gaps, so dust still fits
    var fs = c.fullscreen === true || (typeof c.fullscreen === "number" && c.fullscreen >= 2);
    out.push({
      address: c.address,
      cls: c["class"] || "",
      title: c.title || "",
      idleSec: idle,
      step: step,
      level: step / cfg.stages,
      exempt: exempt,
      fullscreen: fs,
      x: at[0],
      y: at[1],
      w: size[0],
      h: size[1],
      monitor: (typeof c.monitor === "number") ? c.monitor : -1,
      workspace: (c.workspace && typeof c.workspace.id === "number") ? c.workspace.id : -1
    });
  }
  out.sort(function (a, b) { return b.idleSec - a.idleSec; });
  return out;
}

// ---------------------------------------------------------------------------
// Particles
// ---------------------------------------------------------------------------

function enabledKinds(cfg) {
  var out = [];
  if (cfg.effectMotes) out.push("mote");
  if (cfg.effectGrain) out.push("grain");
  if (cfg.effectSmudges) out.push("smudge");
  if (cfg.effectStreaks) out.push("streak");
  if (cfg.effectCobwebs) out.push("cobweb");
  if (cfg.effectFibers) out.push("fiber");
  return out;
}

function spawnParticles(count, x, y, w, h, cfg) {
  var kinds = enabledKinds(cfg);
  if (kinds.length === 0) return [];
  var out = [];
  for (var i = 0; i < count; i++) {
    var kind = kinds[Math.floor(Math.random() * kinds.length)];
    var p = {
      kind: kind,
      x: x + Math.random() * w,
      y: y + Math.random() * h,
      vx: 0, vy: 0,
      size: 1,
      len: 0,
      corner: 0,
      targetAlpha: randRange(0.35, 1.0),
      twinklePhase: Math.random() * Math.PI * 2,
      twinkleSpeed: randRange(0.4, 1.8),
      scatterVx: 0, scatterVy: 0, scatterTime: 0,
      age: 0,
      alpha: 0
    };

    if (kind === "cobweb") {
      // Place at a random corner of the window.
      p.corner = Math.floor(Math.random() * 4);
      p.x = (p.corner === 0 || p.corner === 2) ? x : x + w;
      p.y = (p.corner < 2) ? y : y + h;
      
      var maxSize = Math.min(w, h) * 0.35;
      p.size = Math.min(randRange(22, 52), maxSize);
      p.targetAlpha = randRange(0.18, 0.4);
      p.twinkleSpeed = 0;
      p.vx = 0; p.vy = 0;

    } else if (kind === "fiber") {
      // a loose strand of lint: a short curved line that drifts and turns slowly
      p.len = randRange(8, 26);
      p.ang = Math.random() * Math.PI * 2;
      p.curve = randRange(-5, 5);
      p.spin = randRange(-0.25, 0.25);
      p.size = 1;
      p.vx = randRange(-cfg.particleDrift * 0.4, cfg.particleDrift * 0.4);
      p.vy = randRange(-cfg.particleDrift * 0.4, cfg.particleDrift * 0.4);
      p.targetAlpha = randRange(0.25, 0.6);

    } else if (kind === "smudge") {
      p.size = randRange(14, 38);
      p.vx = randRange(-cfg.particleDrift * 0.15, cfg.particleDrift * 0.15);
      p.vy = randRange(-cfg.particleDrift * 0.15, cfg.particleDrift * 0.15);
      p.targetAlpha = randRange(0.05, 0.14);

    } else if (kind === "streak") {
      p.len = randRange(6, 22);
      p.size = randRange(0.4, 1.2);
      p.vx = randRange(-0.15, 0.15);
      p.vy = randRange(0.5, 2.5);
      p.targetAlpha = randRange(0.15, 0.4);

    } else if (kind === "grain") {
      p.size = randRange(0.3, 0.9);
      p.vx = randRange(-0.15, 0.15);
      p.vy = randRange(-0.15, 0.15);
      p.targetAlpha = randRange(0.4, 1.0);

    } else { // mote
      p.size = randRange(cfg.particleSizeMin, cfg.particleSizeMax);
      p.vx = randRange(-cfg.particleDrift, cfg.particleDrift);
      p.vy = randRange(-cfg.particleDrift, cfg.particleDrift);
    }
    out.push(p);
  }
  return out;
}

function stepParticles(particles, dt, x, y, w, h, dustLevel, cfg) {
  var maxV = Math.max(cfg.particleDrift * 2, 0.01);
  var margin = 6;
  for (var i = 0; i < particles.length; i++) {
    var p = particles[i];
    p.age += dt;

    if (p.kind === "spider") {
      stepSpider(p, dt, x, y, w, h, dustLevel, cfg);
      continue;
    }

    if (p.scatterTime > 0) {
      p.scatterTime = Math.max(0, p.scatterTime - dt);
      p.x += p.scatterVx * dt;
      p.y += p.scatterVy * dt;
      var damp = Math.exp(-dt * 3.0);
      p.scatterVx *= damp;
      p.scatterVy *= damp;
    }

    if (p.kind === "cobweb") {
      // Static.
    } else if (p.kind === "streak") {
      p.y += p.vy * dt;
      if (p.y > y + h + 4) {
        p.y = y - 4;
        p.x = x + Math.random() * w;
      }
    } else if (p.kind === "grain") {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.x < x) p.x = x + w;
      if (p.x > x + w) p.x = x;
      if (p.y < y) p.y = y + h;
      if (p.y > y + h) p.y = y;
    } else {
      // mote, smudge: random-walk drift.
      p.vx += randRange(-0.6, 0.6) * dt;
      p.vy += randRange(-0.6, 0.6) * dt;
      var v2 = p.vx * p.vx + p.vy * p.vy;
      if (v2 > maxV * maxV) {
        var s = maxV / Math.sqrt(v2);
        p.vx *= s; p.vy *= s;
      }
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.kind === "fiber") p.ang += p.spin * dt;
      if (p.x < x - margin) p.x = x + w + margin;
      if (p.x > x + w + margin) p.x = x - margin;
      if (p.y < y - margin) p.y = y + h + margin;
      if (p.y > y + h + margin) p.y = y - margin;
    }

    var fadeIn = Math.min(1, p.age / 1.5);
    p.alpha = p.targetAlpha * dustLevel * fadeIn * cfg.particleOpacity;
    if (cfg.particleTwinkle)
      p.twinklePhase += p.twinkleSpeed * dt * Math.PI;
  }
}

function scatterParticles(particles, cx, cy, strength) {
  for (var i = 0; i < particles.length; i++) {
    var p = particles[i];
    if (p.kind === "spider") {                 // spiders scurry away from the focus point
      p.ang = Math.atan2(p.y - cy, p.x - cx) + randRange(-0.4, 0.4);
      p.run = 1.4;
      p.state = "walk";
      p.timer = 3;
      continue;
    }
    if (p.kind === "cobweb") continue;   // cobwebs stay attached
    var dx = p.x - cx;
    var dy = p.y - cy;
    var d = Math.sqrt(dx * dx + dy * dy);
    if (d < 0.5) { dx = randRange(-1, 1); dy = randRange(-1, 1); d = 1; }
    var f = strength * 260 / Math.max(d, 25);
    p.scatterVx += (dx / d) * f;
    p.scatterVy += (dy / d) * f;
    p.scatterTime = 0.9;
  }
}

function remapParticles(particles, oldX, oldY, oldW, oldH, newX, newY, newW, newH) {
  if (oldW <= 0 || oldH <= 0) {
    // Degenerate old bounds: re-seed uniformly inside the new rect.
    for (var k = 0; k < particles.length; k++) {
      var q = particles[k]
      if (q.kind === "cobweb") {
        q.x = (q.corner === 0 || q.corner === 2) ? newX : newX + newW
        q.y = (q.corner < 2) ? newY : newY + newH
        var maxSz = Math.min(newW, newH) * 0.35
        q.size = Math.max(8, Math.min(q.size, maxSz))
      } else {
        q.x = newX + Math.random() * newW
        q.y = newY + Math.random() * newH
      }
    }
    return
  }
  var sx = newW / oldW
  var sy = newH / oldH
  var shortSide = Math.min(newW, newH)
  for (var i = 0; i < particles.length; i++) {
    var p = particles[i]
    if (p.kind === "cobweb") {
      // Re-anchor to the new corner.
      p.x = (p.corner === 0 || p.corner === 2) ? newX : newX + newW
      p.y = (p.corner < 2) ? newY : newY + newH
      // Rescale the web's radius with the window, keeping it proportional to
      // the smaller dimension. Clamped both ways: never below 8 px
      // (unreadable), never above 35% of the shorter side.
      var scaled = p.size * Math.min(sx, sy)
      p.size = Math.max(8, Math.min(scaled, shortSide * 0.35))
    } else {
      p.x = newX + (p.x - oldX) * sx
      p.y = newY + (p.y - oldY) * sy
      // Reset streaks that ended up past the (possibly shorter) bottom.
      if (p.kind === "streak" && p.y > newY + newH) {
        p.y = newY
        p.x = newX + Math.random() * newW
      }
    }
  }
}

// ---- spiders: they walk across the window, stop, turn, and run when it is focused ----

function spiderCount(w, h, cfg) {
  if (!cfg.particles || !cfg.effectSpiders) return 0;
  if (w < 160 || h < 120) return 0;
  return clamp(Math.round(w * h / 260000), 1, cfg.spiderMax);
}

function spawnSpiders(count, x, y, w, h, cfg) {
  var out = [];
  for (var i = 0; i < count; i++) {
    var spd = randRange(14, 38);
    out.push({
      kind: "spider",
      x: x + Math.random() * w, y: y + Math.random() * h,
      vx: 0, vy: 0,
      size: randRange(3.2, 6),
      len: 0, corner: 0,
      targetAlpha: 1, twinklePhase: 0, twinkleSpeed: 0,
      scatterVx: 0, scatterVy: 0, scatterTime: 0,
      age: 0, alpha: 0,
      ang: Math.random() * Math.PI * 2,
      baseSpd: spd, spd: spd,
      state: "walk", timer: randRange(1, 6),
      legPhase: Math.random() * 6.28, run: 0
    });
  }
  return out;
}

function stepSpider(p, dt, x, y, w, h, level, cfg) {
  if (p.run > 0) p.run = Math.max(0, p.run - dt);
  p.timer -= dt;
  if (p.state === "pause" && p.run <= 0) {
    if (p.timer <= 0) {
      p.state = "walk";
      p.timer = randRange(2, 7);
      p.ang += randRange(-1.2, 1.2);
    }
  } else {
    var sp = p.run > 0 ? 130 : p.spd;
    p.ang += randRange(-2.1, 2.1) * dt;
    p.x += Math.cos(p.ang) * sp * dt;
    p.y += Math.sin(p.ang) * sp * dt;
    p.legPhase += sp * dt * 0.45;
    if (p.timer <= 0 && p.run <= 0) { p.state = "pause"; p.timer = randRange(0.8, 3.5); }
    // at the edge of the window, turn back toward the middle
    var m = 10;
    if (p.x < x + m || p.x > x + w - m || p.y < y + m || p.y > y + h - m) {
      var da = Math.atan2(y + h / 2 - p.y, x + w / 2 - p.x) - p.ang;
      while (da > Math.PI) da -= Math.PI * 2;
      while (da < -Math.PI) da += Math.PI * 2;
      p.ang += da * Math.min(1, dt * 4);
      p.x = clamp(p.x, x + 2, x + w - 2);
      p.y = clamp(p.y, y + 2, y + h - 2);
    }
  }
  // they only show up once the window is properly dusty
  var ramp = clamp((level - 0.25) / 0.35, 0, 1);
  p.alpha = 0.85 * ramp * Math.min(1, p.age / 1.5) * (0.5 + 0.5 * cfg.particleOpacity);
}

// Dust and spiders are sized separately: the dust budget is the particle cap,
// the spiders are a few per window.
function resizeSet(set, wantDust, wantSpiders, x, y, w, h, cfg) {
  var dust = [], spiders = [];
  for (var i = 0; i < set.length; i++) (set[i].kind === "spider" ? spiders : dust).push(set[i]);
  if (dust.length > wantDust) dust = dust.slice(0, wantDust);
  else if (dust.length < wantDust) dust = dust.concat(spawnParticles(wantDust - dust.length, x, y, w, h, cfg));
  if (spiders.length > wantSpiders) spiders = spiders.slice(0, wantSpiders);
  else if (spiders.length < wantSpiders) spiders = spiders.concat(spawnSpiders(wantSpiders - spiders.length, x, y, w, h, cfg));
  return dust.concat(spiders);
}

// ---- dust layer: a fine powder over the whole window ----------------------------------
// Specks are not stored: each one is a pure function of (window seed, index), so the
// same window always gets the same powder, and it scales when the window is resized.

function powderCount(w, h, cfg) {
  if (!cfg.particles || !cfg.effectPowder) return 0;
  return clamp(Math.round(w * h * cfg.powderDensity / 1000), 0, 7000);
}

function hashStr(s) {
  var h = 2166136261;
  s = String(s);
  for (var i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}

function rand01(seed, i, k) {
  var h = Math.imul(seed ^ Math.imul(i + 1, 0x9E3779B1) ^ Math.imul(k + 1, 0x85EBCA6B), 0xC2B2AE35);
  h ^= h >>> 15; h = Math.imul(h, 0x2C1B3C6D); h ^= h >>> 12;
  return (h >>> 0) / 4294967296;
}

function particleCount(w, h, cfg) {
  if (!cfg.particles) return 0;
  if (enabledKinds(cfg).length === 0) return 0;
  var area = w * h;
  var n = Math.round(area * cfg.particleDensity / 1000);
  return clamp(n, 0, cfg.particleMax);
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

function formatDuration(sec) {
  sec = Math.round(sec);
  if (sec < 60) return sec + "s";
  var m = Math.floor(sec / 60);
  if (m < 60) {
    var s = sec % 60;
    return s > 0 ? m + "m " + s + "s" : m + "m";
  }
  var h = Math.floor(m / 60);
  var r = m % 60;
  return r > 0 ? h + "h " + r + "m" : h + "h";
}

function formatSetting(fmt, v) {
  switch (fmt) {
  case "minutes": return formatDuration(v * 60);
  case "percent": return Math.round(v * 100) + "%";
  case "density": return v.toFixed(2) + " / kpx\u00b2";
  case "px": return v.toFixed(1) + " px";
  case "pxs": return v.toFixed(1) + " px/s";
  case "mins": return v + "m";
  case "kpx": return v + " / kpx\u00b2";
  default: return String(v);
  }
}

function statusText(enabled, dusty, total) {
  if (!enabled) return "Paused";
  if (total === 0) return "No windows";
  if (dusty === 0) return "All clean  \u00b7  " + total + (total === 1 ? " window" : " windows");
  return dusty + (dusty === 1 ? " dusty window" : " dusty windows") + "  \u00b7  " + total + " total";
}

function formatIdle(sec) {
  var m = Math.floor(sec / 60);
  if (m < 1) return "<1m";
  if (m < 60) return m + "m";
  var h = Math.floor(m / 60);
  var r = m % 60;
  return h + "h " + (r < 10 ? "0" + r : r) + "m";
}
