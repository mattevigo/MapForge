# Visibility is computed as CPU segment polygons, not a shader

The Fog Overlay needs to know, for every point of a Map, whether it is bright, dim or unlit given the Walls and Lights on that Map. We compute this on the CPU as an exact visibility polygon per Light — cast rays at Wall endpoints, sort by angle, and build the lit region as a polygon — then draw the polygons with `SwiftUI.Canvas` and blend modes. The alternative, a Metal fragment shader raymarching per pixel, buys nothing at the scale this app works at: a hand-authored Map has tens of Walls, not thousands, and Walls change only while the DM is editing them, never during play.

## Consequences

The geometry lands in a pure, testable module alongside `ScaleMath` and `ViewportMath`, with no GPU and no rendering context needed to unit-test it — which is the real payoff, because "can the players see round that corner" is exactly the kind of question that must be right and is miserable to verify by eye.

Visibility is computed in Map space and cached until Walls, Lights or Pawns change. Panning the Viewport must never trigger a recompute: it is a drag-rate operation, and issue 09 already cost a round of work on drag smoothness.

Shadow edges at Walls are hard, because a visibility polygon has no notion of penumbra. Soft edges come only from the gradient at a Light's range limit. Area lights with true soft shadows would mean abandoning this approach.

## Considered Options

- **Metal fragment shader, raymarching per pixel** — rejected: real work, a GPU dependency in the test path, and it solves a performance problem this app does not have. Worth revisiting only if Wall counts reach the thousands or soft area shadows become a requirement.
- **A third-party geometry or shadowcasting library** — rejected: no maintained Swift package does segment shadowcasting (that ecosystem is JS VTTs and game engines), so a dependency would supply only intersection primitives we would wrap anyway. This repo has zero third-party code. Revisit if degenerate cases — collinear overlapping Walls, rays through exact vertices — prove harder to get right than expected.
