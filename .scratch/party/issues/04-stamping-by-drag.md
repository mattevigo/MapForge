# 04 — Stamping a Character onto the Map by drag

Status: ready-for-agent

Depends on: 01, 02, 03

The payoff: drag a Character from the Party group onto the preview and a Pawn appears.

Note this is the app's **first** drag-and-drop. Nothing in the repo uses `Transferable`,
`onDrop`, `NSItemProvider` or `UTType` — every existing "drag" is an in-view `DragGesture`.
Greenfield, with no house style to match.

## Build

**The payload.** A `Transferable` carrying the `Character.ID` under a private `UTType`
(`com.mapforge.character-id`), declared in `Info.plist`/`project.yml` as an exported type. A
private type means a stray file or text dropped on the preview is refused by the type system
rather than by hand-written validation. Deployment target is macOS 15
(`project.yml`), so `.draggable` / `.dropDestination` are available with room to spare.

**The source.** `.draggable` on each Character row from issue 03.

**The target.** `.dropDestination` on the *ordinary* preview — the same surface `PawnLayer`
draws on, not `FogOverlay`. Stamping is **live**: no mode, works during play, and is not
undoable. It follows `movePawn`, not `addPawn`. See ADR 0007 for why.

**The coordinates.** The drop point comes in the preview's space; `PawnLayer` already owns
the inverse of `PlayerPlacement` for exactly this (`PawnLayer.swift:63-65`) — reuse that
arithmetic rather than deriving it twice, and be careful to measure in the layer's own named
coordinate space, which is the bug recorded in the comment at `PawnLayer.swift:54-56`.

Placement is **free-form**, under the cursor, with no Grid snapping — consistent with
click-to-place (`FogOverlay.swift:341`), with dragging a Pawn, and with Line measurements.

**Out of bounds.** A drop resolving outside the Map's image pixels creates nothing. Not a
clamp — a refusal. A Pawn outside the image is meaningless to Visibility, whose four implicit
boundary Walls sit at exactly those bounds.

**The stamp.** Build the Pawn from the Character: `label` = name, `colorHex`, `brightSquares`
= sightSquares, `isBig`, `kind = .player`, `isHidden = false`, `characterID` = the
Character's id. `light.dimSquares` is re-derived, never set — `Pawn.dimSquares(forSight:)`
(`FogDocument.swift:214`). The same Character may be stamped repeatedly; duplicates share a
label and are **not** auto-renamed.

**Persistence.** Flush on drop rather than waiting out `FogAutosave`'s 0.5 s debounce — a drop
is one completed action, so reuse the `onCommit` path a drag-end already takes
(`PawnLayer.swift:67-70`).

## Tests

- A drop inside the image creates exactly one Pawn, at the expected image pixel for a known
  preview geometry, with every field taken from the Character.
- A drop outside the image creates nothing.
- The drop works with no fog-editing mode active, and leaves `FogEdits` untouched — ⌘Z after
  a stamp does not remove the Pawn.
- Stamping the same Character twice yields two Pawns with the same label and distinct ids.
- The Pawn reaches disk without waiting out the debounce.
- A stamped Pawn's Light matches a hand-placed Pawn of the same sight — the feature must not
  create a second way for a Pawn to be lit.

## Done when

A DM defines a Party once and starts a session by dragging its Characters onto the Map.
