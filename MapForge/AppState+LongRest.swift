import Foundation

/// The Long Rest: the DM granting the active Party the rulebook's long rest in one gesture,
/// from the Party panel (ADR-0037, `CONTEXT.md`).
extension AppState {
    /// What a Long Rest would do to the active Party right now: who it would change, and from
    /// what. The other Parties are other campaigns, and are not woken for it. Empty with no
    /// Party at all.
    var longRestOfActiveParty: LongRest {
        LongRest(of: activeParty?.characters ?? []) { note(for: $0) }
    }

    /// Why a Long Rest cannot be taken right now, in words for the DM — or nil when it can.
    ///
    /// Said rather than only enforced, as `encounterRefusal` is. A fight running on the open
    /// Map refuses it, since nobody long-rests mid-fight; a fight paused on another Map does
    /// not, and meets the rested party when it resumes. A party with nobody to change is not
    /// asked to confirm a Long Rest that would do nothing.
    var longRestRefusal: String? {
        if encounter != nil {
            return String(localized: "Nobody long-rests mid-fight.",
                          comment: "Why the Long Rest button is disabled while an Encounter runs")
        }
        if !longRestOfActiveParty.changesAnyone {
            return String(localized: "The party is already rested.",
                          comment: "Why the Long Rest button is disabled when it would change nobody")
        }
        return nil
    }

    /// Takes a Long Rest for the active Party: every Character with a note returns to its
    /// note's maximum hit points, loses its temporary hit points and drops one level of
    /// exhaustion, and every Pawn sharing them follows (ADR-0037). Returns what it did, or nil
    /// when it was refused and changed nothing.
    ///
    /// Asked for only after the DM confirmed it, because it overwrites a whole party's numbers
    /// with one click — and not undoable, like every other live action: the confirmation is
    /// the escape.
    ///
    /// Recorded in the Session Log here, as one Line naming the Party and each Character it
    /// changed, so no caller can grant a Long Rest the evening does not hear of.
    @discardableResult
    func takeLongRest() -> LongRest? {
        guard longRestRefusal == nil, let party = activeParty else { return nil }
        let longRest = longRestOfActiveParty
        // Read before the write, which moves the roster's copies to where the Long Rest
        // leaves them.
        let moved = longRest.rested.compactMap { rested -> CharacterNumbersMoved? in
            guard let before = character(id: rested.id) else { return nil }
            return CharacterNumbersMoved(of: before, becoming: rested,
                                         maxHP: note(for: before)?.maxHP)
        }
        writeSharedNumbers(of: longRest.rested)
        recordSessionLongRest(of: party, moved)
        return longRest
    }
}
