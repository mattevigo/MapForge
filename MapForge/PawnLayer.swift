import SwiftUI

/// Pawns on the Control Window's normal preview, draggable.
///
/// Separate from `FogOverlay` because this is the *live* half of issue 04: the party moves
/// during play, not during prep, so a DM must be able to slide a token without entering an
/// editing mode first. Fog authoring stays behind the mode; moving tokens does not.
struct PawnLayer: View {
    let map: MapScale
    /// Where the Map image sits in this container — the mirror's frame, which already
    /// carries the Viewport pan.
    let frame: CGRect
    let pawns: [Pawn]
    /// The Map's own Lights, drawn as markers beneath the tokens. Not a Pawn's light: a
    /// Pawn already draws a token at exactly that point.
    let lights: [Light]
    /// Whether each Pawn is currently invisible to players, so the DM can see at a glance
    /// what the table can and cannot. Never used to hide one here: the Control Window
    /// exists so the DM sees everything.
    let isDimmed: (Pawn) -> Bool
    /// The same question for a Light Marker, and the same answer: faded, never absent.
    let isLightDimmed: (Light) -> Bool
    let onMove: (Pawn.ID, MapPoint) -> Void
    /// Called when a drag ends, so the move reaches disk without waiting out the debounce.
    ///
    /// Carries where the drag *began*, which only this view knows: `onMove` has already
    /// overwritten the Pawn's position many times by now, so the Combat Log's "from" has
    /// to come from the gesture rather than the document. A drag that ends where it
    /// started passes the same point twice and records nothing.
    let onCommit: (Pawn.ID, MapPoint) -> Void
    /// A Light Marker being dragged, and the drag ending. A Light is moved exactly as a Pawn
    /// is — live, in this view, with no mode — but its ending carries no origin: nothing
    /// records where a torch used to be.
    var onMoveLight: (Light.ID, MapPoint) -> Void = { _, _ in }
    var onCommitLight: () -> Void = {}
    /// A drag on a member of the Selection, which carries every member: the translation so
    /// far in image pixels, and the drag ending. Both hand back the `SelectionMove` this
    /// view took as the drag began, which holds where each member started — each Pawn's
    /// "from" in the Logs, for the same reason `onCommit` carries one.
    var onMoveSelection: (SelectionMove, CGVector) -> Void = { _, _ in }
    var onCommitSelection: (SelectionMove) -> Void = { _ in }
    /// The Pawn the DM's pointer rests on, whose label shows over its Face. The caller works
    /// it out with `pawnID(under:)` from the cursor it already tracks, rather than this view
    /// tracking hover on each token: reading the cursor adds no gesture, so dragging a Pawn,
    /// Add, a Measurement and the Viewport see exactly the clicks they saw before.
    var hoveredPawnID: Pawn.ID?
    /// What the DM has picked, each member of which wears a ring. Handed in the way
    /// `hoveredPawnID` is, and for a stronger reason: this layer is the Control Window's
    /// alone, so a ring drawn here cannot reach the Player Display — drawing it inside the
    /// shared `PawnToken` or `LightMarker` would put one flag between the table and what
    /// the DM picked. Picking a Pawn does not show its label: the ring says which, and a
    /// Face says who.
    var selection = Selection()

    @State private var dragStart: MapPoint?
    /// The Selection being carried, when the drag began on a member; nil for a drag that
    /// moves one thing alone. Decided once, as the drag begins: a drag is the whole
    /// Selection's or one thing's from start to finish.
    @State private var selectionMove: SelectionMove?
    /// The Pawn being dragged, which keeps its label for the whole drag. The pointer is on
    /// it throughout, but the cursor the caller tracks need not follow a held button, and a
    /// stale one would hand the label to whichever Pawn stands where the drag began.
    @State private var draggedPawnID: Pawn.ID?

    static let coordinateSpace = "pawnLayer"

