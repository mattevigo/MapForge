# 01 — Reproduce the dead interactions

Status: done

Establish, by driving the real app, what actually happens when the DM tries to delete a Wall and when they draw one. Two of this feature's four reported items are for behaviour that is already implemented, so the first job is finding out whether the code is dead at runtime or merely unreachable.

This issue is **ready-for-human**, not `ready-for-agent`: it is an observation task on real hardware with a real map, and its output is a written finding that shapes issues 02, 04 and 05.

## Why this comes first

Wall selection is a child `TapGesture` inside a `ForEach`, competing with the parent's `exclusively` gesture chain (`FogOverlay.swift:88-92`), gated by `.allowsHitTesting(tool == .walls && !chain.isDrawing)` (`:136`) and by `@FocusState` (`:64`, set in `place()` and `.onAppear`).

Four defects in this app have come from that exact construct — two gesture-composition bugs, a `hitTest` override that muted `scrollWheel`, and an `NSViewRepresentable` that never got a frame — and every one of them was invisible to the unit suite. The `fog-of-war` spec and its issue 06 both record this. Building a new deletion affordance without checking first would bury a fifth.

## What to determine

**Wall deletion.** In Fog editing mode with the **Walls** tool active, click an existing Wall:

- Does it highlight (accent colour, stroke width 4 vs 2.5)?
- If it highlights, does ⌫ delete it?
- Does it behave differently right after drawing a chain vs. on a Wall from a loaded `.fog.json`?
- Does it behave differently with a *different* tool active? All three object kinds are always drawn, but only the active tool's kind is clickable — so a Wall click while the Pawns tool is active is silently inert by design.

**Wall drawing.** Draw a chain across open artwork:

- Does the vertex land where the pointer is, or somewhere else?
- If it moves, which of the three mechanisms is responsible — the 45° angle constraint (`WallSnap.constrainAngle`, on by default, ⇧ frees it), endpoint snap (welds to a nearby Wall end, green indicator), or Grid snap (rounds to a lattice intersection, secondary-colour indicator)? The `snapIndicator` at `FogOverlay.swift:259-272` distinguishes the last two by colour.
- Is the effect present when no Grid is declared? Grid snap cannot fire without one (`ControlView.swift:331-336`), so if the pull persists on an undeclared-Grid Map, it is the angle constraint or endpoint snap.

**Light and Pawn deletion.** Same select-then-⌫ path, same cascade in `deleteSelected()` (`FogOverlay.swift:373-384`). Confirm whether they work, since a failure in all three points at the shared key handler or focus, while a Wall-only failure points at the per-Wall `TapGesture`.

## Acceptance

A `## Findings` section appended to this file recording, for each of the above, what was observed — enough that issue 02 knows whether it is fixing a bug or building an affordance, and issue 04 knows whether removing Grid snap is sufficient or whether the angle constraint is also implicated.

## Findings (2026-09-02, on the real app)

Driven on the Gnoll Lair map — 7 Walls, 1 Pawn, a Grid fitted at 31.97116 squares.

**Wall deletion was dead, and the cause was not any of the four this issue guessed at.**

- **Selection works.** Clicking a Wall with the Walls tool active highlights it: accent
  colour, stroke width 4 against orange 2.5. The child `TapGesture` inside the `ForEach`
  fires and sets `selectedWall`. The construct this issue was most suspicious of — the one
  behind four previous defects — is healthy.
- **⌫ did nothing, and produced the system beep.** That beep is the finding. It is AppKit
  reporting that *no responder consumed the key*, which is a different fact from "the
  overlay lost focus to something else". The overlay was never accepting focus at all.
- **Cause: `FogOverlay` is a `ZStack` whose children are every one `.position()`-placed,**
  so the stack has no hit-testable region of its own for `.focusable()`/`.focused()` to
  attach to. `.onKeyPress(.delete)` therefore never fired for a selection made by clicking.
  This is the same geometry that stopped an `NSViewRepresentable` ever getting a non-zero
  frame in Grid Fit — recorded at `ScrollWheel.swift:6-8`, and the reason scroll-wheel
  handling uses a local event monitor instead. **Fifth defect from this shape.**
- **Lights and Pawns had the same failure** for the same reason — a shared cause, as this
  issue predicted a shared failure would indicate, though it pointed at the key handler
  rather than at focus never being acquired.

A first wrong fix is worth recording, because it is the trap: making the selection gesture
set `focused = true` looks obviously right and changes nothing, because the view it focuses
cannot hold focus. The beep is what distinguishes the two hypotheses, and only a human at
the app could report it.

**Fix:** `DeleteKey.swift` — a local `NSEvent` monitor, the mechanism already proven to
reach this layer. Guarded twice, because a monitor is process-global: it declines when
nothing is selected, and never claims ⌫ while the first responder is an `NSText`/
`NSTextView`, so typing in "Grid squares wide" or a Pawn label is untouched.
`.onKeyPress(.delete)` is kept alongside — if focus ever does land there it consumes the
event first. Confirmed working on the real app.

**Wall drawing / snapping: not established.** The session went to deletion and the
snapping question was not exercised. Issue 04 removed Grid snapping regardless, which was
unconditional. Whether the 45° angle constraint is what the DM experienced as "walls will
not go where I point" is **still open** — it is the remaining candidate now that Grid snap
is gone, and it wants a separate sitting.

### Consequences for other issues

- **Issue 02 is a bug fix, not an affordance change** — and the bug is now fixed. What
  remains of it is the discoverability half: de-emphasising inactive object kinds and
  hover feedback on Walls. Both stand on their own merits.
- **Issue 05's token-anchored popover** was gated on "if issue 01 finds the existing
  gesture layer healthy". The *gesture* layer is healthy; the *focus* layer was not. A
  popover does not need focus the way a key handler does, so this is not blocked — but the
  caution that made the live-row `TextField` the chosen route is vindicated, not weakened.
- **Issue 06 gains its sharpest evidence yet.** The unit suite was 243 tests and green
  through every step of this, including while deletion was completely dead. Only driving
  the real app found it, and only a human could report the beep that identified it.

## Comments

- 2026-09-02 (grilling session): created via /grilling. The session established that wall deletion and pawn labels are both already implemented, which turned the feature from four builds into two builds and two diagnoses. The two questions this issue answers — what happened on a delete attempt, and how snapping misbehaved — are the two the DM could not answer from memory.
