import Foundation

/// The Stat Editor's pointer where the two tabs of the live panel read it.
@MainActor
extension AppState {
    /// Whom the Stat Editor edits, in either tab (`CombatSelectionPolicy.subject`).
    var statEditorSubject: Pawn.ID? {
        CombatSelectionPolicy.subject(pointedAt: statEditorPawn, during: encounter)
    }
}
