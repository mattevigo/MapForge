import CoreGraphics

private let mmPerInch: CGFloat = 25.4

/// Physical and pixel geometry of one display, plus its Calibration correction.
struct DisplayMetrics: Equatable {
    var pixelSize: CGSize
    var physicalSizeMM: CGSize
    var backingScaleFactor: CGFloat
    /// Measured length ÷ nominal length from the ruler Calibration. 1 = trust EDID.
    /// < 1 means the glass is smaller than EDID claims, so a real inch spans more pixels.
    var calibrationFactor: CGFloat = 1

    var pixelsPerInch: CGSize {
        CGSize(width: pixelSize.width / (physicalSizeMM.width * calibrationFactor / mmPerInch),
               height: pixelSize.height / (physicalSizeMM.height * calibrationFactor / mmPerInch))
    }

    var pointsPerInch: CGSize {
        CGSize(width: pixelsPerInch.width / backingScaleFactor,
               height: pixelsPerInch.height / backingScaleFactor)
    }
}

/// A Map's declared physical size (Grid-based or direct).
struct MapScale: Equatable {
    var imagePixelSize: CGSize
    var physicalWidthInches: CGFloat

    /// Grid convention: one square is 1 physical inch, so squares-wide pins the width.
    static func grid(squaresWide: CGFloat, imagePixelSize: CGSize) -> MapScale {
        MapScale(imagePixelSize: imagePixelSize, physicalWidthInches: squaresWide)
    }

    var physicalHeightInches: CGFloat {
        guard imagePixelSize.width > 0 else { return 0 }
        return physicalWidthInches * imagePixelSize.height / imagePixelSize.width
    }

    var physicalSizeInches: CGSize {
        CGSize(width: physicalWidthInches, height: physicalHeightInches)
    }
}

/// The Viewport resolved against a Map and display: fixed size, clamped origin (map inches).
struct Viewport: Equatable {
    var originInches: CGPoint
    var sizeInches: CGSize
}

enum ScaleMath {
    /// How many map inches the display shows at True Scale — the Viewport's fixed size.
    static func visibleMapInches(display: DisplayMetrics, screenSizePoints: CGSize) -> CGSize {
        CGSize(width: screenSizePoints.width / display.pointsPerInch.width,
               height: screenSizePoints.height / display.pointsPerInch.height)
    }

    /// Clamp a desired Viewport origin (map inches) so it never leaves the Map bounds.
    /// An axis where the Map fits inside the Viewport centers instead (negative origin = letterbox).
    static func clampedViewportOrigin(desired: CGPoint, viewportSize: CGSize, mapSize: CGSize) -> CGPoint {
        func clamp(_ desired: CGFloat, room: CGFloat) -> CGFloat {
            room >= 0 ? min(max(desired, 0), room) : room / 2
        }
        return CGPoint(x: clamp(desired.x, room: mapSize.width - viewportSize.width),
                       y: clamp(desired.y, room: mapSize.height - viewportSize.height))
    }

    /// The effective Viewport origin: the desired one clamped, or centered when none is set.
    static func viewportOrigin(desired: CGPoint?, viewportSize: CGSize, mapSize: CGSize) -> CGPoint {
        let desired = desired ?? CGPoint(x: (mapSize.width - viewportSize.width) / 2,
                                         y: (mapSize.height - viewportSize.height) / 2)
        return clampedViewportOrigin(desired: desired, viewportSize: viewportSize, mapSize: mapSize)
    }

    /// The Viewport for a Map on a display: size from the glass, origin clamped
    /// (or centered when `desiredOrigin` is nil).
    static func resolvedViewport(map: MapScale, display: DisplayMetrics, screenSizePoints: CGSize,
                                 desiredOrigin: CGPoint?) -> Viewport {
        let size = visibleMapInches(display: display, screenSizePoints: screenSizePoints)
        return Viewport(originInches: viewportOrigin(desired: desiredOrigin,
                                                     viewportSize: size,
                                                     mapSize: map.physicalSizeInches),
                        sizeInches: size)
    }

    /// The frame (in points) the Map must occupy on the Player Display for True Scale, centered.
    /// Overflows the screen when the Map is physically larger; letterboxes when smaller.
    static func trueScaleFrame(map: MapScale, display: DisplayMetrics, screenSizePoints: CGSize) -> CGRect {
        let viewport = resolvedViewport(map: map, display: display,
                                        screenSizePoints: screenSizePoints, desiredOrigin: nil)
        return trueScaleFrame(map: map, display: display, screenSizePoints: screenSizePoints,
                              viewportOriginInches: viewport.originInches)
    }

    /// True Scale frame with the Viewport's top-left placed at `viewportOriginInches` (map inches).
    static func trueScaleFrame(map: MapScale, display: DisplayMetrics, screenSizePoints: CGSize,
                               viewportOriginInches: CGPoint) -> CGRect {
        CGRect(x: -viewportOriginInches.x * display.pointsPerInch.width,
               y: -viewportOriginInches.y * display.pointsPerInch.height,
               width: map.physicalWidthInches * display.pointsPerInch.width,
               height: map.physicalHeightInches * display.pointsPerInch.height)
    }
}
