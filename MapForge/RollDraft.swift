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
        case .savingThrow: "Saving Throw"
        case .abilityCheck: "Ability Check"
        }
    }

    /// What the sheet asks for before a subject is chosen.
    var prompt: String {
        switch self {
        case .savingThrow: "Choose the ability"
        case .abilityCheck: "Choose the skill"
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

    /// Nil until the DM picks a face. There is no default: an unrolled die is not a 1.
    var d20: Int?

    /// The subject, one of which is relevant per `kind`. Two fields rather than one
    /// enum-of-either, because the sheet shows one grid or the other and switching kinds
    /// mid-sheet is not a thing it offers.
    var ability: Ability?
    var skill: Skill?

    /// Optional by design — see `Roll.difficultyClass`.
    var difficultyClass: Int?

    var modifier: Int = 0

    init(pawn: Pawn, kind: RollKind) {
        self.pawn = pawn
        self.kind = kind
        // The design's default: the DC a DM reaches for most, pre-selected but replaceable.
        self.difficultyClass = 15
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
            return "\(ability.title) Saving Throw"
        case .abilityCheck:
            guard let skill else { return kind.prompt }
            return "\(skill.title) · \(skill.ability.title)"
        }
    }
}
