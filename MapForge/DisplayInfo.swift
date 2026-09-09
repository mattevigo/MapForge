import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var isBuiltin: Bool {
        displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    /// Stable across replug and reboot, unlike `displayID`. Falls back to the transient
    /// ID only when CoreGraphics has no UUID for the display, which keeps the picker
    /// working for the session even though the choice will not be remembered.
    var displayIdentity: DisplayIdentity? {
        guard let id = displayID else { return nil }
        let uuid = CGDisplayCreateUUIDFromDisplayID(id).map {
            CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
        }
        return DisplayIdentity(uuid: uuid ?? "display-id:\(id)", name: localizedName)
    }

    @MainActor
    var displayCandidate: DisplayCandidate? {
        displayIdentity.map {
            DisplayCandidate(identity: $0, isBuiltin: isBuiltin, metrics: DisplayMetrics(screen: self))
        }
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
