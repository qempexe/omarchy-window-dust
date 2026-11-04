.pragma library

// The dust itself: how dusty a window is, what Hyprland is told, and the particles.
// No QML and no I/O, so it is tested with node (tests/test_model.js).

function clamp(x, lo, hi) { return Math.min(hi, Math.max(lo, x)); }
function lerp(a, b, t) { return a + (b - a) * t; }
function randRange(lo, hi) { return lo + Math.random() * (hi - lo); }

function hex2(n) {
  const s = Math.round(clamp(n, 0, 255)).toString(16);
  return s.length < 2 ? "0" + s : s;
}

// "#8b8378" -> "8b8378"
function bare(c) { return String(c || "").replace(/^#/, "").toLowerCase(); }

// "#8b8378" -> { r, g, b }
function rgbOf(c) {
  const h = bare(c);
  if (!/^[0-9a-f]{6}$/.test(h)) return { r: 139, g: 131, b: 120 };
  return { r: parseInt(h.substr(0, 2), 16), g: parseInt(h.substr(2, 2), 16), b: parseInt(h.substr(4, 2), 16) };
}

// ---------------------------------------------------------------------------
// Dust maths
// ---------------------------------------------------------------------------

function dustLevel(idleSec, graceSec, rampSec, curve) {
  let t = clamp((idleSec - graceSec) / rampSec, 0, 1);
  switch (curve) {
  case "linear": return t;
  case "early": return 1 - (1 - t) * (1 - t);
  case "late": return t * t;
  default: return t * t * (3 - 2 * t);
  }
}

function toStep(level, stages) { return Math.round(level * stages); }

function effects(step, cfg) {
  let level = step / cfg.stages;
  let alpha = Math.round(lerp(cfg.startOpacity, cfg.minOpacity, level) * 1000) / 1000;
  let borderAlpha = lerp(0.35, 0.95, level);
  return {
    alpha: alpha,
    border: "rgba(" + bare(cfg.dustColor) + hex2(borderAlpha * 255) + ")"
  };
}

// ---------------------------------------------------------------------------
// Lua dispatcher builders (Hyprland set_prop API)
// ---------------------------------------------------------------------------

function setProp(prop, value, address) {
  let v = (typeof value === "number") ? String(value) : JSON.stringify(String(value));
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
  let fx = effects(step, cfg);
  let out = [setProp("opacity_inactive", fx.alpha, address)];
  if (cfg.tintBorder)
    out.push(setProp("inactive_border_color", fx.border, address));
  return out;
}

// how often the dust clock moves: twice per stage, never faster than 2 s or slower than 30 s
function tickMs(cfg) {
  return Math.round(clamp(cfg.settleMinutes * 60 * 1000 / cfg.stages / 2, 2000, 30000));
}

function reconcile(last, clients, clock) {
  let next = {};
  for (let i = 0; i < clients.length; i++) {
    let c = clients[i];
    let prev = last[c.address];
    let v = (typeof prev === "number" && prev <= clock) ? prev : clock;
    if (c.focusHistoryID === 0) v = clock;
    next[c.address] = v;
  }
  return next;
}

function isExempt(client, cfg) {
  const cls = String(client["class"] || "").toLowerCase();
  if (cfg.exempt.indexOf(cls) >= 0) return true;
  return cfg.exemptFloating === true && client.floating === true;
}

// clients (hyprctl -j clients) -> one entry per window, the dustiest first
function compute(last, clients, clock, cfg) {
  const graceSec = cfg.dustAfterMinutes * 60;
  const rampSec = cfg.settleMinutes * 60;
  const out = [];
  for (let i = 0; i < clients.length; i++) {
    const c = clients[i];
    const idle = Math.max(0, clock - (typeof last[c.address] === "number" ? last[c.address] : clock));
    const exempt = isExempt(c, cfg);
    const step = (!cfg.enabled || exempt) ? 0
      : toStep(dustLevel(idle, graceSec, rampSec, cfg.curve), cfg.stages);
    const at = c.at || [0, 0];
    const size = c.size || [0, 0];
    // real fullscreen only (2); "maximised" (1) keeps the bar and gaps, so dust still fits
    const fs = c.fullscreen === true || (typeof c.fullscreen === "number" && c.fullscreen >= 2);
    out.push({
      address: c.address,
      cls: c["class"] || "",
      title: c.title || "",
      idleSec: idle,
      step: step,
      level: step / cfg.stages,
      exempt: exempt,
      fullscreen: fs,
      floating: c.floating === true,
      pinned: c.pinned === true,
      order: typeof c.focusHistoryID === "number" ? c.focusHistoryID : 99,
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

// The windows drawn over `e` on its screen: floating ones over tiled ones, and among
// floating windows the more recently focused one. Their rectangles are kept clear of
// e's dust. `shown` tells which windows are on screen now.
function above(e, a) {
  if (a.address === e.address || a.monitor !== e.monitor) return false;
  if (a.floating && !e.floating) return true;
  if (a.floating === e.floating && a.order < e.order) return true;
  return a.pinned && !e.pinned;
}
function occluders(e, entries, shown) {
  const out = [];
  for (let i = 0; i < entries.length; i++) {
    const a = entries[i];
    if (shown[a.address] !== true || !above(e, a)) continue;
    // only the part over e matters
    const x0 = Math.max(e.x, a.x), y0 = Math.max(e.y, a.y);
    const x1 = Math.min(e.x + e.w, a.x + a.w), y1 = Math.min(e.y + e.h, a.y + a.h);
    if (x1 - x0 > 1 && y1 - y0 > 1) out.push([x0, y0, x1 - x0, y1 - y0]);
  }
  return out;
}

// how dusty a window is right now, as words for the panel
function stateText(e) {
  if (e.exempt) return "never dusted";
  if (e.level <= 0) return "clean";
  if (e.level < 0.25) return "a few specks";
  if (e.level < 0.5) return "dusty";
  if (e.level < 0.85) return "very dusty";
  return "buried";
}

function idleText(sec) {
  const m = Math.floor(sec / 60);
  if (m < 1) return "under a minute";
  if (m < 60) return m + "m";
  const h = Math.floor(m / 60), r = m % 60;
  if (h < 48) return h + "h " + (r < 10 ? "0" + r : r) + "m";
  return Math.floor(h / 24) + "d " + (h % 24) + "h";
}

// ---------------------------------------------------------------------------
// Particles
// ---------------------------------------------------------------------------

function enabledKinds(cfg) {
  let out = [];
  if (cfg.effectMotes) out.push("mote");
  if (cfg.effectGrain) out.push("grain");
  if (cfg.effectSmudges) out.push("smudge");
  if (cfg.effectStreaks) out.push("streak");
  if (cfg.effectCobwebs) out.push("cobweb");
  if (cfg.effectFibers) out.push("fiber");
  return out;
}

function spawnParticles(count, x, y, w, h, cfg) {
  let kinds = enabledKinds(cfg);
  if (kinds.length === 0) return [];
  let out = [];
  for (let i = 0; i < count; i++) {
    let kind = kinds[Math.floor(Math.random() * kinds.length)];
    let p = {
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
      
      let maxSize = Math.min(w, h) * 0.35;
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
  let maxV = Math.max(cfg.particleDrift * 2, 0.01);
  let margin = 6;
  for (let i = 0; i < particles.length; i++) {
    let p = particles[i];
    p.age += dt;

    if (p.kind === "spider") {
      stepSpider(p, dt, x, y, w, h, dustLevel, cfg);
      continue;
    }

    if (p.scatterTime > 0) {
      p.scatterTime = Math.max(0, p.scatterTime - dt);
      p.x += p.scatterVx * dt;
      p.y += p.scatterVy * dt;
      let damp = Math.exp(-dt * 3.0);
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
      let v2 = p.vx * p.vx + p.vy * p.vy;
      if (v2 > maxV * maxV) {
        let s = maxV / Math.sqrt(v2);
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

    let fadeIn = Math.min(1, p.age / 1.5);
    p.alpha = p.targetAlpha * dustLevel * fadeIn * cfg.particleOpacity;
    if (cfg.particleTwinkle)
      p.twinklePhase += p.twinkleSpeed * dt * Math.PI;
  }
}

function scatterParticles(particles, cx, cy, strength) {
  for (let i = 0; i < particles.length; i++) {
    let p = particles[i];
    if (p.kind === "spider") {                 // spiders scurry away from the focus point
      p.ang = Math.atan2(p.y - cy, p.x - cx) + randRange(-0.4, 0.4);
      p.run = 1.4;
      p.state = "walk";
      p.timer = 3;
      continue;
    }
    if (p.kind === "cobweb") continue;   // cobwebs stay attached
    let dx = p.x - cx;
    let dy = p.y - cy;
    let d = Math.sqrt(dx * dx + dy * dy);
    if (d < 0.5) { dx = randRange(-1, 1); dy = randRange(-1, 1); d = 1; }
    let f = strength * 260 / Math.max(d, 25);
    p.scatterVx += (dx / d) * f;
    p.scatterVy += (dy / d) * f;
    p.scatterTime = 0.9;
  }
}

function remapParticles(particles, oldX, oldY, oldW, oldH, newX, newY, newW, newH) {
  if (oldW <= 0 || oldH <= 0) {
    // Degenerate old bounds: re-seed uniformly inside the new rect.
    for (let k = 0; k < particles.length; k++) {
      let q = particles[k]
      if (q.kind === "cobweb") {
        q.x = (q.corner === 0 || q.corner === 2) ? newX : newX + newW
        q.y = (q.corner < 2) ? newY : newY + newH
        let maxSz = Math.min(newW, newH) * 0.35
        q.size = Math.max(8, Math.min(q.size, maxSz))
      } else {
        q.x = newX + Math.random() * newW
        q.y = newY + Math.random() * newH
      }
    }
    return
  }
  let sx = newW / oldW
  let sy = newH / oldH
  let shortSide = Math.min(newW, newH)
  for (let i = 0; i < particles.length; i++) {
    let p = particles[i]
    if (p.kind === "cobweb") {
      // Re-anchor to the new corner.
      p.x = (p.corner === 0 || p.corner === 2) ? newX : newX + newW
      p.y = (p.corner < 2) ? newY : newY + newH
      // Rescale the web's radius with the window, keeping it proportional to
      // the smaller dimension. Clamped both ways: never below 8 px
      // (unreadable), never above 35% of the shorter side.
      let scaled = p.size * Math.min(sx, sy)
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
  let out = [];
  for (let i = 0; i < count; i++) {
    let spd = randRange(14, 38);
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
    let sp = p.run > 0 ? 130 : p.spd;
    p.ang += randRange(-2.1, 2.1) * dt;
    p.x += Math.cos(p.ang) * sp * dt;
    p.y += Math.sin(p.ang) * sp * dt;
    p.legPhase += sp * dt * 0.45;
    if (p.timer <= 0 && p.run <= 0) { p.state = "pause"; p.timer = randRange(0.8, 3.5); }
    // at the edge of the window, turn back toward the middle
    let m = 10;
    if (p.x < x + m || p.x > x + w - m || p.y < y + m || p.y > y + h - m) {
      let da = Math.atan2(y + h / 2 - p.y, x + w / 2 - p.x) - p.ang;
      while (da > Math.PI) da -= Math.PI * 2;
      while (da < -Math.PI) da += Math.PI * 2;
      p.ang += da * Math.min(1, dt * 4);
      p.x = clamp(p.x, x + 2, x + w - 2);
      p.y = clamp(p.y, y + 2, y + h - 2);
    }
  }
  // they only show up once the window is properly dusty
  let ramp = clamp((level - 0.25) / 0.35, 0, 1);
  p.alpha = 0.85 * ramp * Math.min(1, p.age / 1.5) * (0.5 + 0.5 * cfg.particleOpacity);
}

// Dust and spiders are sized separately: the dust budget is the particle cap,
// the spiders are a few per window.
function resizeSet(set, wantDust, wantSpiders, x, y, w, h, cfg) {
  let dust = [], spiders = [];
  for (let i = 0; i < set.length; i++) (set[i].kind === "spider" ? spiders : dust).push(set[i]);
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
  let h = 2166136261;
  s = String(s);
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}

function rand01(seed, i, k) {
  let h = Math.imul(seed ^ Math.imul(i + 1, 0x9E3779B1) ^ Math.imul(k + 1, 0x85EBCA6B), 0xC2B2AE35);
  h ^= h >>> 15; h = Math.imul(h, 0x2C1B3C6D); h ^= h >>> 12;
  return (h >>> 0) / 4294967296;
}

function particleCount(w, h, cfg) {
  if (!cfg.particles) return 0;
  if (enabledKinds(cfg).length === 0) return 0;
  let area = w * h;
  let n = Math.round(area * cfg.particleDensity / 1000);
  return clamp(n, 0, cfg.particleMax);
}