    var body: some View {
        ZStack(alignment: .topLeading) {
            let side = PlayerPlacement.squareSidePoints(map: map, frame: frame)
            let pointedAt = draggedPawnID ?? hoveredPawnID
            // Under the tokens: a Pawn standing on a brazier must not be hidden by it.
            ForEach(lights) { light in
                let p = PlayerPlacement.viewPoint(light.at, map: map, frame: frame)
                LightMarker(squareSide: max(side, 12))
                    // The same 0.4 a Pawn the players cannot see gets, because it is the
                    // same statement: the table cannot see this.
                    .opacity(isLightDimmed(light) ? 0.4 : 1)
                    // Unfaded, as a Pawn's ring is.
                    .overlay {
                        if selection.contains(light: light.id) {
                            SelectionRing(shape: AnyShape(Circle()),
                                          diameter: LightMarker.diameter(squareSide: max(side, 12)))
                        }
                    }
                    // A marker is a small dot; the grab area is a square's worth, so the
                    // DM is not hunting nine points with a trackpad. Under the tokens still,
                    // so a Pawn standing on a brazier is what a drag there picks up.
                    .frame(width: Self.lightGrabSide(squareSide: side),
                           height: Self.lightGrabSide(squareSide: side))
                    .contentShape(Circle())
                    .position(x: p.x, y: p.y)
                    .gesture(drag(light))
                    .accessibilityIdentifier("light-marker-\(light.name ?? "unnamed")")
            }
            ForEach(pawns) { pawn in
                let p = PlayerPlacement.viewPoint(pawn.at, map: map, frame: frame)
                let tokenSide = Self.tokenSide(map: map, frame: frame)
                PawnToken(pawn: pawn, squareSide: tokenSide,
                          isHovered: pawn.id == pointedAt)
                    .opacity(isDimmed(pawn) ? 0.4 : 1)
                    // Over the faded token, not faded with it: which Pawns are picked is
                    // the DM's to see at full strength, whatever the table can see.
                    .overlay {
                        if selection.contains(pawn: pawn.id) {
                            let diameter = tokenSide * pawn.squaresAcross
                            SelectionRing(shape: PawnToken.outline(for: pawn.kind,
                                                                   diameter: diameter),
                                          diameter: diameter)
                        }
                    }
                    .position(x: p.x, y: p.y)
                    .gesture(drag(pawn))
                    // A test hook, and the only way to ask "is this Pawn on the preview":
                    // the token is a ZStack that publishes as one element, so its label
                    // Text is not separately queryable. Without this, the preview drawing
                    // nothing at all is indistinguishable from it drawing everything —
                    // which is how `.scratch/pawns-not-drawn/` survived a whole feature.
                    .accessibilityIdentifier("pawn-token-\(pawn.label)")
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
    }

    /// One Grid square in this layer's points, as a token is drawn: never under 12, so a
    /// Map with no Grid declared, or zoomed far out, still shows a token to grab.
    static func tokenSide(map: MapScale, frame: CGRect) -> CGFloat {
        max(PlayerPlacement.squareSidePoints(map: map, frame: frame), 12)
    }

    /// How far across a Light Marker can be grabbed, in this layer's points: a square's
    /// worth, never under 18. Named so `token(under:)` asks whether a press or a click
    /// landed on a marker by the same measure the marker is grabbed by.
    static func lightGrabSide(squareSide side: CGFloat) -> CGFloat { max(side, 18) }

    /// The Pawn or Light Marker under `point` as drawn — `point` and `frame` in the same view
    /// space, the one this layer draws in — or nil on the bare Map.
    ///
    /// Asked of the tokens on screen, not of `LiveHitTest`'s Map-space footprints, because
    /// the question is whose drag a press belongs to, and each token's drag is attached to
    /// what is drawn: a token's whole disc (`pawnID(under:)`) and a marker's square-wide grab
    /// area (`lightGrabSide`, a circle, as its `contentShape` is). A ⇧-click picks by it and
    /// a plain click on the bare Map is one where it finds nothing, so a click the DM sees
    /// land on a marker's grab area is never taken for the bare Map; and the selection
    /// rectangle declines a drag that starts on one, which is that token's own drag. The
    /// Pawn first: it is drawn over any marker it stands on.
    static func token(under point: CGPoint, pawns: [Pawn], lights: [Light], map: MapScale,
                      frame: CGRect) -> LiveHitTest? {
        if let id = pawnID(under: point, pawns: pawns, map: map, frame: frame) {
            return .pawn(id)
        }
        let side = PlayerPlacement.squareSidePoints(map: map, frame: frame)
        let radius = lightGrabSide(squareSide: side) / 2
        return lights.last { light in
            let centre = PlayerPlacement.viewPoint(light.at, map: map, frame: frame)
            let dx = point.x - centre.x, dy = point.y - centre.y
            return dx * dx + dy * dy <= radius * radius
        }.map { .light($0.id) }
    }

    /// The Pawn whose token, as drawn, is under `point` — in the space `frame` is given in.
    ///
    /// Asked of the token on screen rather than of `LiveHitTest`, which measures in image
    /// pixels and, with no Grid declared, answers for a 12-pixel speck at the centre of a
    /// token that may be a hundred pixels across. A disc answers inside the disc and a
    /// Treasure across its square, a Big Pawn across both squares, and the last Pawn drawn,
    /// the one on top, before any under it.
    static func pawnID(under point: CGPoint, pawns: [Pawn], map: MapScale,
                       frame: CGRect) -> Pawn.ID? {
        let side = tokenSide(map: map, frame: frame)
        return pawns.last { pawn in
            let centre = PlayerPlacement.viewPoint(pawn.at, map: map, frame: frame)
            let radius = side * pawn.squaresAcross / 2
            let dx = point.x - centre.x, dy = point.y - centre.y
            switch pawn.kind {
            case .player, .creature: return dx * dx + dy * dy <= radius * radius
            case .treasure: return abs(dx) <= radius && abs(dy) <= radius
            }
        }?.id
    }

    /// A Light Marker's drag: the marker alone, or the whole Selection when it is a member.
    /// Its ending carries no origin — nothing records where a torch used to be.
    private func drag(_ light: Light) -> some Gesture {
        drag(.light(light.id), from: light.at,
             moveAlone: { onMoveLight(light.id, $0) },
             commitAlone: { _ in onCommitLight() })
    }

    /// A Pawn's drag: the Pawn alone, or the whole Selection when it is a member.
    private func drag(_ pawn: Pawn) -> some Gesture {
        drag(.pawn(pawn.id), from: pawn.at,
             moveAlone: { onMove(pawn.id, $0) },
             commitAlone: { onCommit(pawn.id, $0) })
    }

    /// The one drag every token has. One `dragStart` serves them all: only one thing is
    /// under the cursor at a time.
    ///
    /// Whether the drag is the whole Selection's or `token`'s alone is decided once, as it
    /// begins, and holds to its end. `moveAlone` takes where the token goes; `commitAlone`
    /// where it stood as the drag began.
    ///
    /// Measured in this layer's own named space, never the token's — a token placed with
    /// `.position()` moves as it is dragged, and measuring against it makes the gesture a
    /// feedback loop. That is the bug issue 09 cost a round of work on.
    private func drag(_ token: LiveHitTest, from position: MapPoint,
                      moveAlone: @escaping (MapPoint) -> Void,
                      commitAlone: @escaping (_ origin: MapPoint) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                if dragStart == nil {
                    dragStart = position
                    // Membership is asked once, here, and the members' origins taken with
                    // it: the one pass over the whole Map a Selection drag makes. Every
                    // update after it is the members' alone.
                    selectionMove = SelectionMove(grabbing: token, selection: selection,
                                                  pawns: pawns, lights: lights)
                }
                if case .pawn(let id) = token { draggedPawnID = id }
                guard let start = dragStart, let translation = imageTranslation(value)
                else { return }
                if let selectionMove {
                    onMoveSelection(selectionMove, translation)
                } else {
                    moveAlone(MapPoint(x: start.x + translation.dx, y: start.y + translation.dy))
                }
            }
            .onEnded { _ in
                // `dragStart` is where the token stood before any of this drag's updates,
                // which is the only place that value still exists.
                let origin = dragStart ?? position
                let carried = selectionMove
                dragStart = nil
                selectionMove = nil
                draggedPawnID = nil
                if let carried { onCommitSelection(carried) } else { commitAlone(origin) }
            }
    }

    /// The drag so far in image pixels — container points back into the image, the inverse
    /// of `PlayerPlacement` — or nil while the layer has no size to measure against.
    private func imageTranslation(_ value: DragGesture.Value) -> CGVector? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        return CGVector(dx: value.translation.width / frame.width * map.imagePixelSize.width,
                        dy: value.translation.height / frame.height * map.imagePixelSize.height)
    }
}

/// The ring a member of the Selection wears on the Control Window: the token's own outline,
/// drawn just outside it in the system accent colour.
///
/// Outside rather than over the edge, so a Face is not cropped by it and a token in a
/// colour near the accent's still shows a gap of its own; a dark hairline beneath the
/// accent keeps it readable on pale artwork, where a blue on sandstone would fade.
private struct SelectionRing: View {
    let shape: AnyShape
    /// The width of what it rings — the token's disc or square, or a Light Marker's dot.
    let diameter: CGFloat

    private static let gap: CGFloat = 2
    private static let width: CGFloat = 3

    var body: some View {
        let side = diameter + 2 * (Self.gap + Self.width / 2)
        ZStack {
            shape.stroke(Color.black.opacity(0.55), lineWidth: Self.width + 2)
            shape.stroke(Color.accentColor, lineWidth: Self.width)
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }
}
