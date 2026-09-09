# 03 — Tokens follow the light

Status: ready-for-agent

Blocked by: 02

While Solo Sight is on, a party Pawn is drawn to players only where the remaining light
reaches it — the rule Creatures already follow. This is the half of the feature that makes
it a per-observer view rather than a dimmer switch.

## What to build

**One function, more inputs.** `PlayerVisibility.showsToPlayers` (`PlayerVisibility.swift:26`)
stops being a pure function of a Pawn and takes the solo state and the lit regions as well.
Do **not** add a second type consulted alongside it: two functions answering "what do
players see" is how the two screens drift apart, which is the divergence `PawnToken`'s own
comment exists to prevent. `PlayerVisibility` stays a pure enum so the whole rule remains
testable without a window.

The rule, in order:

1. **`isHidden` still wins.** Rule 1 is untouched — a hidden Pawn is absent whatever the
   light and whatever the mode.
2. **The isolated Pawn is always drawn.** It is the subject of the mode; a mode named after
   a Pawn where that Pawn can vanish is a bug report waiting to happen. Special-case it
   *before* the light test, so a flame-off isolated Pawn standing in the dark is still on
   screen.
3. **Every other Pawn is discovered by light** — drawn where `Visibility.level(at:)` at its
   point is bright or dim, absent where unlit. Dim reveals, for the reason the `creatures`
   spec already gives: 5e treats dim light as lightly obscured, not as blindness.
4. **Creatures and Treasures are unchanged.** They already follow rule 3 always. Under Solo
   Sight they simply have less light to be found by, which falls out for free.

**Control Window unchanged in kind.** `isDimmedForDM` (`PlayerVisibility.swift:38-42`) grows
to cover Pawns the table has lost to Solo Sight, so `PawnLayer` (`PawnLayer.swift:32`) and
`FogOverlay` (`FogOverlay.swift:210`) draw them at 0.4 rather than removing them. The DM
sees every Pawn, always — "a DM as blind as the players cannot run the game" — and now sees
*which* ones the table has lost. That readout is most of the mode's value to the DM.

## Scope

- Party Pawns only change behaviour, and only while the mode is on. With no isolated Pawn,
  `showsToPlayers` must return exactly what it returns today.
- Revealed by the Pawn's **point**, not its footprint, including for a Big Pawn —
  consistent with every other reveal in the app.
- No fade, no animation, no partial draw at the edge of a radius.

## Acceptance

With Solo Sight on *P*: a party Pawn inside *P*'s reach is on the Player Display; one
around a corner, in a wall-shadowed region, is not; one standing in a brazier-lit room is,
because Map Lights are not isolated. *P* itself is on screen in every case, including with
its own flame off and no Map Light near it. A hidden Pawn stays off screen throughout. The
Control Window shows all of them, the invisible ones dimmed. Turning the mode off restores
every token immediately. With no isolated Pawn, existing `PlayerVisibility` tests pass
unchanged.
