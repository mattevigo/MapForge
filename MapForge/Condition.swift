import Foundation

/// One of the fourteen boolean states of DnD 5.5e a Combatant can be under.
///
/// Exhaustion is deliberately absent: it is a level from 0 to 6, not a boolean, and lives
/// on `StatBlock` as an `Int`. Concentration is absent too — it is not a Condition in the
/// rules and should not render in a row beside one.
///
/// Conditions carry no duration and expire on nobody's schedule. Encoding "until the end
/// of your next turn" and its cousins is a system in itself, and half of that system is
/// worse than a DM's memory.
enum Condition: String, Codable, CaseIterable, Equatable, LocalizedTitle {
    case blinded
    case charmed
    case deafened
    case frightened
    case grappled
    case incapacitated
    case invisible
    case paralyzed
    case petrified
    case poisoned
    case prone
    case restrained
    case stunned
    case unconscious

    var titleResource: LocalizedStringResource {
        switch self {
        case .blinded: return LocalizedStringResource("Blinded", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .charmed: return LocalizedStringResource("Charmed", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .deafened: return LocalizedStringResource("Deafened", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .frightened: return LocalizedStringResource("Frightened", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .grappled: return LocalizedStringResource("Grappled", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .incapacitated: return LocalizedStringResource("Incapacitated", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .invisible: return LocalizedStringResource("Invisible", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .paralyzed: return LocalizedStringResource("Paralysed", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .petrified: return LocalizedStringResource("Petrified", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .poisoned: return LocalizedStringResource("Poisoned", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .prone: return LocalizedStringResource("Prone", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .restrained: return LocalizedStringResource("Restrained", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .stunned: return LocalizedStringResource("Stunned", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        case .unconscious: return LocalizedStringResource("Unconscious", comment: "A Condition: the rulebook heading form, never agreeing with a Pawn")
        }
    }

    /// The SF Symbol drawn in an Order row. Fourteen of these will not fit as words in a
    /// 320-point panel, so the icon is the primary presentation and the title is the
    /// accessibility label behind it.
    var symbolName: String {
        switch self {
        case .blinded: return "eye.slash"
        case .charmed: return "heart.circle"
        case .deafened: return "ear.trianglebadge.exclamationmark"
        case .frightened: return "exclamationmark.triangle"
        case .grappled: return "hand.raised.fill"
        case .incapacitated: return "xmark.circle"
        case .invisible: return "eye.trianglebadge.exclamationmark"
        case .paralyzed: return "bolt.slash"
        case .petrified: return "cube.fill"
        case .poisoned: return "drop.triangle"
        case .prone: return "arrow.down.to.line"
        case .restrained: return "link"
        case .stunned: return "sparkles"
        case .unconscious: return "zzz"
        }
    }
}
