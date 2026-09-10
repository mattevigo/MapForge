# 01 — The Measurement model and the metres conversion

Status: ready-for-agent

The pure, testable core: what a Measurement *is*, what shape it projects, and how a distance
in Grid squares becomes "9 m". No views, no gestures.

## Build

**`Squares` and `DistanceUnit`.** A distance value type wrapping a `CGFloat` count of Grid
squares, and an enum with one case, `.metres`, at 1.5 m per square. Formatting lives on the
unit. The unit is a hardcoded constant in one named place — no preference, no persistence —
but the enum is shaped so `.feet` (5 ft per square) is one case and one picker later. This
matters more than it looks: see the spec's note on why `* 1.5` at call sites is the thing to
avoid.

Positions already have `MapPoint` for exactly this reason (`FogDocument.swift:21-27`);
distances are currently bare `CGFloat`s named `brightSquares`/`dimSquares`. Do **not**
retrofit `Light` and `Pawn` here — new code only.

**`MeasurementShape`.** `.cone`, `.square`, `.circle`, `.line`.

**`MeasurementOrigin`.** Either a `MapPoint` or a `Pawn.ID`. A sum type, not a point plus an
optional ID — the two cases resolve differently and only one of them can go stale.

**`Measurement`.** Origin, shape, distance in `Squares`, and a direction (needed by `.cone`
and `.line`, ignored by the radius shapes).

**Projection.** A pure function from a `Measurement` plus the pixels-per-square to a
`Polygon` in image pixels. `Polygon` already exists (`Polygon.swift:8`) and `FogCanvas`
already converts one to a `Path`, so producing one means the drawing issue has nothing to
invent.

- **Circle** — radius. Approximate with a vertex count that stays smooth at True Scale.
- **Square** — the distance is the **side length**, centred on the Origin. Typing 6 gives a
  6 m × 6 m box. Deliberate; see the spec.
- **Cone** — apex at the Origin, 53.13° total (`2·atan(0.5)`), length along the direction.
- **Line** — a bare segment from the Origin. A degenerate polygon is fine, or return the two
  points; the drawing issue strokes it rather than filling it.

**Readout text.** "6 m radius" for Circle, "6 m across" for Square, plain "9 m" for Cone and
Line. The distinction is the whole reason Square-as-side-length is safe.

**Snapping.** A helper rounding a free distance to the nearest whole square (1.5 m). Used by
dragging, bypassed by typing.

## Tests

Unit tests, no UI. The geometry is the part that must not be wrong:

- A 5e cone's width at its end equals its length (the 53.13° property, stated as the
  invariant rather than as a hardcoded vertex list).
- Square of distance *d* spans *d* across, not *2d* — the regression this decision exists to
  prevent.
- Circle of distance *d* spans *2d* across.
- Squares→metres at 1.5, and a `DistanceUnit` round-trip that would catch a hardcoded 1.5
  elsewhere.
- Snapping lands on square multiples.

## Done when

The model and projection are covered by tests and nothing else imports a `1.5`.
