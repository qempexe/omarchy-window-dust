.pragma library

// What the Settings tab shows, in order. The panel builds its rows from this list.
//
//   group        heading the row sits under (a header is added when it changes)
//   key          the setting's name in window-dust.json
//   type         boolean | stepper | enum | string | color | palette | preset | tags | actions | number
//   label        short name; description is one line under it
//   defaultValue must equal Model.DEFAULTS (tests/schema.test.js checks this)
//   options      enum: the values; stepper: Model.OPTIONS[key] is used
//   labels       enum: the shown names, same order as options
//   fmt          stepper: how the number is shown (see Model.formatSetting)
//   showWhen     only while the theme is this value
//   requires     "particles" or "away": only while that switch is on
//   virtual      not a stored setting (preset chips, palette picker, buttons)
//   ui: "hidden" stored and validated, but no row (file-only keys)

var PALETTE = [
    "#1c1210", "#141414", "#000000", "#2b2b2b",
    "#e9dcc8", "#e0e0e0", "#ffffff", "#8b8378",
    "#c8905a", "#d4a35a", "#e06c75", "#98c379",
    "#56b6c2", "#61afef", "#c678dd", "#aaaaaa"
]

var SCHEMA = [
    // ── Theme ──
    { group: "Theme", key: "theme", type: "enum", label: "Colours",
      description: "Follow Omarchy uses the bar's own colours and your theme's accent. Custom starts from a warm brown.",
      options: ["follow", "custom", "mono"],
      labels: ["Follow Omarchy", "Custom", "Monochrome"], defaultValue: "follow" },
    { group: "Theme", key: "palette", type: "palette", virtual: true, showWhen: "custom",
      label: "Custom colours", description: "Pick Background, Text or Accent, then a swatch or a hex code." },

    // ── Preset ──
    { group: "Preset", key: "preset", type: "preset", virtual: true,
      label: "How fast dust settles", description: "Sets timing, fade and particle density together." },

    // ── Timing ──
    { group: "Timing", key: "dustAfterMinutes", type: "stepper", fmt: "minutes",
      label: "Dust starts after", description: "How long a window stays untouched before the first speck.",
      defaultValue: 20 },
    { group: "Timing", key: "settleMinutes", type: "stepper", fmt: "minutes",
      label: "Settles fully over", description: "How long dust then takes to reach its maximum. This is the speed.",
      defaultValue: 180 },
    { group: "Timing", key: "stages", type: "stepper", fmt: "int",
      label: "Stages", description: "Visible steps from clean to fully dusty. More is smoother.",
      defaultValue: 8 },
    { group: "Timing", key: "curve", type: "enum", label: "How dust settles",
      description: "The shape of the build-up over time.",
      options: ["smooth", "linear", "early", "late"],
      labels: ["Smooth", "Linear", "Early", "Late"], defaultValue: "smooth" },

    // ── Look ──
    { group: "Look", key: "minOpacity", type: "stepper", fmt: "percent",
      label: "Fades down to", description: "Inactive opacity of a fully dusty window.",
      defaultValue: 0.55 },
    { group: "Look", key: "dustColor", type: "color",
      label: "Dust colour", description: "Colour of the particles and the border tint.",
      defaultValue: "8b8378" },
    { group: "Look", key: "tintBorder", type: "boolean",
      label: "Border tint", description: "Tint the inactive border as well as fading the window.",
      defaultValue: true },

    // ── Effects ──
    { group: "Effects", key: "effectPowder", type: "boolean", label: "Dust layer",
      description: "A fine powder of dust over the whole window, heaviest at the bottom and in the corners.",
      defaultValue: true },
    { group: "Effects", key: "effectSpiders", type: "boolean", label: "Spiders",
      description: "Small spiders that crawl across a dusty window and scurry off when you focus it.",
      defaultValue: true },
    { group: "Effects", key: "effectFibers", type: "boolean", label: "Fibres",
      description: "Loose strands of lint that drift and turn slowly.", defaultValue: true },
    { group: "Effects", key: "effectMotes", type: "boolean", label: "Motes",
      description: "Drifting specks with a faint halo.", defaultValue: true },
    { group: "Effects", key: "effectGrain", type: "boolean", label: "Grain",
      description: "Tiny sharp static flecks.", defaultValue: true },
    { group: "Effects", key: "effectSmudges", type: "boolean", label: "Smudges",
      description: "Large soft grime blobs.", defaultValue: true },
    { group: "Effects", key: "effectStreaks", type: "boolean", label: "Streaks",
      description: "Falling drips.", defaultValue: true },
    { group: "Effects", key: "effectCobwebs", type: "boolean", label: "Cobwebs",
      description: "Thin arcs in a window corner, only at high dust.", defaultValue: true },

    // ── Particles ──
    { group: "Particles", key: "particles", type: "boolean", label: "Particle overlay",
      description: "Draw dust over windows. Off keeps only the fade and border tint.",
      defaultValue: true },
    { group: "Particles", key: "powderDensity", type: "stepper", fmt: "kpx", requires: "particles",
      label: "Dust layer amount", description: "Fine specks per 1000 px\u00b2 at full dust.", defaultValue: 8 },
    { group: "Particles", key: "spiderMax", type: "stepper", fmt: "int", requires: "particles",
      label: "Spiders per window", description: "The most spiders one large window can have.", defaultValue: 2 },
    { group: "Particles", key: "particleDensity", type: "stepper", fmt: "density", requires: "particles",
      label: "Density", description: "Particles per 1000 px\u00b2 of window area.", defaultValue: 0.22 },
    { group: "Particles", key: "particleMax", type: "stepper", fmt: "int", requires: "particles",
      label: "Max per window", description: "Hard cap, so a huge window stays cheap.", defaultValue: 240 },
    { group: "Particles", key: "particleSizeMax", type: "stepper", fmt: "px", requires: "particles",
      label: "Speck size (max)", description: "Largest mote radius.", defaultValue: 2.6 },
    { group: "Particles", key: "particleDrift", type: "stepper", fmt: "pxs", requires: "particles",
      label: "Drift speed", description: "Base random-walk speed.", defaultValue: 4 },
    { group: "Particles", key: "particleOpacity", type: "stepper", fmt: "percent", requires: "particles",
      label: "Brightness", description: "Multiplier on top of the dust level.", defaultValue: 0.75 },
    { group: "Particles", key: "particleTwinkle", type: "boolean", requires: "particles",
      label: "Twinkle", description: "A subtle brightness pulse per particle.", defaultValue: true },
    { group: "Particles", key: "hideOnFullscreen", type: "boolean", requires: "particles",
      label: "Hide in fullscreen", description: "No dust on a screen while one of its windows is fullscreen; it returns afterwards.",
      defaultValue: true },
    { group: "Particles", key: "scatterOnFocus", type: "boolean", requires: "particles",
      label: "Scatter on focus", description: "Blow the dust outward when a window is focused.",
      defaultValue: true },

    // ── Away and exempt ──
    { group: "Away and exempt", key: "pauseWhenAway", type: "boolean",
      label: "Pause dust while away", description: "The dust clock stops while you are idle or locked.",
      defaultValue: true },
    { group: "Away and exempt", key: "awayMinutes", type: "stepper", fmt: "mins", requires: "away",
      label: "Away after", description: "Idle time before you count as away.", defaultValue: 5 },
    { group: "Away and exempt", key: "exempt", type: "tags",
      label: "Never dusted", description: "Window classes that never gather dust. Press Enter to add one, click one to remove it.",
      defaultValue: ["mpv", "vlc", "spotify"] },

    // ── Bar ──
    { group: "Bar", key: "barIcon", type: "string", maxLength: 8,
      label: "Bar icon", description: "Text or glyph shown in the bar.", defaultValue: "\uDB80\uDCE2" },
    { group: "Bar", key: "barShowCount", type: "boolean",
      label: "Show dusty count", description: "The number of noticeably dusty windows next to the icon.",
      defaultValue: true },

    // ── Reset ──
    { group: "Reset", key: "actions", type: "actions", virtual: true,
      label: "Housekeeping", description: "Reset puts every setting back to its default." },

    // ── file-only (validated, no row) ──
    { group: "File", key: "enabled", type: "boolean", ui: "hidden", defaultValue: true },
    { group: "File", key: "startOpacity", type: "number", ui: "hidden", defaultValue: 0.95 },
    { group: "File", key: "particleSizeMin", type: "number", ui: "hidden", defaultValue: 0.8 },
    { group: "File", key: "customBackground", type: "string", ui: "hidden", defaultValue: "#1c1210" },
    { group: "File", key: "customText", type: "string", ui: "hidden", defaultValue: "#e9dcc8" },
    { group: "File", key: "customAccent", type: "string", ui: "hidden", defaultValue: "#c8905a" }
]
