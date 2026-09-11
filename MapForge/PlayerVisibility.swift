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
    /// 2. **The Pawn under Solo Sight is always drawn.** It is the subject of the mode,
    ///    and a mode named after one Pawn where that Pawn can vanish leaves the table
    ///    staring at darkness with no way to read what went wrong.
    /// 3. **A party Pawn is always drawn — unless Solo Sight is on.** Turning fog on is not
    ///    turning tokens off, and a player's own miniature must never vanish. Everything
    ///    the players *discover* — a Creature, a Treasure — falls through to the light
    ///    rules below instead. Solo Sight puts the rest of the party through the same
    ///    discovery rule for as long as it is on: with the other torches out, a party
    ///    member around a corner is genuinely absent, which is the whole point of the mode
    ///    (ADR 0004). Note this is not line of sight — the Map's own braziers still reveal
    ///    people, because a sconce is the room, not another character's influence.
    /// 4. **With no fog being drawn, everything shows.** Either the DM switched the Fog
    ///    Overlay off — in which case a Creature that stayed hidden is a token nobody can
    ///    explain — or no Grid is declared, so there is no Visibility to hide behind and
    ///    every Creature would silently vanish. Both read as bugs.
    /// 5. **Otherwise it is drawn only where the light reaches it**, bright or dim. Dim
    ///    reveals: 5e treats it as lightly obscured, not as blindness, and a Creature — or
    ///    a chest — on floor the players can plainly see would otherwise be invisible for
    ///    no reason they could infer.
    /// `soloSightPawnID` has no default on purpose: a call site that forgot it would
    /// compile and silently render the pre-Solo-Sight rules, which is the second answer to
    /// "what do players see" that this type exists to prevent. Make the compiler ask.
    static func showsToPlayers(pawn: Pawn, regions: [LitRegion],
                               isFogOverlayOn: Bool, hasVisibility: Bool,
                               soloSightPawnID: Pawn.ID?) -> Bool {
        if pawn.isHidden { return false }
        if soloSightPawnID == pawn.id { return true }
        if !pawn.isDiscovered, soloSightPawnID == nil { return true }
        guard isFogOverlayOn, hasVisibility else { return true }
        return Visibility.level(at: pawn.at, in: regions) != .unlit
    }

    /// Whether a **Light Marker** is drawn on the Player Display.
    ///
    /// The same shape as the Pawn rules, and deliberately so: a marker is the only thing
    /// besides a Pawn the table's screen draws over the Map, and it should not get a second
    /// idea of what "visible" means.
    ///
    /// 1. **A doused Light shows nothing.** This is the eye's role here — the DM's "not
    ///    yet". A lantern placed for later, or a brazier the party is meant to find unlit,
    ///    would otherwise telegraph exactly where the DM intends light to appear. The same
    ///    class of giveaway as a hidden Pawn's torch, which `VisibilityCache` already fixed
    ///    once.
    /// 2. **With no fog being drawn, every burning Light shows.** No Overlay, or no Grid, so
    ///    there is no darkness to hide behind and a marker that vanished reads as a bug.
    /// 3. **Otherwise drawn only where the light reaches it**, bright or dim, exactly as a
    ///    Creature is. A burning Light nearly always lights its own point, so this rarely
    ///    bites — but a zero-radius Light must not become the one thing on the Player
    ///    Display that ignores the fog.
    static func showsLightMarkerToPlayers(light: Light, regions: [LitRegion],
                                          isFogOverlayOn: Bool, hasVisibility: Bool) -> Bool {
        if !light.isOn { return false }
        guard isFogOverlayOn, hasVisibility else { return true }
        return Visibility.level(at: light.at, in: regions) != .unlit
    }

    /// Whether the DM's own surfaces draw this Light Marker faded. The same standing rule
    /// as for a Pawn: never absent, only de-emphasised, because a DM who cannot find their
    /// own torches cannot run the fight.
    static func isLightMarkerDimmedForDM(light: Light, regions: [LitRegion],
                                         isFogOverlayOn: Bool, hasVisibility: Bool) -> Bool {
        !showsLightMarkerToPlayers(light: light, regions: regions,
                                   isFogOverlayOn: isFogOverlayOn, hasVisibility: hasVisibility)
    }

    /// Whether the DM's own surfaces draw this Pawn faded.
    ///
    /// The Control Window shows the Map fully lit with Visibility as a tint precisely so
    /// the DM sees everything — a DM as blind as the players cannot run the fight. So a
    /// Pawn the players cannot see is never hidden here, only de-emphasised, which is what
    /// tells the DM at a glance what the table can and cannot see.
    static func isDimmedForDM(pawn: Pawn, regions: [LitRegion],
                              isFogOverlayOn: Bool, hasVisibility: Bool,
                              soloSightPawnID: Pawn.ID?) -> Bool {
        !showsToPlayers(pawn: pawn, regions: regions,
                        isFogOverlayOn: isFogOverlayOn, hasVisibility: hasVisibility,
                        soloSightPawnID: soloSightPawnID)
    }
}
