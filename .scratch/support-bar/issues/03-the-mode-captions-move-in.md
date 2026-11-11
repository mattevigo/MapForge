# 03 — The mode captions move in

Status: ready-for-agent

Moving what already exists, before anything new is written. Depends on 01, and settles the
height 01 reserves — do these together if the height proves contentious.

## What exists

Three caption rows sit between the controls and the preview at the top of the window:

- `ControlView.swift:127-131` — the Grid Fit caption
- `:132-136` — the Viewport caption
- `:137-140` — the fog caption, `Text(tool.hint)`, with per-tool strings defined at
  `FogOverlay.swift:19-28`

These are the de-facto help text of the app: long sentences carrying `⌥-drag`, `⇧`, `⌫` and
`Esc`, and the only place any keyboard shortcut is rendered at all. Shortcuts are declared at
`:507`, `:509`, `:512`, `:514`, `:526`, `:529` and shown nowhere.

The Grid Fit caption carries a comment worth reading before touching any of this:

> Shown for the whole mode, not just before the first drag: the caption vanishing mid-drag
> resized the preview under the cursor.

Which is the same bug 01 reserves height against, already encountered once here.

## Build

**Move all three strings into the bar and delete the three rows.** Not duplicate — move. Two
surfaces reserving height for the same text is how the stack gets fragile again, and the top
rows are between the controls and the preview, which is the worst place for prose the DM reads
while dragging.

**The mode hint beats Player Display truth.** While a mode is active the DM is mid-task and
the instructions matter more than the standing state; the standing state returns when the mode
ends. Encode this in `SupportMessage` as a priority rather than as a chain of `if`s in the
view.

**`FogTool.hint` stays where it is** (`FogOverlay.swift:19-28`). It belongs with the tool enum
and the bar can read it. Do not move the strings into the bar's own file.

**Check the height.** These three strings are the longest text the bar will hold, and the fog
captions in particular are full sentences. If one line at `.caption` will not hold the longest,
the bar is two lines — decide it with the test from 01, not by looking at it once at one window
width.

## Tests

- `SupportMessageTests`: each mode yields its caption; the fog mode yields the current tool's
  hint and changes with the tool.
- Mode hint takes priority over the idle Player Display line.
- Leaving a mode restores the idle line.
- The three old caption rows are gone — a UI test that the preview's container height is
  identical in `.normal` and in `.fog`, which it is not today.

## Done when

The captions read from the bottom of the window, the top of the stack has three fewer
conditional rows, and entering or leaving a mode no longer changes the preview's height.

## Comments
