.pragma library
.import "Util.js" as Util

// Every setting Window Dust has. The settings panel builds its tabs and rows from
// `groups`, and resolve() at the bottom turns window-dust.json into a full, checked config.
//
//   kind: enum (pick one), steps (a number picked from a list, with − and +), bool (on/off),
//         string (text), color (#rrggbb), palette (3 colors), tags (a list of names),
//         presets (buttons that set many things at once), windows (the dusty windows),
//         about (the About page)
//   control: how an enum is shown: seg (buttons), tiles (little pictures), scheme, chips
//   fmt: how a steps value is shown (see format())
//   when: the row is greyed out unless these other settings have these values

// custom color swatches: backgrounds, text colors, accents
var swatches = [
  "#1c1210", "#141414", "#1a1b26", "#282a36", "#2e3440", "#2d353b", "#1f1f28", "#3b2a1f",
  "#e9dcc8", "#e0e0e0", "#ffffff", "#c0caf5", "#d8dee9", "#dcd7ba", "#f8f8f2", "#e0def4",
  "#c8905a", "#d4a35a", "#7aa2f7", "#cba6f7", "#a7c080", "#88c0d0", "#fabd2f", "#e06c75"
];

// dust colors to start from
var dustColors = ["#8b8378", "#b5a07a", "#7d8590", "#55504a", "#e8dcc0", "#9a8f7e", "#6f7a6a", "#a08a8a"];

var particlesOn = [{ key: "particles", is: ["true"] }];

