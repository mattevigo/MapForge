import SwiftUI

/// The colours a Health Bar is drawn in — kept apart from `HealthBar`, which stays pure, and
/// in one place because two surfaces draw it: the Player Display's strip and the DM's rows.
/// The DM's row is coloured by the tier the table is being shown, so the two must never
/// disagree about which colour Bloodied is.
extension HealthBar.Tier {
    var color: Color {
        switch self {
        case .healthy: return .green
        case .bloodied: return .orange
        case .critical: return .red
        }
    }
}

extension HealthBar {
    /// Temporary hit points, after the fill. Teal because the Encounter tab already writes
    /// `+temp` in teal, so the DM reads the segment and the number as one thing.
    static let temporaryColor = Color.teal

    /// The empty part of the bar — what stays visible at 0, which is how the table sees a
    /// Pawn is down rather than barless.
    static let trackColor = Color.black.opacity(0.55)

    /// The table's empty track: near-black with blood in it, opaque so the Map under the
    /// token never shows through and passes for fill.
    static let tableTrackColor = Color(red: 0.16, green: 0.03, blue: 0.03)

    /// The frame round the table's bar, which keeps its edge on a black Map and a white one.
    static let tableFrameColor = Color.black

    /// The rim at the frame's outer edge, the dull bronze a game's enemy bar is set in, so the
    /// bar keeps an edge on a black Map too.
    static let tableRimColor = Color(red: 0.62, green: 0.50, blue: 0.32)
}
