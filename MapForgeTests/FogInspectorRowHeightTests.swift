import XCTest
import SwiftUI
@testable import MapForge

/// The reserved inspector row must be tall enough for the real inspectors.
///
/// `fogInspectorRowHeight` is a hand-picked constant, which is the one weak point in the
/// fix for the "zoom changes while I select" glitch: reserving a row shorter than the
/// controls it holds would clip them, and reserving one taller than needed wastes preview
/// height. Both inspectors are measured here against the real SwiftUI layout so the
/// constant cannot silently drift away from the views it is sized for.
final class FogInspectorRowHeightTests: XCTestCase {

    /// The Pawn inspector's controls, in the arrangement `ControlView` builds them.
    /// Mirrors the real row's widths and `.callout` font — the rounded-border text fields
    /// and the menu picker are what set the height floor.
    private struct PawnInspectorRow: View {
        var body: some View {
            HStack(spacing: 10) {
                TextField("label", text: .constant("1"))
                    .textFieldStyle(.roundedBorder).frame(width: 90)
                ColorPicker("", selection: .constant(.red), supportsOpacity: false)
                    .labelsHidden()
                Picker("", selection: .constant(PawnKind.player)) {
                    ForEach(PawnKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 104)
                Toggle("Big", isOn: .constant(false))
                Text("Sight:")
                TextField("range", value: .constant(6.0), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 52)
                Text("squares").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private struct LightInspectorRow: View {
        var body: some View {
            HStack(spacing: 10) {
                // The name field, added when Lights gained names. Mirrors the real row: if
                // this drifts from `ControlView.lightInspector` the constant stops being
                // measured against what it actually reserves room for.
                TextField("name", text: .constant("trapped brazier"))
                    .textFieldStyle(.roundedBorder).frame(width: 110)
                Text("Bright:")
                TextField("bright", value: .constant(4.0), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 52)
                Text("Dim:")
                TextField("dim", value: .constant(8.0), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 52)
                Text("squares").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    @MainActor
    private func fittingHeight<V: View>(_ view: V) -> CGFloat {
        NSHostingView(rootView: view).fittingSize.height
    }

    @MainActor
    func testTheReservedRowFitsBothInspectors() {
        let pawn = fittingHeight(PawnInspectorRow())
        let light = fittingHeight(LightInspectorRow())

        XCTAssertGreaterThanOrEqual(ControlView.fogInspectorRowHeight, pawn,
                                    "the reserved row is shorter than the Pawn inspector — it will clip")
        XCTAssertGreaterThanOrEqual(ControlView.fogInspectorRowHeight, light,
                                    "the reserved row is shorter than the Light inspector — it will clip")
    }

    /// And not needlessly tall: every point reserved here is a point the preview loses.
    @MainActor
    func testTheReservedRowDoesNotWastePreviewHeight() {
        let tallest = max(fittingHeight(PawnInspectorRow()), fittingHeight(LightInspectorRow()))
        XCTAssertLessThanOrEqual(ControlView.fogInspectorRowHeight - tallest, 8,
                                 "the reserved row is \(ControlView.fogInspectorRowHeight) pt for a \(tallest) pt inspector")
    }
}
