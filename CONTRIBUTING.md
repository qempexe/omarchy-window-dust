# Contributing to Window Dust

Everyone taking part is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

Bug reports and ideas are welcome as [issues](https://github.com/qempexe/omarchy-window-dust/issues).
For a bug, the Omarchy version, what you did and the lines from
`qs log -p "$OMARCHY_PATH/shell" --tail 100` that mention `window-dust` help most.

## How it fits together

- `qml/Service.qml` runs once, whatever the number of bars and screens. It reads the
  windows with `hyprctl`, keeps the dust clock, tells Hyprland the fade and the tint,
  moves the particles and makes one overlay per screen.
- `qml/js/Model.js` is the dust itself, with no QML and no I/O: how dusty a window is,
  the Hyprland commands, which windows cover which, and every kind of particle.
- `qml/js/Schema.js` is every setting: its tab, label, hint, default and range. The
  panel builds its rows from it, and `resolve()` checks window-dust.json against it.
- `qml/overlay/Overlay.qml` draws: for each dusty window on its screen, a dust layer
  canvas (drawn when the dust changes) and a specks canvas (drawn every frame while
  there is moving dust).

## Adding a setting

1. Add an item to the right group in `qml/js/Schema.js`: `key`, `label`, `kind`,
   `fallback`, a short `hint`, and the range or options. The row, the search, the reset
   arrow, the saved value and its checking all come from that.
2. Use it through `cfg.<key>` in `Model.js` or the overlay.
3. Run the tests.

`key` is what gets saved in people's settings. It never changes once released; a label
can.

## Adding a kind of dust

1. In `Model.js`, add it to `enabledKinds()` and give it its start in
   `spawnParticles()` and its motion in `stepParticles()`.
2. Draw it in `drawParticle()` in `Overlay.qml`, with the dust color it is given.
3. Add an `effect…` switch for it in `Schema.js`.

Keep it cheap: it is drawn up to sixty times a second for every speck, so no gradients
per speck where a plain fill will do, and no loops over pixels.

## Testing

```bash
node tests/test_model.js
```

Then copy the plugin to `~/.config/omarchy/plugins/io.github.qempexe.window-dust`, run
`omarchy restart shell`, pick **Demo**, and look at it on a dark and a light theme, with
the bar on the top and on a side, and with a floating window over a dusty one.

## Style

- JavaScript is modern (`const`, `let`, arrow functions). Names other files read stay
  top-level `var` or `function`, which is how a `.pragma library` file shares them.
- Text from windows (titles, classes) is shown as plain text only.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, one line each.
