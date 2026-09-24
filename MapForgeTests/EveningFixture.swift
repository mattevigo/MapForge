import Foundation
@testable import MapForge

extension AppState {
    /// Opens `directory` as the Workspace and starts a Session in it — the state a DM is in
    /// when they press Play.
    ///
    /// A fight cannot start before the evening has (`EncounterNeedsASessionTests`), so every
    /// test that calls `startEncounter` begins one first. Shared rather than written into
    /// each fixture, so the next precondition a fight grows is one edit and not nine.
    @MainActor
    func beginEvening(in directory: URL) {
        open(Workspace(url: directory))
        startSession()
    }
}
