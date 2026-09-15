import XCTest
@testable import MapForge

/// What `Add` places, and what it inherits.
///
/// The inheritance table is the reason this is a type rather than a closure in the view: a
/// DM populating an encounter places six goblins in a row, and each one arriving with the
/// wrong colour or the wrong size is six corrections. Inheriting **per Kind** is the part
/// worth asserting — a goblin's colour must not follow a Player onto the Map.
final class AddPlacementTests: XCTestCase {
    private let imageSize = CGSize(width: 400, height: 300)

    private func pawn(_ label: String, kind: PawnKind, colorHex: String,
                      sight: CGFloat = 6, isBig: Bool = false) -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 10), label: label, colorHex: colorHex,
             brightSquares: sight, kind: kind, isBig: isBig)
    }

    // MARK: Defaults with nothing to inherit from

    func testTheFirstPlayerTakesTheDefaults() throws {
        let placed = AddPlacement.pawn(kind: .player, at: MapPoint(x: 100, y: 100),
                                       existing: [])
        let new = try XCTUnwrap(placed)
        XCTAssertEqual(new.kind, .player)
        XCTAssertEqual(new.colorHex, Pawn.defaultColorHex)
        XCTAssertEqual(new.light.brightSquares, 6)
        XCTAssertFalse(new.isBig)
        XCTAssertEqual(new.at, MapPoint(x: 100, y: 100))
    }

    func testTheFirstLightTakesTheDefaults() {
        let placed = AddPlacement.light(at: MapPoint(x: 50, y: 50), existing: [])
        XCTAssertEqual(placed.brightSquares, 4)
        XCTAssertEqual(placed.dimSquares, 8, "dim defaults to twice bright, the 5e convention")
        XCTAssertEqual(placed.name, "Light 1")
        XCTAssertTrue(placed.isOn)
    }

    // MARK: Inheritance

    func testANewPawnInheritsFromTheLastOfItsOwnKind() throws {
        let existing = [pawn("Vex", kind: .player, colorHex: "#1E88C8", sight: 9),
                        pawn("Goblin", kind: .creature, colorHex: "#2E7D32", sight: 4, isBig: true)]

        let creature = try XCTUnwrap(AddPlacement.pawn(kind: .creature,
                                                       at: MapPoint(x: 100, y: 100),
                                                       existing: existing))
        XCTAssertEqual(creature.colorHex, "#2E7D32")
        XCTAssertEqual(creature.light.brightSquares, 4)
        XCTAssertTrue(creature.isBig)
    }

    /// The defect the per-Kind rule prevents: a goblin's green must not follow a Player
    /// onto the Map just because the goblin was placed most recently.
    func testANewPlayerDoesNotInheritFromACreature() throws {
        let existing = [pawn("Vex", kind: .player, colorHex: "#1E88C8", sight: 9),
                        pawn("Goblin", kind: .creature, colorHex: "#2E7D32", sight: 4, isBig: true)]

        let player = try XCTUnwrap(AddPlacement.pawn(kind: .player,
                                                     at: MapPoint(x: 100, y: 100),
                                                     existing: existing))
        XCTAssertEqual(player.colorHex, "#1E88C8")
        XCTAssertEqual(player.light.brightSquares, 9)
        XCTAssertFalse(player.isBig)
    }

    func testAKindWithNoneOnTheMapYetTakesTheDefaults() throws {
        let existing = [pawn("Goblin", kind: .creature, colorHex: "#2E7D32", isBig: true)]

        let treasure = try XCTUnwrap(AddPlacement.pawn(kind: .treasure,
                                                       at: MapPoint(x: 100, y: 100),
                                                       existing: existing))
        XCTAssertEqual(treasure.colorHex, Pawn.defaultColorHex)
        XCTAssertFalse(treasure.isBig, "a Treasure inherited a Creature's size")
    }

    func testANewLightInheritsTheLastOnesRadii() {
        let existing = [Light(at: MapPoint(x: 0, y: 0), brightSquares: 6, dimSquares: 7,
                              name: "Light 1")]
        let placed = AddPlacement.light(at: MapPoint(x: 50, y: 50), existing: existing)

        XCTAssertEqual(placed.brightSquares, 6)
        XCTAssertEqual(placed.dimSquares, 7, "dim was re-derived instead of inherited")
    }

    /// A doused torch is a live state, not a property of "the kind of torch I am placing" —
    /// a new Light always burns, or a DM who doused one would place invisible ones after it.
    func testANewLightBurnsEvenIfTheLastOneWasDoused() {
        var doused = Light(at: MapPoint(x: 0, y: 0), brightSquares: 4, name: "Light 1")
        doused.isOn = false
        XCTAssertTrue(AddPlacement.light(at: MapPoint(x: 50, y: 50), existing: [doused]).isOn)
    }

    // MARK: Naming

    /// The two schemes differ deliberately and this records which is which. `Light.nextName`
    /// fills gaps — the renumbering defect the `light-names` feature exists to fix — while
    /// `Pawn.nextLabel` takes the highest and adds one, so a deleted Pawn's number is not
    /// handed to a different token mid-fight. Both guarantee the new one is unused.
    func testANewPawnTakesAnUnusedLabel() throws {
        let existing = [pawn("1", kind: .player, colorHex: Pawn.defaultColorHex),
                        pawn("3", kind: .player, colorHex: Pawn.defaultColorHex)]
        let placed = try XCTUnwrap(AddPlacement.pawn(kind: .player, at: MapPoint(x: 1, y: 1),
                                                     existing: existing))

        XCTAssertEqual(placed.label, "4", "the highest label plus one")
        XCTAssertFalse(existing.map(\.label).contains(placed.label))
    }

    func testANewLightReusesAFreedName() {
        let lights = [Light(at: MapPoint(x: 0, y: 0), brightSquares: 4, name: "Light 1"),
                      Light(at: MapPoint(x: 1, y: 0), brightSquares: 4, name: "Light 3")]
        XCTAssertEqual(AddPlacement.light(at: MapPoint(x: 2, y: 0), existing: lights).name,
                       "Light 2")
    }

    // MARK: The image bounds

    /// A click outside the image places nothing. `Stamp` already refuses a drop outside
    /// rather than clamping, and `CONTEXT.md` says a Pawn beyond the implicit Walls is
    /// meaningless to Visibility — so this refuses too, rather than silently landing the
    /// token at the edge where the DM did not point.
    func testAClickOutsideTheImagePlacesNothing() {
        XCTAssertNil(AddPlacement.pawn(kind: .player, at: MapPoint(x: 500, y: 100),
                                       existing: [], imageSize: imageSize))
        XCTAssertNil(AddPlacement.pawn(kind: .player, at: MapPoint(x: -5, y: 100),
                                       existing: [], imageSize: imageSize))
        XCTAssertNil(AddPlacement.pawn(kind: .player, at: MapPoint(x: 100, y: 400),
                                       existing: [], imageSize: imageSize))
    }

    func testAClickInsideTheImageIsAccepted() {
        XCTAssertNotNil(AddPlacement.pawn(kind: .player, at: MapPoint(x: 399, y: 299),
                                          existing: [], imageSize: imageSize))
    }
}

