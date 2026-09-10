import SwiftUI

/// The marker shown under the cursor while a Measurement Shape is armed and waiting for
/// the click that says where it starts.
///
/// An armed tool draws nothing on the Map yet, so without this it is indistinguishable
/// from an idle one — and the click that would place an Origin looks like a click that
/// does nothing. Green, because it is the Measurement about to exist.
///
/// The Control Window only. The table has no use for watching a crosshair hunt for a
/// point, and the Player Display's rule is narrow on purpose (ADR 0005): it shows what
/// the table is entitled to know, and a Measurement being aimed is not yet an answer.
struct MeasurementCrosshair: View {
    /// Fixed size, like the readout capsule and unlike a Pawn token: this marks where the
    /// pointer is, which is a fact about the cursor rather than about the Map.
    private let arm: CGFloat = 9

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: -arm, y: 0))
                path.addLine(to: CGPoint(x: arm, y: 0))
                path.move(to: CGPoint(x: 0, y: -arm))
                path.addLine(to: CGPoint(x: 0, y: arm))
            }
            // A dark halo under the stroke: green on a lit tavern floor is otherwise
            // invisible, and this is the one thing on screen saying the tool is live.
            .stroke(Color.black.opacity(0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Path { path in
                path.move(to: CGPoint(x: -arm, y: 0))
                path.addLine(to: CGPoint(x: arm, y: 0))
                path.move(to: CGPoint(x: 0, y: -arm))
                path.addLine(to: CGPoint(x: 0, y: arm))
            }
            .stroke(Color.green, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .frame(width: arm * 2, height: arm * 2)
        .allowsHitTesting(false)
    }
}
