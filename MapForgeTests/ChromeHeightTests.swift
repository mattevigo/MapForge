import XCTest
import SwiftUI
@testable import MapForge

/// The controls above the preview must cost the same height in every mode.
///
/// This was `FogInspectorRowHeightTests`, which guarded one row inside the fog mode. The
/// defect it was written for is older and wider than that row: **anything** in the stack
/// above the preview that appears or vanishes steals height from the `GeometryReader` the
/// preview is measured against, `fitted(container:)` recomputes to a different scale, and
/// the Map visibly jumps. Within the fog mode that showed up as "the zoom changes while I
/// select"; across modes it showed up as the Map resizing the moment a DM pressed "Edit
/// Fog…", because the Wall Editor's hint added two rows the Live View did not have.
///
/// So the captions share one reserved region rather than each appearing on its own, and the
/// constant is measured against the real SwiftUI layout — a hand-picked number that clips
/// the text it reserves room for would be worse than no reservation at all.
final class ChromeHeightTests: XCTestCase {

    /// A caption as `ControlView` builds it: `.caption`, secondary, wrapped to the line
    /// limit, at a width a narrow Control Window would give it.
    @MainActor
    private func captionHeight(_ text: String, width: CGFloat = 520) -> CGFloat {
        let view = Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(ControlView.modeHintLineLimit)
            .frame(width: width, alignment: .leading)
        return NSHostingView(rootView: view).fittingSize.height
    }

    @MainActor
    func testTheReservedRowFitsEveryModesHint() {
        for hint in ControlView.everyModeHint {
            XCTAssertGreaterThanOrEqual(ControlView.modeHintRowHeight, captionHeight(hint),
                                        "the reserved row clips: \(hint.prefix(40))…")
        }
    }

    /// At a narrow Control Window, where a long hint has the least room to wrap into. The
    /// Wall Editor's is the one that tests this — it is the longest by far, and the two-line
    /// limit is what decides whether its last gesture is readable.
    @MainActor
    func testTheReservedRowFitsTheLongestHintOnANarrowWindow() {
        XCTAssertGreaterThanOrEqual(
            ControlView.modeHintRowHeight,
            captionHeight(ControlView.wallEditorHint, width: 380),
            "the Wall Editor's hint clips on a narrow window")
    }

    /// And not needlessly tall: every point reserved here is a point the preview loses.
    @MainActor
    func testTheReservedRowDoesNotWastePreviewHeight() {
        let tallest = ControlView.everyModeHint.map { captionHeight($0) }.max() ?? 0
        XCTAssertLessThanOrEqual(ControlView.modeHintRowHeight - tallest, 8,
                                 "\(ControlView.modeHintRowHeight) pt reserved for a \(tallest) pt caption")
    }

    /// Two lines, so a long hint wraps rather than being truncated — and no more, or the
    /// reserved row costs the preview more than the hint is worth.
    func testHintsAreAllowedTwoLines() {
        XCTAssertEqual(ControlView.modeHintLineLimit, 2)
    }

    /// The Live View has a hint too — the empty string would reserve a shorter row than the
    /// others and make the height mode-dependent again, which is the whole defect.
    func testEveryModeHasAHintSoTheHeightNeverDependsOnTheMode() {
        XCTAssertFalse(ControlView.everyModeHint.contains(where: \.isEmpty),
                       "an empty hint reserves a different height from a real one")
    }
}
