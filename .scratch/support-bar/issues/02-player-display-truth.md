# 02 — Player Display truth, and the Solo Sight indicator

Status: ready-for-agent

What the bar says when nothing else is competing for it. Depends on 01.

## The problem

The DM's standing anxiety in MapForge is not "what does this button do" — it is **"what can
the table see right now?"** The app's answer today is scattered: a `tv`/`tv.slash` icon in the
Player Display block (`ControlView.swift:1636-1637`), a Fog switch that only appears when the
Map has fog content (`:1129-1142`), and for Solo Sight, nothing at all.

Solo Sight is the sharp case. It changes what the entire table sees, it is reachable from a
toggle in a panel row (`soloSightToggle`, `:1094-1116`), and its only indication that it is on
is that *other* rows drop to 0.5 opacity (`:1045`). The exploration of this window called it
"the one 'global mode' with no persistent indicator anywhere except dimmed rows". A DM who
forgets Solo Sight is on is showing the table one character's view of a room and does not know
it.

## Build

**One line of text describing what the table is getting.** The state to read is all present:
`appState.playerScreen` and `playerMetrics` (`AppState.swift:125`), `appState.isFogOverlayOn`
(`:338`), `appState.resolvedSoloSightPawnID` / `soloSightPawnID` (`:348`).

Phrasing follows `CONTEXT.md` exactly — Player Display, Map, Fog Overlay, Solo Sight, Pawn.
Roughly:

| State | The line |
|---|---|
| No Player Display selected | Not presenting — the table sees nothing |
| Presenting, fog off | The table sees the whole Map |
| Presenting, fog on | The table sees the Map where it is lit |
| Solo Sight on | The table sees only what *«Pawn»* sees |

**Solo Sight wins over the others** when it is on, because it is the most surprising state and
the one most likely to be forgotten. It names the Pawn — the Pawn's label is DM-side
bookkeeping (`PlayerVisibility.showsPawnLabelToPlayers`, `:47`) and the bar is DM-side, so
naming it here is correct and useful.

**Solo Sight is clickable to clear it.** The single exception to the bar being read-only. Put
the affordance on the Solo Sight line only — an `×`, or the line itself as a button — and
nowhere else. The DM notices the state in the bar, so clearing it belongs where they noticed
it. Route through whatever `soloSightToggle` already calls rather than a second path into the
same state.

**Nothing else is clickable.** Not the "not presenting" line, tempting as a jump to the display
picker is. A bar that is half-interactive teaches poking, and poking mid-session is how the
wrong screen goes black.

## Tests

- `SupportMessageTests.swift`: a pure type mapping app state to the line, in the style of
  `SoloSightControl.swift` and `MeasurementControl.swift` — every case above, plus Solo Sight
  beating fog-on and not-presenting.
- Solo Sight's line names the isolated Pawn's label.
- Clearing Solo Sight from the bar leaves the same state as clearing it from the panel toggle.
- No other bar line exposes a control.

## Done when

The bar always says what the table can see, Solo Sight is impossible to leave on unnoticed,
and clearing it from the bar is one click.

## Comments
