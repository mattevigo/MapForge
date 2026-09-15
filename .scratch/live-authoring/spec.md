# Live Authoring — Pawns and Lights leave the Wall Editor

Status: specced, not started

Every Pawn and every Light is added, edited, moved and deleted in the **Live View**. The
fog-editing mode becomes the **Wall Editor** and authors Walls alone, with Pawns and Light
Markers drawn in it for reference but inert.

Vocabulary: see [CONTEXT.md](../../CONTEXT.md) — **Live View**, **Wall Editor**, **Add**,
**Pawn**, **Light**, **Pawn Kind**. The decision and its cost:
[ADR-0013](../../docs/adr/0013-pawns-and-lights-are-authored-in-the-live-view.md).

## Decisions

Settled in a grilling session; the reasoning is here so the issues don't re-litigate it.

**The line moved because only Walls needed precision.** See ADR-0013. A Pawn was already a
live object — dragged, hidden, renamed, torch-toggled in the Live View — and only its
*creation* and four of its fields required a mode switch. The split ran through the middle of
one concept, and cost a reconciliation mechanism to hold together.

**Right-click on a Pawn or a Light opens one divided menu.** `Edit…` and `Delete` above a
divider, the Measurement Shapes below. Not a second menu and not left-click: left-click on a
Pawn is already the drag, and the Measurement state machine owns left-click when armed
(`ControlView.swift:426-429`). The hit-test-under-`mirrorCursor` pattern already exists for
pinned Measurements (`measurementUnderCursor`, `ControlView.swift:785-805`) and is what this
extends. Right-click on empty Map is unchanged — Measurement Shapes only.

**Adding is armed from a button, not from the menu.** An `Add` control offers Light, Player,
Creature, Treasure; picking one arms a placement with a crosshair, and the next left-click on
the Map places it. This is the Measurement arming pattern (`startMeasurement`,
`ControlView.swift:817`, `MeasurementCursor`) reused rather than reinvented — the DM has
already learned it. **At most one thing is armed at a time**, Measurement included: arming a
placement disarms a live Measurement and vice versa, and Esc backs out of either. Two armed
tools would make a left-click's meaning unguessable.

**The Kind is chosen when arming, not in the sheet.** A DM adding four goblins arms four
times and never opens a form. What is placed inherits from the last thing of that Kind placed
— exactly as the fog editor does today (`FogOverlay.place(at:)`) — so the second goblin is
already the right colour and size. No sheet opens automatically after placing.

**Two sheets, buffered, OK/Cancel.** `Edit Pawn` carries label, colour, Kind, Big and sight;
`Edit Light` carries name, bright radius, dim radius and on/off. One sheet with half its
fields greyed out would be worse than two honest ones, and they are reached from different
objects. Fields buffer and commit on OK: a data-entry sheet that has already applied half its
changes when the DM hits Escape is the worst of both.

**Modals, not popovers — and this is the app's first.** A popover dismisses on outside click,
which is hostile mid-field. The standing "this app has no modals" stance
(`ControlView.swift:1538`) was written when every editor was one or two fields on a row that
had to reserve constant height or the Map jumped mid-click
(`ControlView.swift:195-206`, guarded by `FogInspectorRowHeightTests` and
`PreviewContainerStabilityTests`). A six-field form is the case it was not written against. A
sheet also sidesteps the height-reservation trap entirely. The cost is accepted: while the
sheet is up, the DM cannot see their own Map. The Player Display is a separate window and
carries on unaffected.

**Live View edits are not undoable.** `FogEdits` is snapshot-based and mode-local
(`FogEdits.swift:14-225`) — it cannot exist outside the Wall Editor, and should not: every
change to a Pawn is a live action now, and live actions in this app are not undoable
(`AppState.swift:569-577`). Cancel on the sheet is the escape that undo would otherwise be.
The Wall Editor keeps its own undo stack, unchanged, for Walls.

**`Add` needs no declared Grid.** This was nearly made to refuse without one, by analogy with
Measurement (`MeasurementControl.swift:19-28`). The analogy is wrong. Measurement refuses
because it would show the table a *wrong number*; a Light without a Grid shows *nothing* —
`AppState.litRegions` already returns `[]` when `pixelsPerSquare` is nil
(`AppState.swift:542`), so the whole fog engine is inert. Refusing would make the new path
stricter than the fog editor it replaces, and would stop a DM laying out a room's braziers
before declaring the Grid, which is a reasonable order to work in. The Edit Light sheet
carries the existing orange no-Grid warning instead: place freely, be told the radius does
nothing yet.

