import Foundation

/// The Stat Editor's pointer where the two tabs of the live panel read it.
@MainActor
extension AppState {
    /// Whom the Stat Editor edits, in either tab: the Pawn the DM pointed at, or — during a
    /// fight, with nothing pointed at — whoever's Turn it is. Outside a fight there is no
    /// Turn to fall back on, so pointing at nothing edits nothing.
    ///
    /// One reading for both tabs, so the editor at the foot of each cannot disagree about
    /// whom it is showing.
    var statEditorSubject: Pawn.ID? {
        statEditorPawn ?? encounter?.activeCombatantID
    }
}
