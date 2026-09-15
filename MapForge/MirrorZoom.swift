import CoreGraphics

/// The DM's private magnifier over the Live View's mirror.
///
/// The mirror shows exactly what the Player Display shows, letterbox and all. This lets the
/// DM look *closer* at it without the table seeing anything change: the Viewport is not
/// touched, so the Player Display keeps rendering precisely what it was. That is the whole
/// distinction from "Pan Viewport…", which moves what the players see and is a deliberate,
/// visible act.
///
/// Two consequences follow, and both are enforced here rather than left to the view:
///
/// **The floor is the mirror, not the image.** `PreviewTransform`, which serves Grid Fit and
/// the Wall Editor, floors at the whole image aspect-fitted — right for authoring, wrong
/// here. Zooming out past the mirror would show the DM map the table is not being shown, on
/// a surface whose entire promise is that it shows what the table sees.
///
/// **Panning is held inside the mirrored region** for the same reason: magnified, the DM
/// moves the magnifier, and the magnifier cannot leave the glass.
struct MirrorZoom: Equatable {
    /// Preview points per mirrored point. 1 is a true, unmagnified mirror.
    private(set) var scale: CGFloat = 1
    /// Where the magnified frame's top-left sits relative to the mirror's, in mirror points.
    private var offset: CGSize = .zero

    /// Past this, the DM is magnifying interpolation rather than resolving detail — the
    /// mirror is already a scaled rendering of the image, so there is nothing further down
    /// there to see.
    static let maxScale: CGFloat = 8

    private static let sensitivity: CGFloat = 0.01

    /// Whether the DM is looking closer than the table is. Drives the affordance that says
    /// so, and the one that puts it back.
    var isMagnified: Bool { scale > 1 }

    /// The rect the mirror's layers should be drawn into: the mirrored frame, magnified and
    /// offset. Every layer reads this one rect, so they cannot drift apart from each other
    /// or from the Pawns drawn against them.
    func frame(mirroring mirror: CGRect, container: CGSize) -> CGRect {
        CGRect(x: mirror.minX + offset.width,
               y: mirror.minY + offset.height,
               width: mirror.width * scale,
               height: mirror.height * scale)
    }

    /// Scroll to zoom, holding the point under the cursor in place — the property that makes
    /// this read as a magnifier rather than a jump.
    mutating func zoom(by delta: CGFloat, at cursor: CGPoint, container: CGSize) {
        guard delta != 0, container.width > 0, container.height > 0 else { return }
        let target = (scale * exp(delta * Self.sensitivity)).clamped(to: 1...Self.maxScale)
        guard target != scale else { return }

        // Where the cursor sits within the magnified frame, as a fraction. Held across the
        // scale change, which is what pins the point under the cursor.
        let width = container.width * scale
        let height = container.height * scale
        let fractionX = width > 0 ? (cursor.x - offset.width) / width : 0.5
        let fractionY = height > 0 ? (cursor.y - offset.height) / height : 0.5

        scale = target
        offset = CGSize(width: cursor.x - fractionX * container.width * scale,
                        height: cursor.y - fractionY * container.height * scale)
        clamp(container: container)
    }

    /// Drag to move the magnifier. Inert at 1: panning a true mirror would show the DM map
    /// the players cannot see.
    mutating func pan(by translation: CGSize, container: CGSize) {
        guard isMagnified else { return }
        offset = CGSize(width: offset.width + translation.width,
                        height: offset.height + translation.height)
        clamp(container: container)
    }

    /// Back to a true mirror.
    mutating func reset() {
        scale = 1
        offset = .zero
    }

    /// Hold the magnified frame over the mirrored region: its edges may not come inside the
    /// container, or the DM would see past what the table is shown.
    private mutating func clamp(container: CGSize) {
        guard isMagnified else {
            offset = .zero
            return
        }
        let overhangX = container.width * scale - container.width
        let overhangY = container.height * scale - container.height
        offset = CGSize(width: offset.width.clamped(to: -overhangX...0),
                        height: offset.height.clamped(to: -overhangY...0))
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
