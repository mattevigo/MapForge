import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var isBuiltin: Bool {
        displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }
}

extension DisplayMetrics {
    /// EDID-based metrics for a screen. Nil when the display reports no physical size.
    @MainActor
    init?(screen: NSScreen) {
        guard let id = screen.displayID else { return nil }
        let mm = CGDisplayScreenSize(id)
        guard mm.width > 0, mm.height > 0 else { return nil }
        self.init(
            pixelSize: CGSize(width: screen.frame.width * screen.backingScaleFactor,
                              height: screen.frame.height * screen.backingScaleFactor),
            physicalSizeMM: mm,
            backingScaleFactor: screen.backingScaleFactor
        )
    }
}

extension NSImage {
    /// True pixel dimensions of the backing representation (NSImage.size is in points).
    var pixelSize: CGSize {
        let widest = representations.max(by: { $0.pixelsWide < $1.pixelsWide })
        guard let rep = widest, rep.pixelsWide > 0 else { return size }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}
