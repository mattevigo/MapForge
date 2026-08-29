# 05 — Player Display window lifecycle

Status: ready-for-agent
Blocked by: 04

Borderless fullscreen window (no menu bar/dock, black background) on the external display showing only the Map at True Scale. Exactly one external display → auto-present there; 2+ → picker. Observe display connect/disconnect: on unplug keep all state in the app model and show a "no player display" badge in the Control Window; on replug restore the window with identical Map/Viewport/rotation/Blackout state.

Acceptance: plug in HDMI → map appears fullscreen; yank the cable and reconnect → same view returns; Mac's own display never shows the player window.

## Comments

- 2026-08-29 (bug fix, landed early on feature/viewport-panning): presenting the Player window buried any app window left on that screen — the Control Window restored fullscreen on the external display, the Player window covered it above the menu bar, and every control became unclickable (reported as "the buttons don't work" / a perceived crash). `present()` now relocates windows off the target screen first (`WindowLayout.controlWindowRelocation`, unit-tested) and is idempotent: the `NSHostingView` is built once instead of on every `squaresWide`/`viewportOrigin` didSet (once per drag tick). The hosting-view churn itself has no unit-test seam (AppKit window internals) — verified live via scripted UI drive; this issue should re-verify on real unplug/replug.
