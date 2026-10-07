import CoreGraphics
import Foundation

/// A Wall: a two-sided segment that blocks Light.
///
/// Endpoints are in the Map's **image pixels**, not inches, so a Wall stays welded to
/// the artwork when the Grid changes — re-running Grid Fit alters what a Wall means
/// physically, never where it sits on the picture.
struct Wall: Codable, Equatable, Identifiable {
    var id = UUID()
    var from: MapPoint
    var to: MapPoint

    init(id: UUID = UUID(), from: MapPoint, to: MapPoint) {
        self.id = id
        self.from = from
        self.to = to
    }
}

/// A point on the Map in image pixels.
///
/// A named type rather than a bare `CGPoint` because `CGPoint` encodes as an anonymous
/// `[x, y]` array: the file would say `"from": [100, 200]` and a reader — human or a
/// later version of this app — would have to guess the units. Walls are in image pixels
/// while Light radii are in Grid squares, and quietly confusing the two misplaces
/// everything on the Map.
struct MapPoint: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    /// Nests the pair under its unit, so the file reads
    /// `"from": {"imagePixels": {"x": 100, "y": 200}}` — the unit named *and* the
    /// components named. Encoding a bare CGPoint would give `[100, 200]`, leaving a
    /// reader to guess both.
    private enum CodingKeys: String, CodingKey { case imagePixels }
    private struct Components: Codable { var x: CGFloat; var y: CGFloat }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let components = try container.decode(Components.self, forKey: .imagePixels)
        self.init(x: components.x, y: components.y)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Components(x: x, y: y), forKey: .imagePixels)
    }
}

/// The fog data authored on one Map — and the Map's Grid — as persisted in
/// `<map>.fog.json`.
///
/// The Grid lives here rather than in the `<map>.mapforge.json` Sidecar `CONTEXT.md`
/// names, reversing an earlier decision recorded in this file. See
/// [ADR 0003](../docs/adr/0003-grid-in-the-fog-file.md): a Light's radii and a Pawn's
/// range are stored in **Grid squares**, so this file already carried a measurement whose
/// unit it did not define, and a relaunch handed back Lights that meant nothing. Rejoining
/// the two halves in one file makes the measurement whole. The name is now a misnomer —
/// renaming would strand every file already written beside a Map.
struct FogDocument: Codable, Equatable {
    /// The format this document is written in. Always `current` on encode — see
    /// `encode(to:)`. Carries what was *read* after a decode, so a reader can branch on it.
    ///
    /// 2 added the Grid; version 1 files decode with it absent.
    var version = current

    /// The version this app writes.
    static let current = 2
    /// The Map's Grid: its width in squares, or nil when the DM has never declared one.
    ///
    /// One optional rather than a value and a flag, which could contradict each other.
    /// Optional is also what makes a version 1 file decode: the synthesised `Codable`
    /// leaves an absent key nil rather than throwing.
    var squaresWide: Double?
    var walls: [Wall] = []
    var lights: [Light] = []
    var pawns: [Pawn] = []

    /// Whether this Map has anything worth a file. Nothing is written for an empty
    /// document: MapForge must not litter the user's map folder with files for Maps
    /// the DM never authored.
    ///
    /// A Grid alone is not empty. A DM who runs Grid Fit and stops there has authored
    /// something — and that is the case on a fresh Map, where discarding it would mean
    /// re-fitting on every launch, which is the complaint this feature exists to fix.
    var isEmpty: Bool {
        squaresWide == nil && walls.isEmpty && lights.isEmpty && pawns.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case version, squaresWide, walls, lights, pawns
    }

    /// Stamps the version being written rather than echoing the one that was read.
    ///
    /// `version` is a decoded property, so a version 1 file loaded and saved again would
    /// go back to disk as `"version": 1` while carrying the version 2 `squaresWide` key —
    /// a file that lies about its own format. Every `.fog.json` already beside a Map takes
    /// exactly this path the first time its Grid is fitted.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.current, forKey: .version)
        try container.encodeIfPresent(squaresWide, forKey: .squaresWide)
        try container.encode(walls, forKey: .walls)
        try container.encode(lights, forKey: .lights)
        try container.encode(pawns, forKey: .pawns)
    }
}

