import Foundation

/// What a Character's row in the Party panel shows of its hit points: the DM's exact Health
/// Bar, the numbers as the Encounter tab writes them, and its exhaustion level when it has
/// any (ADR-0036, ADR-0037).
///
/// Pure, so what the row shows is decided where a test can reach it, and the row's view only
/// draws it. Read from the Block a Stamp would give one of its Pawns right now —
/// `Stamp.statBlock(from:of:)` — so the roster and a Pawn dropped from it cannot disagree
/// about how hurt the Character is.
struct CharacterHitPoints: Equatable {
    /// The DM's exact Health Bar, or nil when the note gives no maximum to be a fraction of.
    let bar: HealthBar?
    /// `current+temp/max`, or nil on the same terms as `bar`.
    let numbers: HitPointNumbers?
    /// Its exhaustion level, or nil at 0, which shows no marker at all. Shown whether or not
    /// the note gives a maximum: exhaustion is shared on its own terms, not the hit points'.
    let exhaustion: Exhaustion?

    /// What `character`'s row shows, read from `note` — the note the app found for it — or
    /// nil, for a Character with no note, or whose note cannot be found: it has no shared
    /// numbers, and its Pawns keep their own, as a Creature's do (ADR-0037).
    init?(character: PartyCharacter, note: CharacterNote?) {
        guard let block = Stamp.statBlock(from: note, of: character) else { return nil }
        bar = HealthBar(kind: .player, stats: block)
        numbers = HitPointNumbers(stats: block)
        exhaustion = block.exhaustion > 0 ? Exhaustion(level: block.exhaustion) : nil
    }

    /// What the row's bar and numbers say when pointed at: the tier, in words, so it is never
    /// told by colour alone, and that every Pawn of the Character shows these same numbers.
    ///
    /// Nothing about the table, unlike a Pawn's row (`HealthBarReadout.tooltip`): whether the
    /// table sees a bar is each Pawn's own switch, and a Character has none — it is never on
    /// a Map. One sentence per tier, the tier after the dash, as `HealthBarReadout` writes it
    /// (ADR-0022).
    static func tooltip(for tier: HealthBar.Tier) -> String {
        switch tier {
        case .healthy:
            return String(localized: "Shared by every Pawn of this Character, on every Map — Healthy.")
        case .bloodied:
            return String(localized: "Shared by every Pawn of this Character, on every Map — Bloodied.")
        case .critical:
            return String(localized: "Shared by every Pawn of this Character, on every Map — Critical.")
        }
    }

    /// The short marker the Encounter tab writes beside a Combatant's Conditions, and the
    /// tooltip that names the level, so the level is never told by a glyph alone.
    struct Exhaustion: Equatable {
        let level: Int
        /// The Encounter tab's own string, so each language's initial for exhaustion is the
        /// same in both places.
        var marker: String { String(localized: "E\(level)") }
        var tooltip: String { String(localized: "Exhaustion \(level)") }
    }
}

/// A Stat Block's hit points as the DM reads them on the Control Window: `current+temp/max`.
/// Drawn by `HitPointNumbersText`, in the Encounter tab's rows and the Party panel's alike.
struct HitPointNumbers: Equatable {
    let current: Int
    let temporary: Int
    let max: Int

    /// Nil when the block lacks either total.
    init?(stats: StatBlock) {
        guard let current = stats.currentHP, let max = stats.maxHP else { return nil }
        self.current = current
        temporary = stats.temporaryHP
        self.max = max
    }

    /// The three parts in the order they are written, each drawn in its own colour.
    var currentText: String { "\(current)" }
    /// Nil with no temporary hit points, which are then not written at all.
    var temporaryText: String? { temporary > 0 ? "+\(temporary)" : nil }
    var maxText: String { "/\(max)" }

    /// The whole, as one string.
    var text: String { currentText + (temporaryText ?? "") + maxText }
}
