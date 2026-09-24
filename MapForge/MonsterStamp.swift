import Foundation

/// What saying "this Creature is that Monster" copies onto the Pawn — the decisions, kept out
/// of the sheet and out of `AppState` so they can be proved without either.
///
/// A sibling of `Stamp`, which does the same for a Character, and a **copy** for the same
/// reason (ADR-0007, ADR-0020): the numbers are taken now, and the Pawn then leads its own
/// life. Nothing here reads the Bestiary again afterwards.
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

    // MARK: The label

    /// The label a Pawn takes on becoming `monster`: "GG1", "GG2" for two Gnoll Guerrieri.
    ///
    /// Only a label that is still the bare number the Pawn was born with
    /// (`Pawn.nextLabel`) is replaced — anything else is something the DM typed, and is
    /// theirs. Numbered one past the highest label of the same initials on the Map, whatever
    /// Monster it belongs to: Gnoll Guerriero and Goblin Guerriero share "GG" and share one
    /// run of numbers, because what a label is *for* in the Order is telling two rows apart.
    static func label(for monster: Monster, replacing label: String, among pawns: [Pawn]) -> String {
        guard Int(label) != nil else { return label }
        let prefix = initials(of: monster.name)
        guard !prefix.isEmpty else { return label }
        let highest = pawns.compactMap { pawn -> Int? in
            guard pawn.label.hasPrefix(prefix) else { return nil }
            return Int(pawn.label.dropFirst(prefix.count))
        }.max() ?? 0
        return "\(prefix)\(highest + 1)"
    }

    /// The first letter of each word, capitalised — or the first two letters of a name that
    /// is one word, because "W1" is too thin to read at a glance. Punctuation is stepped
    /// over, so "(antica)" gives A and "d'Ossa" gives D.
    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
            .map { $0.filter(\.isLetter) }
            .filter { !$0.isEmpty }
        guard words.count != 1 else {
            let word = words[0]
            return word.prefix(1).uppercased() + word.dropFirst().prefix(1).lowercased()
        }
        return words.map { $0.prefix(1).uppercased() }.joined()
    }
}
