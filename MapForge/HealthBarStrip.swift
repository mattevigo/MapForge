import SwiftUI

/// The bar itself: the track, the fill in its tier's colour, and the temporary hit points
/// straight after it in teal — and no digits, ever (ADR-0036).
///
/// One view for both screens: the Player Display's strip under each token and the DM's rows
/// (`HealthBarReadout`). Fractions come from `HealthBar`, so the DM's bar and the table's
/// are cut at the same point. It fills whatever frame its caller gives it.
///
/// Drawn **beside** `PawnToken` and never inside it: the token must look the same on both
/// screens, and only the Player Display draws a bar on the Map.
struct HealthBarStrip: View {
    let bar: HealthBar

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                // Drawn at 0 too: an empty track is how a Pawn that is down reads.
                Rectangle().fill(HealthBar.trackColor)
                Rectangle()
                    .fill(HealthBar.temporaryColor)
                    .frame(width: width * (bar.fill + bar.temporary))
                Rectangle()
                    .fill(bar.tier.color)
                    .frame(width: width * bar.fill)
            }
        }
        .clipShape(Capsule())
    }
}
