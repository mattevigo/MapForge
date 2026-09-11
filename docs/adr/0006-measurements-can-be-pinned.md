# Pinning retires the one-Measurement-at-a-time rule

The Measurement feature shipped with "at most one exists at a time", and the reasoning was
borrowed from Solo Sight: ADR 0004 kept one `Pawn.ID?` rather than a set because "one
optional is a strict subset of a set of IDs and upgrades cleanly if a real use case
appears". The same sentence was written into `CONTEXT.md` and into the measurement spec.

The use case appeared. A DM comparing two spell areas, or holding the route a character
already walked while measuring what is left of their movement, needs both shapes on the Map
at once. **Pinning** is that upgrade: a settled Measurement can be parked, and any number of
pinned ones coexist with the one being taken.

## The live slot is unchanged

`AppState.measurement` is still a single optional. Everything that drives a Measurement —
the click that places its Origin, the mouse that aims it, the digits typed into it, the
click that settles it — still has exactly one unambiguous subject, which is the property the
original rule was actually protecting. Pinning moves a finished Measurement *out* of that
slot rather than making the slot plural.

That is why this is not the "multi-select isolation" case ADR 0004 deferred for Solo Sight.
Solo Sight's question is which Pawn the fog is computed from, and two answers to that
require a second lighting pass. Two Measurements require a second polygon.

## Only a settled Measurement pins

A Measurement still following the cursor is not an answer yet, so pinning one would park
whatever the DM happened to be dragging. The pin action is therefore unavailable until the
click that settles it — which also means the gesture reads as "I am done with this one,
keep it".

## Pinned Measurements are shown to the table

They follow ADR 0005 rather than making a new rule: the Player Display shows what the table
is entitled to know, and the DM pinned this one precisely so the table could keep seeing it.
A pin that were DM-only would be a private annotation, which is a different feature and one
nobody asked for.

## Consequences

`Measurement` gains an identity, because two pins of the same shape and distance from the
same Origin are a real thing to have on the Map and could not otherwise be told apart.
`==` deliberately excludes it: every existing caller asks "has this changed", and an id in
the comparison would make every copy unequal to itself.

Pinned Measurements invalidate exactly as the live one does — cleared on a Map switch, on
entering fog editing, and individually when an anchoring Pawn is deleted. A pin does not
make a stale anchor any less stale, and `fog`'s `didSet` is where both are dropped, for the
reason recorded there: a reference into a document needs the document to invalidate it.

Nothing is persisted. A pin survives the next click, not the next session — the same posture
as the Fog Overlay switch and Solo Sight, and for the same reason: nobody wants to reopen a
Map tomorrow and find last week's fireball still on it.

Right-click becomes context-sensitive: over a Measurement it offers pin or unpin, over open
Map it offers the shape list. That is a fourth meaning for the button, after "open the shape
menu", "finish a chain" and "disarm the tool", and each is resolved by what is under the
cursor or what state the tool is in. It is the cost of keeping the whole interaction on the
Map rather than in the window chrome.

## Considered Options

- **Keep one Measurement and let the DM re-measure** — the status quo, and it is what the
  original rule assumed a DM would do. Rejected because comparing two areas is not
  re-measuring: the comparison *is* the question, and it cannot be asked one shape at a time.
- **A pinned Measurement replaces the live slot rather than a second list** — rejected: it
  makes "one pinned plus one live" the ceiling for no saving, since the drawing path has to
  handle a collection either way.
- **Pin from the window chrome instead of the shape's own context menu** — rejected for the
  reason the shape picker moved onto the Map: the DM is already pointing at the shape they
  mean, and a chrome control makes them say which one.
- **Persist pins in `<map>.fog.json`** — rejected. It would make a Measurement authored data
  alongside Walls and Lights, which is exactly what `CONTEXT.md` says it is not.
