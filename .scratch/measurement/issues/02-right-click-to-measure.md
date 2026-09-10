# 02 — Right-click to start and dismiss, with the Pawn-anchored Origin

Status: ready-for-agent
Blocked by: 01

The interaction. Right-click on the normal-mode mirror starts a Measurement at that point;
right-click on a Pawn starts it at that Pawn; right-click again dismisses it.

## The two things `.normal` does not have yet

Both are built here. They are the accepted cost of putting this feature where it belongs
(see the spec).

**An absolute view→map inverse.** `PreviewTransform.imagePoint(from:)` exists but serves the
fog/grid-fit preview only. The mirror uses `PlayerPlacement.viewPoint` forward, and
`PawnLayer.swift:63-64` open-codes a *delta* inverse inside the drag. Add the named inverse
of `PlayerPlacement.viewPoint(_:map:frame:)` and use it in both places, so the mirror has one
conversion rather than two.

**Continuous hover.** `.onContinuousHover` exists only in `FogOverlay` (`:98-103`); the
mirror gives no mouse-move feedback at all. Add it, storing the cursor the same way, so the
shape can follow the cursor live.

## The gesture

Right-click is unused everywhere in the target — no `.contextMenu`, no `rightMouseDown`, no
`NSMenu` — so nothing is being displaced.

`FogOverlay.swift:86-97` and `ControlView.swift:604-609` are the warnings that matter:
chained `.gesture()` calls do not compose, the outermost wins, and this render layer has
produced four defects that way. `PawnLayer` already owns a left-drag on the token, and child
gestures beat ancestor gestures.

So: **one** right-click handler on the mirror that hit-tests Pawns itself, rather than a
second gesture attached to the token. Hit a Pawn → `.pawn(id)` Origin. Otherwise →
`.point(mapPoint)`.

Right-click while a Measurement exists dismisses it, whatever it hits. Modal and
unambiguous — no "dismiss which?" because there is only ever one.

## State and its self-invalidation

A `@Published var measurement: Measurement?` on `AppState`, beside `isFogOverlayOn`
(`AppState.swift:242`) and `soloSightPawnID` (`:252`) — transient, never persisted, reset on
launch.

Follow `soloSightPawnID`'s **`resolved…` guard** pattern (`AppState.swift:276-280`) for the
Pawn-anchored case: never read a stale `Pawn.ID` directly. A Measurement anchored to a Pawn
follows it as it is dragged, and ends when the Pawn does. Clear the Measurement on the same
events Solo Sight clears on — map switch (`:189`), entering fog editing (`:400`), and the
`fog` `didSet` (`:64-66`) for deletion.

**Availability.** No declared Grid → no Measurement; right-click does nothing. Model it as a
pure function like `SoloSightControl.availability(for:isFogOverlayOn:hasDeclaredGrid:)`
(`SoloSightControl.swift:40-49`) so it is testable and so the picker in issue 04 can disable
itself from the same answer.

## Tests

- Right-click on empty map yields a point Origin at the right map pixel; on a Pawn, that
  Pawn's Origin.
- Second right-click clears, wherever it lands.
- Dragging an anchored Pawn moves the Measurement with it.
- Deleting the anchor Pawn, switching Map, and entering fog editing each clear it.
- No declared Grid → right-click is inert.
- The new inverse round-trips against `PlayerPlacement.viewPoint`.

## Done when

A Measurement can be started, anchored, moved and dismissed. Nothing is drawn yet — verify
through state, not pixels.
