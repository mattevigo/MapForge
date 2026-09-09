# MapForge v3 — Table Ready

Status: closed 2026-09-02 — 01, 03, 04 done; 05 substantially done; 02, 05's follow-up and 06 wontfix

Four things that stood between the DM and running an actual session, collected after the first real use of the Fog of War feature. The name is the acceptance bar: not "these four diffs landed" but "a game ran and nothing got in the way".

Vocabulary: see [CONTEXT.md](../../CONTEXT.md) — **Grid**, **Grid Fit**, **Wall**, **Light**, **Pawn**, **Sidecar**, **Calibration**.

## What this is

A polish pass, but not a uniform one. The four reported items turned out to be four different kinds of problem, and that finding shapes the whole feature:

| Reported | Reality |
|---|---|
| "delete already placed walls" | **Already built.** Click a Wall, press ⌫; undoable; the hint text says so. Never once verified in a running app. |
| "pawns should have editable labels" | **Already built.** Model, rendering on both screens, an inspector `TextField`, undoable. Unreachable at the table and invisible at small zoom. |
| "grid fit should persist per screen" | **Genuinely missing**, by an explicit `wontfix`. And "per screen" is the wrong axis — see below. |
| "never snap to the grid" | **Half true.** Pawns already do not snap. Walls and Lights snap to the Grid *and* to Wall endpoints. |

Two of the four are features that exist in the code but did not exist for the DM. That is the same failure mode the Fog of War feature already recorded four times, and this feature treats it as a first-class problem rather than a coincidence.

## Diagnose before redesigning

Wall selection is a child `TapGesture` inside a `ForEach`, competing with the parent's `exclusively` gesture chain, gated by `.allowsHitTesting` and by `@FocusState`. Four defects in this app have come from exactly that construct, every one invisible to the unit suite, all of them in a layer whose UI tests have never run.

So a reported-missing feature is a bug report until proven otherwise. Issue 01 reproduces on the real app first; issues 02 and 05 build on what it finds. Building a new deletion affordance on top of a dead gesture would bury the defect rather than fix it.

**This was right, and the reason was wrong.** Issue 01 found deletion dead — vindicating the whole approach — but not in the gesture. Selection worked. `FogOverlay` is a `ZStack` whose children are every one `.position()`-placed, so it has no hit-testable region for `.focusable()` to attach to and could never hold focus at all: `.onKeyPress(.delete)` never fired and ⌫ simply beeped. Fifth defect from this shape, the same one that stopped an `NSViewRepresentable` getting a frame in Grid Fit.

Two lessons worth carrying forward. **The distinguishing evidence was a sound** — a beep means AppKit found no responder, which is a different fact from focus going elsewhere, and no amount of reading the code separates those two. **And the plausible fix was wrong**: making the selection gesture claim focus looks obviously correct and changes nothing, because the view it focuses cannot accept focus. In this layer, prefer the mechanism already proven to reach it — a local event monitor — over the idiomatic one.

## "Per screen" is Calibration, and Calibration is not in scope

`squaresWide` is the only input that pins a Map's physical size — `physicalWidthInches = squaresWide`. The display contributes separately, through `pointsPerInch` derived from EDID. A Map that is 30 squares wide is 30 inches wide on every screen; that is the True Scale invariant the app is built on.

So "Grid Fit should persist depending on the screen" is two wants wearing one sentence:

1. *Stop making me re-fit the Grid on every launch* — per-Map persistence. **In scope** (issue 03).
2. *The size is wrong on my TV specifically* — that is **Calibration**, whose `calibrationFactor` exists in `DisplayMetrics`, is hardcoded to `1`, and has no storage and no UI because `map-presenter` issue 04 is `wontfix`. **Out of scope**, and a feature in its own right: it needs a ruler-measurement flow and a real per-UUID keyspace, since `DisplayPreferences` today stores one flat UUID, not a dictionary.

If a physical ruler check on the Player Display comes out wrong once the Grid persists, that is the signal to reopen Calibration.

## The Sidecar decision, reversed

`FogDocument.swift` states that `.fog.json` is deliberately *not* the Sidecar, and that `squaresWide` staying in memory is an accepted consequence. This feature reverses that, because the consequence turned out not to be acceptable and the reasoning had a hole in it.

`Light.brightSquares` and `Pawn`'s range are stored in **Grid squares**. The Grid is not stored at all. So a relaunch already restores Lights with radii in a unit that no longer exists — `AppState.litRegions` returns empty and the DM sees a warning. The two halves of one measurement were already split across a file and a process lifetime.

Putting the Grid in `.fog.json` (version 2) rejoins them. A separate `<map>.mapforge.json` would leave one measurement in two files that can drift apart, for the sake of a boundary that stopped being real once radii were denominated in squares. Recorded as [ADR 0003](../../docs/adr/0003-grid-in-the-fog-file.md).

`map-presenter` issue 03 stays `wontfix`: rotation and gridless physical width are still unbuilt, and this does not build them.

## Snapping

Three mechanisms are tangled in the report, and only one goes:

