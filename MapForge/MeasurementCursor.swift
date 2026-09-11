import SwiftUI

/// The marker shown under the cursor while a Measurement Shape is armed and waiting for
/// the click that says where it starts.
///
/// An armed tool draws nothing on the Map yet, so without this it is indistinguishable
/// from an idle one — and the click that would place an Origin looks like a click that
/// does nothing. A ruler rather than a crosshair: it says *what* the next click will do,
/// where a bare cross says only "something is armed".
///
/// The Control Window only. The table has no use for watching a ruler hunt for a point,
/// and the Player Display's rule is narrow on purpose (ADR 0005): it shows what the table
/// is entitled to know, and a Measurement being aimed is not yet an answer.
struct MeasurementCursor: View {
    /// Fixed size, like the readout capsule and unlike a Pawn token: this marks where the
    /// pointer is, which is a fact about the cursor rather than about the Map.
    private let side: CGFloat = 15

    var body: some View {
        Image(systemName: "ruler")
            .font(.system(size: side, weight: .semibold))
            .foregroundStyle(.green)
            // A dark halo under the glyph: green on a lit tavern floor is otherwise
            // invisible, and this is the one thing on screen saying the tool is live.
            .shadow(color: .black.opacity(0.7), radius: 1)
            .shadow(color: .black.opacity(0.4), radius: 3)
            // Offset so the glyph sits beside the point it is about to place rather than
            // covering it — the cursor's own tip is what the DM is aiming with.
            .offset(x: side * 0.7, y: side * 0.7)
            .allowsHitTesting(false)
    }
}
