# 05 — The tooltip sweep

Status: ready-for-agent

Independent of the bar entirely — it can ship before 01 if that is convenient. Grouped here
because it answers the same question from the other side.

## What exists

Tooltips are not missing from this app. There are **25 `.help(...)` call sites**:

- `CombatPanel.swift` — 13 (`:87`, `:95`, `:103`, `:115`, `:123`, `:224`, `:282`, `:319`,
  `:341`, `:355`, `:367`, `:375`, `:381`)
- `ControlView.swift` — 10 (`:918`, `:924`, `:1005`, `:1029`, `:1070`, `:1114`, `:1140`,
  `:1365`, `:1416`, `:1569`)
- `StatEditor.swift` — 2 (`:101`, `:150`)

They cluster in the Combat panel and the Pawn rows — the newest feature. The sweep was never
carried back, and the pattern of what is missing is the problem:

**Every button in `modeControls` has none** — `Fit Grid…` (`:496`), `Pan Viewport…` (`:498`),
`Edit Fog…` (`:500`), `Snap to N` (`:503`), `Cancel` (`:506`, `:511`, `:527`), `Done` (`:508`,
`:513`, `:528`), `Undo` (`:524`). Also bare: `Open Map…` (`:101`), the Grid squares field and
stepper (`:227-231`), the fog Tool picker (`:516-521`), the Player Display picker
(`:1638-1645`), the Scene/Combat tab picker (`:1170-1176`), and everything in the Party editor
except the `plus` button.

**The controls that change what the table sees are exactly the unlabelled ones.**

`accessibilityLabel` is worse off: two uses total, both in `CombatPanel.swift` (`:244`, `:298`).
`accessibilityIdentifier` is used widely but purely as a test hook.

## Build

**Write the copy rule down first**, in the spec or as a short section in `CONTEXT.md`, because
this is the app's most-read prose and the next feature's buttons will inherit whatever register
this sets:

- **Say the effect, not the name.** A tooltip reading "Blackout" on a button labelled Blackout
  is noise. "Hides the Map from the players instantly" is help.
- **Use `CONTEXT.md`'s vocabulary.** Map, Pawn, Player Display, Grid, Viewport, Fog Overlay.
  Never image, token, TV, screen, calibration — the `_Avoid_` lists are the rule.
- **Name the keyboard shortcut where one exists.** No shortcut is rendered anywhere in this app
  today except inside the mode captions. `Cancel` is `Esc`; `Done` is `Return`; `Undo` is `⌘Z`.
- **A disabled control's tooltip says why it is disabled**, reusing the `.explanation` strings
  from `MeasurementControl` and `SoloSightControl` where they apply. `soloSightHelp`
  (`ControlView.swift:1118-1124`) already does this and is the model.

**Then sweep every interactive control in the Control Window**, not a subset. A half-swept app
is worse than an unswept one: once controls 1–11 have tooltips, the bare control 12 reads as
broken rather than as undocumented.

**Add `accessibilityLabel` where the control is icon-only**, which is most of the Combat header
(`CombatPanel.swift:76-139`), the flame toggles, the eye toggles, the binoculars. Note that
`initiative-tracker` issue 05 — the one issue in that feature with no `## Comments` block —
covers "icon-only controls, accessibility labels, disable it and say why". Check what landed
there before writing the same thing twice, and if it did land, this issue shrinks to the
non-combat half of the window.

## Tests

Tooltips are hard to assert on in XCTest and mostly are not worth it. What is worth it:

- A test that enumerates the interactive controls in `ControlView` and fails on any without
  help text, if that can be done without a fragile reflection trick. If it cannot, say so in
  the comments and leave it — do not build something baroque.
- `accessibilityLabel` presence on icon-only controls **is** assertable in `MapForgeUITests`
  and should be.

## Done when

Every control in the Control Window explains its effect on hover, in the app's own vocabulary,
with its shortcut where it has one — and the rule that made them consistent is written down
somewhere the next feature will find it.

## Comments
