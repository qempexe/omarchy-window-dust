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
  effectCobwebs: true
};

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
  particleOpacity: [0.4, 0.55, 0.75, 0.9, 1.0]
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
              particleDensity: 0.15, particleOpacity: 0.55 } },
  { id: "normal", label: "Normal",
    values: { dustAfterMinutes: 20, settleMinutes: 180, minOpacity: 0.55, stages: 8, curve: "smooth",
              particleDensity: 0.22, particleOpacity: 0.75 } },
  { id: "dramatic", label: "Dramatic",
    values: { dustAfterMinutes: 10, settleMinutes: 60, minOpacity: 0.35, stages: 12, curve: "early",
              particleDensity: 0.5, particleOpacity: 0.9 } },
  { id: "demo", label: "Demo (2 min)",
    values: { dustAfterMinutes: 0.25, settleMinutes: 1.5, minOpacity: 0.4, stages: 12, curve: "linear",
              particleDensity: 0.4, particleOpacity: 0.85 } }
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
  return out;
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
    out.push({
      address: c.address,
      cls: c["class"] || "",
      title: c.title || "",
      idleSec: idle,
      step: step,
      level: step / cfg.stages,
      exempt: exempt,
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

function formatIdle(sec) {
  var m = Math.floor(sec / 60);
  if (m < 1) return "<1m";
  if (m < 60) return m + "m";
  var h = Math.floor(m / 60);
  var r = m % 60;
  return h + "h " + (r < 10 ? "0" + r : r) + "m";
}
