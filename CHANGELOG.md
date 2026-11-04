## 1.0.0

- New panel: its own popup window with a header card (on/off switch, status, close), Windows and Settings tabs, and a footer. Click outside or press Esc to close
- Settings are now built from `Settings.js` and saved by `SettingsStore.qml` to the same `~/.config/omarchy/window-dust.json`; the file is watched, so hand edits apply live
- Theme setting: Follow Omarchy (the bar's own colours plus your theme's accent), Custom (starts from a warm brown) or Monochrome
- Preset chips, a hex field for the dust colour, a never-dusted list you can type into, a configurable bar icon and an option to hide the dusty count
- New effect: **dust layer**, a fine powder over the whole window with a haze that settles toward the bottom and in the corners
- New effect: **spiders** that crawl across dusty windows, pause, turn, and run from the focus point when you focus a window
- New effect: **fibres** (drifting lint)
- New settings: dust layer amount, spiders per window; presets set them too
- Dust now disappears while a window is fullscreen and returns afterwards (new setting **Hide in fullscreen**, on by default)
- Settings changes that only affect looks (theme, bar icon) no longer respawn the particles
- `Foreground.qml`, `FieldBox.qml`, `FlatButton.qml` and `SectionLabel.qml` added; `Chip.qml` and `SettingStepper.qml` removed
- Existing settings and dust state carry over unchanged; an old `brown` theme setting is read as Custom

## 0.2.0

- Fix particles not following window move/resize
- Scale cobweb radius proportionally on resize instead of keeping spawn-time size
- Fix multi-monitor leaking (particles on wrong screen)
- Widen Hyprland event coverage and add 1.5 s heartbeat poll
