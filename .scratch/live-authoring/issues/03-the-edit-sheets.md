# 03 — The Edit Pawn and Edit Light sheets

Status: ready-for-human
Blocked by: 01

Two modal sheets. `Edit Pawn`: label, colour, Kind, Big, sight. `Edit Light`: name, bright
radius, dim radius, on/off. Buffered, committed on OK, discarded on Cancel.

## These are the app's first modals, deliberately

`ControlView.swift:1538` records the standing stance — "this app has no modals, and one text
field does not justify introducing the first." That held while every editor was one or two
fields on a row that had to reserve constant height or the Map jumped mid-click
(`ControlView.swift:195-206`). A six-field form is the case it was not written against, and a
sheet sidesteps the height problem entirely. A popover was rejected: it dismisses on outside
click, which is hostile in the middle of a text field.

Update the comment at `:1538` rather than leaving it to contradict the code.

## The fields are the ones that already exist

Do not design a new form. `pawnInspector` (`ControlView.swift:993-1051`) and `lightInspector`
(`:1756-1796`) have exactly these fields with their widths, formatters and validation — lift
them. Issue `01` deletes those rows; read them before it does.

**Edit Pawn** — label (`TextField`), colour (`ColorPicker`, `#RRGGBB`), Kind (`Picker` over
`PawnKind.allCases`), Big (`Toggle`), sight (`TextField`, Grid squares).

**Edit Light** — name (`TextField`), Bright (`TextField`, squares), Dim (`TextField`,
squares), On (`Toggle`).

Not here: the Stat Block. It has its own editor and its own file (ADR-0009); one OK button
writing two persistence layers is where save semantics get murky.

## Buffer and commit

Bind the fields to local `@State`, seeded on open from the Pawn or Light. OK writes them all
through `AppState`'s live setters; Cancel writes nothing. This is the app's *only* undo for
these edits — Live View changes are not undoable by design (ADR-0013), so Cancel has to
actually work. Escape must behave as Cancel.

Writing through `AppState` and not `FogEdits` is the point: these are live actions, and
`FogEdits` no longer has the methods anyway after `01`.

## Details that will bite

- **Dim defaults to twice bright** (`FogDocument.swift:134`). The sheet must not re-apply
  that on every OK, or a DM who deliberately set dim equal to bright will have it silently
  doubled back. Seed the buffer from the stored value; apply the default only when creating.
- **No declared Grid**: carry over `lightInspector`'s orange warning. Radii are in squares and
  mean nothing until the Grid is declared (`AppState.litRegions` returns `[]`,
  `AppState.swift:542`). Warn; do not disable. See the spec.
- **Kind is freely editable**, mid-Encounter included. Changing it flips whether the Pawn
  emits Light and which side of the Fog Overlay it draws on; the Encounter picks up the new
  Kind and the Combat Log needs no entry — a Kind change is not a Change.
- **A Treasure is never a Combatant.** Changing a Combatant's Kind to Treasure must take it
  out of the Order, the same removal `05` performs.
- Sight is a Pawn's single radius, not a bright/dim pair (`CONTEXT.md`, **Pawn**). Do not
  expose dim on the Pawn sheet.
- The sheet must close if its subject disappears underneath it (Map switched, Pawn deleted).
  Follow the `resolved…` guard pattern at `AppState.swift:276-280` — never hold a stale
  `Pawn.ID`.

## Tests

- Editing every field and pressing OK writes all of them; the fog file round-trips.
- Cancel and Escape write nothing, including after every field was touched.
- Dim survives OK unchanged when it was set equal to bright.
- Changing Kind on a live Combatant updates the Pawn and leaves the Combat Log untouched;
  changing it to Treasure removes it from the Order.
- Opening the sheet with no declared Grid shows the warning and still commits.
- Switching Map with the sheet open closes it and writes nothing.

## Done when

Both sheets open from `02`'s `Edit…`, commit on OK, and discard on Cancel.