var groups = [
  {
    title: "Windows",
    items: [
      { key: "windows", label: "Dusty windows", kind: "windows",
        hint: "Every window and how dusty it is. Click one to focus it, or use its buttons." }
    ]
  },
  {
    title: "Dust",
    items: [
      { key: "enabled", section: "Window Dust", label: "Dust gathers", kind: "bool", fallback: true,
        hint: "Off cleans every window and stops the clock. Your settings stay." },
      { key: "preset", section: "Ready made", label: "How fast dust settles", kind: "presets",
        hint: "Sets the timing, the fade and how thick the dust gets in one go. Change anything after." },
      { key: "dustAfterMinutes", section: "Timing", label: "Dust starts after", kind: "steps", fmt: "minutes", fallback: 20,
        min: 0.05, max: 10080, options: [0.25, 1, 5, 10, 20, 30, 45, 60, 90, 120, 180, 240, 480, 720],
        hint: "How long a window stays untouched before the first speck." },
      { key: "settleMinutes", section: "Timing", label: "Settles fully over", kind: "steps", fmt: "minutes", fallback: 180,
        min: 0.25, max: 10080, options: [1.5, 5, 15, 30, 60, 120, 180, 360, 720, 1440],
        hint: "How long the dust then takes to reach its thickest. This is the speed." },
      { key: "stages", section: "Timing", label: "Stages", kind: "steps", fmt: "int", fallback: 8,
        min: 2, max: 32, round: true, options: [4, 6, 8, 12, 16, 24],
        hint: "Steps from clean to fully dusty. More is smoother." },
      { key: "curve", section: "Timing", label: "How dust settles", kind: "enum", fallback: "smooth", control: "tiles",
        options: ["smooth", "linear", "early", "late"],
        labels: { smooth: "Smooth", linear: "Steady", early: "Fast at first", late: "Slow at first" },
        hint: "The shape of the build-up over time." }
    ]
  },
  {
    title: "Look",
    items: [
      { key: "minOpacity", section: "Fade", label: "Fades down to", kind: "steps", fmt: "percent", fallback: 0.55,
        min: 0.1, max: 1, options: [0.2, 0.3, 0.4, 0.5, 0.55, 0.6, 0.7, 0.8, 0.9, 1],
        hint: "How see-through a fully dusty window gets while it isn't focused. 100% keeps it solid." },
      { key: "tintBorder", section: "Fade", label: "Dusty border", kind: "bool", fallback: true,
        hint: "Tints the window border in the dust color as well." },
      { key: "dustColor", section: "Color", label: "Dust color", kind: "color", fallback: "#8b8378", presets: dustColors,
        hint: "The color of the specks, the haze and the border tint." },
      { key: "effectPowder", section: "Effects", label: "Dust layer", kind: "bool", fallback: true,
        hint: "A fine powder over the whole window, thicker toward the bottom and in the corners.", when: particlesOn },
      { key: "effectMotes", section: "Effects", label: "Motes", kind: "bool", fallback: true,
        hint: "Specks that drift about with a faint halo.", when: particlesOn },
      { key: "effectGrain", section: "Effects", label: "Grain", kind: "bool", fallback: true,
        hint: "Tiny sharp flecks.", when: particlesOn },
      { key: "effectSmudges", section: "Effects", label: "Smudges", kind: "bool", fallback: true,
        hint: "Large soft blobs of grime.", when: particlesOn },
      { key: "effectStreaks", section: "Effects", label: "Streaks", kind: "bool", fallback: true,
        hint: "Thin drips that run down.", when: particlesOn },
      { key: "effectFibers", section: "Effects", label: "Fibres", kind: "bool", fallback: true,
        hint: "Loose strands of lint that drift and turn.", when: particlesOn },
      { key: "effectCobwebs", section: "Effects", label: "Cobwebs", kind: "bool", fallback: true,
        hint: "Webs in the corners, once a window is half dusty.", when: particlesOn },
      { key: "effectSpiders", section: "Effects", label: "Spiders", kind: "bool", fallback: true,
        hint: "Small spiders that walk across a dusty window and run when you focus it.", when: particlesOn }
    ]
  },
  {
    title: "Particles",
    items: [
      { key: "particles", section: "Particles", label: "Draw dust", kind: "bool", fallback: true,
        hint: "Off keeps only the fade and the border tint, and draws nothing over your windows." },
      { key: "particleDensity", section: "Amount", label: "Density", kind: "steps", fmt: "density", fallback: 0.22,
        min: 0.01, max: 3, options: [0.1, 0.15, 0.22, 0.35, 0.5, 0.75, 1],
        hint: "Moving specks per 1000 square pixels of window.", when: particlesOn },
      { key: "particleMax", section: "Amount", label: "Most per window", kind: "steps", fmt: "int", fallback: 240,
        min: 20, max: 1500, round: true, options: [80, 140, 200, 240, 360, 500],
        hint: "A cap, so a big window on a big screen stays light.", when: particlesOn },
      { key: "powderDensity", section: "Amount", label: "Dust layer amount", kind: "steps", fmt: "kpx", fallback: 8,
        min: 0.5, max: 60, options: [2, 4, 8, 12, 20, 30],
        hint: "Fine specks per 1000 square pixels when fully dusty.", when: [{ key: "particles", is: ["true"] }, { key: "effectPowder", is: ["true"] }] },
      { key: "spiderMax", section: "Amount", label: "Spiders per window", kind: "steps", fmt: "int", fallback: 2,
        min: 1, max: 12, round: true, options: [1, 2, 3, 5, 8],
        hint: "The most a large window gets. Small windows get fewer, tiny ones none.", when: [{ key: "particles", is: ["true"] }, { key: "effectSpiders", is: ["true"] }] },
      { key: "particleSizeMax", section: "Motion", label: "Biggest speck", kind: "steps", fmt: "px", fallback: 2.6,
        min: 0.5, max: 12, options: [1.5, 2, 2.6, 3.5, 5],
        hint: "The radius of the largest mote.", when: particlesOn },
      { key: "particleDrift", section: "Motion", label: "Drift", kind: "steps", fmt: "pxs", fallback: 4,
        min: 0, max: 60, options: [0, 1, 2, 4, 7, 12, 20],
        hint: "How fast the specks wander. 0 keeps them still.", when: particlesOn },
      { key: "particleOpacity", section: "Motion", label: "Brightness", kind: "steps", fmt: "percent", fallback: 0.75,
        min: 0.05, max: 1, options: [0.4, 0.55, 0.75, 0.9, 1],
        hint: "How strongly the dust shows.", when: particlesOn },
      { key: "particleTwinkle", section: "Motion", label: "Twinkle", kind: "bool", fallback: true,
        hint: "A slight shimmer on every speck.", when: particlesOn },
      { key: "scatterOnFocus", section: "Motion", label: "Blow it away on focus", kind: "bool", fallback: true,
        hint: "Focusing a window blows its dust outward and sends the spiders running.", when: particlesOn },
      { key: "fps", section: "Motion", label: "Frames per second", kind: "steps", fmt: "fps", fallback: 30,
        min: 10, max: 60, round: true, options: [15, 24, 30, 60],
        hint: "How smoothly the dust moves. Fewer frames use less power. Nothing is drawn while no window is dusty.", when: particlesOn },
      { key: "occlude", section: "Motion", label: "Stay behind windows in front", kind: "bool", fallback: true,
        hint: "A floating window over a dusty one stays clean.", when: particlesOn }
    ]
  },
  {
    title: "Behavior",
    items: [
      { key: "pauseWhenAway", section: "Away", label: "Pause while you're away", kind: "bool", fallback: true,
        hint: "The dust clock stops while you're idle or locked, so a night away doesn't bury everything." },
      { key: "awayMinutes", section: "Away", label: "Away after", kind: "steps", fmt: "minutes", fallback: 5,
        min: 1, max: 240, options: [1, 2, 5, 10, 15, 30],
        hint: "Idle time before you count as away.", when: [{ key: "pauseWhenAway", is: ["true"] }] },
      { key: "hideOnFullscreen", section: "Windows", label: "Hide in fullscreen", kind: "bool", fallback: true,
        hint: "No dust on a screen while one of its windows is fullscreen. It comes back where it was." },
      { key: "exemptFloating", section: "Windows", label: "Never dust floating windows", kind: "bool", fallback: false,
        hint: "Pickers, dialogs and other floating windows stay clean." },
      { key: "exempt", section: "Windows", label: "Never dusted", kind: "tags", fallback: ["mpv", "vlc", "spotify"], max: 64,
        presets: ["mpv", "vlc", "spotify", "steam", "obs", "discord"],
        hint: "Window classes that never gather dust. Right click a window on the Windows tab to add it." }
    ]
  },
  {
    title: "Panel",
    items: [
      { key: "colorMode", section: "Colors", label: "Colors", kind: "enum", fallback: "theme", control: "scheme",
        options: ["theme", "borders", "custom", "monochrome"],
        labels: { theme: "Follow theme", borders: "Window borders", custom: "Custom", monochrome: "Monochrome" },
        hint: "Follow theme matches your Omarchy theme live. Window borders takes the accent from your theme's window border. Custom lets you choose. Monochrome removes every hue." },
      { key: "customColors", section: "Colors", label: "Custom colors", kind: "palette",
        fallback: { customBackground: "#1c1210", customText: "#e9dcc8", customAccent: "#c8905a" },
        targets: [{ key: "customBackground", label: "Background" }, { key: "customText", label: "Text" }, { key: "customAccent", label: "Accent" }],
        presets: swatches,
        hint: "Pick one, then a swatch or a hex code.",
        when: [{ key: "colorMode", is: ["custom"] }] },

      { key: "barIcon", section: "Button", label: "Bar icon", kind: "string", fallback: "󰃢", maxLength: 8,
        presets: ["󰃢", "󰜙", "󰮃", "Dust"],
        hint: "A glyph or a short word for the button." },
      { key: "barShowCount", section: "Button", label: "Show the dusty count", kind: "bool", fallback: true,
        hint: "How many windows are dusty, next to the icon." },
      { key: "rightClick", section: "Button", label: "Right click", kind: "enum", fallback: "clean", control: "seg",
        options: ["clean", "pause", "none"], labels: { clean: "Dust everything off", pause: "Pause", none: "Nothing" },
        hint: "What a right click on the button does." },
      { key: "middleClick", section: "Button", label: "Middle click", kind: "enum", fallback: "pause", control: "seg",
        options: ["pause", "clean", "none"], labels: { pause: "Pause", clean: "Dust everything off", none: "Nothing" },
        hint: "What a middle click on the button does." },

      { key: "openAs", section: "Window", label: "Open as", kind: "enum", fallback: "panel", control: "seg",
        options: ["panel", "window"], labels: { panel: "Bar panel", window: "Own window" },
        hint: "Where the button opens this panel. You can always pop it out or dock it back from the header." },
      { key: "windowWidth", section: "Window", label: "Panel width", kind: "int", fallback: 560, min: 460, max: 1000, step: 20,
        hint: "How wide the panel opens." },
      { key: "windowHeight", section: "Window", label: "Panel height", kind: "int", fallback: 640, min: 440, max: 1000, step: 20,
        hint: "How tall the panel opens." },

      { key: "density", section: "Look", label: "Spacing", kind: "enum", fallback: "comfortable", control: "seg",
        options: ["compact", "comfortable", "spacious"],
        labels: { compact: "Compact", comfortable: "Comfortable", spacious: "Spacious" },
        hint: "How much air there is between things in this panel." },
      { key: "cornerRadius", section: "Look", label: "Panel roundness", kind: "int", fallback: 6, min: 0, max: 20, step: 2,
        hint: "0 is square, 20 is very round." },
      { key: "frame", section: "Look", label: "Window outline", kind: "bool", fallback: false,
        hint: "Draw the panel edge in color instead of a plain neutral line." },
      { key: "frameGradient", section: "Look", label: "Outline gradient", kind: "bool", fallback: true,
        hint: "When your theme's window border is a gradient, the outline runs through all its colors.",
        when: [{ key: "frame", is: ["true"] }] },
      { key: "fontScale", section: "Look", label: "Text size", kind: "int", fallback: 100, min: 80, max: 150, step: 5, divisor: 100, decimals: 2,
        hint: "1 is normal, 1.25 is a quarter bigger." },
      { key: "opacity", section: "Look", label: "Panel opacity", kind: "int", fallback: 96, min: 50, max: 100, step: 2,
        hint: "Background of this panel." },
      { key: "speed", section: "Look", label: "Panel animations", kind: "enum", fallback: "on", control: "seg",
        options: ["on", "off"], labels: { on: "On", off: "Off" },
        hint: "Off makes switches and tabs change at once." }
    ]
  },
  {
    title: "About",
    items: [
      { key: "about", label: "About", kind: "about", hint: "The version, and more plugins." }
    ]
  }
];

