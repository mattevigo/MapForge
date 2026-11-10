import Foundation

/// The Encounter Difficulty where it meets the fight the DM has framed (ADR-0032).
///
/// Read, never kept: each time the Combat tab draws it, the Pawns are looked up through the
/// advisory references the Monster's page and the Character's page already follow
/// (ADR-0020, and the ADR-0007 amendment). Nothing here writes, so ticking a Pawn in, a
/// Monster renamed in the notes or a Character levelling up reaches it at once — and no Turn,
/// Stat Block or Log depends on it.
@MainActor
extension AppState {
    /// The fight being rated, read: its Encounter Difficulty, and every Pawn in it that could
    /// not be counted, with why.
    var encounterDifficultyReading: EncounterDifficultyReading {
        encounterDifficultyReading(of: pawnsBeingRated)
    }

    /// The Pawns whose fight is rated, in the fight's order. While an Encounter runs, its
    /// Combatants in the Order's sequence, so a Benched one — dead, fled or set aside — is
    /// left out and one joining counts at once. Before Play, the non-Treasure Pawns ticked
    /// into the next fight, the ones Play would roll for, in the Map's order: there is no
    /// Order yet.
    var pawnsBeingRated: [Pawn] {
        guard let encounter else {
            return fog.pawns.filter { $0.kind != .treasure && isInCombat($0.id) }
        }
        let pawns = Dictionary(fog.pawns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return encounter.order.compactMap { pawns[$0] }.filter { $0.kind != .treasure }
    }

    /// What `pawns` add up to, and which of them could not be counted. An uncounted Pawn is
    /// left out of the totals and named instead, never guessed (ADR-0032); a Treasure is
    /// neither, having no numbers to count.
    func encounterDifficultyReading(of pawns: [Pawn]) -> EncounterDifficultyReading {
        var levels: [CharacterLevel] = []
        var challengeRatings: [ChallengeRating] = []
        var uncounted: [UncountedPawn] = []
        for pawn in pawns {
            switch tally(pawn) {
            case .challengeRating(let challengeRating): challengeRatings.append(challengeRating)
            case .level(let level): levels.append(level)
            case .uncounted(let reason):
                uncounted.append(UncountedPawn(id: pawn.id, label: pawn.label, reason: reason))
            case .nothing: break
            }
        }
        let encounterDifficulty = challengeRatings.isEmpty
            ? nil : EncounterDifficulty(levels: levels, challengeRatings: challengeRatings)
        return EncounterDifficultyReading(encounterDifficulty: encounterDifficulty, uncounted: uncounted)
    }

    /// What one Pawn gives the reckoning.
    ///
    /// By the Pawn's kind first, as `modifierSource(for:)` is, because each link outlives the
    /// kind it was made for: a Player keeps a `monsterName` the DM gave it as a Creature, and
    /// the party does not fight itself.
    private func tally(_ pawn: Pawn) -> Tally {
        switch pawn.kind {
        case .creature:
            guard let monsterName = pawn.monsterName else { return .uncounted(.noMonster) }
            guard let monster = bestiary.monster(named: monsterName) else {
                return .uncounted(.monsterNotInBestiary(monsterName: monsterName))
            }
            guard let challengeRating = ChallengeRating(monster.challengeRating) else {
                return .uncounted(.challengeRatingNotCounted(trimmedOrNil(monster.challengeRating)))
            }
            return .challengeRating(challengeRating)
        case .player:
            switch characterNote(for: pawn) {
            case .noCharacter: return .uncounted(.noCharacter)
            case .characterGone: return .uncounted(.characterGone)
            case .unlinked: return .uncounted(.noNote)
            case .missing(let noteName): return .uncounted(.noteNotFound(noteName: noteName))
            case .found(let note):
                guard let level = CharacterLevel(note.level) else {
                    return .uncounted(.levelNotCounted(trimmedOrNil(note.level)))
                }
                return .level(level)
            }
        case .treasure:
            return .nothing
        }
    }

    /// A note's text without the spaces around it, or nil when nothing is written: what an
    /// uncounted reason quotes back to the DM.
    private func trimmedOrNil(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return text
    }
}

/// What one Pawn gives the Encounter Difficulty.
private enum Tally {
    case challengeRating(ChallengeRating)
    case level(CharacterLevel)
    case uncounted(UncountedPawn.Reason)
    /// A Treasure, which has no numbers and is no one's to count.
    case nothing
}

/// The fight being rated, as `AppState` reads it: what counted, reckoned, beside the Pawns
/// that did not.
struct EncounterDifficultyReading: Equatable {
    /// Nil when no Creature counts: a fight with nothing to fight has nothing to rate.
    var encounterDifficulty: EncounterDifficulty?
    /// In the fight's order: the Order's while it runs, the Map's before Play. Never a
    /// Treasure.
    var uncounted: [UncountedPawn]
}

/// A Pawn in the fight being rated whose numbers could not be read from the notes, and why
/// — so the DM, who can fix the note, knows which one to fix.
struct UncountedPawn: Equatable {
    var id: UUID
    var label: String
    var reason: Reason

    enum Reason: Equatable {
        /// A Creature the DM never said was a Monster.
        case noMonster
        /// A Creature whose Monster has left the notes since the DM said it was one.
        case monsterNotInBestiary(monsterName: String)
        /// A Monster whose note's `cr` is not one the rules give XP for, quoted; nil when the
        /// note writes none.
        case challengeRatingNotCounted(String?)

        /// A Player not Stamped from a Character.
        case noCharacter
        /// A Player whose Character has been deleted from every Party since the Stamp.
        case characterGone
        /// A Player whose Character was never linked to a note.
        case noNote
        /// A Player whose Character's note is not among the notes read.
        case noteNotFound(noteName: String)
        /// A Character's note whose `level` is not a whole number from 1 to 20, quoted; nil
        /// when the note writes none.
        case levelNotCounted(String?)

        /// Which side the Pawn was to count for.
        var kind: PawnKind {
            switch self {
            case .noMonster, .monsterNotInBestiary, .challengeRatingNotCounted: return .creature
            case .noCharacter, .characterGone, .noNote, .noteNotFound, .levelNotCounted: return .player
            }
        }
    }
}
