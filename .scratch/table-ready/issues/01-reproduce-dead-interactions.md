# 01 — Reproduce the dead interactions

Status: ready-for-human

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

## Comments

- 2026-09-02 (grilling session): created via /grilling. The session established that wall deletion and pawn labels are both already implemented, which turned the feature from four builds into two builds and two diagnoses. The two questions this issue answers — what happened on a delete attempt, and how snapping misbehaved — are the two the DM could not answer from memory.