// kept in the file but never shown
var hiddenItems = [
  { key: "startOpacity", kind: "steps", fallback: 0.95, min: 0.1, max: 1 },
  { key: "particleSizeMin", kind: "steps", fallback: 0.8, min: 0.3, max: 6 }
];

// ---------- ready made speeds ----------
var presets = [
  { key: "gentle", label: "Gentle", hint: "An hour, then half a day",
    set: { dustAfterMinutes: 60, settleMinutes: 720, minOpacity: 0.7, stages: 8, curve: "smooth",
           particleDensity: 0.15, particleOpacity: 0.55, powderDensity: 4, spiderMax: 1 } },
  { key: "normal", label: "Normal", hint: "20 minutes, then 3 hours",
    set: { dustAfterMinutes: 20, settleMinutes: 180, minOpacity: 0.55, stages: 8, curve: "smooth",
           particleDensity: 0.22, particleOpacity: 0.75, powderDensity: 8, spiderMax: 2 } },
  { key: "dramatic", label: "Dramatic", hint: "10 minutes, then an hour",
    set: { dustAfterMinutes: 10, settleMinutes: 60, minOpacity: 0.35, stages: 12, curve: "early",
           particleDensity: 0.5, particleOpacity: 0.9, powderDensity: 20, spiderMax: 3 } },
  { key: "demo", label: "Demo", hint: "Fully dusty in 2 minutes",
    set: { dustAfterMinutes: 0.25, settleMinutes: 1.5, minOpacity: 0.4, stages: 12, curve: "linear",
           particleDensity: 0.4, particleOpacity: 0.85, powderDensity: 14, spiderMax: 3 } }
];

