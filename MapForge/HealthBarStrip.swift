import SwiftUI

/// The bar itself: the track, the fill in its tier's colour, and the temporary hit points
/// straight after it in teal — and no digits, ever (ADR-0036).
///
/// One view for both screens: the Player Display's strip under each token and the DM's rows
/// (`HealthBarRowBar`). Fractions come from `HealthBar`, so the DM's bar and the table's are
/// cut at the same point; only the look differs (`Style`). It fills whatever frame its caller
/// gives it.
///
/// Drawn **beside** `PawnToken` and never inside it: the token must look the same on both
/// screens, and only the Player Display draws a bar on the Map.
struct HealthBarStrip: View {
    /// How the bar is dressed. The fill, its colour and where it is cut are the same in both.
    enum Style {
        /// A plain rounded strip, on the Control Window's panel.
        case row
        /// The table's: square-ended in a black frame with a bronze rim, over a near-black
        /// blood-red track, the
        /// fill glossed lighter above and darker below — the look of a game's enemy health bar,
        /// so it reads as one across the room over any Map, light or dark.
        case table
    }

    let bar: HealthBar
    var style: Style = .row
    /// The empty part, for `.row`: the DM's rows pass one that reads on the panel in light and
    /// dark appearance alike. `.table` draws its own.
    var track: Color = HealthBar.trackColor

    var body: some View {
        switch style {
        case .row:
            segments(track: track)
                .clipShape(Capsule())
        case .table:
            GeometryReader { geometry in
                let frame = Self.frameWidth(forHeight: geometry.size.height)
                segments(track: HealthBar.tableTrackColor)
                    .overlay(gloss)
                    .padding(frame)
                    .background(HealthBar.tableFrameColor)
                    // A hairline of bronze outside the black: on a dark Map the black frame
                    // and the empty track sink into it, and a Pawn that is down would lose its
                    // bar rather than show an empty one.
                    .overlay(Rectangle().strokeBorder(HealthBar.tableRimColor,
                                                      lineWidth: frame / 2))
            }
        }
    }

    /// The track, then the temporary segment, then the fill over it — the fill drawn last so a
    /// rounding slip between the two widths can never let teal show through the tier's colour.
    private func segments(track: Color) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                // Drawn at 0 too: an empty track is how a Pawn that is down reads.
                Rectangle().fill(track)
                Rectangle()
                    .fill(HealthBar.temporaryColor)
                    .frame(width: width * (bar.fill + bar.temporary))
                Rectangle()
                    .fill(bar.tier.color)
                    .frame(width: width * bar.fill)
            }
        }
    }

    /// Light along the top edge, shade along the bottom: the fill reads as a rounded tube of
    /// colour rather than a flat stripe. Over the empty track it barely shows, which is right —
    /// there is nothing there to light.
    private var gloss: some View {
        LinearGradient(stops: [.init(color: .white.opacity(0.45), location: 0),
                               .init(color: .white.opacity(0.08), location: 0.45),
                               .init(color: .black.opacity(0.10), location: 0.55),
                               .init(color: .black.opacity(0.40), location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
    }

    /// The black frame around the table's bar: one point, but never more than a sixth of the
    /// bar's height, so at the 4 pt floor the colour inside still outweighs the frame.
    static func frameWidth(forHeight height: CGFloat) -> CGFloat {
        min(1, height / 6)
    }
}
