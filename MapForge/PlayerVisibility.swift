import Foundation

/// Whether a Pawn is drawn on the Player Display.
///
/// Pure, so the rule can be tested without a window — the same split `ScaleMath`,
/// `WallSnap` and `ViewportMath` make. It decides what players do and do not get to see,
/// which is the one thing in this app that must never be wrong by accident.
enum PlayerVisibility {
    /// The rules, in priority order.
    ///
    /// 1. **Hidden wins over everything.** The DM has said "not yet"; a monster that
    ///    reappeared because someone lit a torch would defeat the control.
    /// 2. **A party Pawn is always drawn.** Turning fog on is not turning tokens off, and
    ///    a player's own miniature must never vanish. Everything the players *discover* —
    ///    a Creature, a Treasure — falls through to the light rules below instead.
    /// 3. **With no fog being drawn, everything shows.** Either the DM switched the Fog
    ///    Overlay off — in which case a Creature that stayed hidden is a token nobody can
    ///    explain — or no Grid is declared, so there is no Visibility to hide behind and
    ///    every Creature would silently vanish. Both read as bugs.
    /// 4. **Otherwise it is drawn only where the light reaches it**, bright or dim. Dim
    ///    reveals: 5e treats it as lightly obscured, not as blindness, and a Creature — or
    ///    a chest — on floor the players can plainly see would otherwise be invisible for
    ///    no reason they could infer.
    static func showsToPlayers(pawn: Pawn, regions: [LitRegion],
                               isFogOverlayOn: Bool, hasVisibility: Bool) -> Bool {
        if pawn.isHidden { return false }
        if !pawn.isDiscovered { return true }
        guard isFogOverlayOn, hasVisibility else { return true }
        return Visibility.level(at: pawn.at, in: regions) != .unlit
    }

    /// Whether the DM's own surfaces draw this Pawn faded.
    ///
    /// The Control Window shows the Map fully lit with Visibility as a tint precisely so
    /// the DM sees everything — a DM as blind as the players cannot run the fight. So a
    /// Pawn the players cannot see is never hidden here, only de-emphasised, which is what
    /// tells the DM at a glance what the table can and cannot see.
    static func isDimmedForDM(pawn: Pawn, regions: [LitRegion],
                              isFogOverlayOn: Bool, hasVisibility: Bool) -> Bool {
        !showsToPlayers(pawn: pawn, regions: regions,
                        isFogOverlayOn: isFogOverlayOn, hasVisibility: hasVisibility)
    }
}
