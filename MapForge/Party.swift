import CoreGraphics
import Foundation

/// A member of the party, defined once and reused across every Map.
///
/// A definition, not a token: a Character is never *on* a Map — dragging one Stamps a
/// `Pawn` from it, and the Pawn is a copy that then leads its own life. See
/// `docs/adr/0007-characters-are-stamped-not-linked.md`.
///
/// Named `PartyCharacter` rather than `Character` because Swift's `Character` is a grapheme
/// cluster in the standard library. Shadowing it would compile and then quietly break any
/// string code in the module — a hidden cost far worse than three extra letters. `CONTEXT.md`
/// still calls the domain term a Character; this is a spelling, not a different concept.
struct PartyCharacter: Codable, Equatable, Identifiable {
    var id = UUID()
    /// The DM's label for it — "Durga" — which every Pawn it Stamps is labelled with. Need not
    /// be its note's name.
    var name: String
    /// "#RRGGBB", as `Pawn.colorHex` is.
    var colorHex: String
    /// The sight range a Stamped Pawn gets, in Grid squares. The app's own, never read from
    /// the note: a Pawn's sight is also the light it sheds for the whole table (ADR-0024).
    var sightSquares: CGFloat
    /// The `name` of the note its numbers and size are read from — "Durga Pietraferma" — or
    /// nil while the DM has not said which note is its own. A name rather than a path, as a
    /// Pawn's `monsterName` is, so the roster does not write the vault's layout down.
    ///
    /// The numbers themselves are not here. They were, typed in the app, and drifted from the
    /// notes within weeks; now the notes are the only place they are written (ADR-0024).
    var noteName: String?

    /// What click-to-place already gives a Pawn, so a Stamped Pawn and a hand-placed one
    /// start from the same defaults rather than drifting apart.
    static let defaultSightSquares: CGFloat = 6

    init(id: UUID = UUID(),
         name: String,
         colorHex: String = Pawn.defaultColorHex,
         sightSquares: CGFloat = PartyCharacter.defaultSightSquares,
         noteName: String? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sightSquares = sightSquares
        self.noteName = noteName
    }

    /// Says which note is this Character's own. A Character still nameless — one being
    /// created from the note — takes the note's full name for the DM to shorten; one that has
    /// a name keeps it, because "Durga" is the DM's label and the note's "Durga Pietraferma"
    /// is not a correction of it.
    mutating func link(to note: CharacterNote) {
        noteName = note.name
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = note.name }
    }

    /// Forgets which note is its own: it stamps no numbers until linked again.
    mutating func unlink() {
        noteName = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, colorHex, sightSquares, noteName
    }

    /// Hand-written so a `parties.json` written before notes still opens — with every
    /// Character unlinked, and its typed `isBig`, `initiativeBonus`, `armorClass` and `maxHP`
    /// ignored, to vanish at the next write. They are not used to link it: which note is a
    /// Character's own is the DM's to say, never the app's to guess (ADR-0024).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        sightSquares = try container.decode(CGFloat.self, forKey: .sightSquares)
        noteName = try container.decodeIfPresent(String.self, forKey: .noteName)
    }
}

/// A named roster of Characters — a campaign's cast, defined once.
///
/// Characters are an array, not a set: the order is the DM's, and reordering it is a
/// meaningful thing to want later.
struct Party: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var characters: [PartyCharacter] = []

    init(id: UUID = UUID(), name: String, characters: [PartyCharacter] = []) {
        self.id = id
        self.name = name
        self.characters = characters
    }
}

/// The whole roster as it sits on disk.
///
/// Versioned from the start, and the version is *stamped* on encode rather than echoed from
/// what was read — the rule `FogDocument` learned, so a file written by this app always
/// announces the shape this app writes.
struct PartyBook: Codable, Equatable {
    static let current = 1

    var version: Int
    var parties: [Party]

    init(parties: [Party] = []) {
        self.version = Self.current
        self.parties = parties
    }

    var isEmpty: Bool { parties.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case version, parties
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.current
        parties = try container.decodeIfPresent([Party].self, forKey: .parties) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.current, forKey: .version)
        try container.encode(parties, forKey: .parties)
    }
}
