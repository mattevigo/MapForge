import Foundation

/// The Health Bars where they meet the rest of the app (ADR-0036).
@MainActor
extension AppState {
    /// What the **Player Display** draws under each Pawn: its Health Bar, keyed by Pawn,
    /// for exactly the Pawns `PlayerVisibility.showsHealthBarToPlayers` lets the table see
    /// one for.
    ///
    /// Worked out here rather than in the view for the reason `playerMeasurements` is: the
    /// view is handed an answer and cannot get the question wrong — forget the switch, read
    /// last Turn's numbers, or draw a bar under a Pawn the table cannot see.
    var playerHealthBars: [Pawn.ID: HealthBar] {
        let regions = litRegions
        var bars: [Pawn.ID: HealthBar] = [:]
        for pawn in fog.pawns {
            let stats = healthBarStats(for: pawn.id)
            guard PlayerVisibility.showsHealthBarToPlayers(
                pawn: pawn, stats: stats, regions: regions,
                isFogOverlayOn: isFogOverlayOn, hasVisibility: hasDeclaredGrid,
                soloSightPawnID: resolvedSoloSightPawnID,
                areHealthBarsOn: showsHealthBarsToPlayers),
                let stats, let bar = HealthBar(kind: pawn.kind, stats: stats) else { continue }
            bars[pawn.id] = bar
        }
        return bars
    }

    /// The numbers a Pawn's bar is drawn from: the Encounter's, while it holds the Pawn, or
    /// the ones beside the Map. The Encounter's first because during a fight the Log is
    /// the authority (ADR-0008) and the copy beside the Map only follows it — today after
    /// every Change, but the bar should not depend on how promptly that copy is kept, and
    /// the Encounter tab reads its numbers the same way. Nil when the DM has given the Pawn
    /// no numbers at all.
    private func healthBarStats(for pawn: Pawn.ID) -> StatBlock? {
        encounter?.blocks[pawn] ?? statsDocument.blocks[pawn]
    }
}