function presetFor(key) {
  for (let i = 0; i < presets.length; i++) if (presets[i].key === key) return presets[i];
  return null;
}

// ---------- defaults and lookups, worked out once from the groups above ----------

var colorKeys = {};
var defaults = {};
var itemByKey = {};
var PAGE_KINDS = ["presets", "about", "windows"];

function addItem(item) {
  itemByKey[item.key] = item;
  if (PAGE_KINDS.indexOf(item.kind) !== -1) return;
  if (item.kind === "palette") {
    for (let t = 0; t < item.targets.length; t++) {
      const colorKey = item.targets[t].key;
      defaults[colorKey] = item.fallback[colorKey];
      colorKeys[colorKey] = item.fallback[colorKey];
    }
  } else {
    defaults[item.key] = item.fallback;
  }
}
for (let g = 0; g < groups.length; g++)
  for (let i = 0; i < groups[g].items.length; i++) addItem(groups[g].items[i]);
for (let h = 0; h < hiddenItems.length; h++) addItem(hiddenItems[h]);

// settings that only change how the panel and the button look: changing one never
// restarts the dust (no respawned particles, no window props set again)
var panelKeys = [];
for (let pg = 0; pg < groups.length; pg++) {
  if (groups[pg].title !== "Panel") continue;
  const its = groups[pg].items;
  for (let pi = 0; pi < its.length; pi++) {
    if (its[pi].kind === "palette") for (let pt = 0; pt < its[pi].targets.length; pt++) panelKeys.push(its[pi].targets[pt].key);
    else panelKeys.push(its[pi].key);
  }
}

