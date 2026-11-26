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
    /// A throwaway Pawn for drawing a Character's swatch — in the roster row, and under the
    /// cursor while dragging.
    ///
    /// The Character is shown as the Pawn it would Stamp rather than as a coloured dot, so
    /// what the DM drags looks like what they will get, Big footprint included. Never added
    /// to a document: its position is meaningless and its id changes on every redraw.
    static func preview(of character: PartyCharacter, note: CharacterNote?,
                        noteFace: PawnFace? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 0, y: 0),
             label: character.name,
             colorHex: character.colorHex,
             brightSquares: character.sightSquares,
             isBig: note?.isBig ?? false,
             characterID: character.id,
             face: face(of: character, noteFace: noteFace))
    }

    /// The Face a Pawn Stamped from `character` wears: the one the DM cut for the Character,
    /// or else `noteFace`, the cut of the picture its note names — the DM's own winning over
    /// the note's, as a label typed wins over one given (ADR-0028).
    ///
    /// A copy, remembered as the Character's, so re-cutting it later can offer to re-cut that
    /// Character too. The same file, never written again — a cut is never rewritten, so the
    /// Character changing its Face later cannot reach a Pawn already Stamped.
    private static func face(of character: PartyCharacter, noteFace: PawnFace?) -> PawnFace? {
        (character.face ?? noteFace).map { PawnFace(file: $0.file, origin: .character) }
    }

    /// The Stat Block a Stamped Pawn starts with, copied from its Character's note — or none,
    /// when the Character has no note the app could read (ADR-0024). A Pawn without one is a
    /// Pawn the DM types numbers onto, exactly as one placed by hand; a Stat Block of
    /// defaults would pass AC 10 off as the hero's.
    ///
    /// A sibling of `pawn(from:note:droppedAt:map:frame:)` rather than another return value from
    /// it, because the two land in different files: the Pawn in `<map>.fog.json`, its
    /// numbers in `<map>.combat/stats.json`. Keeping them separate at the seam keeps that
    /// split visible at every call site.
    ///
    /// A note records what a Character is at full strength; the Character records what the
    /// evening has done to it — so the Pawn arrives at `character`'s current and temporary hit
    /// points and exhaustion, which it then shares rather than copies (ADR-0037), and at full
    /// when no Character is given. No Conditions and no concentration: those belong to the
    /// place and the fight a Pawn is in, and this Pawn has not been in either yet.
    static func statBlock(from note: CharacterNote?,
                          of character: PartyCharacter? = nil) -> StatBlock? {
        guard let note else { return nil }
        let block = StatBlock(initiativeBonus: note.initiativeBonus ?? 0,
                              armorClass: note.armorClass ?? StatBlock.defaultArmorClass,
                              currentHP: note.maxHP,
                              maxHP: note.maxHP)
        return character?.sharedNumbers.laid(over: block, maxHP: note.maxHP) ?? block
    }

    /// The Pawn a Character Stamps when dropped at `droppedAt`, or nil when the drop misses
    /// the Map.
    ///
    /// `droppedAt` and `frame` must be in the same coordinate space — the one thing this
    /// cannot check, and the bug `PlayerPlacement.mapPoint` documents at length.
    static func pawn(from character: PartyCharacter,
                     note: CharacterNote?,
                     noteFace: PawnFace? = nil,
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
                    isBig: note?.isBig ?? false,
                    characterID: character.id,
                    face: face(of: character, noteFace: noteFace))
    }
}
