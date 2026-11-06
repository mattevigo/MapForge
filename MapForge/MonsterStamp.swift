import Foundation

/// What saying "this Creature is that Monster" copies onto the Pawn — the decisions, kept out
/// of the sheet and out of `AppState` so they can be proved without either.
///
/// A sibling of `Stamp`, which does the same for a Character, and a **copy** for the same
/// reason (ADR-0007, ADR-0020): the numbers are taken now, and the Pawn then leads its own
/// life. Nothing here reads the Bestiary again afterwards.
///
/// The numbers only: the label and the Face a Monster gives follow the rule an Item's do, and
/// are `DefinitionStamp`'s.
enum MonsterStamp {
    /// `existing` as the Monster leaves it.
    ///
    /// Becoming a Monster means arriving whole, so current hit points are set to the
    /// maximum — including over a wound, which is why `healing(from:over:)` exists and the
    /// sheet asks first (ADR-0021). What belongs to the fight rather than to the creature —
    /// temporary hit points, Conditions, exhaustion, concentration, the roster — is left
    /// exactly as it was.
    ///
    /// A number the note lacks is not stamped: a Monster with no `hp` must not wipe hit
    /// points a DM typed by hand.
    static func statBlock(from monster: Monster, over existing: StatBlock) -> StatBlock {
        var block = existing
        if let armorClass = monster.armorClass { block.armorClass = armorClass }
        if let bonus = monster.initiativeBonus { block.initiativeBonus = bonus }
        if let hitPoints = monster.hitPoints {
            block.maxHP = hitPoints
            block.currentHP = hitPoints
        }
        return block
    }

    /// The hit points a stamp would overwrite, in words for the confirmation.
    struct Healing: Equatable {
        /// "12/27" — or "5" when there is no maximum to set it against.
        var before: String
        var after: String
    }

    /// What the stamp would do to hit points that already exist, or nil when it destroys
    /// nothing — a first stamp onto a Pawn with none, a note with no `hp`, a Pawn already at
    /// exactly these numbers. Asked only then, because a dialog that appears when nothing can
    /// be lost is one the DM learns to click through.
    static func healing(from monster: Monster, over existing: StatBlock) -> Healing? {
        guard let current = existing.currentHP else { return nil }
        let after = statBlock(from: monster, over: existing)
        guard after.currentHP != existing.currentHP || after.maxHP != existing.maxHP else {
            return nil
        }
        return Healing(before: hitPoints(current, of: existing.maxHP),
                       after: hitPoints(after.currentHP ?? current, of: after.maxHP))
    }

    private static func hitPoints(_ current: Int, of max: Int?) -> String {
        max.map { "\(current)/\($0)" } ?? "\(current)"
    }
}
