import XCTest
@testable import MapForge

/// Whether a Light's marker is drawn, on each screen.
///
/// Tested through `PlayerVisibility` for the reason that type exists: a Light Marker is the
/// only thing besides a Pawn the Player Display draws over the Map, so what it reveals must
/// never be wrong by accident — and proving it needs no window.
final class LightMarkerTests: XCTestCase {
    private let lit = MapPoint(x: 0, y: 0)
    private let dark = MapPoint(x: 5000, y: 5000)

    private func regions() -> [LitRegion] {
        Visibility.compute(walls: [],
                           lights: [Light(at: MapPoint(x: 0, y: 0), brightSquares: 4)],
                           pixelsPerSquare: 10)
    }

    private func light(at point: MapPoint, isOn: Bool = true) -> Light {
        var light = Light(at: point, brightSquares: 3)
        light.isOn = isOn
        return light
    }

    private func shows(_ light: Light, isFogOverlayOn: Bool = true,
                       hasVisibility: Bool = true) -> Bool {
        PlayerVisibility.showsLightMarkerToPlayers(light: light, regions: regions(),
                                                   isFogOverlayOn: isFogOverlayOn,
                                                   hasVisibility: hasVisibility)
    }

    // MARK: - Burning and lit

    func testABurningLightOnLitFloorShows() {
        XCTAssertTrue(shows(light(at: lit)))
    }

    func testABurningLightOnUnlitFloorIsHidden() {
        // A brazier in a room the party has not reached stays theirs to discover.
        XCTAssertFalse(shows(light(at: dark)))
    }

    // MARK: - Doused

    func testADousedLightIsHiddenEvenOnLitFloor() {
        // The giveaway the creatures feature fixed once: a fixture placed for later must
        // not telegraph where the DM intends light to appear.
        XCTAssertFalse(shows(light(at: lit, isOn: false)))
    }

    func testADousedLightIsHiddenWithTheFogOverlayOff() {
        // Doused beats "no fog to hide behind" — it is the DM's "not yet", like the eye.
        XCTAssertFalse(shows(light(at: lit, isOn: false), isFogOverlayOn: false))
    }

    func testADousedLightIsHiddenWithNoGridDeclared() {
        XCTAssertFalse(shows(light(at: lit, isOn: false), hasVisibility: false))
    }

    // MARK: - No fog being drawn

    func testWithTheFogOverlayOffEveryBurningLightShows() {
        XCTAssertTrue(shows(light(at: dark), isFogOverlayOn: false))
    }

    func testWithNoGridDeclaredEveryBurningLightShows() {
        // No Visibility exists to hide behind, and a marker that vanished would read as a
        // bug — the same reasoning the Pawn rules already give.
        XCTAssertTrue(shows(light(at: dark), hasVisibility: false))
    }

    // MARK: - The DM sees everything

    func testTheDMSeesADousedLightFaded() {
        XCTAssertTrue(PlayerVisibility.isLightMarkerDimmedForDM(
            light: light(at: lit, isOn: false), regions: regions(),
            isFogOverlayOn: true, hasVisibility: true))
    }

    func testTheDMSeesALightInTheDarkFaded() {
        XCTAssertTrue(PlayerVisibility.isLightMarkerDimmedForDM(
            light: light(at: dark), regions: regions(),
            isFogOverlayOn: true, hasVisibility: true))
    }

    func testTheDMDoesNotFadeALightThePlayersCanSee() {
        XCTAssertFalse(PlayerVisibility.isLightMarkerDimmedForDM(
            light: light(at: lit), regions: regions(),
            isFogOverlayOn: true, hasVisibility: true))
    }

    // MARK: - The table never reads a Light's name

    /// The counterpart of `PawnLabelTests.testTheTableNeverReadsALabel`. A Light's name is the
    /// DM's bookkeeping, exactly as a Pawn's label is, and must not cross the room.
    func testTheTableNeverReadsALightsName() {
        XCTAssertFalse(PlayerVisibility.showsLightNameToPlayers,
                       "a Light's name would be drawn where the players can read it")
    }

    /// And the decision lives where every other leak is settled, rather than inside a view.
    ///
    /// `LightMarker` draws no text today, so the invariant currently holds by accident — this
    /// is what turns it into a rule. A future issue that wants the name on the marker for the
    /// DM must consult the constant rather than discover the question for itself.
    func testWhetherTheTableReadsLightNamesIsSettledWhereEveryOtherLeakIs() {
        // Both live on PlayerVisibility, beside the rules about which Pawns and Markers draw
        // at all. If either moves into a view, this stops compiling and that is the point.
        XCTAssertEqual(PlayerVisibility.showsLightNameToPlayers,
                       PlayerVisibility.showsPawnLabelToPlayers,
                       "a Light's name and a Pawn's label should reach the table alike")
    }
}
