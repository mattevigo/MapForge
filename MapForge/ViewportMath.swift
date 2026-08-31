import CoreGraphics

/// Pure geometry for the Control Window's Viewport views: the pannable rectangle
/// in Viewport mode, and the Player Display mirror outside it.
enum ViewportMath {
    /// The Viewport (map inches) expressed in the Map's image-pixel coordinates.
    static func viewportRectInImagePixels(originInches: CGPoint, sizeInches: CGSize,
                                          map: MapScale) -> CGRect {
        guard map.physicalWidthInches > 0 else { return .zero }
        let pixelsPerMapInch = map.imagePixelSize.width / map.physicalWidthInches
        return CGRect(x: originInches.x * pixelsPerMapInch,
                      y: originInches.y * pixelsPerMapInch,
                      width: sizeInches.width * pixelsPerMapInch,
                      height: sizeInches.height * pixelsPerMapInch)
    }

    /// Where the mirrored Viewport region sits in the preview container (aspect-fit,
    /// centered). Content outside this rect must be masked: it is map the players
    /// cannot see, and showing it would make the mirror lie.
    static func mirrorViewportRect(viewportRect: CGRect, container: CGSize) -> CGRect {
        guard viewportRect.width > 0, viewportRect.height > 0 else { return .zero }
        let scale = min(container.width / viewportRect.width,
                        container.height / viewportRect.height)
        let size = CGSize(width: viewportRect.width * scale, height: viewportRect.height * scale)
        return CGRect(x: (container.width - size.width) / 2,
                      y: (container.height - size.height) / 2,
                      width: size.width,
                      height: size.height)
    }

    /// The frame the full image must occupy in the preview container so that
    /// `viewportRect` (image pixels) lands exactly on `mirrorViewportRect` — the
    /// mirror of what the Player Display shows.
    static func mirrorImageFrame(imagePixelSize: CGSize, viewportRect: CGRect,
                                 container: CGSize) -> CGRect {
        guard viewportRect.width > 0, viewportRect.height > 0 else { return .zero }
        let scale = min(container.width / viewportRect.width,
                        container.height / viewportRect.height)
        let visible = mirrorViewportRect(viewportRect: viewportRect, container: container)
        return CGRect(x: visible.minX - viewportRect.minX * scale,
                      y: visible.minY - viewportRect.minY * scale,
                      width: imagePixelSize.width * scale,
                      height: imagePixelSize.height * scale)
    }
}
