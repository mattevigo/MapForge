# 02 — Naming a Light

Status: ready-for-agent

Auto-naming on placement, and the two places the DM retypes it. Depends on 01.

## What exists

**Placement**: `FogOverlay.place(...)` (`FogOverlay.swift:361-371`), on a click with the Lights
tool. It already copies the previous Light's radii:

```swift
case .lights:
    selectedLight = nil
    let point = MapPoint(transform.imagePoint(from: location))
    let previous = lights.last
    edits.addLight(Light(at: point,
                         brightSquares: previous?.brightSquares ?? 4,
                         dimSquares: previous?.dimSquares))
```

The Pawn equivalent one case above calls `Pawn.nextLabel(after: pawns)` at `:355`.

**The live row**: `lightLiveRow` (`ControlView.swift:1549-1571`) — a flame toggle, then
`Text("Light \(number)")` at `:1563`, a spacer, and the radii with a `.help`. Available in
every mode.

**The fog inspector**: `lightInspector` (`:1575-1606`) — "Bright:" and "Dim:" fields, 52pt
each. Only shown when `mode == .fog && tool == .lights` (`:1577`), inside the fixed-height
`ZStack` at `:153-157`.

**The Pawn precedent, in both places**:

| | Pawn | Route | Undoable |
|---|---|---|---|
| Fog inspector | `ControlView.swift:893-898` | `FogEdits.setPawnLabel` (`FogEdits.swift:111-113`) | yes |
| Live panel row | `ControlView.swift:1011-1016` | `AppState.setPawnLabel` (`AppState.swift:519-523`) | no |

## Build

**`Light.nextName(after:)`**, mirroring `Pawn.nextLabel(after:)` (`PawnToken.swift:139-151`).
Read that implementation first — it is written specifically to not reuse a number after a
delete, which is the whole defect being fixed here. Called from `FogOverlay.swift:361-371`
beside the radii copying.

**The live row becomes editable.** Replace `Text("Light \(number)")` at `:1563` with a
`TextField` bound the way the Pawn row's is (`:1011-1016`), routed through a new
`AppState.setLightName` beside `setLight` (`AppState.swift:330-334`). Keep `number` for the
accessibility identifier at `:1561` — see the spec's exclusions.

**Falling back when the name is nil**: show `"Light \(number)"` as the placeholder, so an
unnamed Light still reads sensibly. The field is `String?` at the model level; the binding
turns `nil` into `""` and `""` back into `nil` rather than storing an empty string.

**The inspector gains a name field**, prepended to `lightInspector`, routed through a new
`FogEdits.setLightName` beside `setLightRadii` (`FogEdits.swift:73-78`) — undoable, and
following `setPawnLabel`'s `editPawn` → `record()` shape.

**Check `fogInspectorRowHeight`.** It is 24 (`ControlView.swift:874`), reserved
unconditionally so selection does not make the preview jump (`:867-873`). Adding a field to
the Light inspector may or may not exceed it — `FogInspectorRowHeightTests` has a
`LightInspectorRow` mirror view at `:38-51` and asserts the constant fits both inspectors
(`:59`) and is not needlessly tall. **Update the mirror, then let the test tell you** whether
the constant moves. Do not eyeball it.

**Live renames must survive a fog-edit session.** `AppState.carryLiveState`
(`AppState.swift:661-665`) preserves Pawn live edits across entering and leaving fog mode via
`recordLiveEdit(.label)`, and **currently carries Pawn state only**. A live Light rename needs
equivalent handling or it will be silently discarded the next time the DM opens fog editing.
If extending `carryLiveState` proves invasive, the fallback is to route the live rename through
`FogEdits` as well and accept that it is undoable — but say so in the comments, because it
breaks the symmetry with Pawn deliberately rather than by accident.

## Tests

- `LightNameTests.swift`, modelled on `PawnLabelTests.swift` (`:9-39` is the auto-numbering
  section): a placed Light is named; the name does not reuse a number after a delete; the
  second Light placed after deleting the first does not collide.
- `FogEditsTests`: `setLightName` is undoable and appears in the same history as walls and
  lights (`testUndoUnwindsWallsAndLightsInOneHistory` at `:71` is the shape).
- `AppStateFogTests`: the live rename is not undoable and survives a fog-edit round trip.
- `FogInspectorRowHeightTests`: the reserved row still fits both inspectors.

## Done when

A Light is placed already named, deleting one never renames another, and the DM can retype the
name from the panel during play or from the inspector while authoring.

## Comments
