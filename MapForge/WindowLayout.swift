import CoreGraphics

/// Pure geometry for keeping the Control Window reachable.
enum WindowLayout {
    /// Where the Control Window must move when the Player Display it sits on is about
    /// to be covered by the Player window — nil when it can stay (not in the way, or
    /// nowhere else to go). Centered on its new screen, shrunk to fit it.
    ///
    /// The Mac's own screen wins when it is among the candidates: that is what the Control
    /// Window is — the DM-facing window on the Mac's own display. Taking whichever screen
    /// came first put it on an arbitrary second external instead, thousands of points off
    /// to the side of a wide desktop, where the DM has to hunt for it.
    static func controlWindowRelocation(controlFrame: CGRect, playerScreenFrame: CGRect,
                                        otherScreenFrames: [CGRect],
                                        mainScreenFrame: CGRect? = nil) -> CGRect? {
        guard controlFrame.intersects(playerScreenFrame) else { return nil }
        // Matched by origin, not by whole-frame equality: the candidate list and the main
        // screen come from separately-derived `NSScreen` reads, and a bitwise CGRect
        // comparison that missed would silently fall back to the arbitrary first screen —
        // the behaviour this preference exists to remove. Two screens cannot share an
        // origin, so the origin identifies one.
        let preferred = mainScreenFrame.flatMap { main in
            otherScreenFrames.first { $0.origin == main.origin }
        }
        guard let home = preferred ?? otherScreenFrames.first else { return nil }
        let size = CGSize(width: min(controlFrame.width, home.width),
                          height: min(controlFrame.height, home.height))
        return CGRect(x: home.minX + (home.width - size.width) / 2,
                      y: home.minY + (home.height - size.height) / 2,
                      width: size.width,
                      height: size.height)
    }
}
