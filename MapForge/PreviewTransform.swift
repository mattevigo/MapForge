import CoreGraphics

/// The mapping between image pixels and Control Window preview points: `scale` preview
/// points per image pixel, `origin` the image's top-left corner in the container.
///
/// Grid Fit used to hold this implicitly as a permanently aspect-fit rect, which capped
/// the achievable precision — one grid square of a 3000 px map is ~15 pt in the preview,
/// so a 1 pt mis-drag is a ~7% error in the derived squares-wide. Making the transform
/// explicit lets the DM zoom in to draw. Only the *preview* zooms: the Player Display
/// keeps rendering at True Scale, untouched by anything here.
struct PreviewTransform: Equatable {
    let imagePixelSize: CGSize
    /// Preview points per image pixel.
    private(set) var scale: CGFloat
    /// The image's top-left corner in container coordinates.
    private(set) var origin: CGPoint

    /// One image pixel to one preview point. Zooming past this magnifies interpolation,
    /// not detail — the fit square is stored in image pixels, so there is nothing more
    /// to resolve.
    static let maxScale: CGFloat = 1

    /// The zoomed-out floor: the whole image aspect-fit and centered, as Grid Fit always
    /// showed it. Zoom never goes below this — the map can't be smaller than the preview.
    /// An image smaller than the preview would aspect-fit *above* 1:1; it is pinned at
    /// 1:1 instead and centered, rather than shown upscaled and blurry.
    static func fitted(imagePixelSize: CGSize, container: CGSize) -> PreviewTransform {
        let scale = min(fitScale(imagePixelSize: imagePixelSize, container: container), maxScale)
        var transform = PreviewTransform(imagePixelSize: imagePixelSize, scale: scale, origin: .zero)
        transform.origin = CGPoint(x: (container.width - transform.imageRect.width) / 2,
                                   y: (container.height - transform.imageRect.height) / 2)
        return transform
    }

    /// The aspect-fit scale, uncapped — the raw floor before the 1:1 ceiling applies.
    private static func fitScale(imagePixelSize: CGSize, container: CGSize) -> CGFloat {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return 1 }
        return min(container.width / imagePixelSize.width,
                   container.height / imagePixelSize.height)
    }

    /// The image's frame in container coordinates — what the preview draws into.
    var imageRect: CGRect {
        CGRect(x: origin.x, y: origin.y,
               width: imagePixelSize.width * scale,
               height: imagePixelSize.height * scale)
    }

    /// One preview point expressed in image pixels, floored at a whole pixel: the arrow-key
    /// nudge auto-refines as the DM zooms in, but never becomes a keypress that moves the
    /// square by a sub-pixel amount and reads as dead.
    var nudgeStepImagePixels: CGFloat {
        guard scale > 0 else { return 1 }
        return max(1, 1 / scale)
    }

    // MARK: Conversions

    func viewPoint(from imagePoint: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + imagePoint.x * scale, y: origin.y + imagePoint.y * scale)
    }

    func imagePoint(from viewPoint: CGPoint) -> CGPoint {
        guard scale > 0 else { return .zero }
        return CGPoint(x: (viewPoint.x - origin.x) / scale, y: (viewPoint.y - origin.y) / scale)
    }

    func viewRect(ofSquareCenteredAt center: CGPoint, side: CGFloat) -> CGRect {
        let topLeft = viewPoint(from: CGPoint(x: center.x - side / 2, y: center.y - side / 2))
        return CGRect(x: topLeft.x, y: topLeft.y, width: side * scale, height: side * scale)
    }

    // MARK: Zoom and pan

    /// Zoom to `scale`, keeping the image point currently under `anchoringViewPoint` there —
    /// so zooming at the cursor doubles as navigation and rarely needs a pan afterwards.
    func zoomed(to newScale: CGFloat, anchoringViewPoint anchor: CGPoint, container: CGSize) -> PreviewTransform {
        let anchoredImagePoint = imagePoint(from: anchor)
        var next = self
        next.scale = Self.clampScale(newScale, imagePixelSize: imagePixelSize, container: container)
        next.origin = CGPoint(x: anchor.x - anchoredImagePoint.x * next.scale,
                              y: anchor.y - anchoredImagePoint.y * next.scale)
        return next.settled(in: container)
    }

    func panned(by translation: CGSize, container: CGSize) -> PreviewTransform {
        var next = self
        next.origin = CGPoint(x: origin.x + translation.width, y: origin.y + translation.height)
        return next.settled(in: container)
    }

    /// The same view, re-clamped against a container that changed size: the scale is held
    /// inside the new floor and ceiling, and the image re-settled against the new edges.
    /// Anchored at the centre, which only matters when the scale had to change.
    func resized(to container: CGSize) -> PreviewTransform {
        zoomed(to: scale, anchoringViewPoint: CGPoint(x: container.width / 2, y: container.height / 2),
               container: container)
    }

    // MARK: Clamping

    /// The zoom floor is fit-to-window and the ceiling is 1:1 — but on an image smaller
    /// than the preview the fit scale already exceeds 1:1, so the range would invert.
    /// The ceiling wins there, pinning such an image at 1:1.
    private static func clampScale(_ scale: CGFloat, imagePixelSize: CGSize, container: CGSize) -> CGFloat {
        let minScale = min(fitScale(imagePixelSize: imagePixelSize, container: container), maxScale)
        return min(max(scale, minScale), maxScale)
    }

    /// Keep the image covering the container on any axis large enough to fill it, and
    /// centered on any axis that isn't — the letterboxing Grid Fit always had, so an
    /// axis that fits stays put no matter how far the DM drags.
    private func settled(in container: CGSize) -> PreviewTransform {
        var next = self
        let rect = imageRect
        next.origin = CGPoint(x: Self.settledAxis(origin: rect.minX, extent: rect.width, container: container.width),
                              y: Self.settledAxis(origin: rect.minY, extent: rect.height, container: container.height))
        return next
    }

    private static func settledAxis(origin: CGFloat, extent: CGFloat, container: CGFloat) -> CGFloat {
        guard extent > container else { return (container - extent) / 2 }
        return min(max(origin, container - extent), 0)
    }
}
