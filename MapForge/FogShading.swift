import CoreGraphics

/// How dark each Visibility level is drawn, on each surface.
///
/// Pure numbers rather than colours buried in a view, because getting one wrong is not a
/// crash — it is players seeing a room the DM meant to hide, discovered at the table.
///
/// The two surfaces show the same Visibility at different strengths. Players get the truth:
/// unlit is black. The DM gets a tint they can read through, because a DM as blind as the
/// players cannot run the game.
enum FogShading {
    /// Darkness over the Map on the Player Display, 0 (clear) to 1 (black).
    static func player(_ level: VisibilityLevel, isOverlayOn: Bool = true) -> CGFloat {
        guard isOverlayOn else { return 0 }
        switch level {
        case .bright: return 0
        // Dim must read as a distinct third state — clearly darker than bright, clearly
        // short of hidden — or the 5e bright/dim distinction is decorative.
        case .dim: return 0.55
        case .unlit: return 1
        }
    }

    /// The DM's tint over a fully-lit Map. Same ordering as the players see, so the DM
    /// never misjudges what is hidden — only weaker, so they can see into it.
    static func control(_ level: VisibilityLevel, isOverlayOn: Bool = true) -> CGFloat {
        guard isOverlayOn else { return 0 }
        switch level {
        case .bright: return 0
        case .dim: return 0.25
        case .unlit: return 0.5
        }
    }

    /// The gradient at a Light's range limit: full strength through the middle, reaching
    /// zero exactly at the rim, so a torch fades out instead of ending in a suspicious
    /// circle. Wall shadow edges stay hard — a visibility polygon has no penumbra, and
    /// blurring them would make "can I see round that corner" ambiguous.
    static func falloffOpacity(atFractionOfRadius fraction: CGFloat) -> CGFloat {
        let clamped = min(max(fraction, 0), 1)
        guard clamped > falloffStart else { return 1 }
        return 1 - (clamped - falloffStart) / (1 - falloffStart)
    }

    /// Where the fade begins, as a fraction of the radius. Late enough that most of a
    /// Light is at full strength, early enough that the edge is not a hard ring.
    private static let falloffStart: CGFloat = 0.75
}
