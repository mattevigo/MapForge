import Foundation

/// One of the six Abilities of DnD 5.5e.
///
/// The app holds no ability *scores* — a Pawn has no Strength number. What a DM needs mid
/// fight is the total bonus that applied to this Roll, which they already know, not a
/// character sheet they must first fill in. See
/// `docs/adr/0017-a-roll-is-recorded-not-resolved.md`.
enum Ability: String, Codable, CaseIterable {
    case strength, dexterity, constitution, intelligence, wisdom, charisma

    /// Named in full in the domain; the abbreviation is for controls too narrow for the word.
    var title: String {
        switch self {
        case .strength: String(localized: "Strength")
        case .dexterity: String(localized: "Dexterity")
        case .constitution: String(localized: "Constitution")
        case .intelligence: String(localized: "Intelligence")
        case .wisdom: String(localized: "Wisdom")
        case .charisma: String(localized: "Charisma")
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

/// One of the eighteen Skills of DnD 5.5e, each permanently tied to one Ability.
///
/// The tie is **derived, never stored**: a Skill that changed its Ability would change it for
/// every Roll ever recorded, which is the behaviour a rules revision actually wants. Copying
/// the Ability onto the Line would instead let a Log disagree with itself.
enum Skill: String, Codable, CaseIterable {
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

    var title: String {
        switch self {
        case .acrobatics: String(localized: "Acrobatics")
        case .animalHandling: String(localized: "Animal Handling")
        case .arcana: String(localized: "Arcana")
        case .athletics: String(localized: "Athletics")
        case .deception: String(localized: "Deception")
        case .history: String(localized: "History")
        case .insight: String(localized: "Insight")
        case .intimidation: String(localized: "Intimidation")
        case .investigation: String(localized: "Investigation")
        case .medicine: String(localized: "Medicine")
        case .nature: String(localized: "Nature")
        case .perception: String(localized: "Perception")
        case .performance: String(localized: "Performance")
        case .persuasion: String(localized: "Persuasion")
        case .religion: String(localized: "Religion")
        case .sleightOfHand: String(localized: "Sleight of Hand")
        case .stealth: String(localized: "Stealth")
        case .survival: String(localized: "Survival")
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
