# 01 — The Wall Editor loses its tools

Status: ready-for-human

The fog-editing mode authors Walls and nothing else. Pawns and Light Markers stay drawn in it
for reference — a Wall is traced against the room its tokens stand in — but are inert.

Do this first. It is the only issue that is pure subtraction, and it clears the ground the
other four build on. It leaves the app briefly *worse*: until `04` lands there is no way to
create a Pawn except Stamping, and no way to create a Light at all. That is expected; do not
soften it by keeping a tool around.

## Delete

- `FogTool` (`FogOverlay.swift:8-29`) and the segmented `Picker` bound to it
  (`ControlView.swift:577-582`). The mode needs no tool selection with one job.
- The `.pawns` and `.lights` branches of `FogOverlay.place(at:)` (`:339-377`), the light and
  pawn drag gestures (`lightDragGesture` :174 and its pawn twin), and their selection and
  `⌫` handling in `deleteSelected()` (`:425-445`). Wall selection and deletion stay.
- `pawnInspector` (`ControlView.swift:993-1051`) and `lightInspector` (`:1756-1796`). Their
  fields move into the sheets in `03` — read them there before deleting, they are the field
  list.
- `FogEdits`' Pawn and Light methods: `addPawn`, `deletePawn`, `editPawn` and its callers
  (`movePawn`, `setPawnLabel`, `setPawnKind`, `setPawnIsBig`, `setPawnColor`, `setPawnSight`),
  `addLight`, `deleteLight`, `setLightName`, the light radius setters, and the drag
  coalescing pair `beginLightDrag`/`endLightDrag` (`FogEdits.swift:52-214`). The rename
  coalescing and `renamingLight` go with them.
- `carryLiveState(onto:)` and the `LivePawnEdit` OptionSet (`AppState.swift:834-858`), and
  the `liveEdits` dictionary. Their only job was stopping this mode's Cancel from clobbering
  live Pawn edits made while it was open; with no Pawn editing here, there is nothing to
  reconcile. Check every reference before deleting — this is the subtlest removal in the
  issue.

## Keep

- The `fogInspectorRowHeight` reservation (`ControlView.swift:195-211`). It still holds the
  Wall selection inspector, and the constant height is load-bearing whatever is in it: a row
  that appears and disappears resizes the preview and makes the Map jump mid-click. Two tests
  guard this (`FogInspectorRowHeightTests`, `PreviewContainerStabilityTests`) — they must
  still pass.
- `FogEdits`' snapshot history, `original`, Cancel-restores-wholesale, and the Undo button.
  Wall tracing is exactly what it was built for.
- The mode's zoom, pan, Esc-cancels-chain, Shift-frees-angle and corner welding.
- `fogEditingMapURL` and `isFogEditingCurrentMap` (`AppState.swift:868, :890`) — the
  map-changed-mid-mode guard is unrelated to tools.
- Pawn and Light *drawing* in the mode. Only the interaction goes.

## Inert means no hit-testing

Not "selectable but not editable". Clicks must pass through Pawns and Light Markers to Wall
placement underneath, or tracing a Wall across a token becomes impossible — and that is now
the mode's only job.

## Tests

- Placing a Wall vertex on top of a Pawn works and does not select the Pawn.
- `⌫` with a Wall selected deletes the Wall; with no Wall selected it does nothing, and no
  Pawn or Light is deleted.
- Undo still unwinds Wall edits and still cannot unwind past the document the mode opened
  with.
- Cancel restores the Walls the mode opened with, and leaves Pawns and Lights exactly as the
  Live View left them — this is the behaviour `carryLiveState` used to buy, and it should now
  be true for free because the mode never touches them.
- The inspector row height is unchanged whether a Wall is selected or not.
- A `.fog.json` written before this change still loads (`FogDocumentTests` must pass — the
  file format is untouched).

## Done when

The mode has no tool picker, touches no Pawn and no Light, and still traces and undoes Walls.
