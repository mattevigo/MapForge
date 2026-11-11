# 01 — The bar reserves its height

Status: ready-for-agent

Structural, and deliberately alone: the strip exists, at the right height, showing nothing
worth reading. Everything else in this feature depends on it. Nothing depends on the content
decisions, so 02 through 06 can follow in any order.

## The problem

There is no bottom-of-window UI anywhere in the Control Window. `ControlView.body`
(`ControlView.swift:95-221`) ends with the `HStack { preview; livePanel }` at `:168-171`, and
both children claim the remaining height. A `grep` for `statusBar|footer|toolbar|ToolbarItem`
returns nothing.

Adding a row is easy. Adding one that does not break the preview is the whole issue.
`ControlView.swift:141-152` records the bug class in the codebase's own words:

> anything in this stack that appears or vanishes resizes the preview

A conditionally-shown row steals height from the preview, which shrinks the `GeometryReader`
the preview's transform arithmetic measures against, and the Map **visibly jumps mid-click**.
The existing remedy is `fogInspectorRowHeight: CGFloat = 24` (`:874`) — a constant reserved
height so the row costs the same empty or full — plus the testable-by-design helper
`fogPreviewContainer(geometry:hasInspectorSelection:)` (`:883-885`), tested in
`MapForgeTests/PreviewContainerStabilityTests.swift` and `FogInspectorRowHeightTests.swift`.

## Build

**A new `SupportBar.swift`**, a view taking a single string (or nothing) and rendering it at
`Self.height`, a constant on the view in the style of `fogInspectorRowHeight`.

**Mounted after `:171`**, inside the outer `VStack` so it sits below both the preview and the
live panel. Not `.safeAreaInset` — the preview's transform arithmetic measures the
`GeometryReader` inside this stack, and a safe-area inset changes what that reader reports in
a way the existing stability tests do not model.

**The height is derived from the longest content it must hold**, which issue 03 determines —
the three existing mode captions are the longest prose in the app and carry `⌥-drag`, `⇧`,
`⌫` and `Esc`. Size for those now, in the same way `FogInspectorRowHeightTests` sizes for both
inspectors, and accept two lines if one will not do. A bar that truncates the fog caption is
worse than the caption staying where it is.

**Visually**, follow the established surface convention: `Color(nsColor: .textBackgroundColor)`
with a `RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))`, matching
`ControlView.swift:1248-1250` and `CombatPanel.swift:29-31`. Text is `.caption`
`.foregroundStyle(.secondary)`, as the mode captions already are (`:129`, `:134`, `:139`).

**The window's `minHeight` goes up by the bar's height.** It is 400 today (`:177`). The
preview must not be squeezed to buy the bar its room.

## Tests

- `SupportBarHeightTests.swift`, mirroring `FogInspectorRowHeightTests`: a mirror view holding
  the longest string the bar must show, asserting `SupportBar.height` fits it and is not
  needlessly taller.
- A `PreviewContainerStabilityTests`-style assertion that the preview container's height is
  the same whether the bar has content or not.
- A UI test that the preview does not resize when the bar's content changes. Note the finding
  in `initiative-tracker` issue 04's comments: the live panel's `ScrollView` publishes as
  Disabled on macOS, so anything inside it must be clicked by coordinate and `isHittable` will
  always be false. The bar is outside that `ScrollView` and should not inherit the problem —
  confirm that rather than assuming it.

## Done when

The Control Window has an empty strip along its bottom at a constant height, the preview's
measured container is unchanged by whatever the strip holds, and the height is justified by a
test rather than by eye.

## Comments