/// The arming rules `ControlView` enforces, stated where a test can reach them.
///
/// The view's own `@State` is not reachable from a unit test — this is the layer the repo's
/// four gesture-composition defects lived in, and no unit test could reach those either.
/// What *is* testable is the policy the view asks, so the mutual exclusion is expressed as
/// one predicate rather than as two flags read in the right order.
final class ArmedToolTests: XCTestCase {
    func testAClickIsClaimedWhileAddIsArmed() {
        XCTAssertTrue(ArmedTool.claimsLeftClick(hasArmedAdd: true, hasArmedShape: false,
                                                hasMeasurement: false))
    }

    func testAClickIsClaimedWhileMeasuring() {
        XCTAssertTrue(ArmedTool.claimsLeftClick(hasArmedAdd: false, hasArmedShape: true,
                                                hasMeasurement: false))
        XCTAssertTrue(ArmedTool.claimsLeftClick(hasArmedAdd: false, hasArmedShape: false,
                                                hasMeasurement: true))
    }

    /// The default state, and the one that matters most: an idle Map must let the click
    /// through to the Pawn drag underneath, which is the commonest action on this surface.
    func testAnIdleMapLetsTheClickThroughToThePawnDrag() {
        XCTAssertFalse(ArmedTool.claimsLeftClick(hasArmedAdd: false, hasArmedShape: false,
                                                 hasMeasurement: false))
    }

    /// Digits type a distance, which only a Measurement has — an armed `Add` must not eat
    /// them, or typing while placing a token would silently go nowhere.
    func testOnlyAMeasurementClaimsTypedDigits() {
        XCTAssertFalse(ArmedTool.claimsDigits(hasArmedShape: false, hasMeasurement: false))
        XCTAssertTrue(ArmedTool.claimsDigits(hasArmedShape: true, hasMeasurement: false))
        XCTAssertTrue(ArmedTool.claimsDigits(hasArmedShape: false, hasMeasurement: true))
    }
}
