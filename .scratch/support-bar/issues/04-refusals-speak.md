# 04 — Refusals speak

Status: ready-for-agent

The reason this feature is worth building. Depends on 01; independent of 02 and 03 beyond the
priority rule they share.

## The problem

This repo has already diagnosed this defect and closed it unfixed for want of somewhere to put
the answer. `.scratch/table-ready/issues/02-wall-deletion-made-real.md` is `wontfix`, and its
finding is that the wall-deletion model, the key handler and the hint text all exist — "what's
missing is any signal to the DM about why a click did nothing."

The `table-ready` spec generalises it: of four reported defects, two were **fully built in code
but did not exist for the DM**. "Already built… Never once verified in a running app."
"Already built… Unreachable at the table and invisible at small zoom."

Meanwhile the app has the principle written down twice, in `MeasurementControl.swift:5-9` and
`SoloSightControl.swift:4-9`, in identical words:

> Every unavailable state carries a reason — a control that is merely inert teaches the DM
> nothing, and they are reading it in front of players.

Both types already carry an `.explanation` string for every disabled reason —
`MeasurementControl.Availability` (`:30-39`) has `.noGrid` and `.noMap`;
`SoloSightControl.Availability` (`:32-36`) has `.pawnIsHidden`, `.fogOverlayOff` and `.noGrid`.
**The copy is written. It has no display.** Some of it surfaces in a context menu
(`ControlView.swift:657-675`) and in a tooltip (`soloSightHelp`, `:1118-1124`), neither of
which the DM is looking at when the thing silently fails.

## Build

**A transient message channel into the bar.** A refusal displaces whatever the bar is showing
for a few seconds, then the bar returns to the mode hint or the idle line. Highest priority in
`SupportMessage`.

**Wire the refusals that already have reasons**, first:

- `MeasurementControl.Availability.disabled(_)` — arming a shape with no Grid or no Map
- `SoloSightControl.Availability.disabled(_)` — isolating a hidden Pawn, or with Fog off

**Then the silent no-ops that have no reason type yet**, which are the ones `table-ready` was
actually about:

- ⌫ in fog mode with nothing selected (`FogOverlay.swift:421-433` returns silently)
- A click with the Walls tool that starts nothing the DM can see
- A Stamp refused outside the image bounds — `CONTEXT.md` states the rule ("a Stamp outside it
  is refused") and the DM currently sees a drag that simply does nothing
- A Pawn drag stopping at the Map edge — the same rule, the other direction

Give these `.explanation` strings in the same register as the existing ones, and prefer a new
case on a pure policy type over a string built in a view. `SoloSightControl.swift` is the
template: a small enum, every case carrying its reason, tested without a view.

**Timing is a constant on the bar**, not a magic number at each call site. Three seconds is a
reasonable start; a DM mid-fight is not reading fast.

**A refusal never interrupts a mode hint permanently.** When it expires, the bar recomputes
rather than restoring a cached string — the mode may have changed while it was displayed.

## Tests

- `SupportMessageTests`: a refusal beats both the mode hint and the idle line; after expiry the
  bar shows what the current state says, not what it showed before.
- Each newly-wired refusal produces its explanation: no-Grid measurement, hidden-Pawn Solo
  Sight, ⌫ with no selection, Stamp outside the bounds.
- The existing `MeasurementControl` and `SoloSightControl` explanations are reused verbatim
  rather than re-worded in a second place.

## Done when

Every refusal the DM can trigger says why, in the same strip, in the app's own vocabulary —
and `.scratch/table-ready/issues/02-wall-deletion-made-real.md` can be pointed at this issue as
the thing that made it cheap.

## Comments
