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

    init(id: UUID = UUID(), from: CGPoint, to: CGPoint) {
        self.init(id: id, from: MapPoint(from), to: MapPoint(to))
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
    var imagePixels: CGPoint

    init(_ imagePixels: CGPoint) {
        self.imagePixels = imagePixels
    }

    init(x: CGFloat, y: CGFloat) {
        self.init(CGPoint(x: x, y: y))
    }

    var x: CGFloat { imagePixels.x }
    var y: CGFloat { imagePixels.y }
}

/// The fog data authored on one Map, as persisted in `<map>.fog.json`.
///
/// Not the Sidecar. `CONTEXT.md` names `<map>.mapforge.json` as the home for per-Map
/// metadata, but that issue is `wontfix`; fog was given its own file deliberately. The
/// accepted consequence is that `squaresWide` is still in-memory only, so a relaunch
/// returns a DM's Walls but not their Grid — and Light radii, being in squares, have no
/// physical meaning until it is re-entered.
struct FogDocument: Codable, Equatable {
    /// Somewhere for a later format change to branch on. Bump when the shape changes
    /// incompatibly; a reader that does not recognise a version must not discard the file.
    var version = 1
    var walls: [Wall] = []
    var lights: [Light] = []
    var pawns: [Pawn] = []

    /// Whether this Map has any fog worth a file. Nothing is written for an empty
    /// document: MapForge must not litter the user's map folder with files for Maps
    /// the DM never authored.
    var isEmpty: Bool { walls.isEmpty && lights.isEmpty && pawns.isEmpty }
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

    init(id: UUID = UUID(), at: CGPoint, brightSquares: CGFloat,
         dimSquares: CGFloat? = nil, isOn: Bool = true) {
        self.init(id: id, at: MapPoint(at), brightSquares: brightSquares,
                  dimSquares: dimSquares, isOn: isOn)
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

    var at: MapPoint {
        get { light.at }
        set { light.at = newValue }
    }

    init(id: UUID = UUID(), at: CGPoint, label: String, colorHex: String,
         brightSquares: CGFloat, dimSquares: CGFloat? = nil) {
        self.id = id
        self.label = label
        self.colorHex = colorHex
        self.light = Light(at: at, brightSquares: brightSquares, dimSquares: dimSquares)
    }
}
