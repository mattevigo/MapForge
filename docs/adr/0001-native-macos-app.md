# Native macOS app, not web/Electron

MapForge's defining requirement is True Scale: rendering a Map at its exact physical dimensions on the Player Display. Only native macOS APIs (`CGDisplayScreenSize`, `NSScreen`) expose a display's physical size and identity, and native gives first-class multi-display fullscreen control. We build a Swift/SwiftUI macOS app rather than a web app or Electron shell, accepting macOS lock-in for a personal tool that only runs on a Mac anyway.

## Considered Options

- **Plain web app** — rejected: browsers cannot know a display's physical size, so True Scale would always require manual calibration, and fullscreen-on-a-chosen-display is fragile.
- **Electron/Tauri** — rejected: needs native shims for the one feature that matters most; heavier runtime for no gain.