/// A Light: a point source illuminating out to a bright and a dim radius, blocked by Walls.
///
/// Radii are in **Grid squares**, not pixels, because a Light is a physical thing — every
/// 5e stat block reads "bright light in a 20-foot radius and dim light for an additional
/// 20 feet". The consequence is that a Light has no physical meaning until the Map's Grid
/// is declared.
struct Light: Codable, Equatable, Identifiable {
    var id = UUID()
    var at: MapPoint
    var brightSquares: CGFloat
    /// Defaults to twice bright, the 5e convention, so a torch is entered as one number.
    /// Zero is legal: a sharp-edged source with no falloff band.
    var dimSquares: CGFloat
    var isOn = true
    /// The DM's own name for this Light — "trapped brazier", "goes out in round 3".
    ///
    /// **Never drawn on the Player Display**, exactly as a Pawn's label is not: a Light named
    /// for the DM's notes must not cross the room. `PlayerVisibility.showsLightNameToPlayers`
    /// is where that is settled, beside every other rule about what the table sees.
    ///
    /// Optional, and that is load-bearing rather than stylistic. `Light`'s conformance is
    /// synthesised, and Swift's synthesised `decode` requires every key unless the property
    /// is optional — a defaulted `String` here would make every `.fog.json` written before
    /// today fail to load outright, which is the `Pawn` break documented below at length.
    /// "Unnamed" is also a real state: a Light placed before this feature has no name, and
    /// the roster falls back to its position.
    var name: String?

    init(id: UUID = UUID(), at: MapPoint, brightSquares: CGFloat,
         dimSquares: CGFloat? = nil, isOn: Bool = true, name: String? = nil) {
        self.id = id
        self.at = at
        self.brightSquares = brightSquares
        self.dimSquares = dimSquares ?? brightSquares * 2
        self.isOn = isOn
        self.name = name
    }

    /// Hand-written for one reason: `encodeIfPresent`, so an unnamed Light writes no `name`
    /// key rather than `"name": null` in every entry of every file. The precedent and the
    /// reasoning are `Pawn.encode(to:)`'s treatment of `characterID`.
    ///
    /// Decoding stays synthesised. An optional key is exactly what the synthesised decoder
    /// handles correctly, and hand-writing it would add a second place for the two halves to
    /// disagree.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(at, forKey: .at)
        try container.encode(brightSquares, forKey: .brightSquares)
        try container.encode(dimSquares, forKey: .dimSquares)
        try container.encode(isOn, forKey: .isOn)
        try container.encodeIfPresent(name, forKey: .name)
    }

    /// The next name for a Light placed on a Map that already holds these.
    ///
    /// Mirrors `Pawn.nextLabel(after:)`, and exists for the same defect: numbering from
    /// `count + 1` reuses a number after a delete. Lights had that defect and could not fix
    /// it, because there was no stored value to hold the answer — the roster numbered them by
    /// position, so deleting Light 2 silently renamed Light 3.
    static func nextName(after lights: [Light]) -> String {
        let used = Set(lights.compactMap(\.name))
        var n = 1
        // In the Interface Language of the moment it is placed; from then on the name is the
        // DM's, and is never translated again.
        func name(_ n: Int) -> String { String(localized: "Light \(n)") }
        while used.contains(name(n)) { n += 1 }
        return name(n)
    }
}

/// A Pawn: a token with a label and a colour, drawn for players whether or not the Fog
/// Overlay is active.
///
/// A Pawn is also a Light — its range of sight and its range of illumination are the same
/// number. That collapse follows from this being a lighting simulation: with no
/// per-observer masks and one shared Player Display, a Pawn that sees 30 ft and a Pawn
/// that lights 30 ft are indistinguishable. So a Pawn *has* a Light rather than repeating
/// its fields, and Visibility reads both alike.
struct Pawn: Codable, Equatable, Identifiable {
    var id = UUID()
    var label: String
    /// `#RRGGBB`. Stored as a string so the file stays portable and human-readable —
    /// an archived `NSColor` would be neither.
    var colorHex: String
    var light: Light

    /// What this Pawn *is*: a party member, a Creature, or a Treasure.
    ///
    /// An enum rather than the booleans this replaces, because the three are mutually
    /// exclusive — a chest is not also a goblin — and a second flag beside `isCreature`
    /// would make `isCreature && isTreasure` representable and meaningless. It also makes
    /// the live panel's split a `switch` over every case rather than two filters that
    /// happen to partition the array today.
    ///
    /// Still one type with a flag rather than three types: placement, dragging, labels,
    /// colour, selection, deletion and undo are identical, and only lighting and render
    /// order branch. The cost is that a non-emitting Pawn carries a `light` it does not
    /// use — the same collapse this type already makes in the other direction, and it
    /// means promoting one back to a party member keeps its radii rather than needing
    /// them re-entered.
    var kind: PawnKind = .player

    /// Whether this Pawn emits no Light and hides in darkness — true of everything that
    /// is not a party member. The one place that rule lives, so `Visibility` and
    /// `PlayerVisibility` cannot disagree about it.
    var isDiscovered: Bool { kind.isDiscovered }

    /// Taken off the Player Display by the DM without being deleted. Beats lighting: a
    /// hidden Pawn is invisible to players however well lit it is, which is the point of
    /// the control. Still visible, de-emphasised, on the Control Window.
    var isHidden = false

