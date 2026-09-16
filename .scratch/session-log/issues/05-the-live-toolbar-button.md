# 05 — The Live Toolbar button

Status: ready-for-agent

Start/Stop Session joins the switch row, and the two toolbars get their names in the code.

Depends on 03. Independent of 04.

## What to build

**The button.** In the `HStack` at `ControlView.swift:261-265` — today the fog switch, the
measurement visibility switch and a `Spacer` — add a Start/Stop Session control at the trailing
edge, after the `Spacer` so the switches keep their position.

- Label toggles "Start Session" / "Stop Session". A **width** change, not a height change, so
  the height guards are unaffected — but confirm against `ChromeHeightTests`, which measures
  this row.
- Disabled with no Workspace open (issue 03's refusal, surfaced). Tooltip or hint: a Session
  needs somewhere to write.
- Accessibility identifier `session-toggle`.
- Stopping asks for no confirmation. Starting one is cheap and a DM who stops by accident
  starts again; a modal at the table is the thing ADR-0014's reasoning keeps avoiding.

**The names.** `CONTEXT.md` now defines **Setup Toolbar** and **Live Toolbar**. Make the code
say so — this is the whole reason the terms were coined, and a glossary the source ignores is
worse than none:

- Rename the computed properties or add `// MARK:` sections for the two regions:
  `ControlView.swift:205-213` (Open Map, filename, Workspace) and `:224-227` (`modeControls`)
  are the **Setup Toolbar**; `:261-265` is the **Live Toolbar**.
- Keep `modeControls` as the name of what it is — it is a *part* of the Setup Toolbar, not the
  whole of it.
- A doc comment on each naming the term and pointing at `CONTEXT.md`, in the house style.

Do **not** restructure the rows. The Setup Toolbar spanning two non-adjacent rows is a fact
about the current layout, and merging them is a layout change with height consequences that
this issue has no reason to take on.

## Tests

- `MapForgeUITests`: `session-toggle` exists, is disabled without a Workspace, and its label
  changes after a press.
- `ChromeHeightTests` still passes — the added control must not change the row's height.

## Acceptance

A DM with a Workspace open can start and stop a Session from the row that holds the fog switch.
The code names the two toolbars as `CONTEXT.md` does.
