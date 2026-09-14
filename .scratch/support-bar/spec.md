# Support Bar: tell the DM what the table can see, and what each control does

Status: ready-for-agent

MapForge has a discoverability problem it has already diagnosed once and closed without
fixing. The `table-ready` spec found that of four reported defects, **two were fully built in
code but did not exist for the DM** — "Already built… Unreachable at the table and invisible
at small zoom." Its issue 02 is `wontfix` with the diagnosis written out: the wall-deletion
model, the key handler and the hint text all exist, and "what's missing is any signal to the
DM about why a click did nothing."

That signal has nowhere to go. There is no status bar, no footer, no transient-message
surface anywhere in the Control Window. This feature builds one — a **Support Bar** across
the bottom — and finishes the half-swept tooltips that should accompany it.

See `CONTEXT.md` for the vocabulary this is written in, and:

- `.scratch/table-ready/issues/02-wall-deletion-made-real.md` — the prior diagnosis this retires
- `.scratch/table-ready/issues/05-pawn-labels-at-the-table.md` — the same failure, one term over
- `docs/adr/0011-the-support-bar-reserves-its-height.md` — why the bar is a fixed height

## The shape of it

A single strip along the bottom of the Control Window, below the preview and the live panel,
at a **constant reserved height**. It shows one line of text at a time, chosen by priority:

1. **A refusal**, for a few seconds, when the DM does something the app declines to do.
2. **The current mode's hint**, whenever a mode is active — the three captions that live at
   the top of the window today, moved here.
3. **Player Display truth**, otherwise — what the table can see right now.

Alongside it, every interactive control in the Control Window gains a `.help()` tooltip. The
app already has 25 of them; this finishes the sweep and settles what they say.

## Why a bar rather than more tooltips

A tooltip answers "what is this thing I am pointing at". It cannot answer "what is the table
seeing" or "why did that click do nothing", because in neither case is the DM pointing at
anything. Those are the two questions MapForge actually fails to answer, and both need a
surface that is present without being pointed at.

## Rules worth stating once

- **The bar reserves constant height.** Never intrinsic, never conditional. `ControlView.swift`
  (`:141-152`) records the bug: "anything in this stack that appears or vanishes resizes the
  preview", which shrinks the `GeometryReader` the preview's transform measures against and
  makes the Map visibly jump mid-click. `fogInspectorRowHeight` already exists to prevent
  exactly this. The bar follows the same discipline, with the same kind of test.
- **The Player Display never gets chrome.** `CONTEXT.md` defines it as "the external screen
  showing only the Map, fullscreen, with no controls". The bar is Control Window only, and
  this is an invariant rather than a preference.
- **The bar is read-only, with one exception.** Solo Sight can be cleared from it. A
  half-clickable status bar teaches the DM to poke at it, and poking at things mid-session is
  how the wrong screen goes black. Solo Sight earns the exception because it is the one state
  that is both easy to forget and actively misleading to the table while it is on.
- **Refusals use the reasons already written.** `MeasurementControl.swift` (`:5-9`) and
  `SoloSightControl.swift` (`:4-9`) both already state the principle — "Every unavailable
  state carries a reason — a control that is merely inert teaches the DM nothing, and they are
  reading it in front of players" — and both already carry an `.explanation` string per
  disabled reason. The copy exists. It has no display.
- **Tooltips teach the effect, not the name.** "Blackout" on a button labelled Blackout is
  noise. "Hides the Map from the players instantly" is help. Where a keyboard shortcut exists,
  it goes in the tooltip, because no shortcut is rendered anywhere in this app today.
- **Tooltips are written in `CONTEXT.md`'s vocabulary.** Map, Pawn, Player Display, Grid —
  never image, token, TV, calibration. These become the most-read prose in the app and are
  where the ubiquitous language either holds or rots.
- **The mode captions move, they are not duplicated.** Today's three captions
  (`ControlView.swift:127-140`) are deleted from the top of the stack as the bar gains them.
  Keeping both would reserve height twice and reintroduce the jump this feature is careful
  about.

## What this deliberately excludes

- **Anything on the Player Display.** See the invariant above.
- **Search, filter or navigation from the bar.** It reports; it does not drive.
- **Onboarding, a first-run tour, or a help window.** A DM reading a tour is not at the table.
- **The `pawns-not-drawn` bug.** The Control Window's preview draws no Pawns at all
  (`.scratch/pawns-not-drawn/01-tokens-missing-from-the-mirror.md`, `needs-triage`). That is
  the more severe defect, it blocks verifying `initiative-tracker` issue 07, and a Support Bar
  narrating an empty preview would be absurd. **Fix it first, separately.** This feature
  assumes it is fixed and does not touch it.

## Files

- `ControlView.swift` — the bar is appended after the `HStack` at `:168-171`; the captions at
  `:127-140` are removed; the tooltip sweep is largely here
- `SupportBar.swift` — new: the view, at a constant reserved height
- `SupportMessage.swift` — new: the priority rule, as a pure testable type in the style of
  `SoloSightControl.swift` and `MeasurementControl.swift`
- `CombatPanel.swift`, `StatEditor.swift` — remaining tooltip gaps
- `MapForgeTests/SupportBarHeightTests.swift` — new, mirroring `FogInspectorRowHeightTests`
- `MapForgeTests/SupportMessageTests.swift` — new: the priority rule

## Issues

1. `01-the-bar-reserves-its-height.md` — the empty strip, correct height, nothing in it
2. `02-player-display-truth.md` — the idle state, including the Solo Sight indicator
3. `03-the-mode-captions-move-in.md` — absorb the three existing captions, delete the old rows
4. `04-refusals-speak.md` — transient messages, retiring `table-ready` 02's wontfix
5. `05-the-tooltip-sweep.md` — finish the 25, write the copy rules down
6. `06-escape-cancels-fog-mode.md` — the missing keyboard shortcut

## Comments

- 2026-09-14 (grilling session): created via `/grilling`. Nineteen questions over four rounds,
  three codebase explorations. The brief was "a small bar at the bottom with important support
  infos like when I hover each button it tells what is that button" — the grilling separated
  that into two mechanisms (the bar is not where hover text belongs), and the exploration found
  that the tooltip half is already 25 controls in and was simply never finished. The
  `table-ready` finding, that features exist in code without existing for the DM, is what moved
  this from polish to a real fix.