    /// **Big**: the token occupies 2×2 squares instead of 1×1 — an ogre, not a goblin.
    ///
    /// Purely visual. The radii stay measured from the Pawn's point, because a creature's
    /// size does not change how far its torch reaches or how far it sees, in 5e or here.
    /// The token is simply drawn twice as wide about the same centre, with no snapping:
    /// Pawns have never snapped, and a Big Pawn that jumped to a lattice would be the
    /// behaviour this app removed on purpose.
    ///
    /// Independent of `kind` — an ogre ally, a goblin and a big hoard are all meaningful.
    var isBig = false

    /// Which `PartyCharacter` Stamped this Pawn, when one did.
    ///
    /// **Advisory, and read by exactly one thing**: the Party panel's count of how many of a
    /// Character's Pawns stand on this Map. Nothing about drawing, lighting, discovery or
    /// persistence may branch on it, and a Pawn whose Character has been deleted is in no way
    /// diminished — it simply stops being counted.
    ///
    /// This is not a link. The Pawn holds its own label, colour and sight, copied at the
    /// moment of the drag, so `<map>.fog.json` stays readable with no roster present. See
    /// `docs/adr/0007-characters-are-stamped-not-linked.md` for why a reference was rejected.
    var characterID: UUID?

    /// Which `Monster` this Creature was said to be, by the `name:` its note gives it.
    ///
    /// **Advisory**, in `characterID`'s sense, and read by exactly two things: the Combat
    /// tab's reference view, which looks the Monster's actions up by it, and `AddPlacement`,
    /// which gives the next Creature the same Monster. The Pawn's numbers were *copied* into
    /// its Stat Block when the Monster was chosen (`MonsterStamp`), so a Creature whose note
    /// has been renamed or deleted loses a page of reference and nothing else.
    ///
    /// A name, not a path and not an ID: the notes carry no IDs, a path would write the DM's
    /// vault layout into a file meant to be portable, and a name is something a DM opening
    /// this file can read. See `docs/adr/0020-monsters-are-read-from-the-dms-notes.md`.
    var monsterName: String?

    /// How many Grid squares a token spans. The one place the 2 lives, so every surface
    /// that sizes a token agrees.
    static func squaresAcross(isBig: Bool) -> CGFloat { isBig ? 2 : 1 }

    /// How far past a Pawn's sight the visible region fades out, in Grid squares.
    ///
    /// **Cosmetic only.** A character's sight is not a light source, and DnD has no band of
    /// "dim vision" — you see to your range or you do not. Without any falloff the edge of
    /// what a Pawn reveals is a hard circular cut, which reads as a rendering artefact
    /// rather than as darkness, so one square of feathering softens it.
    ///
    /// One square, not a ratio. The previous rule gave dim twice bright — the 5e convention
    /// for *torches*, correct for a `Light` and wrong here: it drew a 12-square halo around
    /// a character who can see 6.
    static let sightFeatherSquares: CGFloat = 1

    /// The dim radius a Pawn's sight implies. Derived, never stored — a stored copy is what
    /// let the two drift apart, so that a Pawn kept the halo of whatever radius it was first
    /// created with.
    static func dimSquares(forSight sight: CGFloat) -> CGFloat {
        max(0, sight) + sightFeatherSquares
    }

    /// This Pawn's own span, in Grid squares.
    var squaresAcross: CGFloat { Self.squaresAcross(isBig: isBig) }

    var at: MapPoint {
        get { light.at }
        set { light.at = newValue }
    }

    init(id: UUID = UUID(), at: MapPoint, label: String, colorHex: String,
         brightSquares: CGFloat,
         kind: PawnKind = .player, isHidden: Bool = false, isBig: Bool = false,
         characterID: UUID? = nil, monsterName: String? = nil) {
        self.id = id
        self.label = label
        self.colorHex = colorHex
        self.light = Light(at: at, brightSquares: brightSquares,
                           dimSquares: Self.dimSquares(forSight: brightSquares))
        self.kind = kind
        self.isHidden = isHidden
        self.isBig = isBig
        self.characterID = characterID
        self.monsterName = monsterName
    }

