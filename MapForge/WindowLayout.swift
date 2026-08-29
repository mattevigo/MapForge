import CoreGraphics

/// Pure geometry for keeping the Control Window reachable.
enum WindowLayout {
    /// Where the Control Window must move when the Player Display it sits on is about
    /// to be covered by the Player window — nil when it can stay (not in the way, or
    /// nowhere else to go). Centered on the first other screen, shrunk to fit it.
    static func controlWindowRelocation(controlFrame: CGRect, playerScreenFrame: CGRect,
                                        otherScreenFrames: [CGRect]) -> CGRect? {
        guard controlFrame.intersects(playerScreenFrame),
              let home = otherScreenFrames.first else { return nil }
        let size = CGSize(width: min(controlFrame.width, home.width),
                          height: min(controlFrame.height, home.height))
        return CGRect(x: home.minX + (home.width - size.width) / 2,
                      y: home.minY + (home.height - size.height) / 2,
                      width: size.width,
                      height: size.height)
    }
}
