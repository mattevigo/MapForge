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
}

enum ScaleMath {
    /// The frame (in points) the Map must occupy on the Player Display for True Scale, centered.
    /// Overflows the screen when the Map is physically larger; letterboxes when smaller.
    static func trueScaleFrame(map: MapScale, display: DisplayMetrics, screenSizePoints: CGSize) -> CGRect {
        let size = CGSize(width: map.physicalWidthInches * display.pointsPerInch.width,
                          height: map.physicalHeightInches * display.pointsPerInch.height)
        return CGRect(x: (screenSizePoints.width - size.width) / 2,
                      y: (screenSizePoints.height - size.height) / 2,
                      width: size.width,
                      height: size.height)
    }
}