var settingKeys = [];
for (const name in defaults) settingKeys.push(name);

function isSetting(key) { return settingKeys.indexOf(key) !== -1; }

// the setting for a key, or null (itemByKey["constructor"] is not one of ours)
function itemFor(key) {
  const item = itemByKey[key];
  if (item && typeof item === "object" && item.key === key) return item;
  return null;
}

function parseNum(value) {
  if (typeof value === "number") return value;
  if (typeof value === "string" && /^-?[0-9]{1,15}(\.[0-9]+)?$/.test(value.trim())) return parseFloat(value);
  return NaN;
}

function validHex(s) { return typeof s === "string" && /^#[0-9a-fA-F]{6}$/.test(s); }

// a window class as the exempt list keeps it: lower case, no spaces around, short
function className(v) {
  return Util.toText(v).replace(/[\u0000-\u001f\u007f<>]/g, "").trim().toLowerCase().slice(0, 80);
}

// Checks one value against its setting. Anything odd gives the default back, so a
// hand-edited window-dust.json can't break anything. Unknown keys give undefined.
function clean(key, value) {
  if (typeof colorKeys[key] === "string") {
    if (validHex(value)) return value.toLowerCase();
    return colorKeys[key];
  }
  const item = itemFor(key);
  if (item === null) return undefined;
  if (value === null || value === undefined) return Array.isArray(item.fallback) ? item.fallback.slice() : item.fallback;

  if (item.kind === "enum") {
    const t = Util.toText(value);
    return item.options.indexOf(t) !== -1 ? t : item.fallback;
  }
  if (item.kind === "steps" || item.kind === "int") {
    let n = parseNum(value);
    if (!isFinite(n)) return item.fallback;
    if (item.kind === "int" || item.round) n = Math.round(n);
    if (item.kind === "int" && item.step > 1) n = item.min + Math.round((n - item.min) / item.step) * item.step;
    if (n < item.min) return item.min;
    if (n > item.max) return item.max;
    return Math.round(n * 1000) / 1000;
  }
  if (item.kind === "bool") {
    if (value === true || value === "true") return true;
    if (value === false || value === "false") return false;
    return item.fallback;
  }
  if (item.kind === "color") {
    const c = Util.toText(value).trim();
    if (validHex(c)) return c.toLowerCase();
    if (/^[0-9a-fA-F]{6}$/.test(c)) return "#" + c.toLowerCase();   // the way 1.x saved it
    return item.fallback;
  }
  if (item.kind === "tags") {
    if (!Array.isArray(value)) return item.fallback.slice();
    const out = [];
    for (let i = 0; i < value.length && out.length < item.max; i++) {
      const s = className(value[i]);
      if (s !== "" && out.indexOf(s) === -1) out.push(s);
    }
    return out;
  }
  // text: no control characters and no < >, so it always shows as plain text
  let text = Util.toText(value).replace(/[\u0000-\u001f\u007f<>]/g, "");
  if (item.maxLength) text = text.slice(0, item.maxLength);
  if (key === "barIcon" && text.trim() === "") return item.fallback;
  return text;
}

// Settings saved by 1.x: theme follow / custom / mono / brown became colorMode
function migrate(obj) {
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) return {};
  const out = {};
  for (const k in obj) if (k !== "__proto__" && k !== "theme") out[k] = obj[k];
  if (obj.colorMode === undefined && typeof obj.theme === "string") {
    const map = { follow: "theme", custom: "custom", brown: "custom", mono: "monochrome" };
    if (map[obj.theme]) out.colorMode = map[obj.theme];
  }
  return out;
}

