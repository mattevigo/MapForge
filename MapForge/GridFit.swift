import CoreGraphics

/// Pure geometry for Grid Fit: declaring a Map's Grid from a square drawn
/// over one artwork grid square in the Control Window preview.
enum GridFit {
    /// The rect (in container coordinates) an image occupies when aspect-fit and centered.
    static func fittedImageRect(imagePixelSize: CGSize, container: CGSize) -> CGRect {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return .zero }
        let scale = min(container.width / imagePixelSize.width,
                        container.height / imagePixelSize.height)
        let size = CGSize(width: imagePixelSize.width * scale,
                          height: imagePixelSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2,
                      y: (container.height - size.height) / 2,
                      width: size.width,
                      height: size.height)
    }

    /// Squares-wide implied by a square of `squareSide` drawn over one grid square
    /// of an image `imageWidth` wide. The ratio is unit-free — both values just have
    /// to be in the same coordinate space (one square = 1 inch).
    static func squaresWide(imageWidth: CGFloat, squareSide: CGFloat) -> CGFloat? {
        guard squareSide > 0, imageWidth > 0 else { return nil }
        return imageWidth / squareSide
    }

    /// Inverse of `squaresWide`: the span of one grid square for a declared count.
    static func squareSide(imageWidth: CGFloat, squaresWide: CGFloat) -> CGFloat? {
        guard squaresWide > 0, imageWidth > 0 else { return nil }
        return imageWidth / squaresWide
    }

    /// The integer squares-wide to offer as a "Snap to N?" affordance, or nil.
    /// Never applied silently — the UI shows it for one-click acceptance.
    /// The threshold is absolute (a fraction of one square), not relative to the
    /// value: relative would keep the affordance permanently visible on large maps.
    static func snapSuggestion(for squaresWide: CGFloat) -> Int? {
        let snapThresholdSquares: CGFloat = 0.25
        guard squaresWide > 0 else { return nil }
        let nearest = squaresWide.rounded()
        let offset = abs(squaresWide - nearest)
        guard nearest >= 1, offset > 1e-9, offset <= snapThresholdSquares else { return nil }
        return Int(nearest)
    }
}