**Deleting a Pawn Benches it rather than erasing its history.** `⌫`-after-select inside the
fog mode was the app's *only* deletion path (`FogOverlay.deleteSelected`), and it leaves with
the tools — so `Delete` in the menu is not a new convenience, it is the replacement. A Pawn
deleted mid-Encounter leaves the Order exactly as Benching does; the Combat Log still names
it, which `CONTEXT.md` already requires of a Pawn that is gone. No confirmation prompt: it is
a live action and the DM can add another.

**The Wall Editor keeps Pawns and Lights visible but inert.** A Wall is traced against the
room its tokens stand in, so hiding them would make tracing harder. Inert means no
hit-testing at all — clicks pass through to Wall placement — which also removes the conflict
that made a tool picker necessary in the first place.

## What this deletes

Worth stating, because the feature is a net simplification and issues should not preserve
what it is meant to remove:

- `FogTool` and its segmented picker — the Wall Editor has one job.
- `carryLiveState(onto:)` and the `LivePawnEdit` OptionSet (`AppState.swift:834-858`), whose
  whole purpose was stopping the fog mode's Cancel from clobbering live Pawn edits. With no
  Pawn editing in the Wall Editor, there is nothing to reconcile.
- `FogEdits`' Pawn and Light methods, and the fog-mode `pawnInspector` / `lightInspector`
  rows — their six and four fields move into the sheets.

## Scope

In: the divided right-click menu, the `Add` button and its armed placement, the two sheets,
Delete from the Live View, the Wall Editor's reduction to Walls, and the deletions above.

Out: editing a Stat Block from these sheets — it has its own editor (`StatEditor`) and is
stored in a different file for a stated reason (ADR-0009). Editing a Wall from the Live View.
Multi-select. Undo for live edits. Converting Light radii from squares to metres — still
deferred, see the `measurement` spec.

## Risk

Everything here lands in `ControlView.swift` and the mirror's gesture layer, which has a
documented history of **four gesture-composition defects** plus a hit-testing one that killed
a whole layer (`ControlView.swift:757-760`, `FogOverlay.swift:86-92`). Three of those were
unreachable by any unit test. Prefer `.contextMenu` and modifiers over composed gestures,
read position from `mirrorCursor` and never from an `NSEvent` (`RightClick.swift:6-16`), and
expect the real verification to be manual.

`MapForgeUITests` still hangs and has never run — noted in the `fog-of-war` spec and not
fixed here.

## What only a human can check

Everything below is in the layer no unit test reaches — the one the four gesture-composition
defects lived in. A code review of the implementation raised each; they are recorded here
rather than left as absent tests.

- **The hit-test after the preview is resized.** `LiveHitTest` is held by unit tests against
  Map points; whether `mirrorCursor` still agrees with the Map after a window resize is view
  wiring.
- **Inertness in the Wall Editor.** `allowsHitTesting(false)` on the token layers is the
  whole mechanism, and nothing but a real click proves it. The model half is held
  (`WallEditorTests.testAWallCanBeTracedAcrossAPawn`).
- **The sheets themselves.** Escape behaving as Cancel comes from `.keyboardShortcut(.cancelAction)`;
  that the sheet closes on a Map switch or on its subject being deleted is now wired through
  `editing = nil` and an `.onChange(of: appState.fog)` guard, with the model half held by
  `LiveAuthoringTests` — but the closing is view state.
- **The crosshair, and Esc backing out of an armed `Add`.**

## Settled during implementation

- **A deleted Pawn keeps its Stat Block.** Issue 05 listed the opposite as a test. The
  Combat Log still names a Pawn that is gone, and a line describing a Pawn whose numbers were
  thrown away describes nothing — so the block outlives the token, as `removePawnFromMap`
  already intended. Held by `testDeletingAPawnKeepsItsStatBlockForTheLog`.
- **A Light outside the image is refused, exactly as a Pawn is.** An exemption was tried on
  the grounds that a Light out there lights nothing visible. It was wrong: `LiveHitTest` only
  reaches what the DM can click, so such a Light could never be selected, edited or deleted.
- **Benching a Pawn edited into a Treasure writes `.combatantRemoved`.** That records it
  leaving the Order, not the Kind change — issue 03's "a Kind change is not a Change" and
  issue 05's removal rule describe one event from two sides.

## Issues

- `01` — the Wall Editor loses its tools
- `02` — right-click on a Pawn or Light: the divided menu
- `03` — the Edit Pawn and Edit Light sheets
- `04` — Add: the armed placement
- `05` — Delete from the Live View
