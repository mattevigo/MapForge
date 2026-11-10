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
    /// The Encounter Difficulty of the fight being rated, or nil when no Creature in it
    /// counts — a fight with nothing to fight has nothing to rate.
    var encounterDifficulty: EncounterDifficulty? {
        encounterDifficulty(of: pawnsBeingRated)
    }

    /// The Pawns whose fight is rated. While an Encounter runs, its Combatants: the Pawns in
    /// the Order, so a Benched one — dead, fled or set aside — is left out and one joining
    /// counts at once. Before Play, the non-Treasure Pawns ticked into the next fight: the
    /// ones Play would roll for.
    var pawnsBeingRated: [Pawn] {
        guard let encounter else {
            return fog.pawns.filter { $0.kind != .treasure && isInCombat($0.id) }
        }
        let order = Set(encounter.order)
        return fog.pawns.filter { $0.kind != .treasure && order.contains($0.id) }
    }

    /// What `pawns` add up to. A Pawn that cannot be counted is left out of the totals.
    func encounterDifficulty(of pawns: [Pawn]) -> EncounterDifficulty? {
        let challengeRatings = pawns.compactMap(challengeRating(of:))
        guard !challengeRatings.isEmpty else { return nil }
        return EncounterDifficulty(levels: pawns.compactMap(level(of:)),
                                   challengeRatings: challengeRatings)
    }

    /// A Creature's Challenge Rating, through its Monster in the Bestiary, when its note's
    /// `cr` counts.
    ///
    /// By the Pawn's kind first, as `modifierSource(for:)` is, because each link outlives the
    /// kind it was made for: a Player keeps a `monsterName` the DM gave it as a Creature, and
    /// the party does not fight itself.
    func challengeRating(of pawn: Pawn) -> ChallengeRating? {
        guard pawn.kind == .creature else { return nil }
        return ChallengeRating(bestiary.monster(named: pawn.monsterName)?.challengeRating)
    }

    /// A Player's level, through its Character and that Character's note, when the note's
    /// `level` counts.
    func level(of pawn: Pawn) -> CharacterLevel? {
        guard pawn.kind == .player, let id = pawn.characterID,
              let character = character(id: id) else { return nil }
        return CharacterLevel(note(for: character)?.level)
    }
}
