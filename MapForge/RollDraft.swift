import Foundation

/// Which of the two Rolls a sheet is taking.
///
/// They differ in what is being rolled against and in nothing else: both carry a Difficulty
/// Class, a d20 and a Modifier. Two cases rather than one with a flag, because a DM presses
/// two different buttons and a reader opening the Log sees two different words.
enum RollKind: Hashable {
    case savingThrow
    case abilityCheck

    var title: String {
        switch self {
        case .savingThrow: String(localized: "Saving Throw")
        case .abilityCheck: String(localized: "Ability Check")
        }
    }

    /// What the sheet asks for before a subject is chosen.
    var prompt: String {
        switch self {
        case .savingThrow: String(localized: "Choose the ability")
        case .abilityCheck: String(localized: "Choose the skill")
        }
    }

    /// The same request in the middle of a sentence, under the d20 grid. Its own string rather
    /// than `prompt` lowercased: a German noun keeps its capital wherever it stands.
    var caption: String {
        switch self {
        case .savingThrow: String(localized: "choose the ability")
        case .abilityCheck: String(localized: "choose the skill")
        }
    }
}

/// The fields the Roll sheet offers, buffered until Record.
///
/// A draft rather than bindings onto anything live, for `EditPawnDraft`'s reason: Cancel
/// must discard rather than un-apply.
///
/// **This never touches a Stat Block.** A Roll is written to a Log and nothing else — it does
/// not apply what the result implies, because a failed Dexterity save means half damage and
/// the app does not know how much. See `docs/adr/0017-a-roll-is-recorded-not-resolved.md`.
struct RollDraft: Equatable {
    /// Who rolled. Carried whole so the recorder can snapshot the label, as `pawnMoved` does.
    let pawn: Pawn
    let kind: RollKind

    /// The note the Modifier is offered from, or nil when the Pawn has none (ADR-0029).
    let source: ModifierSource?

    /// Nil until the DM picks a face. There is no default: an unrolled die is not a 1.
    var d20: Int?

    /// The subject, one of which is relevant per `kind`. Two fields rather than one
    /// enum-of-either, because the sheet shows one grid or the other and switching kinds
    /// mid-sheet is not a thing it offers.
    var ability: Ability? { didSet { offerForSubject() } }
    var skill: Skill?

    /// Optional by design — see `Roll.difficultyClass`.
    var difficultyClass: Int?

    /// What the field holds: the note's offer until the DM types, and theirs from then on.
    private(set) var modifier: Int = 0

    /// The note's offer `modifier` holds, or nil when it holds a number the DM typed or a 0
    /// nobody offered. What the sheet's caption is shown on.
    private(set) var offer: ModifierOffer?

    /// Set by the DM's first edit of the field and never cleared: a blessed +6 typed for the
    /// wrong save survives the DM clicking the right one.
    private var isTyped = false

    init(pawn: Pawn, kind: RollKind, source: ModifierSource? = nil) {
        self.pawn = pawn
        self.kind = kind
        self.source = source
        // The design's default: the DC a DM reaches for most, pre-selected but replaceable.
        self.difficultyClass = 15
    }

    /// The DM's own number. From now on the subject they pick no longer moves it.
    mutating func typeModifier(_ value: Int) {
        modifier = value
        isTyped = true
        offer = nil
    }

    /// The note's number for the subject just chosen, or 0 when it gives none — the offer for
    /// the previous subject must not stand in for this one's. Nothing once the DM has typed.
    private mutating func offerForSubject() {
        guard !isTyped else { return }
        offer = switch kind {
        case .savingThrow: ability.flatMap { source?.savingThrow($0) }
        case .abilityCheck: nil
        }
        modifier = offer?.value ?? 0
    }

    /// Where the offered Modifier came from, while the field still holds it: the note's own
    /// bonus, or the Ability's modifier worked out from the note's score — said apart, because
    /// the second is the number a proficient save would beat. Which Ability is not said: the
    /// DM has just picked it, and the sheet's subtitle names it.
    var offerCaption: String? {
        guard let offer, let source else { return nil }
        switch offer.basis {
        case .listed:
            return String(localized: "From \(source.noteName)'s note",
                          comment: "Under the Roll sheet's Modifier: the note the number was offered from")
        case .score:
            return String(localized: "From \(source.noteName)'s note (Ability modifier)",
                          comment: "Under the Roll sheet's Modifier: the note whose score for the chosen Ability the number was worked out from")
        }
    }

    /// The Roll this draft would record, or nil while it is not yet recordable.
    ///
    /// Gated on the die **and** the subject, never on the Difficulty Class.
    var roll: Roll? {
        guard let d20, hasSubject else { return nil }
        return Roll(d20: d20, modifier: modifier, difficultyClass: difficultyClass)
    }

    private var hasSubject: Bool {
        switch kind {
        case .savingThrow: ability != nil
        case .abilityCheck: skill != nil
        }
    }

    /// What the sheet shows under its title: the prompt until a subject is chosen, then the
    /// Roll being taken.
    var subtitle: String {
        switch kind {
        case .savingThrow:
            guard let ability else { return kind.prompt }
            return String(localized: "\(ability.title) Saving Throw")
        case .abilityCheck:
            guard let skill else { return kind.prompt }
            return String(localized: "\(skill.title) · \(skill.ability.title)")
        }
    }
}

/// The note a rolling Pawn's Modifier is offered from: its Character's, or its Monster's
/// (ADR-0029).
///
/// The note's saves already matched onto the Abilities they name, so the sheet asks by
/// `Ability` and never by a string. A save whose name matches nothing is dropped, silently —
/// the cost is a suggestion the score gives instead, or the DM types, and the Combat tab still
/// shows the note's own list.
struct ModifierSource: Equatable {
    /// The fence's `name`, for the caption: "Durga Pietraferma", "Gnoll Guerriero".
    let noteName: String
    private let saves: [Ability: Int]
    private let scores: AbilityScores?

    init(note: CharacterNote) {
        self.init(noteName: note.name, saves: note.saves, scores: note.abilityScores)
    }

    init(monster: Monster) {
        self.init(noteName: monster.name, saves: monster.saves, scores: monster.abilityScores)
    }

    private init(noteName: String, saves: [Monster.Proficiency], scores: AbilityScores?) {
        self.noteName = noteName
        self.saves = Dictionary(saves.compactMap { save in
            Ability.named(save.name).map { ($0, save.bonus) }
        }, uniquingKeysWith: { first, _ in first })
        self.scores = scores
    }

    /// What the note offers a Saving Throw with `ability`: the save it lists, else the
    /// Ability's modifier from its score — a Monster lists only the saves it is proficient in —
    /// else nothing.
    func savingThrow(_ ability: Ability) -> ModifierOffer? {
        if let listed = saves[ability] { return ModifierOffer(value: listed, basis: .listed) }
        guard let scores else { return nil }
        return ModifierOffer(value: scores.modifier(ability), basis: .score)
    }
}

/// A number the note offers for the Modifier, and which of the note's numbers it is.
struct ModifierOffer: Equatable {
    enum Basis: Equatable {
        /// The bonus the note writes for this very save or skill.
        case listed
        /// Worked out from the chosen Ability's score, the note listing nothing for it.
        case score
    }

    let value: Int
    let basis: Basis
}