- **Grid snapping** — a vertex rounds to a Grid intersection. **Removed**, for Walls and Lights. It welds geometry to a lattice that (until issue 03) did not survive a relaunch, and the DM asked for it to stop.
- **Endpoint snapping** — a new vertex welds to an existing Wall endpoint. **Kept.** It is what makes a hand-traced room watertight, and `testATracedRoomIsWatertight` is the acceptance test for the whole Wall feature. It is also not "the grid" in any sense the DM would have perceived.
- **The 45° angle constraint** — on by default, ⇧ frees it. **Untouched by the decision, under suspicion by issue 01.** It is not snapping, but "walls will not go where I point" feels identical from the DM's chair.

Pawns already do not snap. No change.

## Authoring vs. play, revisited

Fog of War drew the line sharply: geometry editing is prep-time, and at the table you toggle Lights, drag Pawns, and kill the Overlay. That line holds, with one deliberate crossing: **a Pawn's label becomes editable during play**.

A label is not geometry. Renaming "3" to "Goblin B" mid-fight is the same *kind* of act as moving a Pawn — live, small, immediate — so it follows `movePawn`'s existing precedent exactly: it writes straight to `AppState.fog` and is **not undoable**. The mode-local fog undo stack cannot unwind past what the mode opened with, so there is no stack for a live edit to land in anyway.

Everything else — Wall, Light and Pawn deletion, geometry, colour, radii — stays inside Fog editing mode.

## Scope

In: reproducing the reported-dead interactions on real hardware; removing Grid snapping; persisting the Grid per Map in `.fog.json` v2; live Pawn label editing; making labels legible at small sizes; de-emphasising inactive object kinds; getting `MapForgeUITests` to run.

Out: Calibration and the ruler flow; the `<map>.mapforge.json` Sidecar, rotation and gridless physical width; redo (there is still only undo); Pawn or Wall editing during live play beyond the label; any new authoring tool.

## Issues

1. [01 — Reproduce the dead interactions](issues/01-reproduce-dead-interactions.md)
2. [02 — Wall deletion, made real](issues/02-wall-deletion-made-real.md)
3. [03 — Persist the Grid in the fog file](issues/03-persist-the-grid.md)
4. [04 — Remove Grid snapping](issues/04-remove-grid-snapping.md)
5. [05 — Pawn labels at the table](issues/05-pawn-labels-at-the-table.md)
6. [06 — Get the UI tests running](issues/06-ui-tests-running.md)

## Closed 2026-09-02

The acceptance bar was "not these four diffs landed, but a game ran and nothing got in the
way". The four things that got in the way are fixed. What is left open is recorded as
`wontfix` with reasoning, not forgotten.

### What the four reports turned out to be

The spec opened by claiming two of the four were already-built features the DM could not
reach. That was half right, and the half it got wrong is the most useful thing here.

| Reported | Spec's guess | What it actually was |
|---|---|---|
| delete already placed walls | built but undiscoverable | **built and broken.** `FogOverlay` could never hold keyboard focus, so ⌫ beeped and did nothing |
| pawns should have editable labels | built but unreachable at the table | **right** — plus invisible below 16 pt, which no one had noticed |
| grid fit should persist per screen | genuinely missing | **right**, and "per screen" was Calibration, correctly split out |
| never snap to the grid | three mechanisms, only one goes | **right** — and grid snap turned out not to be load-bearing for watertightness after all |

Two more defects surfaced that nobody reported: a Pawn's "Sight" field wrote only the bright
radius, so the outer circle sat fixed at twice whatever the Pawn was first created with; and
`isEmpty` would have deleted the fog file of a DM who fitted the Grid and stopped.

### The lesson that generalises

**Four separate reports of "please add X" were X existing but broken or unreachable.** The
spec named this failure mode and still under-diagnosed it: it assumed discoverability where
the truth was a runtime defect. "A reported-missing feature is a bug report until proven
otherwise" was the right instinct and did not go far enough — *reproduce before deciding
which kind of missing it is*, because the two have opposite fixes and feel identical from
the DM's chair.

**The distinguishing evidence was a sound.** A beep means AppKit found no responder; silence
would have meant focus went elsewhere. No amount of reading the code separates those, and
the first fix — making the selection gesture claim focus — was plausible, obvious and
useless, because the view it focused could not accept focus.

**The unit suite was green throughout**, 209 tests to 276, while wall deletion did not work
at all. Every defect this feature found was found by a human at the app. That is issue 06's
argument, and closing 06 unresolved is the one real loss here.

## Assumptions

Recorded from the grilling session on 2026-09-02, where two questions could not be answered from memory. Correct these by editing rather than by conversation:

- ~~**What happened when a Wall was clicked for deletion is unknown**~~ — **answered
  2026-09-02**: it highlighted and ⌫ beeped. Not one of the four guesses. `FogOverlay`'s
  `.position()`-based `ZStack` cannot hold focus at all, so `.onKeyPress(.delete)` never
  fired. Fixed via a local event monitor. See issue 01's findings.
- **How snapping misbehaved is still unknown** — the session went to deletion and never
  exercised drawing. Grid snap is gone regardless (issue 04), so the remaining candidate is
  the **45° angle constraint**. Needs a separate sitting at the app.
