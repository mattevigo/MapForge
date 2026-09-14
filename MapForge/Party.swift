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
    var name: String
    /// "#RRGGBB", as `Pawn.colorHex` is.
    var colorHex: String
    /// The sight range a Stamped Pawn gets, in Grid squares.
    var sightSquares: CGFloat
    var isBig = false

    /// The combat numbers a Stamped Pawn's Stat Block starts from. Here rather than typed
    /// per Encounter because a DM who has entered their party's armour class once should
    /// not enter it again every fight — the exact complaint the Party answers. Copied at
    /// drag time like every other field; see `Stamp.statBlock(from:)`.
    var initiativeBonus = 0
    var armorClass = StatBlock.defaultArmorClass
    /// Optional for the same reason `StatBlock.maxHP` is: a Character sketched in without
    /// hit points has none, and 0 would mean something else entirely.
    var maxHP: Int?

    /// What click-to-place already gives a Pawn, so a Stamped Pawn and a hand-placed one
    /// start from the same defaults rather than drifting apart.
    static let defaultSightSquares: CGFloat = 6

    init(id: UUID = UUID(),
         name: String,
         colorHex: String = Pawn.defaultColorHex,
         sightSquares: CGFloat = PartyCharacter.defaultSightSquares,
         isBig: Bool = false,
         initiativeBonus: Int = 0,
         armorClass: Int = StatBlock.defaultArmorClass,
         maxHP: Int? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sightSquares = sightSquares
        self.isBig = isBig
        self.initiativeBonus = initiativeBonus
        self.armorClass = armorClass
        self.maxHP = maxHP
    }

    /// Hand-written so a `parties.json` written before combat numbers existed still opens.
    /// The synthesized decoder throws on a missing non-optional key, which would make a
    /// DM's whole roster unreadable — the migration shape `Pawn` already uses for
    /// `isHidden`, `isBig` and `characterID`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        sightSquares = try container.decode(CGFloat.self, forKey: .sightSquares)
        isBig = try container.decodeIfPresent(Bool.self, forKey: .isBig) ?? false
        initiativeBonus = try container.decodeIfPresent(Int.self, forKey: .initiativeBonus) ?? 0
        armorClass = try container.decodeIfPresent(Int.self, forKey: .armorClass)
            ?? StatBlock.defaultArmorClass
        maxHP = try container.decodeIfPresent(Int.self, forKey: .maxHP)
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