// The whole saved file -> every setting, checked, with defaults filled in
function resolve(saved) {
  saved = migrate(saved);
  const result = {};
  for (const key in defaults) {
    let value = saved[key];
    if (typeof value === "function") value = undefined;
    result[key] = clean(key, value);
  }
  // the first speck is never fainter than a fully dusty window
  if (result.startOpacity < result.minOpacity) result.startOpacity = result.minOpacity;
  if (result.particleSizeMax < result.particleSizeMin) result.particleSizeMax = result.particleSizeMin;
  return result;
}

// the settings that matter to the dust itself, as text, to tell real changes from
// panel-only ones
function engineKey(cfg) {
  const o = {};
  for (const k in cfg) if (panelKeys.indexOf(k) === -1) o[k] = cfg[k];
  return JSON.stringify(o);
}

function presetActive(cfg, preset) {
  for (const k in preset.set) if (cfg[k] !== preset.set[k]) return false;
  return true;
}

// ---------- showing numbers ----------

function duration(sec) {
  sec = Math.round(sec);
  if (sec < 60) return sec + "s";
  const m = Math.floor(sec / 60);
  if (m < 60) { const s = sec % 60; return s > 0 ? m + "m " + s + "s" : m + "m"; }
  const h = Math.floor(m / 60), r = m % 60;
  if (h < 48) return r > 0 ? h + "h " + r + "m" : h + "h";
  const d = Math.floor(h / 24), rh = h % 24;
  return rh > 0 ? d + "d " + rh + "h" : d + "d";
}

// short: without the unit, for the quick picks under a value that shows it
function format(fmt, v, short) {
  const n = typeof v === "number" ? v : parseNum(v);
  if (!isFinite(n)) return "?";
  if (short && (fmt === "density" || fmt === "kpx" || fmt === "px" || fmt === "pxs" || fmt === "fps"))
    return "" + parseFloat(n.toFixed(2));
  switch (fmt) {
  case "minutes": return duration(n * 60);
  case "percent": return Math.round(n * 100) + "%";
  case "density": return parseFloat(n.toFixed(2)) + " / kpx²";
  case "kpx": return parseFloat(n.toFixed(1)) + " / kpx²";
  case "px": return parseFloat(n.toFixed(1)) + " px";
  case "pxs": return parseFloat(n.toFixed(1)) + " px/s";
  case "fps": return Math.round(n) + " fps";
  default: return "" + parseFloat(n.toFixed(2));
  }
}

// the next value in a steps list from where v is now (v may sit between two)
function stepFrom(options, v, dir) {
  if (!options || options.length === 0) return v;
  if (dir > 0) {
    for (let i = 0; i < options.length; i++) if (options[i] > v + 1e-9) return options[i];
    return options[options.length - 1];
  }
  for (let j = options.length - 1; j >= 0; j--) if (options[j] < v - 1e-9) return options[j];
  return options[0];
}
