# MapForge v2 — Fog of War

Status: implemented — needs a human pass on real hardware

Walls, Lights and Pawns authored on a Map at prep time; a Fog Overlay on the Player Display showing the resulting darkness, toggled and adjusted live at the table.

Vocabulary: see [CONTEXT.md](../../CONTEXT.md) — **Wall**, **Light**, **Pawn**, **Visibility**, **Fog Overlay**. Architecture decisions: [docs/adr/0002-cpu-visibility-polygons.md](../../docs/adr/0002-cpu-visibility-polygons.md).

## What this is, and what it is not

This is a **lighting simulation**. Walls block Light, Lights illuminate, the Fog Overlay is the computed darkness. It is deliberately not the two other things that share the name "fog of war":

- Not **hand-painted reveal** — the DM never brushes regions hidden or visible; darkness is derived, never drawn.
- Not **dynamic per-observer vision** — there is no "who is looking" and no memory of what has been explored. Visibility is a pure function of Walls, Lights and Pawns, so the same inputs always give the same result. All players share one Player Display, where party-union vision and "what the Lights reach" look near-identical anyway.

That choice is what collapses a Pawn's range of sight into its range of illumination: with no per-observer masks, a Pawn that sees 30 ft and a Pawn that lights 30 ft are the same object.

## Authoring vs. play

**Prep time** is precise and slow: a new Control Window editing mode beside the existing `gridFit` and `viewport` modes, with the zoom and pan `PreviewTransform` already provides. Wall vertices snap; Lights and Pawns get placed and named.

**At the table** is fast and small: toggle Lights on and off, drag Pawns, kill the Fog Overlay. No geometry editing while five players watch.

## The model

A **Wall** is an independent two-sided segment. The DM draws chained polylines for convenience, but storage is flat segments — two-sided blocking means there is never an inside or outside to get wrong. Walls are stored in **image pixels**, so re-running Grid Fit rescales their physical meaning without moving them relative to the artwork. Four implicit Walls at the image bounds are always present, not editable and not deletable: they close every visibility polygon and stop Light spilling into the letterbox.

A **Light** has a position (image pixels), a bright radius and a dim radius (**Grid squares** — physical, unlike Walls), and an on/off state. Dim defaults to twice bright, matching the 5e convention, so a torch is just "20".

A **Pawn** is a Light with a label and a colour. It is drawn on the Player Display whether or not the Fog Overlay is active — a labelled coloured token is useful on its own.

**Visibility** is three-valued: bright, dim, unlit. It is computed in Map space when Walls, Lights or Pawns change, and never on a Viewport pan.

## Rendering

Exact segment visibility polygons on the CPU, drawn with `SwiftUI.Canvas` and blend modes — see the ADR. Shadow edges at Walls are hard; the only softness is a gradient at each Light's range limit, so a torch fades out instead of ending in a suspicious circle.

The **Player Display** shows the Map with the Fog Overlay composited over it: unlit regions black, dim regions partially darkened. The **Control Window** shows the same Visibility as a translucent tint over a fully-lit Map — the DM must never be as blind as the players.

## Persistence

Per-Map fog data lives in `<map>.fog.json` next to the image. The app is ad-hoc signed with no App Sandbox, so writing beside a user-picked image needs no security-scoped bookmarks.

**Known tension**: `CONTEXT.md` names the **Sidecar** (`<map>.mapforge.json`) as the home for per-Map metadata, but issue 03 that would have built it is `wontfix`. A separate fog file was chosen deliberately rather than reopening it. The consequence is accepted: `squaresWide` is still in-memory only, so after a relaunch a DM has their Walls back but not their Grid — and Light radii, being in squares, have no physical meaning until it is re-entered. If the Sidecar is ever built, the two formats merge.

## Scope

In: Walls with snapping, Lights with bright/dim radii and toggling, Pawns with label and colour, the Visibility engine, the Fog Overlay and its off switch.

Out: doors (a Wall that toggles passable — cheap to add later on this model), per-Pawn vision and explored-area memory, coloured Lights, soft area shadows, image-analysis Wall detection, Wall import from VTT formats.

## Context

The `map-presenter` tracker is closed out. Issues 02–07 are `wontfix`: there is no Library, no Calibration, no Blackout, no rotation, and no persistence beyond two `UserDefaults` strings. This feature is large relative to the app it lands on, and adds the first user-authored data the app has ever saved.

## Status, 2026-09-02

All six issues implemented and merged to `develop`. 203 unit tests.

**Not verified anywhere in this effort**: the `MapForgeUITests` target hangs in the environment the feature was built in, on `develop` as well as on every feature branch, so its ten UI tests have never run. That matters more here than the count suggests — three separate defects found during the work (two gesture-composition bugs and a hit-testing one that made a whole layer dead) lived in exactly the layer those tests cover and that no unit test can reach. Running them is the first thing worth doing.

Also unverified on real hardware: True Scale against a ruler with the overlay active, and whether the DM's tint is readable on an actual Control Window rather than in theory.