    /// Written by hand for the three flags, which decode as false when absent.
    ///
    /// A property default is not enough: Swift's synthesised `decode` requires every key
    /// unless the property is optional, so adding these flags to the synthesised
    /// conformance made every `.fog.json` written before Creatures existed fail to load
    /// outright — a DM's authored fog, unreadable, with the store correctly refusing to
    /// overwrite the file it could not read. Caught by a test that decodes a file with the
    /// keys absent; keep that test.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        // Derived from the decoded sight, not taken from the file: every Pawn written
        // before this rule has dim at twice its sight, and re-deriving corrects it without
        // rewriting anyone's map.
        var decodedLight = try container.decode(Light.self, forKey: .light)
        decodedLight.dimSquares = Self.dimSquares(forSight: decodedLight.brightSquares)
        light = decodedLight
        kind = try Self.decodeKind(from: container)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        isBig = try container.decodeIfPresent(Bool.self, forKey: .isBig) ?? false
        characterID = try container.decodeIfPresent(UUID.self, forKey: .characterID)
        monsterName = try container.decodeIfPresent(String.self, forKey: .monsterName)
    }

    /// Written by hand because `CodingKeys` carries the legacy `isCreature` key that has
    /// no stored property behind it — which also blocks the synthesised `encode`.
    ///
    /// The legacy key is deliberately not written back. A file is rewritten whenever the
    /// DM touches its Map at all, so echoing it would slowly duplicate the same fact in
    /// two places that could then disagree; `kind` is the one the reader trusts, and a
    /// file this app has written is never read by a version that predates it.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(light, forKey: .light)
        try container.encode(kind, forKey: .kind)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(isBig, forKey: .isBig)
        // Omitted when absent, unlike the flags above: a DM who has never defined a Party
        // should see no trace of the feature in their map files, and `"characterID": null`
        // in every Pawn would be exactly that.
        try container.encodeIfPresent(characterID, forKey: .characterID)
        // Omitted when absent for the same reason.
        try container.encodeIfPresent(monsterName, forKey: .monsterName)
    }

    /// Reads `kind`, falling back to the `isCreature` boolean it replaces.
    ///
    /// Three generations of file have to land somewhere sensible: one written before
    /// Creatures existed has neither key and is a party member; one written with the
    /// boolean means `.creature` when it is true; one written since carries `kind`
    /// outright. The old key is read forever and never written — rewriting it would
    /// rewrite maps the DM has not touched, and dropping it would turn every goblin
    /// already on disk back into a party member that lights the room it hides in.
    private static func decodeKind(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> PawnKind {
        if let kind = try container.decodeIfPresent(PawnKind.self, forKey: .kind) {
            return kind
        }
        let wasCreature = try container.decodeIfPresent(Bool.self, forKey: .isCreature) ?? false
        return wasCreature ? .creature : .player
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, colorHex, light, kind, isCreature, isHidden, isBig, characterID,
             monsterName
    }
}

/// What a Pawn is: who the players carry, what they meet, and what they find.
///
/// The distinction is only ever about **light and discovery**. Everything else a Pawn does
/// — moving, labelling, colouring, hiding, being Big — is identical across all three, which
/// is why this is a property of `Pawn` rather than three types.
enum PawnKind: String, Codable, CaseIterable, Equatable {
    /// The party's own tokens: they emit Light, and they are drawn on the Player Display
    /// whatever the fog does. A player's miniature must never vanish.
    case player
    /// A monster: emits no Light, and darkness hides it from players.
    case creature
    /// A chest, a hoard, a body — something the players find. Emits no Light and hides in
    /// darkness exactly as a Creature does; it differs only in being drawn as a square and
    /// in being listed apart, because a DM reasons about loot and monsters separately.
    case treasure

    /// Whether the players have to discover this, rather than carrying it.
    ///
    /// The single rule behind both branches that exist: a discovered Pawn emits no Light
    /// (`VisibilityCache`) and draws under the Fog Overlay (`PlayerVisibility`). Written as
    /// a `switch` with no `default`, so a fourth kind cannot be added without deciding
    /// which side of the fog it falls on.
    var isDiscovered: Bool {
        switch self {
        case .player: return false
        case .creature, .treasure: return true
        }
    }

    /// Whether a Pawn of this kind can be said to be a `Monster`.
    ///
    /// Only a Creature (`CONTEXT.md`, **Monster**): a Player's numbers come from its
    /// Character, and a Treasure has none. One place, so the search box, the draft and `Add`
    /// cannot come to disagree about it. A `switch` with no `default`, as above.
    var canBeMonster: Bool {
        switch self {
        case .creature: return true
        case .player, .treasure: return false
        }
    }

    /// The heading this kind is listed under in the live panel.
    var pluralTitle: String {
        switch self {
        case .player: return String(localized: "Players")
        case .creature: return String(localized: "Creatures")
        // Its own key: English says "Treasure" for the heading and for one of them, where
        // Italian says *Tesori* and *Tesoro*.
        case .treasure: return String(localized: "pawn-kind.treasure.heading", defaultValue: "Treasure")
        }
    }

    /// What the inspector calls this kind in its picker.
    var title: String {
        switch self {
        case .player: return String(localized: "Player")
        case .creature: return String(localized: "Creature")
        case .treasure: return String(localized: "Treasure")
        }
    }
}
