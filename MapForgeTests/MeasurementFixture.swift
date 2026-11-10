import Foundation
@testable import MapForge

/// The Map a Pawn's Measurements are taken on: one blue Rogue on a declared Grid, in an
/// AppState of its own.
///
/// Shared rather than copied into each suite, so the colour tests and the Line Origin tests
/// cannot drift onto two different Rogues.
enum MeasurementFixture {
    /// Where the Rogue stands until a test moves it.
    static let stood = MapPoint(x: 500, y: 400)

    static func rogue() -> Pawn {
        Pawn(at: stood, label: "Rogue", colorHex: "#3366CC", brightSquares: 4)
    }

    /// A fresh AppState with `pawn` alone on a Map 20 squares wide, and preferences no
    /// other test can see.
    @MainActor
    static func state(with pawn: Pawn) -> AppState {
        let defaults = UserDefaults(suiteName: "MeasurementFixture.\(UUID().uuidString)")!
        let state = AppState(preferences: DisplayPreferences(defaults: defaults))
        state.squaresWide = 20
        state.fog.pawns = [pawn]
        return state
    }
}
