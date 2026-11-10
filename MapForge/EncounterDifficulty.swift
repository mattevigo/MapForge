import Foundation

/// How hard a fight is for the party, by the rulebook's reckoning — `CONTEXT.md`,
/// **Encounter Difficulty**, and ADR-0032.
///
/// The DMG 2024's *Combat Encounter Difficulty* procedure run backwards: the Creatures' XP,
/// added up, set against the budgets the Players' levels give. Pure, and built from numbers
/// already read: which Pawns are in the fight, and what their notes say, is `AppState`'s
/// business (`AppState.encounterDifficultyReading`). Reference, never state — nothing holds
/// one for longer than it takes to draw it.
struct EncounterDifficulty: Equatable {
    /// What the counted Creatures are worth, added up.
    var creatureXP: Int
    /// The party's three budgets, or nil when no Player counts: with no level there is no
    /// budget, and so no band, and the Creatures' XP stands on its own (ADR-0032).
    var budgets: Budgets?

    init(levels: [CharacterLevel], challengeRatings: [ChallengeRating]) {
        creatureXP = challengeRatings.reduce(0) { $0 + $1.xp }
        budgets = levels.isEmpty ? nil : levels.map(\.budgets).reduce(Budgets(), +)
    }

    /// Where the total falls among the budgets, or nil with no budgets to fall among.
    var band: Band? {
        budgets.map { Band(of: creatureXP, within: $0) }
    }

    /// The XP a party may spend at each band. Ceilings, not marks to reach: the rules say to
    /// "spend as much of your XP budget as you can without going over".
    struct Budgets: Equatable {
        var low = 0
        var moderate = 0
        var high = 0

        static func + (lhs: Budgets, rhs: Budgets) -> Budgets {
            Budgets(low: lhs.low + rhs.low,
                    moderate: lhs.moderate + rhs.moderate,
                    high: lhs.high + rhs.high)
        }
    }

    /// The rulebook's three bands, and the one past them it leaves unnamed.
    ///
    /// No band below Low: a fight that spends little of the Low budget is still Low, and the
    /// bar shows how little. Any cut-off beneath it would be one MapForge invented.
    enum Band: Equatable, CaseIterable {
        case low
        case moderate
        case high
        /// MapForge's own word, for a fight that overspends even the High budget.
        case beyondHigh

        init(of xp: Int, within budgets: Budgets) {
            if xp <= budgets.low {
                self = .low
            } else if xp <= budgets.moderate {
                self = .moderate
            } else if xp <= budgets.high {
                self = .high
            } else {
                self = .beyondHigh
            }
        }
    }
}

/// A Monster's Challenge Rating, when its note's `cr` is one the rulebook prints: `0`, `1/8`,
/// `1/4`, `1/2` or a whole number from 1 to 30.
///
/// Read strictly, as ADR-0032 asks. "10 (13 in lair)" has two answers and "1/3" none, and a
/// number guessed out of either would look as trustworthy as a real one — the reason
/// `StatblockReader` already gives for refusing to guess a spell slot.
struct ChallengeRating: Equatable {
    /// As the rulebook prints it: "1/4", "12".
    let text: String
    /// What a Creature of this Challenge Rating is worth (MM 2024 p. 8).
    let xp: Int

    /// Nil for anything not countable, an absent `cr` included. Only the surrounding
    /// whitespace is forgiven.
    init?(_ text: String?) {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let xp = Self.xpByChallengeRating[trimmed] else { return nil }
        self.text = trimmed
        self.xp = xp
    }

    /// The 2024 table. `0` is worth 10: the 2024 rules give a CR 0 creature 0 or 10 by its
    /// own stat block, the notes' `statblock` carries no XP to say which, and 10 is the one
    /// nearly every such creature has (ADR-0032).
    static let xpByChallengeRating: [String: Int] = [
        "0": 10, "1/8": 25, "1/4": 50, "1/2": 100,
        "1": 200, "2": 450, "3": 700, "4": 1_100, "5": 1_800,
        "6": 2_300, "7": 2_900, "8": 3_900, "9": 5_000, "10": 5_900,
        "11": 7_200, "12": 8_400, "13": 10_000, "14": 11_500, "15": 13_000,
        "16": 15_000, "17": 18_000, "18": 20_000, "19": 22_000, "20": 25_000,
        "21": 33_000, "22": 41_000, "23": 50_000, "24": 62_000, "25": 75_000,
        "26": 90_000, "27": 105_000, "28": 120_000, "29": 135_000, "30": 155_000,
    ]
}

/// A Character's level, when its note's `level` is a whole number from 1 to 20.
///
/// Read as strictly as a Challenge Rating, and for the same reason: "Guerriero 3 / Ladro 2"
/// is a level the DM can read and the app must not add up.
struct CharacterLevel: Equatable {
    let value: Int

    /// Nil for anything not countable, an absent `level` included. Digits only, so "+3" and
    /// "3/2" are not read as a 3.
    init?(_ text: String?) {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.allSatisfy(\.isASCIIDigit),
              let value = Int(trimmed), Self.budgetsByLevel.indices.contains(value - 1)
        else { return nil }
        self.value = value
    }

    /// What one Character of this level adds to the party's budgets.
    var budgets: EncounterDifficulty.Budgets { Self.budgetsByLevel[value - 1] }

    /// The 2024 table, XP Budget per Character (DMG 2024 p. 114), from level 1 to 20.
    static let budgetsByLevel: [EncounterDifficulty.Budgets] = [
        .init(low: 50, moderate: 75, high: 100),
        .init(low: 100, moderate: 150, high: 200),
        .init(low: 150, moderate: 225, high: 400),
        .init(low: 250, moderate: 375, high: 500),
        .init(low: 500, moderate: 750, high: 1_100),
        .init(low: 600, moderate: 1_000, high: 1_400),
        .init(low: 750, moderate: 1_300, high: 1_700),
        .init(low: 1_000, moderate: 1_700, high: 2_100),
        .init(low: 1_300, moderate: 2_000, high: 2_600),
        .init(low: 1_600, moderate: 2_300, high: 3_100),
        .init(low: 1_900, moderate: 2_900, high: 4_100),
        .init(low: 2_200, moderate: 3_700, high: 4_700),
        .init(low: 2_600, moderate: 4_200, high: 5_400),
        .init(low: 2_900, moderate: 4_900, high: 6_200),
        .init(low: 3_300, moderate: 5_400, high: 7_800),
        .init(low: 3_800, moderate: 6_100, high: 9_800),
        .init(low: 4_500, moderate: 7_200, high: 11_700),
        .init(low: 5_000, moderate: 8_700, high: 14_200),
        .init(low: 5_500, moderate: 10_700, high: 17_200),
        .init(low: 6_400, moderate: 13_200, high: 22_000),
    ]
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
