import Foundation

/// What a Long Rest does to a Party's Characters — the decisions, kept out of the Party panel
/// and out of `AppState` so they can be proved without either, as `MonsterStamp`'s are.
///
/// The rulebook's long rest, as the 2024 rules give it: every Character with a note returns to
/// its note's maximum hit points, loses its temporary hit points and drops one level of
/// exhaustion (ADR-0037). Only those three numbers, the ones a Character shares with its
/// Pawns: Conditions and concentration are the Pawn's, and belong to the place and the fight
/// it is in, so a rest taken in the roster never reaches them.
///
/// A Character with no note is passed over. Its Pawns keep their own numbers, as a Creature's
/// do, and there is no maximum to return it to.
struct LongRest: Equatable {
    /// One Character the rest would change, as the confirmation names it: who, and what from.
    struct Line: Equatable {
        var name: String
        var changes: [Change]

        /// One number the rest moves, with where it starts. Where it ends is the rest's own
        /// rule — the maximum, none, one fewer — so it is not stored twice.
        enum Change: Equatable {
            /// Current hit points `before`, of `max`, returning to `max`.
            case hitPoints(before: Int, max: Int)
            /// Temporary hit points `before`, falling to none.
            case temporaryHP(before: Int)
            /// Exhaustion level `before`, dropping one.
            case exhaustion(before: Int)

            var text: String {
                switch self {
                case let .hitPoints(before, max):
                    return "\(before)/\(max) → \(max)/\(max)"
                case let .temporaryHP(before):
                    return String(localized: "+\(before) temp → 0",
                                  comment: "A Long Rest's line: temporary hit points it clears")
                case let .exhaustion(before):
                    return String(localized: "exhaustion \(before) → \(before - 1)",
                                  comment: "A Long Rest's line: the exhaustion level it lowers")
                }
            }
        }

        /// "Durga 12/48 → 48/48, exhaustion 2 → 1".
        var text: String {
            "\(name) " + changes.map(\.text).joined(separator: ", ")
        }
    }

    /// The Characters the rest changes, already rested, in the Party's order. Only those it
    /// changes, so applying it rewrites nothing that would not move.
    var rested: [PartyCharacter] = []
    /// What the confirmation lists: one line for each Character in `rested`.
    var lines: [Line] = []

    /// Whether the rest would change anyone. A Party already rested is not asked again: a
    /// dialog that appears when nothing can change is one the DM learns to click through.
    var changesAnyone: Bool { !rested.isEmpty }

    /// The Long Rest of `characters`, each with the note `note` finds for it — nil for one
    /// that has none, which the rest passes over.
    init(of characters: [PartyCharacter], note: (PartyCharacter) -> CharacterNote?) {
        for character in characters {
            guard let note = note(character) else { continue }
            var changes: [Line.Change] = []
            var rested = character
            // A note with no maximum gives the rest nothing to return the hit points to, so
            // they stay as they are rather than becoming none.
            if let max = note.maxHP {
                let current = character.currentHP ?? max
                if current != max { changes.append(.hitPoints(before: current, max: max)) }
                // nil is "at full": the note's maximum, whatever it says next week.
                rested.currentHP = nil
            }
            if character.temporaryHP != 0 {
                changes.append(.temporaryHP(before: character.temporaryHP))
                rested.temporaryHP = 0
            }
            if character.exhaustion > 0 {
                changes.append(.exhaustion(before: character.exhaustion))
                rested.exhaustion = character.exhaustion - 1
            }
            guard !changes.isEmpty else { continue }
            self.rested.append(rested)
            lines.append(Line(name: character.name, changes: changes))
        }
    }
}
