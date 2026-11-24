import Foundation

/// The strip under a Pawn on the Player Display that tells the table how hurt it is, never
/// by how much (`CONTEXT.md`, **Health Bar**; ADR-0036).
///
/// Pure, and nothing but the arithmetic, so the line between Healthy and Bloodied is
/// decided in one place a test can reach — the Player Display draws it and the DM's rows
/// show which tier the table is seeing, and two answers to that would be a DM telling the
/// table one thing while the screen says another.
struct HealthBar: Equatable {
    /// The colour of the bar. The bounds halve: the second half of a creature's hit points
    /// is where a fight's drama is, and Bloodied at a half is the rulebook's own line
    /// (ADR-0022), so the table's word and the app's agree.
    enum Tier: Equatable {
        /// Above half.
        case healthy
        /// At half or below.
        case bloodied
        /// At a quarter or below — and at 0, where the bar is empty.
        case critical
    }

    /// How much of the bar is filled, 0…1: current hit points over maximum. Linear — a
    /// sharp-eyed player can read it to within a tenth, and that is accepted (ADR-0036).
    let fill: Double

    /// How much of the bar the temporary hit points take, drawn straight after the fill:
    /// temporary over maximum, cut off so `fill + temporary` never passes 1. They lengthen
    /// the bar and never colour it — see `tier`.
    let temporary: Double

    /// Why the table is not being shown a bar it would otherwise see — one answer per
    /// switch the DM can withhold it with (ADR-0036). Decided by
    /// `PlayerVisibility.healthBarWithholding`.
    enum Withholding: Equatable {
        /// The Live Toolbar's **Health Bars** switch is off: no bar reaches the table tonight.
        case allBars
        /// This Pawn's **Show Health Bar to players** is off, in its Stat Block.
        case thisPawn
    }

    /// Read from current over maximum alone. Temporary hit points never move it: the rules
    /// do not let them stop a creature being Bloodied.
    let tier: Tier

    /// The bar a Pawn of this kind with these numbers carries, or nil for none.
    ///
    /// None for a Treasure — a chest with hit points typed into it is still a chest — and
    /// none when the Stat Block lacks either total, or has a maximum with nothing to be a
    /// fraction of: a guessed bar would tell the table something the DM never said.
    init?(kind: PawnKind, stats: StatBlock) {
        // `PawnKind`'s own rule, so the bar and the sheet's toggle cannot disagree about who
        // carries one, and a fourth kind has to decide.
        guard kind.carriesHealthBar else { return nil }
        guard let current = stats.currentHP, let max = stats.maxHP, max > 0 else { return nil }
        fill = Swift.min(Swift.max(Double(current) / Double(max), 0), 1)
        temporary = Swift.min(Swift.max(Double(stats.temporaryHP) / Double(max), 0), 1 - fill)
        // Compared in whole hit points rather than as a fraction, so 25 of 100 is exactly a
        // quarter and not a rounding error either side of one.
        if current * 4 <= max {
            tier = .critical
        } else if current * 2 <= max {
            tier = .bloodied
        } else {
            tier = .healthy
        }
    }
}
