# 06 — Escape cancels fog mode

Status: ready-for-agent

A one-line inconsistency, found while inventorying the mode bar. Independent of everything
else here; bundled because it is the same kind of defect.

## The problem

Two of the three modes let `Esc` cancel them. One does not.

| Mode | Cancel | Shortcut |
|---|---|---|
| Grid Fit | `ControlView.swift:506-507` | `.keyboardShortcut(.cancelAction)` |
| Viewport | `:511-512` | `.keyboardShortcut(.cancelAction)` |
| Fog | `:527` | **none** |

`Done` is consistent across all three (`.defaultAction` at `:509`, `:514`, `:529`). Only fog's
`Cancel` is bare, and fog mode is the one a DM is most likely to want out of in a hurry.

## Build

Add `.keyboardShortcut(.cancelAction)` to the fog `Cancel` button — **but not naively.**

`Esc` already has a meaning inside fog mode: it cancels an in-progress wall chain
(`FogOverlay.swift:114`). Those two meanings must nest rather than collide:

- **A chain is drawing** (`chain.isDrawing`, `FogOverlay.swift:59`) → `Esc` cancels the chain
  and stays in fog mode.
- **No chain is drawing** → `Esc` cancels fog mode, exactly as it does in the other two.

That ordering is the only sensible one — a DM three points into a wall does not want a stray
`Esc` to discard the whole editing session — but it must be deliberate, because SwiftUI's
`.cancelAction` and the overlay's own `.onKeyPress` will otherwise both fire and the result
depends on which view has focus.

**Related, and worth checking while here**: `.scratch/measurement/issues/06-cleanup-after-shipping.md`
(`needs-triage`) records that **right-click carries four meanings** — open the shape menu,
finish a chain, disarm an armed tool, pin/unpin — and that "it grew one meaning at a time
rather than being designed that way. Worth revisiting if it reads as unpredictable in play."
`Esc` is now heading the same way. Do not fix right-click in this issue, but if the fog `Esc`
nesting turns out to need a third case, that is the signal to raise the measurement issue
rather than to add it quietly.

## Tests

- `Esc` mid-chain cancels the chain and fog mode is still active.
- `Esc` with no chain drawing leaves fog mode, discarding edits exactly as the `Cancel` button
  does.
- `Esc` in Grid Fit and Viewport still behaves as it does today.

## Done when

`Esc` means the same thing in all three modes, and means the narrower thing first when a wall
chain is open.

## Comments
