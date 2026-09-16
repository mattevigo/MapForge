# Pawns and Lights are authored in the Live View, not the Wall Editor

The `fog-of-war` spec drew a line down the middle of the app: "prep time is precise and
slow… at the table is fast and small. No geometry editing while five players watch." Walls,
Lights and Pawns were all authored on one side of it, in a single mode with a three-way tool
picker. This decision moves Pawns and Lights to the other side. Only Walls are authored in
the **Wall Editor** now; every Pawn and every Light is added, edited, moved and deleted in
the **Live View**.

## Why the line moved

The split was drawn around *precision*, and only Walls turned out to need it. A Wall vertex
is geometry — it snaps, it welds to its neighbours, it is worth an undo stack. A Pawn is a
token the DM shoves around mid-fight, and the app already treated it that way: dragging a
Pawn, toggling its torch, hiding it and renaming it were all live actions in the Live View
long before this change. Only *creating* one, and setting its colour, Kind, size and sight,
required leaving the table's view — so the line ran through the middle of a single concept.

That cost more than the mode switch. It meant two places to learn for one object, two undo
semantics for edits a DM could not tell apart, and — because a Pawn was editable on both
sides — a reconciliation mechanism (`carryLiveState`, `LivePawnEdit`) whose entire job was
stopping the Wall Editor's Cancel from clobbering live edits made while it was open. Moving
Pawn and Light authoring out deletes that mechanism rather than extending it.

Lights moved with Pawns even though the argument for them is weaker — a Light is positioned
against the Walls it is blocked by, which is an argument for authoring it beside them. The
deciding consideration was that a DM lights a room while looking at the room, and the Live
View is where the room is lit. Splitting the two would also have kept the tool picker alive
for a single remaining case.

## What it costs

Placing a Light is now something that happens while the table is watching. The `fog-of-war`
spec's promise that no authoring happens in front of players is not kept, and is not meant
to be: the Player Display shows the Map, and a Light Marker appearing on it is a thing the
table can see happen. That is accepted. It is cheaper than a DM alt-tabbing out of the game
to add a brazier, which is what the old line actually meant in practice.

Edits made in the Live View are **not undoable**, matching every other live action
(`CONTEXT.md`, **Pawn**). The Edit Pawn and Edit Light sheets buffer their fields and commit
on OK, so Cancel is the escape that undo would otherwise be. The Wall Editor keeps its undo
stack unchanged.

## Consequences

- `FogTool` and its segmented picker are deleted; the Wall Editor has one job and needs no
  tool selection.
- `carryLiveState(onto:)` and the `LivePawnEdit` OptionSet are deleted — with no Pawn or
  Light editing inside the Wall Editor, there is nothing to reconcile.
- Deleting a Pawn becomes reachable from the Live View, which it never was: `⌫`-after-select
  inside the fog mode was the app's only deletion path, and it leaves with the tools.
- The app gains its first modal sheets. The standing "this app has no modals" stance
  (`ControlView.swift`) held while every editor was one or two fields on a row that had to
  reserve constant height or the Map jumped mid-click. A six-field form is the case that
  stance was not written against.
