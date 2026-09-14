# 04 — Tabs in the right-hand panel

Status: done

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

## Comments

**Built, minus the extraction.** Two things this issue got wrong.

**The Scene content did not move into its own file, and the plan to move it was mistaken.**
The panel reads `mode`, `fogEdits`, `tool`, `selectedPawn` and `selectedLight` — the
fog-editing machinery — so "a behaviour-preserving extraction" would in fact mean threading
six or more bindings through the wiring that drives fog editing. That is a rewrite wearing a
move's clothes. Left in place; worth its own issue once the Combat tab shows what genuinely
wants sharing, and `ControlView.swift` is no worse than it was.

**`TabView` is the wrong control here** and was replaced with a segmented `Picker` plus a
`switch`. The picker is also what this window already uses for the fog tool, so the panel
reads as part of the same app rather than as a document with tabs.

**The three long-failing `FogEditingUITests` are fixed, and the cause was not what it looked
like.** Their queries were stale — the Light toggle stopped being a button called "1" when
the panel went vertical, and a `.button`-styled `Toggle` publishes on macOS as a checkBox —
but repairing the queries only moved the failure to "not hittable" at a coordinate plainly
inside the window.

The live panel's `ScrollView` publishes as **Disabled** in the accessibility tree. It does so
at 236 points on `8969b26` as well as at 320 here, so it is AppKit's behaviour and not this
feature's. Everything inside it reports `isHittable == false` and `element.click()` refuses.
A probe settled whether the app was actually broken: a coordinate click at a toggle's own
centre flips it, 1 to 0. The controls are live and always were.

Worth keeping in mind for issues 05 and 06, whose every control lives in that same panel: a
UI test there must click by coordinate, and asserting `isHittable` will always fail. The
tests now also assert the *effect* — the Light douses, the Fog switch flips — rather than
that an element exists, which is what let three of them sit broken for months saying nothing
useful.

- 2026-09-14: verified at the table on real hardware. Closed.
