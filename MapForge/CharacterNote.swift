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

    // The page the Combat tab shows while the Character's Pawn fights (ADR-0007, amended):
    // the note's own words, never computed from. Read with the numbers, in the same pass.
    var species: String?
    /// The note's `class`, subclass and all: "Chierico (Dominio dell'Inganno)".
    var characterClass: String?
    var level: String?
    var speed: String?
    var senses: String?
    var languages: String?
    var saves: [Monster.Proficiency] = []
    var skills: [Monster.Proficiency] = []
    var traits: [Monster.Feature] = []
    var actions: [Monster.Feature] = []
    /// Lines, as the note writes them: the spellcasting ability, save DC and attack bonus,
    /// then the slots per level. No layout of their own — there is nothing in them but text.
    var spells: [String] = []

    /// The note it was read from, relative to the Workspace root, as `Monster.file` is.
    var file = ""
    /// The Distance Units its Speed and Senses name, as `Monster.distanceUnits` are.
    var distanceUnits: Set<DistanceUnit> = []
    /// The picture the fence's `image:` links to, and that picture found among the
    /// Workspace's files, as a Monster's are. What the Character's Face is cut from when the
    /// DM has cut none for it.
    var imageLink: String?
    var picture: NotePicture?

    var id: String { name }
}

/// Every Character note read from the Workspace, beside the Bestiary and read in the same
/// pass (`BestiaryStore`). A reading, never a store.
struct CharacterNotes: Equatable {
    /// Sorted by name, and unique by it.
    var notes: [CharacterNote] = []

    /// Character notes the app could not take — a second note of a name, a fence with none.
    var skipped: [Bestiary.Skipped] = []

    /// The notes whose picture gives no Face, and why.
    var pictureProblems: [PictureProblem] { notes.pictureProblems }

    /// The note a Character remembers. Exact, as `Bestiary.monster(named:)` is: a near miss
    /// must not quietly become another hero's numbers.
    func note(named name: String?) -> CharacterNote? {
        guard let name else { return nil }
        return notes.first { $0.name == name }
    }

    /// The notes a DM typing `query` means, as the Bestiary's search finds Monsters.
    func search(_ query: String) -> [CharacterNote] {
        NameSearch.matches(query, among: notes, name: \.name)
    }
}
