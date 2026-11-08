# Changelog

All notable changes to Window Dust. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [2.0.1] - 2026-11-08

### Fixed

- Settings tabs now share the tab row equally, regardless of their label lengths.

## [2.0.0] - 2026-11-04

### Added

- A new settings panel: seven tabs (Windows, Dust, Look, Particles, Behavior, Panel,
  About), a search over every setting, **Changed only**, a reset arrow on each row,
  and **Pop out** to turn it into a window of its own.
- The Windows tab: every window with a dust meter and how long it has been left alone,
  and buttons to wipe it, dust it at once, or never dust it.
- Colors: **Follow theme**, **Window borders**, **Custom** and **Monochrome**.
- **Stay behind windows in front**: a floating window or a shell panel over a dusty
  one stays clean.
- **Never dust floating windows**.
- **Frames per second** for the moving dust.
- Right and middle click on the button can be set.
- Commands: `omarchy-shell io.github.qempexe.window-dust windows | settings | clean |
  pause | resume | toggle | preset <name> | status`.
- A logo, light and dark, and an About tab.

### Changed

- The dust runs once for all bars and screens, as a service. With a bar on each screen
  it used to run once per bar.
- Each dusty window is drawn on canvases of its own size, and nothing is drawn while no
  window is dusty. The windows are read rarely while nothing moves.
- The dust sits under the shell's own panels and popups, and goes while a workspace
  slides in or out.
- A wiped window's dust is seen flying off before it goes.
- The never-dusted list is edited with chips and a field, with suggestions.

### Fixed

- **Follow theme** took no accent on Omarchy 4.5, where the theme moved.
- On Omarchy 4.5 the panel could fail to open, where the bar window spans the screen.
- Focusing a window showed no scatter: its dust was gone before it could fly off.

## [1.0.0] - 2026-10-13

### Added

- A themed popup panel with Windows and Settings tabs, presets and live-reloaded
  settings.
- The dust layer, spiders and fibres.
- **Hide in fullscreen**.

## [0.2.0] - 2026-10-02

### Fixed

- Particles now follow a window that moves or is resized.
- Cobwebs scale with the window.
- Particles no longer show on the wrong screen.

## [0.1.0] - 2026-10-02

### Added

- First release: windows that gather dust, and a bar button.
