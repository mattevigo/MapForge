import Foundation

/// A Character as the DM's notes write it: the numbers a Stamp copies, read from the
/// Character's own statblock (ADR-0024).
///
/// Not a `PartyCharacter`. A Character is the app's — its label, its colour, its sight — and
/// remembers which note is its own; this is what that note says. Like a `Monster` it is never
/// authored or saved here: it is rebuilt from the notes each time the Workspace opens.
struct CharacterNote: Equatable, Identifiable {
    /// The fence's `name` — "Durga Pietraferma" — and what a Character remembers its note by.
    /// Unique within `CharacterNotes`.
    var name: String

    var armorClass: Int?
    /// The maximum: a Character's note writes no current hit points.
    var maxHP: Int?
    var initiativeBonus: Int?
    /// Large and up — a 2×2 token. A note with no `size` is an ordinary one.
    var isBig = false
    var size: String?

    var id: String { name }
}

/// Every Character note read from the Workspace, beside the Bestiary and read in the same
/// pass (`BestiaryStore`). A reading, never a store.
struct CharacterNotes: Equatable {
    /// Sorted by name, and unique by it.
    var notes: [CharacterNote] = []

    /// Character notes the app could not take — a second note of a name, a fence with none.
    var skipped: [Bestiary.Skipped] = []

    /// The note a Character remembers. Exact, as `Bestiary.monster(named:)` is: a near miss
    /// must not quietly become another hero's numbers.
    func note(named name: String?) -> CharacterNote? {
        guard let name else { return nil }
        return notes.first { $0.name == name }
    }
}
