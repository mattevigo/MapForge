import SwiftUI

/// A Health Bar as the table sees it: a track, a fill in its tier's colour and a teal
/// segment for temporary hit points — and no digits, ever (ADR-0036).
///
/// Its own view, drawn **beside** `PawnToken` and never inside it: the token must look the
/// same on both screens, and only the Player Display draws a bar. Sized by its caller from
/// `HealthBar.frame(below:squareSide:squaresAcross:)`; it fills whatever frame it is given.
struct HealthBarStrip: View {
    let bar: HealthBar

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let shape = RoundedRectangle(cornerRadius: geo.size.height / 2)
            // The track first, at full width, so a Pawn at 0 still has a bar — an empty one,
            // which is how the table sees it is down rather than barless.
            ZStack(alignment: .leading) {
                HealthBar.trackColor
                HStack(spacing: 0) {
                    bar.tier.color
                        .frame(width: width * bar.fill)
                    HealthBar.temporaryColor
                        .frame(width: width * bar.temporary)
                }
            }
            .clipShape(shape)
            .overlay(shape.stroke(Color.black.opacity(0.6), lineWidth: 0.5))
        }
        // Information the DM's screen already speaks in words; nothing here for a
        // reader of the table's screen to announce.
        .accessibilityHidden(true)
    }
}
