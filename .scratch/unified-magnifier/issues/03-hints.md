# 03 — The hint row says it once

Status: ready-for-agent
Blocked by: 02

The gestures no longer belong to one mode, so they are described once, on the surface the DM
uses most.

## What to do

In `ControlView` (`:1354` onward):

- `liveViewHint` — replace "Scroll to zoom — the players see none of it." with
  "Scroll or pinch to zoom; two-finger or middle-drag to pan — the players see none of it."
- `gridFitHint` — drop "scroll to zoom, ⌥-drag to pan".
- `wallEditorHint`, `viewportHint` — unchanged. The Wall Editor's already fills both lines.

## Tests

`ChromeHeightTests` measures the tallest hint against `modeHintRowHeight`; the new Live View
hint must still fit in two lines. If it does not, shorten the text, not the rule.
