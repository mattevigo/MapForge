# MapForge v1 — Map Presenter

Status: ready-for-agent

Native macOS app (Swift/SwiftUI, AppKit where needed; deployment target macOS 15; personal Xcode build) that presents DnD battle Maps on an HDMI-attached Player Display at True Scale, driven from a Control Window on the Mac's own display.

Vocabulary: see [CONTEXT.md](../../CONTEXT.md). Architecture decisions: see [docs/adr/](../../docs/adr/).

## Maps & Library

- A Map is a raster image (PNG/JPEG/WebP) in the Library — a user-chosen watched folder, scanned recursively.
- The map picker is a thumbnail grid grouped by subfolder (the user's folder organization is the navigation).
- Physical size derives from the Grid: the user types squares-wide (1 square = 1 inch physical, the DnD 5 ft convention); height follows from aspect ratio. A toggleable overlay in the Control Window verifies grid alignment. Gridless maps take a directly entered physical size (width) instead.
- Per-Map settings (Grid, rotation, scale mode) persist in a Sidecar `<map>.mapforge.json` next to the image, written once, reused every session.

## True Scale

- Default physical size of a display comes from EDID via `CGDisplayScreenSize`.
- Calibration corrects lying TVs: the app shows a bar of nominal length on the Player Display; the user measures it with a real ruler and types the actual length in **centimeters**. The correction factor is saved in app preferences keyed by display identity. Grid squares stay in **inches**.

## Control & presentation

- Control Window shows the entire Map scaled to fit, with a draggable Viewport frame showing exactly what players see. Pan is free-form (no grid snap), applied live to the Player Display, no animation.
- Rotation: 90° steps, persisted in the Sidecar.
- Map switching is live — selecting a Map immediately replaces the Player Display content. Blackout (plain black) is the masking tool for transitions. Letterbox around a Map smaller than the screen is plain black.

## Player Display lifecycle

- Exactly one external display connected → the player window goes fullscreen there automatically (borderless, no menu bar/dock). Two or more → a picker.
- Unplug/replug auto-recovers: state (Map, Viewport, rotation, Blackout) lives in the app, and the window is restored when the display returns. While disconnected, the Control Window shows a "no player display" badge.
- App relaunch restores the last session — same Map, Viewport, rotation — with Blackout engaged so players never see anything unchosen.

## v1 scope

In: Pan, Blackout, Rotation.
Out (v2 candidates): fog of war, player-side grid overlay, zoom override, staged presentation, custom blackout image, visual grid-drag entry.
