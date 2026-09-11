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
enum Condition: String, Codable, CaseIterable, Equatable {
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

    var title: String {
        switch self {
        case .blinded: return "Blinded"
        case .charmed: return "Charmed"
        case .deafened: return "Deafened"
        case .frightened: return "Frightened"
        case .grappled: return "Grappled"
        case .incapacitated: return "Incapacitated"
        case .invisible: return "Invisible"
        case .paralyzed: return "Paralyzed"
        case .petrified: return "Petrified"
        case .poisoned: return "Poisoned"
        case .prone: return "Prone"
        case .restrained: return "Restrained"
        case .stunned: return "Stunned"
        case .unconscious: return "Unconscious"
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
