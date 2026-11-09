import Foundation

/// One press of the primary button on the Live View, from its first drag step to the
/// mouse-up, as far as the Selection's rules need to know: whether a token's own drag is
/// under way, and whether the release is a click or the end of a drag.
///
/// The Map's tap, the selection rectangle's drag and each token's drag in `PawnLayer` all
/// end on the same mouse-up, in an order SwiftUI does not promise. So a drag's end is not
/// forgotten at once: it is held until that mouse-up has been handled — the run loop's next
/// turn — and a tap heard before *or* after the drag's own `onEnded` finds it.
///
/// A reference, held in `@State` and written without publishing: it is written at drag
/// rate, and nothing on screen is drawn from it.
@MainActor
final class LiveViewPress {
    /// A token's own drag — a Pawn's, a Light Marker's or the whole Selection's — has moved
    /// something and not yet ended.
    private(set) var isTokenDragging = false
    /// The press has become a drag, of any kind, since the last release was handled.
    private var hasDragged = false

    /// A token's own drag has moved it (`PawnLayer`'s drag, from its first point).
    ///
    /// Not yet a drag as far as the click is concerned: a token's drag starts at one point,
    /// and a hand that wobbles a point or two while ⇧-clicking a Pawn is still clicking it.
    /// The release becomes a drag's at the distance every other drag here is one —
    /// `dragged()`, which the same press reaches too once it goes that far.
    func tokenDragged() {
        isTokenDragging = true
    }

    /// The press has moved far enough to be some drag — a token's, the rectangle's, a pan,
    /// the Viewport's — whoever owns it. Reported by the selection rectangle's gesture,
    /// which hears every primary drag on the Live View from three points.
    func dragged() {
        hasDragged = true
    }

    /// A drag's `onEnded`. The token's drag is over now; that the release ended a drag stays
    /// known until the rest of this mouse-up has been heard.
    func ended() {
        isTokenDragging = false
        // A run-loop block rather than `DispatchQueue.main.async`, as `ClickSelectsAll` found:
        // the main queue drains whenever the run loop turns, mid-event-handling included,
        // where a default-mode block waits until the event is done with.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in self?.hasDragged = false }
    }

    /// Whether this release ends a drag, and so is no click — asked by the Map's tap, once.
    /// Asking clears it, and any token drag with it: a drag SwiftUI cancelled without an
    /// `onEnded` can swallow one click at most, rather than every click — and every
    /// rectangle — after it.
    func takeDragEnd() -> Bool {
        defer {
            hasDragged = false
            isTokenDragging = false
        }
        return hasDragged
    }
}
