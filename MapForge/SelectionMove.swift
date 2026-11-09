import CoreGraphics

/// One drag of the whole **Selection**: where each member stood as the drag began.
///
/// Taken once, as the drag begins, and handed back to `AppState` on every update with the
/// translation so far — never a step since the last frame. Each update is then where the
/// origins plus the translation put the members, so a drag held against the image edge and
/// brought back lands every member exactly where the cursor says, with no stop at the edge
/// left over in the formation.
///
/// Built from the document as it stands when the drag begins, so the work proportional to
/// the whole Map is done once per drag: each update after it touches the members alone,
/// which is what keeps a Selection drag at the rate a single Pawn's drag runs at.
struct SelectionMove {
    struct Member<ID: Equatable> {
        let id: ID
        /// Where it sat in the document's array when the drag began. Checked against `id`
        /// before it is used: a hint that saves a search on every frame, never the truth.
        let index: Int
        let origin: MapPoint
    }

    /// In the document's own order, so the Logs record the moves in the order the Map
    /// lists its Pawns, whichever member the DM grabbed.
    let pawns: [Member<Pawn.ID>]
    let lights: [Member<Light.ID>]
    /// The smallest box holding every member's origin: what the image edge limits a
    /// translation against, worked out once as the drag begins rather than on every update.
    private let extent: CGRect?

    /// A drag on `id`, which moves the whole Selection — or nil when `id` is not a member,
    /// and the drag moves that Pawn alone, exactly as it always has.
    init?(grabbingPawn id: Pawn.ID, selection: Selection, pawns: [Pawn], lights: [Light]) {
        guard selection.contains(pawn: id) else { return nil }
        self.init(selection: selection, pawns: pawns, lights: lights)
    }

    /// The same for a Light Marker.
    init?(grabbingLight id: Light.ID, selection: Selection, pawns: [Pawn], lights: [Light]) {
        guard selection.contains(light: id) else { return nil }
        self.init(selection: selection, pawns: pawns, lights: lights)
    }

    private init(selection: Selection, pawns: [Pawn], lights: [Light]) {
        self.pawns = pawns.enumerated().compactMap { index, pawn in
            selection.contains(pawn: pawn.id)
                ? Member(id: pawn.id, index: index, origin: pawn.at) : nil
        }
        self.lights = lights.enumerated().compactMap { index, light in
            selection.contains(light: light.id)
                ? Member(id: light.id, index: index, origin: light.at) : nil
        }
        let xs = self.pawns.map(\.origin.x) + self.lights.map(\.origin.x)
        let ys = self.pawns.map(\.origin.y) + self.lights.map(\.origin.y)
        if let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() {
            extent = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        } else {
            extent = nil
        }
    }

    /// `translation` cut short, along each axis on its own, where the first member — Pawn or
    /// Light — would reach the edge of an image of `size`.
    ///
    /// The whole Selection stops rather than each member being held by `PawnBounds.clamp`
    /// on its own, which would keep everyone on the Map but squash the formation against
    /// the edge: the party would arrive in a different shape from the one it set out in.
    /// Each axis is cut separately, so a party pressed against the east wall still slides
    /// north along it, as one Pawn does.
    ///
    /// No move is ever refused outright: were a member already outside the image, a drag
    /// that takes it no further out is still allowed, and standing still always is.
    func limited(_ translation: CGVector, toImage size: CGSize) -> CGVector {
        guard let extent else { return translation }
        return CGVector(dx: Self.limit(translation.dx, low: extent.minX, high: extent.maxX,
                                       within: size.width),
                        dy: Self.limit(translation.dy, low: extent.minY, high: extent.maxY,
                                       within: size.height))
    }

    /// `delta` held so that `low + delta` and `high + delta` stay within `0...length`.
    private static func limit(_ delta: CGFloat, low: CGFloat, high: CGFloat,
                              within length: CGFloat) -> CGFloat {
        let least = min(-low, 0), most = max(max(length, 0) - high, 0)
        return min(max(delta, least), most)
    }
}
