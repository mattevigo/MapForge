# 04 — The Measurement Shape picker in the Control chrome

Status: ready-for-human
Blocked by: 02

Choosing between Cone, Square, Circle and Line.

## Not a context menu

Right-click starts a Measurement immediately with the last-used shape. The shape is chosen
from a control in the Control Window chrome, where every other object setting already lives
— pawn kind, light radii, all in inspector rows beside the preview
(`ControlView.swift:510-566, 816-846`), never on the map.

Two reasons. `ControlView.swift:604-609` records a deliberate refusal to add a competing
gesture on the token, citing four defects from gesture composition in this render layer; a
menu would be a fifth. And a sticky shape makes the common case — measuring the same spell
repeatedly through a fight — one right-click and one move, where a menu makes it a menu every
time.

## Build

A segmented `Picker`, following `FogTool`'s (`ControlView.swift:366-371`) — the established
idiom for a small exclusive choice in this window. `FogTool` (`FogOverlay.swift:8-29`) is
also the model for an enum carrying its own `label` and `hint` strings.

It belongs with the live-play controls (the `livePanel` column, `ControlView.swift:739-775`,
where Solo Sight lives), not the fog-authoring chrome — measuring is a play action.

Sticky within the session; no persistence, consistent with the Measurement itself.

**Disabled with no declared Grid**, reading its answer from the same availability function as
issue 02 rather than testing `hasDeclaredGrid` a second time. Follow
`SoloSightControl.availability`'s pattern of returning a reason, so the control can say why
it is unavailable rather than being mysteriously dead.

Changing the shape while a Measurement is on screen re-projects it in place — same Origin,
same distance, new shape. Cheap, and it is how a DM compares a cone against a circle from the
same pawn.

## Gotcha

Reserve the row's height unconditionally. Anything that appears and disappears in the outer
`VStack` resizes the `GeometryReader` the preview transform is measured against and makes the
map jump — `ControlView.swift:81-97` and the `fogInspectorRowHeight` at `:495` are the
existing workaround.

## Tests

- The shape is sticky across Measurements.
- Changing the shape re-projects an on-screen Measurement, preserving Origin and distance.
- Disabled without a declared Grid.

## Done when

Spec 2 is usable: all four shapes reachable, the last one used comes back.
