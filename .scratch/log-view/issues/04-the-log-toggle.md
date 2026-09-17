# The Log toggle, and what it takes off screen

Status: done

The control, and the layout swap. Lands before the view itself has content — with issue 05 unbuilt
this shows the empty states and nothing else, which is a shippable increment.

## The toggle

`Toggle("Log", isOn:)` with `.toggleStyle(.button)`, `.accessibilityIdentifier("log-toggle")`,
on the **right** of the Setup Toolbar's second row — `ControlView.swift:331-334`, past the
`Spacer()` that ends it today. That row is the one row in the window with a free right edge.

Bound to `@State private var showingLog: Bool`, **not** a fourth `PreviewMode` case. Reading the
log is orthogonal to arming Grid Fit, and a mode case grows a not-applicable branch in every
`switch` in the file. `viewportToggle` is the precedent: "a toggle, not a mode."

Label is "Log", not "Session Log" — that row's own comment warns "Keep this row short", and
`ViewThatFits` claims the wide branch fits at any width once a `Spacer()` is present. No ellipsis:
in this row it promises a Cancel/Done pair, which a toggle does not have.

Always enabled — not gated on `mapImage` (a Session needs no Map, ADR-0015) and not gated on a
Session (a disabled button teaches nothing; the empty state teaches that Start Session fills it).

## What it replaces

The **Map preview** and the **Live Toolbar** (`ControlView.swift:376-382`), both inside
`mapColumn`. What stays: both Setup rows, the mode hint row, the Log View itself, the Comment Bar,
and the whole Live Panel column.

So the Session toggle is gone while reading. Deliberate: every Live Toolbar switch changes what
the players see, and a DM reaching for one has already decided to look at the Map.

## What it disables

**Add**, **Fit Grid…** and **Edit Fog…** all disable while the Log is open — every one acts on a
Map that is not on screen, and `Add` in particular would otherwise arm a click invisibly. The mode
hint row reads **"Reading the Session Log. Close it to edit the Map."**, which is the only text
that answers "why can't I press Edit Fog". That row is already fixed-height and already exists to
explain the current mode.

A **Map switch** leaves the Log open. A Session crosses Maps (ADR-0015) so the evening's log is
unaffected by which Map is loaded.

## The empty states

Four, because "recording but nothing yet" and "no Session" must not look alike — "am I actually
recording?" is the question this view exists to answer.

- No Workspace: "Open a Workspace to record a Session."
- No Session: "No Session running — press Start Session to begin recording."
- Recording, no Lines: "Recording. Nothing has happened yet."
- Lines: issue 05.

## Done when

- Toggling shows the Log in the Map's place with the Live Toolbar gone.
- The three Map buttons grey and the hint explains why.
- All four states reachable; UI test addresses `log-toggle` by identifier.
- The Comment Bar and Live Panel stay put, and the Map does not change height on toggle
  (`ChromeHeightTests`, `PreviewContainerStabilityTests`).
