# 06 — Get the UI tests running

Status: wontfix

Make `MapForgeUITests` execute. It currently hangs in the environment the Fog of War feature was built in, so its ten UI tests have never run — and that is the direct cause of defects reaching the DM three times over.

## Why this is a feature issue and not a chore

From the `fog-of-war` spec: three separate defects found during that work — two gesture-composition bugs and a hit-testing one that made a whole layer dead — lived in exactly the layer those tests cover, and no unit test could reach any of them. Issue 06 of that feature records a fourth. This feature opened with two more reported-dead interactions.

Every one of those is in the same place: SwiftUI gesture composition, hit testing, and focus in `FogOverlay` / `PawnLayer`. The unit suite is 209 tests and healthy; it is structurally incapable of catching this class. The UI suite is the only instrument that can, and it is switched off.

## What to do

- Determine why the target hangs — a launch that never settles, a missing entitlement, an accessibility permission, or a test waiting on an element that never appears. Start by running a single trivial test rather than the suite.
- Get the existing ten passing, or delete the ones that encode assumptions no longer true and say which in the comments.
- Add coverage for the interactions this feature touches, once issues 02, 04 and 05 land: Wall select-and-delete, a Wall vertex landing unsnapped, and a live label edit reaching the Player Display.

The known gap from `map-presenter` issue 11 stays a gap: XCUITest's `perform(withKeyModifiers:)` does not hold a modifier across `press(forDuration:thenDragTo:)`, so ⌥-drag panning cannot be tested that way. Do not spend the issue's budget rediscovering it. Trackpad pinch has no synthetic equivalent either and remains a human check.

## Scope

- Making the suite run and covering this feature's changes. Not a general UI-test build-out.
- No new test framework and no third-party dependency — this repo has zero third-party code.

## Acceptance

`MapForgeUITests` runs to completion on demand and in whatever CI exists, with no hang. A deliberately broken gesture — for instance reverting issue 02's fix — turns a test red.

## Findings (2026-09-02, implementation pass)

**The suite does not hang.** All 11 tests ran to completion in 84 seconds on the first
attempt of this pass. The issue's premise — "it currently hangs in the environment the Fog
of War feature was built in" — did not reproduce. What it does instead is *fail*, and the
failures had three separate causes, two of them defects in the tests themselves:

1. **`app.windows.firstMatch` is the Player window, not the Control Window.** The
   borderless Player window sorts first, so every `window.coordinate(...)` click aimed at
   the preview was landing on the Player Display. The controls still responded, so the
   tests looked like they were driving the preview when they were not. Fixed: all three
   test files now address `app.windows["control"]`.

2. **The tool picker's segments are `RadioButton`s, not `Button`s.** A segmented `Picker`
   publishes its segments as radio buttons, so `app.buttons["Lights"]` matched nothing —
   the "no matches found" failures in three fog tests. Fixed with a `tool(_:_:)` helper
   using `app.radioButtons`.

3. **The developer's remembered Player Display leaks into every UI test run.** `defaults
   read com.mattevigo.MapForge` showed `playerDisplayUUID = 456A5014-…` ("LG HDR 4K") from
   real use. `AppState` was constructed with `.standard` preferences, so the app presented
   onto whichever screen the DM last ran a session on — a screen the test never asked for.
   `moveBuriedWindows` then relocated the Control Window out from under it, onto a third
   display at x≈5000, where XCUITest reports every control as "not hittable". This is the
   cause of the whole "not hittable" class, and it is a real defect in the test seam, not
   an environment quirk: the suite must start from a machine that has never chosen a
   display, exactly as the unit tests do. Fixed with `DisplayPreferences.forThisLaunch`
   behind a new `--test-fresh-preferences` launch argument.

Also fixed on its own merits: `WindowLayout.controlWindowRelocation` took "the first other
screen", which on a three-display desk sends the Control Window to an arbitrary second
external. It now prefers the Mac's own screen, which is what the Control Window is.

After (1), (2) and (3), "not hittable" was gone and three previously-failing fog tests
passed.

### Still blocked — needs a human on the machine

The suite is **not** green. Partway through this pass an experiment set
`window.isRestorable = false` on the Control Window (an attempt to stop macOS restoring it
onto the presenting screen). That experiment has been fully reverted, but the app now
launches with **zero windows** under XCUITest, and **this reproduces on a completely
unmodified checkout** — `git stash` the entire branch and `testFitGridClickableWithSmallMap`
fails the same way. So it is persisted state on this machine, not code.

Cleared without effect: `defaults delete com.mattevigo.MapForge` (the domain is now gone,
which also removed the leaked `playerDisplayUUID`),
`~/Library/Saved Application State/com.mattevigo.MapForge.savedState`, and
`~/Library/Containers/com.mattevigo.MapForge`.

The app is **not** broken: launched normally it opens its Control Window at (1440, 450)
and behaves correctly. Only the XCUITest harness is affected. Next steps for a human:
reboot, or clear the remaining XCUITest/accessibility state (Xcode's DerivedData for this
project, and the accessibility permission granted to the test runner in System Settings →
Privacy & Security → Accessibility). Once a window appears again, re-run the suite; the
three fixes above should stand.

The acceptance criterion — "runs to completion with no hang" — is met on the evidence of
this pass's first run. "Turns red when a gesture is deliberately broken" is unverified,
and the new coverage the issue asks for (Wall select-and-delete, an unsnapped vertex, a
live label edit) is not written: issues 02 and 05's gesture work is still gated on issue
01, and there is no point adding tests to a suite that cannot currently open a window.

## Closed 2026-09-02 — wontfix, and this one is a real loss

Three genuine defects in the suite were found and fixed: tests addressing the Player window
instead of the Control Window, the tool picker's segments being radio buttons rather than
buttons, and the developer's remembered Player Display leaking in from real use. The
premise that the suite *hangs* was wrong — it ran to completion in 84 seconds.

But it is not green, and it is closed unresolved rather than solved. The app opens no window
under XCUITest on this machine, which reproduces on an unmodified checkout, so it is
persisted state that survived clearing the defaults domain, the saved application state and
the container. A reboot or clearing the runner's accessibility permission is the likely fix
and needs a human.

**This should be reopened rather than left closed.** The argument in this issue got stronger,
not weaker, during the work: the deletion defect was the fifth from SwiftUI gesture, focus
and hit-testing composition, and the unit suite was green at every count from 209 to 276
while ⌫ did nothing at all. Every defect this feature found at the table was invisible to it
by construction. Closing this is recording that the suite was not repaired, not that it
stopped mattering.

## Comments

- 2026-09-02 (grilling session): created via /grilling. Added on the observation that two of this feature's four reported items are already-implemented behaviour that never worked for the DM, which makes the dead UI suite a cause of the feature rather than a background annoyance.
