import Foundation

/// One of the six Abilities of DnD 5.5e.
///
/// A Pawn has no ability *scores* — no Strength number — and the app never asks for one. What
/// a DM needs mid fight is the total bonus that applied to this Roll, not a character sheet
/// they must first fill in. See `docs/adr/0017-a-roll-is-recorded-not-resolved.md`, and
/// `docs/adr/0029-the-modifier-is-offered-from-the-note.md` for the one place a note's
/// numbers reach a Roll.
enum Ability: String, Codable, CaseIterable, LocalizedTitle {
    case strength, dexterity, constitution, intelligence, wisdom, charisma

    /// Named in full in the domain; the abbreviation is for controls too narrow for the word.
    var titleResource: LocalizedStringResource {
        switch self {
        case .strength: LocalizedStringResource("Strength")
        case .dexterity: LocalizedStringResource("Dexterity")
        case .constitution: LocalizedStringResource("Constitution")
        case .intelligence: LocalizedStringResource("Intelligence")
        case .wisdom: LocalizedStringResource("Wisdom")
        case .charisma: LocalizedStringResource("Charisma")
        }
    }

    var abbreviation: String {
        switch self {
        case .strength: String(localized: "STR", comment: "An Ability abbreviated, as the stat block prints it")
        case .dexterity: String(localized: "DEX", comment: "An Ability abbreviated, as the stat block prints it")
        case .constitution: String(localized: "CON", comment: "An Ability abbreviated, as the stat block prints it")
        case .intelligence: String(localized: "INT", comment: "An Ability abbreviated, as the stat block prints it")
        case .wisdom: String(localized: "WIS", comment: "An Ability abbreviated, as the stat block prints it")
        case .charisma: String(localized: "CHA", comment: "An Ability abbreviated, as the stat block prints it")
        }
    }
}

/// The six scores a note's `stats:` writes, read only to offer a Modifier (ADR-0029).
///
/// A Pawn never has these. They live on the `Monster` or `CharacterNote` they were read from,
/// are rebuilt with it each time the notes are read, and never reach a `StatBlock`, a Roll or
/// any file the app saves: the Roll stores the number the DM let stand, not where it came from.
struct AbilityScores: Equatable {
    private let scores: [Int]

    /// `stats:` as the rulebook orders it — STR, DEX, CON, INT, WIS, CHA — or nil when it is
    /// not exactly six. Half a list cannot say which score is whose.
    init?(_ scores: [Int]) {
        guard scores.count == Ability.allCases.count else { return nil }
        self.scores = scores
    }

    subscript(ability: Ability) -> Int {
        scores[Ability.allCases.firstIndex(of: ability)!]
    }

    /// The modifier `ability`'s score gives.
    func modifier(_ ability: Ability) -> Int { Self.modifier(of: self[ability]) }

    /// `floor((score − 10) / 2)`, rounding toward negative infinity: a 9 is −1, not 0, which is
    /// what Swift's `/` would make of it.
    static func modifier(of score: Int) -> Int {
        Int((Double(score - 10) / 2).rounded(.down))
    }
}

/// One of the eighteen Skills of DnD 5.5e, each permanently tied to one Ability.
///
/// The tie is **derived, never stored**: a Skill that changed its Ability would change it for
/// every Roll ever recorded, which is the behaviour a rules revision actually wants. Copying
/// the Ability onto the Line would instead let a Log disagree with itself.
enum Skill: String, Codable, CaseIterable, LocalizedTitle {
    case acrobatics, animalHandling, arcana, athletics, deception, history
    case insight, intimidation, investigation, medicine, nature, perception
    case performance, persuasion, religion, sleightOfHand, stealth, survival

    var ability: Ability {
        switch self {
        case .acrobatics, .sleightOfHand, .stealth: .dexterity
        case .athletics: .strength
        case .arcana, .history, .investigation, .nature, .religion: .intelligence
        case .animalHandling, .insight, .medicine, .perception, .survival: .wisdom
        case .deception, .intimidation, .performance, .persuasion: .charisma
        }
    }

    var titleResource: LocalizedStringResource {
        switch self {
        case .acrobatics: LocalizedStringResource("Acrobatics")
        case .animalHandling: LocalizedStringResource("Animal Handling")
        case .arcana: LocalizedStringResource("Arcana")
        case .athletics: LocalizedStringResource("Athletics")
        case .deception: LocalizedStringResource("Deception")
        case .history: LocalizedStringResource("History")
        case .insight: LocalizedStringResource("Insight")
        case .intimidation: LocalizedStringResource("Intimidation")
        case .investigation: LocalizedStringResource("Investigation")
        case .medicine: LocalizedStringResource("Medicine")
        case .nature: LocalizedStringResource("Nature")
        case .perception: LocalizedStringResource("Perception")
        case .performance: LocalizedStringResource("Performance")
        case .persuasion: LocalizedStringResource("Persuasion")
        case .religion: LocalizedStringResource("Religion")
        case .sleightOfHand: LocalizedStringResource("Sleight of Hand")
        case .stealth: LocalizedStringResource("Stealth")
        case .survival: LocalizedStringResource("Survival")
        }
    }
}

/// What a d20 showed, what was added to it, and what it was against.
///
/// A **record, not a resolution**: the app never generates `d20` and never applies what the
/// result implies. The dice are the table's; remembering them is the app's.
///
/// `succeeded` is computed rather than stored — a stored derivable fact is the drift
/// ADR-0008 was written against — and so is never encoded.
struct Roll: Codable, Equatable {
    /// The face the die showed, 1...20. Chosen by the DM from a grid; there is no RNG in
    /// this feature at all.
    var d20: Int

    /// Everything added to the die — ability bonus, proficiency, expertise, active effects —
    /// as one number the DM types. The parts are on the player's character sheet; the total
    /// is what was said aloud at the table.
    var modifier: Int

    /// Optional, and deliberately so: a DM who asks for a check before deciding what it
    /// beats, or who keeps the number secret, records the Roll without one. Forcing a number
    /// here would invite a made-up one, and a made-up number in an append-only file is worse
    /// than no number.
    var difficultyClass: Int?

    init(d20: Int, modifier: Int, difficultyClass: Int? = nil) {
        self.d20 = d20
        self.modifier = modifier
        self.difficultyClass = difficultyClass
    }

    var total: Int { d20 + modifier }

    /// `nil` when there is no Difficulty Class: the Log reports the total with no verdict.
    var succeeded: Bool? {
        guard let difficultyClass else { return nil }
        return total >= difficultyClass
    }
}
