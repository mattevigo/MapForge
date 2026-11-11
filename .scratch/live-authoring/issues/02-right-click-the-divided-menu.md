# 02 — Right-click on a Pawn or a Light: the divided menu

Status: ready-for-human
Blocked by: 01

Right-click on a Pawn or a Light Marker in the Live View opens one menu: `Edit…` and `Delete`
above a divider, the Measurement Shapes below. Right-click on empty Map is unchanged.

## Why right-click, and why one menu

Left-click on a Pawn is already the drag (`PawnLayer.swift:68-85`), and the Measurement state
machine owns left-click when armed (`ControlView.swift:426-429`, `including: isMeasuring ?
.all : .subviews`). Right-click already opens the menu these items join, so there is nothing
to displace and no divider to invent — `.contextMenu` draws one between `Section`s.

## Extend the hit-test that already exists

`measurementUnderCursor` (`ControlView.swift:785-805`) already does exactly this: hit-test
under `mirrorCursor`, pinned first, return what was hit. Add the Pawn and Light cases beside
it rather than writing a second one — one function answering "what is under the cursor" is
how the menu stays consistent with what the DM thinks they clicked.

Order the hit-test deliberately and write the order down: **Pawn, then Light Marker, then
Measurement**. A Light Marker under a Pawn is the common overlap (a Pawn *is* a Light), and
the Pawn is the thing the DM means. A Big Pawn's 2×2 footprint is its hit area
(`PawnBounds`, `Pawn.squaresAcross`).

Read the cursor from `mirrorCursor` (`ControlView.swift:51`), never from the `NSEvent` — the
event carries no usable location, and the reason is documented at `RightClick.swift:6-16`.
This has already been got wrong once in this codebase.

## The menu

```
Edit…              ← opens the sheet from 03
Delete             ← 05
─────────
Cone / Square / Circle / Line    ← unchanged
```

Rules:

- The Measurement section keeps its existing behaviour exactly, including the
  `measurementAvailability` refusal text when there is no Grid or no Map
  (`MeasurementControl.swift:19-28`). Do not let the Pawn items suppress it — a DM
  right-clicking a Pawn with no Grid declared should still be told why they cannot measure.
- While a Line chain is in progress (`isChaining`) the whole menu stays withheld, as today:
  right-click then finishes the chain (`ControlView.swift:421`, `rightClick()` :827-839).
- Right-click on a Measurement shape keeps offering Pin/Unpin instead of the shape list, as
  today. If a Pawn and a Measurement overlap, the Pawn wins the top section and Pin/Unpin
  takes the bottom — both, not either.

## Tests

- Right-click on a Pawn yields the Pawn items; on empty Map, it does not.
- A Light Marker under a Pawn yields the Pawn's items, not the Light's.
- A Big Pawn is hit across its full 2×2 footprint.
- With no declared Grid, a right-click on a Pawn still shows `Edit…` and still shows the
  Measurement refusal text.
- Mid-chain, right-click finishes the chain and opens no menu.
- The hit-test agrees with `mirrorCursor` after the preview has been resized.

## Done when

The menu opens with the right items on the right object. `Edit…` and `Delete` may be inert
stubs — `03` and `05` fill them.
