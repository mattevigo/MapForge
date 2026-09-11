# 04 — Tabs in the right-hand panel

Status: ready-for-agent

Structural, and deliberately alone: the panel gains tabs and width before anything combat-
shaped goes into it. Depends on issue 01 only, so it can run alongside 02 and 03.

## The problem

`ControlView.swift` is 1,531 lines, and `livePanel` (`:1103`) is a single vertical
`ScrollView` fixed at `width: 236`, holding the Party group, Lights, and one group per
`PawnKind`. There is no tab mechanism anywhere in the app.

## Build

**Two tabs**: **Scene** and **Combat**. Scene is today's `livePanel` contents, moved with no
behavioural change. Combat is empty in this issue beyond a placeholder — issues 05 and 06
fill it.

**Width goes to 320** for both tabs, not just Combat. A panel that resizes when you switch
tabs makes the preview jump, and the preview jumping is the thing
`Self.fogInspectorRowHeight` already exists to prevent (`ControlView.swift:858`). Widening
both once is the calmer answer, and the Control Window is on the DM's own display with room
to spare.

**Extract the panel from `ControlView`.** Move the Scene contents into their own view file
rather than leaving them inline — this is the moment to do it, with nothing else changing.
`ControlView.swift` should shrink by roughly the size of what moves. Do not refactor beyond
the move; a behaviour-preserving extraction is reviewable and a rewrite is not.

**Tab selection is not persisted.** It is the kind of thing `DisplayPreferences` holds, and
it is also a thing that should start on Scene every launch: a DM opening MapForge is setting
up, not mid-fight. Revisit only if the table complains.

**The Combat tab is disabled with no Map open**, exactly as `showsParty` gates the Party
group on `appState.mapURL != nil` (`ControlView.swift`). An Encounter without a Map has
nothing to be about.

## Tests

Mostly UI tests, which `MapForgeUITests` already has three files of:

- Switching tabs shows the other tab's content and preserves the panel's width.
- The Scene tab's controls all still work after the extraction: the Party picker, a
  character row, the light rows, the pawn rows, hide and solo-sight toggles.
- The Combat tab is unavailable before a Map is open and available after.
- The preview does not resize when tabs change.

## Done when

The panel has two working tabs at 320 points, Scene behaves exactly as it did, and the Scene
content lives in its own file. The Combat tab is an empty shell.
