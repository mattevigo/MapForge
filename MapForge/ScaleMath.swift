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

    /// The frame (in points) the Map occupies under **Map Fit**: the whole Map, as large as
    /// the screen allows, in its own proportions and centred — black letterbox on the two
    /// sides the Map does not reach, and never a crop.
    ///
    /// Sized from the image's pixels and nothing else. Map Fit ignores the declared size and
    /// the Grid, so it reads neither the Map's inches nor the display's; the image's own
    /// aspect ratio is what it keeps. A Map smaller than the screen is enlarged until it
    /// touches, which is the difference from True Scale. A Map with no pixels has nothing to
    /// fit and gets the whole screen rather than a division by zero.
    static func mapFitFrame(imagePixelSize: CGSize, screenSizePoints: CGSize) -> CGRect {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return CGRect(origin: .zero, size: screenSizePoints)
        }
        let scale = min(screenSizePoints.width / imagePixelSize.width,
                        screenSizePoints.height / imagePixelSize.height)
        let size = CGSize(width: imagePixelSize.width * scale,
                          height: imagePixelSize.height * scale)
        return CGRect(x: (screenSizePoints.width - size.width) / 2,
                      y: (screenSizePoints.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// The frame the Player Display draws the Map into: fitted to the screen under Map Fit,
    /// otherwise True Scale with the Viewport at `desiredViewportOrigin` (clamped, or
    /// centered when nil). Nil when there is nothing to draw: True Scale on a display that
    /// reports no physical size.
    ///
    /// `display` is optional because only True Scale needs it. Map Fit reads the screen's
    /// points and the image's pixels and nothing else — not the display's inches, not the
    /// Map's — so a screen whose EDID gives no size still shows the players the whole Map
    /// rather than black.
    ///
    /// The Viewport origin is read only when Map Fit is off, and never cleared by it, so
    /// turning Map Fit off returns to True Scale wherever the Viewport was before.
    static func playerFrame(map: MapScale, display: DisplayMetrics?, screenSizePoints: CGSize,
                            desiredViewportOrigin: CGPoint?, isMapFitOn: Bool) -> CGRect? {
        if isMapFitOn {
            return mapFitFrame(imagePixelSize: map.imagePixelSize, screenSizePoints: screenSizePoints)
        }
        guard let display else { return nil }
        let viewport = resolvedViewport(map: map, display: display,
                                        screenSizePoints: screenSizePoints,
                                        desiredOrigin: desiredViewportOrigin)
        return trueScaleFrame(map: map, display: display, screenSizePoints: screenSizePoints,
                              viewportOriginInches: viewport.originInches)
    }

    /// The Viewport the players are shown: under Map Fit the **whole Map**, otherwise the
    /// True Scale one at `desiredOrigin` (clamped, or centered when nil).
    ///
    /// The Live View's green rectangle answers "what do the players see", and under Map Fit
    /// the answer is all of it, so the rectangle must cover the Map rather than go on
    /// outlining a True Scale region nobody is looking at. The partner of `playerFrame`: one
    /// says where the Map lands on the Player Display, this says which part of it is there.
    ///
    /// `desiredOrigin` is read only when Map Fit is off, and never cleared by it, so turning
    /// Map Fit off returns the rectangle to wherever the DM had left it. Nil exactly when
    /// `playerFrame` is: True Scale on a display that reports no physical size.
    static func playerViewport(map: MapScale, display: DisplayMetrics?, screenSizePoints: CGSize,
                               desiredOrigin: CGPoint?, isMapFitOn: Bool) -> Viewport? {
        if isMapFitOn { return Viewport(originInches: .zero, sizeInches: map.physicalSizeInches) }
        guard let display else { return nil }
        return resolvedViewport(map: map, display: display, screenSizePoints: screenSizePoints,
                                desiredOrigin: desiredOrigin)
    }
}
