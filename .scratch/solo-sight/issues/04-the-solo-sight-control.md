# 04 — The Solo Sight control

Status: done

Blocked by: 01

One click in the live row, beside the eye, with radio-button semantics and honest disabled
states.

## What to build

**Where** — `ControlView.pawnLiveRow(_:)` (`ControlView.swift:599-640`), immediately after
the eye Toggle (`:625-638`). The row already carries the token/flame toggle, the rename
field and the eye; this joins it rather than starting a new row.

**Only on party Pawns.** A Creature emits no Light, so isolating one shows a black map. The
control does not appear in `lightLiveRow` and does not appear for `.creature` or
`.treasure`. "What does the dragon see" is a different feature.

**Radio-button semantics.** Pressing an inactive Pawn's control isolates it, moving the
isolation off whichever Pawn had it. Pressing the active one ends the mode. A `.button`-styled
`Toggle` like its neighbours, `isOn` bound to `appState.soloSightPawnID == pawn.id`.

**Icon** — filled when active, outline when not, so the DM reads the state rather than the
control, exactly as the eye does. `person.fill.viewfinder` / `person.viewfinder` is the
suggestion; anything that is not another eye and not another flame will do.

**Disabled, with a reason** — never silently inert:

| Condition | Help text |
|---|---|
| `pawn.isHidden` | Hidden from players. Show it to see the Map through its eyes. |
| `!appState.isFogOverlayOn` | Solo Sight needs the Fog Overlay on — there is no darkness to shrink. |
| `!appState.hasDeclaredGrid` | Same reason the fog itself is inert without a Grid. |

The first is the eye's guarantee winning, per ADR 0004: the mode does not override
`isHidden` and does not silently un-hide.

**Active help text** — say what the table is seeing, since this mode changes the Player
Display: *"Solo Sight. The table sees only what <label>'s own light reaches. Click to
end."*

**Legibility while active.** With one Pawn isolated, the other party Pawns' rows should
read as switched-out — de-emphasise their flame toggles or the rows themselves, so the DM
can see at a glance that the mode is on and who has it. A DM who forgets Solo Sight is
active will misread the Player Display, and that misreading happens in front of players.

## Scope

- One control per party Pawn row. No global "exit Solo Sight" button elsewhere, no menu
  item, no keyboard shortcut in this issue.
- No confirmation, no animation on entering or leaving.

## Acceptance

Clicking the control isolates that Pawn and the Player Display changes immediately; clicking
another Pawn's moves the isolation; clicking the active one restores the normal view. The
control is absent on Creatures and Treasures, and disabled with the stated reason on a
hidden Pawn, with the Fog Overlay off, and with no Grid declared. It never appears in the
undo stack and never writes a `.fog.json`. With the mode active it is visually obvious from
the live panel alone which Pawn holds it.
