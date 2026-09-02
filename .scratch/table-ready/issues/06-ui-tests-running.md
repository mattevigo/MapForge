# 06 — Get the UI tests running

Status: ready-for-agent

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

## Comments

- 2026-09-02 (grilling session): created via /grilling. Added on the observation that two of this feature's four reported items are already-implemented behaviour that never worked for the DM, which makes the dead UI suite a cause of the feature rather than a background annoyance.
