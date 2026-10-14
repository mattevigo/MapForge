import CoreGraphics
import Foundation

/// A Pawn's **Face** as the fog file records it: which kept cut it is drawn as, and where that
/// Face came from. See `CONTEXT.md`, **Face**, and
/// `docs/adr/0028-a-face-is-a-cut-kept-in-the-workspace.md`.
///
/// A file name, never a path and never the picture: what the app keeps is the square the DM
/// cut, copied into the Workspace's `.mapforge/faces/`, so the picture it came from can move,
/// change or disappear without any Map noticing. The colour stays on the Pawn, unseen, so a
/// Face removed shows it again.
struct PawnFace: Codable, Equatable {
    /// The kept cut's file name in `.mapforge/faces/`.
    var file: String
    /// Where the Face came from.
    ///
    /// Recorded because what may later happen to a Face depends on it: one the DM cut by hand
    /// for this Pawn is never replaced when the Pawn becomes another Monster, and is re-cut
    /// without the "this Pawn, or every one?" question. Which Character or Monster a Face came
    /// from is already on the Pawn (`characterID`, `monsterName`), so only the kind of source
    /// is stored here.
    var origin: Origin

    enum Origin: String, Codable {
        /// Cut by the DM for this Pawn, or for the one it inherited the Face from under Add.
        case hand
    }

    /// `from` rather than `origin` in the file, so a DM reading it sees
    /// `"face": {"file": "…png", "from": "hand"}`.
    private enum CodingKeys: String, CodingKey {
        case file
        case origin = "from"
    }
}

/// The square a Face is cut as, in the picture's pixels with the origin at its top left —
/// where it starts, and how it is kept inside the picture however it is moved or resized.
///
/// Pure geometry, so the rules are proved without a picture or a view: the cut is always a
/// square, always inside the picture, on whole pixels, and no smaller than a floor that still
/// makes a recognisable token.
enum FaceCut {
    /// The smallest square a cut may be, in picture pixels — unless the picture itself is
    /// smaller, when the cut is the whole of its short side.
    static let minimumSide: CGFloat = 16

    /// The largest centred square: what a cut starts as, before the DM moves it.
    static func centredSquare(in picture: CGSize) -> CGRect {
        let side = largestSide(in: picture)
        return CGRect(x: ((picture.width - side) / 2).rounded(.down),
                      y: ((picture.height - side) / 2).rounded(.down),
                      width: side, height: side)
    }

    /// `cut` moved by `delta`, stopping at the picture's edges.
    static func moved(_ cut: CGRect, by delta: CGSize, in picture: CGSize) -> CGRect {
        clamped(cut.offsetBy(dx: delta.width, dy: delta.height), in: picture)
    }

    /// `cut` grown or shrunk to `side` about its centre, then shifted back inside the picture
    /// if growing pushed it past an edge.
    static func resized(_ cut: CGRect, toSide side: CGFloat, in picture: CGSize) -> CGRect {
        // The side the cut will really have, before it is placed: centring a side that the
        // floor or the picture then changes would leave the cut off its own centre.
        let side = allowedSide(side, in: picture)
        let resized = CGRect(x: cut.midX - side / 2, y: cut.midY - side / 2,
                             width: side, height: side)
        return clamped(resized, in: picture)
    }

    /// `cut` made square, whole-pixel, within the floor and the picture, and inside it.
    static func clamped(_ cut: CGRect, in picture: CGSize) -> CGRect {
        let side = allowedSide(cut.width, in: picture)
        let x = min(max(cut.minX.rounded(), 0), picture.width.rounded(.down) - side)
        let y = min(max(cut.minY.rounded(), 0), picture.height.rounded(.down) - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// `side` on whole pixels, no smaller than the floor and no larger than the picture.
    private static func allowedSide(_ side: CGFloat, in picture: CGSize) -> CGFloat {
        min(max(side.rounded(), minimumSide), largestSide(in: picture))
    }

    private static func largestSide(in picture: CGSize) -> CGFloat {
        min(picture.width, picture.height).rounded(.down)
    }
}
