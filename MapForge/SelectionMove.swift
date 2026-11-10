import CoreGraphics

/// One drag of the whole **Selection**: where each member stood as the drag began.
///
/// Taken once, as the drag begins, and handed back to `AppState` on every update with the
/// translation so far — never a step since the last frame — for `apply` to carry out. Each update is then where the
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

    /// A drag on `token`, which moves the whole Selection — or nil when `token` is not a
    /// member, and the drag moves that Pawn or Light alone, exactly as it always has.
    init?(grabbing token: LiveHitTest, selection: Selection, pawns: [Pawn], lights: [Light]) {
        guard selection.contains(token) else { return nil }
        self.pawns = Self.members(of: pawns, pickedBy: selection.contains(pawn:))
        self.lights = Self.members(of: lights, pickedBy: selection.contains(light:))
        let xs = self.pawns.map(\.origin.x) + self.lights.map(\.origin.x)
        let ys = self.pawns.map(\.origin.y) + self.lights.map(\.origin.y)
        if let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() {
            extent = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        } else {
            extent = nil
        }
    }

    /// The picked ones among `items`, each with where it sits in the array and where it
    /// stands — the one pass over the whole Map a Selection drag makes.
    private static func members<Item: Locatable>(of items: [Item],
                                                 pickedBy isPicked: (Item.ID) -> Bool)
    -> [Member<Item.ID>] {
        items.enumerated().compactMap { index, item in
            isPicked(item.id) ? Member(id: item.id, index: index, origin: item.at) : nil
        }
    }

    /// Put every member where it stood as the drag began plus `translation` in image pixels,
    /// in `document` — held inside an image of `imageSize` as a whole (`limited`), or not
    /// held at all with no image to hold it in.
    ///
    /// Whether anyone moved: a frame that moved no one need not be written back, and the
    /// caller — `AppState`, the one place `fog` is assigned — writes the lot in one go.
    func apply(_ translation: CGVector, within imageSize: CGSize?,
               to document: inout FogDocument) -> Bool {
        let translation = imageSize.map { limited(translation, toImage: $0) } ?? translation
        let movedPawns = Self.place(pawns, by: translation, in: &document.pawns)
        let movedLights = Self.place(lights, by: translation, in: &document.lights)
        return movedPawns || movedLights
    }

    /// Each of `members` to its origin plus `translation` in `items`, skipping one that has
    /// gone; whether any of them changed place.
    private static func place<Item: Locatable>(_ members: [Member<Item.ID>],
                                               by translation: CGVector,
                                               in items: inout [Item]) -> Bool {
        var moved = false
        for member in members {
            guard let index = index(of: member, in: items) else { continue }
            let destination = MapPoint(x: member.origin.x + translation.dx,
                                       y: member.origin.y + translation.dy)
            guard items[index].at != destination else { continue }
            items[index].at = destination
            moved = true
        }
        return moved
    }

    /// Where `member` stands in `items` now: where it stood as the drag began, unless the
    /// document has changed under the drag, when it is searched for — and nil if it has
    /// gone, so a member deleted mid-drag is left out rather than another moved in its place.
    private static func index<Item: Identifiable>(of member: Member<Item.ID>,
                                                  in items: [Item]) -> Int? {
        if items.indices.contains(member.index), items[member.index].id == member.id {
            return member.index
        }
        return items.firstIndex { $0.id == member.id }
    }

    /// `translation` cut short, along each axis on its own, where the first member — Pawn or
    /// Light — would reach the edge of an image of `size`.
    ///
    /// The whole Selection stops rather than each member being held by `PawnBounds.clamp`
    /// on its own, which would keep everyone on the Map but squash the formation against
    /// the edge: the members would arrive in a different shape from the one they set out in.
    /// Each axis is cut separately, so a Selection pressed against the east wall still slides
    /// north along it, as one Pawn does.
    ///
    /// No move is ever refused outright: were a member already outside the image, a drag
    /// that takes it no further out is still allowed, and standing still always is.
    private func limited(_ translation: CGVector, toImage size: CGSize) -> CGVector {
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

/// A Pawn or a Light: something on the Map with an ID and a place, which is all a Selection
/// drag needs of either. A Pawn's place is its own Light's (`Pawn.at`).
protocol Locatable: Identifiable {
    var at: MapPoint { get set }
}

extension Pawn: Locatable {}
extension Light: Locatable {}
