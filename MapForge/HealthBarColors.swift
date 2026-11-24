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
}
