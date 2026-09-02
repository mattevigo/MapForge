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

    init(id: UUID = UUID(), at: MapPoint, brightSquares: CGFloat,
         dimSquares: CGFloat? = nil, isOn: Bool = true) {
        self.id = id
        self.at = at
        self.brightSquares = brightSquares
        self.dimSquares = dimSquares ?? brightSquares * 2
        self.isOn = isOn
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

    /// A **Creature**: a Pawn the players discover rather than one they carry.
    ///
    /// Inverts both halves of what a Pawn is. It emits no Light — a goblin waiting in the
    /// dark must not illuminate the room it is hiding in — and it is drawn *under* the Fog
    /// Overlay, so darkness hides it from players. The DM always sees it.
    ///
    /// A flag rather than a separate type: placement, dragging, labels, colour, selection,
    /// deletion and undo are identical, and only lighting and render order branch. The
    /// cost is that a Creature carries a `light` it does not emit — the same collapse this
    /// type already makes in the other direction, and it means promoting a Creature to a
    /// party member keeps its radii rather than needing them re-entered.
    var isCreature = false

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
    /// Independent of `isCreature` — an ogre ally and a goblin are both meaningful.
    var isBig = false

    /// How many Grid squares a token spans. The one place the 2 lives, so every surface
    /// that sizes a token agrees.
    static func squaresAcross(isBig: Bool) -> CGFloat { isBig ? 2 : 1 }

    /// This Pawn's own span, in Grid squares.
    var squaresAcross: CGFloat { Self.squaresAcross(isBig: isBig) }

    var at: MapPoint {
        get { light.at }
        set { light.at = newValue }
    }

    init(id: UUID = UUID(), at: MapPoint, label: String, colorHex: String,
         brightSquares: CGFloat, dimSquares: CGFloat? = nil,
         isCreature: Bool = false, isHidden: Bool = false, isBig: Bool = false) {
        self.id = id
        self.label = label
        self.colorHex = colorHex
        self.light = Light(at: at, brightSquares: brightSquares, dimSquares: dimSquares)
        self.isCreature = isCreature
        self.isHidden = isHidden
        self.isBig = isBig
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
        light = try container.decode(Light.self, forKey: .light)
        isCreature = try container.decodeIfPresent(Bool.self, forKey: .isCreature) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        isBig = try container.decodeIfPresent(Bool.self, forKey: .isBig) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, colorHex, light, isCreature, isHidden, isBig
    }
}
