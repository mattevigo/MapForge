import CoreGraphics
import Foundation

/// A member of the party, defined once and reused across every Map.
///
/// A definition, not a token: a Character is never *on* a Map — dragging one Stamps a
/// `Pawn` from it, and the Pawn is a copy that then leads its own life. See
/// `docs/adr/0007-characters-are-stamped-not-linked.md`. The one exception is what the
/// evening does to a Character with a note — its hit points and exhaustion — which its Player
/// Pawns share rather than copy (`docs/adr/0037-a-characters-hit-points-are-shared-not-stamped.md`).
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
    /// The note's numbers themselves are not here. They were, typed in the app, and drifted
    /// from the notes within weeks; now the notes are the only place they are written
    /// (ADR-0024). What is here is what the evening has done to them, `currentHP` below.
    var noteName: String?
    /// The Face the DM cut for this Character, which every Pawn it Stamps is given a copy of —
    /// or nil, when its Pawns are drawn in its colour. Kept in `.mapforge/faces/` with every
    /// other cut, and always cut by hand (ADR-0028).
    var face: PawnFace?

    /// What the evening has done to it: its current hit points, or nil while it is at full —
    /// its note's maximum, whatever that is today. Kept here, beside the Party, rather than in
    /// any one Map's `stats.json`, because every Player Pawn stamped from a Character with a
    /// note shows and changes this same number on whichever Map it stands (ADR-0037).
    ///
    /// Not the note's: it changes several times a minute, and the notes are where the
    /// definition is written, not the evening. Meaningless for a Character with no note, whose
    /// Pawns keep their own, as a Creature's do.
    var currentHP: Int?
    /// Its temporary hit points, shared on the same terms as `currentHP`.
    var temporaryHP: Int = 0
    /// Its exhaustion level, shared on the same terms as `currentHP`. Clamped where it lands,
    /// in a Pawn's Stat Block, which is also the only place it is taken from.
    var exhaustion: Int = 0

    /// What click-to-place already gives a Pawn, so a Stamped Pawn and a hand-placed one
    /// start from the same defaults rather than drifting apart.
    static let defaultSightSquares: CGFloat = 6

    init(id: UUID = UUID(),
         name: String,
         colorHex: String = Pawn.defaultColorHex,
         sightSquares: CGFloat = PartyCharacter.defaultSightSquares,
         noteName: String? = nil,
         face: PawnFace? = nil,
         currentHP: Int? = nil,
         temporaryHP: Int = 0,
         exhaustion: Int = 0) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sightSquares = sightSquares
        self.noteName = noteName
        self.face = face
        self.currentHP = currentHP
        self.temporaryHP = temporaryHP
        self.exhaustion = exhaustion
    }

    /// A Pawn's own Stat Block with this Character's shared numbers laid over it: its current
    /// and temporary hit points and its exhaustion. Everything else stays the Pawn's — armour
    /// class, maximum hit points and initiative bonus as the Stamp copied them from the note,
    /// and Conditions and concentration, which belong to the place and the fight the Pawn is
    /// in (ADR-0037).
    ///
    /// `maxHP` is the note's: what "at full" means while `currentHP` is nil.
    func sharedNumbers(over block: StatBlock, maxHP: Int?) -> StatBlock {
        var block = block
        block.currentHP = currentHP ?? maxHP
        block.temporaryHP = temporaryHP
        block.exhaustion = exhaustion
        return block
    }

    /// Takes the shared numbers from one of its Pawns' Stat Blocks — what an edit to that
    /// Pawn does — and leaves the rest of the block where it is.
    mutating func takeSharedNumbers(from block: StatBlock) {
        currentHP = block.currentHP
        temporaryHP = block.temporaryHP
        exhaustion = block.exhaustion
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
        case id, name, colorHex, sightSquares, noteName, face
        case currentHP, temporaryHP, exhaustion
    }

    /// Hand-written so a `parties.json` written before notes still opens — with every
    /// Character unlinked, and its typed `isBig`, `initiativeBonus`, `armorClass` and `maxHP`
    /// ignored, to vanish at the next write. They are not used to link it: which note is a
    /// Character's own is the DM's to say, never the app's to guess (ADR-0024). One written
    /// before Faces opens with every Character drawn in its colour. One written before shared
    /// hit points opens with every Character at full — its note's maximum, no temporary hit
    /// points, no exhaustion — rather than taking the numbers of whichever of its Pawns the
    /// app happened to open first (ADR-0037).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        sightSquares = try container.decode(CGFloat.self, forKey: .sightSquares)
        noteName = try container.decodeIfPresent(String.self, forKey: .noteName)
        face = try container.decodeIfPresent(PawnFace.self, forKey: .face)
        currentHP = try container.decodeIfPresent(Int.self, forKey: .currentHP)
        temporaryHP = try container.decodeIfPresent(Int.self, forKey: .temporaryHP) ?? 0
        exhaustion = try container.decodeIfPresent(Int.self, forKey: .exhaustion) ?? 0
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
