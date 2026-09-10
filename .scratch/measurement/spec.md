# Measurement

A DM asks a distance mid-play — is the dragon in range, does the fireball catch the rogue —
by right-clicking the Map. A shape is drawn from an Origin towards the cursor, labelled with
its length in metres, on both screens. Right-click again dismisses it.

See `CONTEXT.md` for **Measurement**, **Measurement Shape**, **Measurement Origin** and
**Distance Unit**. See ADR-0005 for why the table sees the number.

## Decisions

Settled in a grilling session; the reasoning is here so the issues don't re-litigate it.

**One at a time, never persisted.** `AppState` holds an optional Measurement beside
`isFogOverlayOn` and `soloSightPawnID` (`AppState.swift:242-252`) — the template for
transient both-screens state. One optional rather than a set, following ADR-0004's reasoning
on `Pawn.ID?`: a strict subset that upgrades cleanly if a real use case appears. Multiples
would also make "right-click dismisses" ambiguous.

**It lives in `.normal` mode.** Measuring is a live performance action in the same class as
Solo Sight and dragging a Pawn, and those live in the mirror. The cost is real and is
accepted: the normal-mode mirror has no absolute view→map inverse today — `PawnLayer.swift:63-64`
open-codes only a *delta* conversion — and no hover tracking at all. Both are built here
rather than moving the feature to a mode that already has them.

**A Measurement rubber-bands until it is settled.** Moving the mouse aims and sizes it;
left-clicking settles the distance so it stops following, and a second left-click un-settles
it. This was missed on the first pass — the design replaced the original "left click to see
the amount" with a live preview and dropped the commit step with it, leaving a Measurement
that could never be read without holding the mouse still. That is the option ADR-0005
rejected under another name: evidence that vanishes the moment the table wants to discuss
it. Typing a distance settles it too. The *aim* keeps following the cursor either way.

**Right-click chooses the shape; left-click drives everything else.** The first design put
the shape picker in the window chrome, reasoning from the four gesture-composition defects
`ControlView.swift` records — but `.contextMenu` is a modifier, not a composed gesture, so
that reasoning did not apply. Choosing the shape belongs where the DM is already pointing.

The menu says *what* to measure and the click after it says *where*. Taking the Origin from
the right-click itself was the second design and it conflated the two, forcing the DM to
open the menu at exactly the point they meant to measure from — a menu is not a precise
instrument. So: right-click, pick a shape, and the tool is armed with a crosshair under the
cursor; left-click places the Origin; move to aim and size; left-click again settles the
distance; left-click once more clears it. Each click advances one step, and the last-used
shape is sticky so the menu opens on it.

Esc backs out of an armed tool, and right-click reopens the menu. The crosshair is the
Control Window's alone — an armed tool draws nothing on the Map, so without it the DM
cannot tell a live tool from an idle one, while the table has no use for watching a
crosshair hunt for a point.

**Metres now, feet later — so the unit is a parameter from day one.** Distances are stored
in Grid squares, as `Light` and `Pawn` already store them, and converted at the rendering
edge by a `DistanceUnit`. Shipping with a hardcoded `.metres` is fine; a `* 1.5` scattered
across call sites is not, because that is what makes the feet switch a hunt-and-peck.

**Walls do not block a Measurement.** 5e range is measured through obstacles, and reusing
`Visibility.compute` would put a Measurement into `VisibilityCache.Inputs`
(`VisibilityCache.swift:16-22`) and invalidate lighting on every mouse move.

**Square is a side length, not a radius.** A spell card says "a 20-foot cube", so typing 6
gives a 6 m box, not a 12 m one. This deliberately breaks the "Square and Circle are both
radius measures" symmetry of the original request; the readout says "6 m across" against the
Circle's "6 m radius" so the difference is visible.

**Cone is 53.13°** (`2·atan(0.5)`) — the 5e cone, as wide at its end as it is long. A 90°
grid-aligned cone would silently mis-measure every fireball, which is the one thing a
measuring tool must not do.

**Available only with a declared Grid.** Without one there is no squares-to-metres
conversion (ADR-0003), so the tool refuses rather than showing a wrong number — the same
posture as Solo Sight being unavailable on a hidden Pawn.

## Deferred

- **Feet.** The `DistanceUnit` enum ships with one case. Adding `.feet` is a case and a
  picker.
- **Light and Pawn inspectors in metres.** They say "squares" today
  (`ControlView.swift:562, 837`), so a Measurement reading "9 m" sits next to a Light reading
  "6 squares". Converting them is a separate change with its own persistence question.
- **A Line with width** (the lightning-bolt template) — Line is a bare ruler for now.
- **Multiple simultaneous Measurements.**

## Issues

- `01` — the Measurement model and the metres conversion
- `02` — right-click to start and dismiss, with the Pawn-anchored Origin
- `03` — drawing the shape and the readout on both screens
- `04` — the Measurement Shape picker in the Control chrome
- `05` — typing a distance
