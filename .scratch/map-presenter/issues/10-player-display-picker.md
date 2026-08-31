# 10 — Player Display picker

Status: ready-for-human
Blocked by: 01

Choose which screen is the Player Display from the Control Window, and remember the choice across launches and replugs. Fills the hole `presentIfPossible()` leaves today: with two or more external screens the app presents nothing behind an orange "picker not built yet" badge. Deliberately the picker slice only — issue 05's unplug/replug lifecycle stays `wontfix`.

Behavior:

- The picker is always visible in the Control Window, in place of today's status badge, with the metrics line kept beneath it. Never a sheet: a modal that reappeared on every replug would fight the silent auto-recovery the spec promises.
- Candidates are every connected screen, the built-in included. Presenting on the built-in is a testing and preview convenience — True Scale is meaningless on a screen the players cannot see — but being unable to exercise the app without a TV attached is a standing tax.
- Entries are annotated with resolution and physical size, so two identical TVs are told apart by text. An "Identify" flash on each screen is a follow-up: it needs its own transient window per screen for a rare case.
- Selection policy, in order: an explicit choice for a connected screen wins; else a remembered screen that is connected; else the sole external screen; else nothing, and the picker waits. Two or more unrecognised screens never auto-present — that ambiguity is what this feature exists to resolve.
- The choice persists keyed by display UUID (`CGDisplayCreateUUIDFromDisplayID`), with `localizedName` stored alongside as a human label. `CGDirectDisplayID` is reassigned on replug and across reboots, so it cannot key persisted state.
- Choosing the only connected screen presents the Player window *below* the Control Window instead of above the menu bar. At `mainMenu + 1` with no other screen to relocate to (`controlWindowRelocation` returns nil), the controls would be buried and unreachable — the failure mode that made the Control Window non-closable in 549c03d.
- A screen whose EDID reports 0 mm is selectable with a warning marker, not hidden or disabled: hiding a screen the user can see plugged in is worse than presenting one whose scale needs Calibration.
- An explicit screen switch engages Blackout, left for the DM to lift — the spec's stated masking tool for transitions. Recorded as a decision only; Blackout is unbuilt (issue 07, wontfix).

Design:

- The selection rule is a pure function over value types — `DisplayIdentity`, not `NSScreen` — unit-tested the way `WindowLayout.controlWindowRelocation` is, with a thin `AppState` adapter left untested. The rule's branches are this feature's whole substance.
- Persistence is a small `DisplayPreferences` type wrapping `UserDefaults`, not a bare `@AppStorage`: `presentIfPossible()` reads it outside any view context. This is the app's first persistence of any kind. Shaped so issue 04's Calibration factor slots in later without a rewrite — but Calibration is not built here.
- `playerScreen` is `private(set)` and derived only inside `presentIfPossible()`; the picker needs a new settable chosen-display property that the policy consults.

Also in scope:

- Fix the false badge at `ControlView.swift:217`: the connected branch requires both `playerScreen` and `playerMetrics`, so a 0 mm EDID display is presented on while the badge reads "No Player Display connected" and `PlayerView` renders black. Branch on `playerScreen` alone; show "physical size unknown" for the metrics. Same lines this feature rewrites — a picker that then lies about the screen you picked is worse than the bug.
- Add a `--test-player-screen builtin` launch argument beside the existing `--test-map` seam, and drop `ModeButtonsUITests`' documented "Requires a connected Player Display" constraint.

Acceptance: with two external displays connected, the picker lists both and choosing one presents the map there; quit and relaunch with the same display attached → it is chosen again with no interaction; unplug it and attach a different single external display → that one auto-presents; attach two unrecognised displays → nothing presents and the picker waits; choose the built-in on a laptop with no external display → the map presents and the Control Window stays clickable.

## Comments

- 2026-08-31 (implementation): two design decisions from the grilling were wrong as written and were corrected against real hardware.

  **Q10's yield condition.** The issue framed the buried-controls danger as "the chosen screen is the only screen". The real condition is "the Control Window has nowhere to go", which `WindowLayout.controlWindowRelocation` already decides — it also returns nil when the window does not overlap the player screen. `moveBuriedWindows` now reports whether any window remains stranded and `present()` drops to `.normal` level on that, rather than counting screens. The `PlayerScreenPolicy.mustYieldToControlWindow` helper the issue called for was deleted: the decision belongs where the window facts are, not in the pure policy.

  **Q9's test seam.** `--test-player-screen builtin` assumed a built-in panel exists. The dev machine is a desktop with three externals and no built-in, so the seam resolved nothing and the tests still failed. Then `first` picked the screen the Control Window sits on, which relocated it mid-test and made every XCUITest click miss. The seam is now `--test-player-screen auto`: prefer a screen the Control Window is *not* on, falling back to the only screen there is (where the Map yields below the controls).

- 2026-08-31 (verified live, 3-external-display Mac): picker lists all three with resolution and physical size — "LG HDR 4K — 3840×2160 px 598×340 mm" vs "Virtual 16:9 — 3840×2160 px 530×298 mm", same resolution told apart by mm. With no choice made nothing presents and the guidance text shows; selecting LG HDR 4K presents there; quit and relaunch restores it with no interaction (`playerDisplayUUID` = 456A5014-…, matching the probed UUID). 44 unit + 2 UI tests pass.

- Not verified: replug behaviour (needs physical cable work) and the single-screen yield path (this machine cannot reach one screen). Both are the acceptance criteria left standing.
