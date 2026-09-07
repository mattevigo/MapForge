# 03 — Hiding a Creature

Status: done

Let the DM take a Creature off the Player Display without deleting it, from the live row.

## What to build

**Model** — `Pawn` gains `var isHidden = false`.

**Player Display** — hidden beats lit. A hidden Creature is absent whatever the
Visibility at its point and whatever the Fog Overlay's state. That is the point of the
control: it is the DM saying "not yet", and a monster that reappeared because someone lit
a torch would defeat it.

**Control Window** — still visible to the DM, de-emphasised, exactly as an unlit Creature
is. The DM must be able to see and move a hidden ambusher.

**Live toggle** — in `ControlView.lightToggles` (`:497`), beside the Fog switch and the
Light and Pawn toggles. Not undoable: it writes straight to `AppState.fog` through a
sibling of `setPawnLight`, for the reason that method already states — a live performance
action, and filling the undo stack with toggles buries the DM's authoring work.

The row already carries a `PawnToken` and a rename field per Pawn (`pawnLiveRow`, added by
`table-ready` issue 05). The hide control joins that row rather than starting a new one.

**Placement** — a way to place a Pawn *as* a Creature. Simplest is a "Creature" toggle
beside the Pawns tool in the fog mode, applied to newly placed Pawns and settable on the
selected one from `pawnInspector`. Deliberately not a fourth tool: the placement gesture,
dragging, labels and colour are identical, and `FogTool` is about what a click places.

## Scope

- One boolean. No "hidden from player X", no reveal scheduling, no fade.
- Hiding is available for any Pawn, not only Creatures — a DM may want a party token off
  the screen too. It simply matters far more for Creatures.

## Acceptance

Toggling a Creature off removes it from the Player Display immediately, in bright light,
with the Fog Overlay both on and off. It stays visible and dimmed on the Control Window.
The state survives a relaunch. Toggling is not undoable and does not appear in the fog
undo stack.
