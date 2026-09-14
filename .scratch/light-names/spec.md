# Light Names: a Light the DM can call something

Status: ready-for-agent

A **Light** has no name. The Control Window identifies one by its position in the list —
`Text("Light \(number)")` at `ControlView.swift:1563`, where `number` is `index + 1` from an
`enumerated()` at `:1224`. The code says so plainly at `:1547-1548`:

> A Light has no label of its own, so it is identified by its position in the list, exactly as
> it was in the row this replaces.

This is not merely inconvenient. **It is a defect this repo has already fixed once, one term
over.** `Pawn.nextLabel(after:)` (`PawnToken.swift:139-151`) exists precisely because
`pawns.count + 1` reused numbers after a delete. Lights have the identical defect and it is
unfixed, because there is no stored value to hold a name: delete Light 2 and Light 3 silently
becomes "Light 2". The accessibility identifier `light-toggle-\(number)` (`:1561`) shifts with
it.

This feature gives a Light a name, mirroring a Pawn's label in every respect that matters.

See `CONTEXT.md` for the vocabulary, in particular the **Light** and **Pawn** entries — the
latter of which already explains why a name of this kind stays on the DM's side of the table.

## The shape of it

`Light` gains an optional name. It is auto-assigned on placement so it is never empty in
practice, editable in both the places a Pawn's label is editable, persisted in the `.fog.json`
sidecar, and **never drawn on the Player Display**.

## Rules worth stating once

- **A Light's name is the DM's bookkeeping and never crosses the room.** `CONTEXT.md` says of a
  Pawn's label that it "is never drawn on the Player Display, so a Pawn can be named for the
  DM's notes without the name crossing the room". The same reasoning applies exactly: a Light
  named "trapped brazier" or "goes out in round 3" is prep, and prep leaking to the table is
  the failure this app exists to prevent. This is free — `LightMarker.swift` draws no text at
  all today, so the correct implementation is to never add any.
- **The field is `String?`, not a defaulted `String`.** `Light`'s `Codable` conformance is
  **synthesised** (`FogDocument.swift:128-144`), and Swift's synthesised `init(from:)` requires
  every non-optional key to be present *even when the property has a default*. `Pawn` learned
  this the hard way and documents it at `FogDocument.swift:222-231`: adding defaulted flags
  "made every `.fog.json` written before Creatures existed fail to load outright". An optional
  decodes from every existing file for free.
- **Encode with `encodeIfPresent`**, following `Pawn.encode(to:)`'s treatment of `characterID`
  (`FogDocument.swift:265-268`), so an unnamed Light does not write `"name": null` into every
  entry.
- **Auto-name on placement.** An empty name would leave the display falling back to the
  fragile index and fix nothing. `nextName(after:)` mirrors `Pawn.nextLabel(after:)`, which
  already solves the after-delete reuse problem.
- **Renaming splits undoable from live, exactly as a Pawn's label does.** In fog mode it goes
  through `FogEdits` and is undoable; from the live panel it goes through `AppState` and is
  not. This is not an accident of Pawn's implementation — `ControlView.swift:979-988` explains
  the reasoning, and `CONTEXT.md` draws the same line between live actions and edits.

## What this deliberately excludes

- **Search, filter, or click-a-row-to-highlight-on-Map.** Genuinely useful, genuinely separate.
  A name invites it; that does not mean it rides in on a text field. File it on its own if the
  table wants it.
- **Changing the `light-toggle-\(number)` accessibility identifier.** It is a test hook, not
  user-facing, and `MapForgeUITests/FogEditingUITests.swift:146` asserts on it — in a suite that
  only recently started running at all. Not worth the churn here.
- **Any change to the Support Bar.** A Light is Map content, not presentation state; the bar
  reports what the table can see. The one place the two meet is that a Light's on/off tooltip
  can now name it — "Douse «trapped brazier»" — which falls out of
  `.scratch/support-bar/issues/05-the-tooltip-sweep.md` for free.

## Files

- `FogDocument.swift:128-144` — `Light` gains `var name: String?`
- `FogOverlay.swift:361-371` — auto-name at placement, beside the radii-copying already there
- `ControlView.swift:1563` — the live row shows and edits the name
- `ControlView.swift:1575-1606` — `lightInspector` gains a name field; check
  `fogInspectorRowHeight` (`:874`) still fits
- `FogEdits.swift` — `setLightName`, undoable, beside `setLightRadii` (`:73-78`)
- `AppState.swift` — `setLightName`, live, beside `setLight` (`:330-334`)
- `MapForgeTests/FogDocumentTests.swift` — the missing-key decode test
- `MapForgeTests/LightNameTests.swift` — new, modelled on `PawnLabelTests.swift`
- `MapForgeTests/FogInspectorRowHeightTests.swift` — the mirror view gains the field

## Issues

1. `01-a-light-has-a-name.md` — the model, the persistence, the compatibility test
2. `02-naming-a-light.md` — auto-naming, and the two places it is edited
3. `03-the-table-never-reads-it.md` — the Player Display suppression, asserted

## Comments

- 2026-09-14 (grilling session): created via `/grilling`, alongside `.scratch/support-bar/`.
  Raised mid-session as "I want to be able to change the name of lights also". The exploration
  turned it from a convenience into a bug fix: the positional identity is the same defect
  `Pawn.nextLabel` was written to solve, still present because nothing could hold a name.
