import CoreGraphics
import Foundation

/// Creating a Pawn from a Character — the decision a drop makes, kept out of the drop
/// handler.
///
/// SwiftUI's drag-and-drop cannot be driven from a unit test, so everything that could be
/// wrong about a drop lives here instead: where it landed, whether that is on the Map at all,
/// and which fields the new Pawn takes. What remains in the view is a call to this and an
/// append.
enum Stamp {
    /// The Pawn a Character Stamps when dropped at `droppedAt`, or nil when the drop misses
    /// the Map.
    ///
    /// `droppedAt` and `frame` must be in the same coordinate space — the one thing this
    /// cannot check, and the bug `PlayerPlacement.mapPoint` documents at length.
    static func pawn(from character: PartyCharacter,
                     droppedAt droppedPoint: CGPoint,
                     map: MapScale,
                     frame: CGRect) -> Pawn? {
        // A zero frame is a view that has not laid out yet; dividing by it yields a NaN that
        // would then poison every distance measured from the Pawn.
        guard frame.width > 0, frame.height > 0,
              map.imagePixelSize.width > 0, map.imagePixelSize.height > 0 else { return nil }

        let point = PlayerPlacement.mapPoint(droppedPoint, map: map, frame: frame)

        // Refused rather than clamped: a Pawn outside the image is meaningless to Visibility,
        // whose four implicit Walls sit at exactly these bounds. The edges themselves are on
        // the Map — a character with their back to the wall is the ordinary case.
        guard (0...map.imagePixelSize.width).contains(point.x),
              (0...map.imagePixelSize.height).contains(point.y) else { return nil }

        // A copy, not a link: every field is taken now and then leads its own life. `kind` is
        // always `.player` because the roster holds the party and nothing else, and
        // `dimSquares` is derived by `Pawn.init` rather than carried over, so a Stamped Pawn
        // and a hand-placed one of the same sight light the Map identically.
        return Pawn(at: point,
                    label: character.name,
                    colorHex: character.colorHex,
                    brightSquares: character.sightSquares,
                    kind: .player,
                    isHidden: false,
                    isBig: character.isBig,
                    characterID: character.id)
    }
}
