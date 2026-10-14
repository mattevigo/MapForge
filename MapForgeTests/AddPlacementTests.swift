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

    private func pawn(_ label: String, kind: PawnKind, colorHex: String = "#2E7D32",
                      sight: CGFloat = 6, isBig: Bool = false, face: String? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 10), label: label, colorHex: colorHex,
             brightSquares: sight, kind: kind, isBig: isBig,
             face: face.map { PawnFace(file: $0, origin: .hand) })
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

    func testTheFirstLightTakesTheDefaults() throws {
        let placed = try XCTUnwrap(AddPlacement.light(at: MapPoint(x: 50, y: 50), existing: []))
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

    func testANewLightInheritsTheLastOnesRadii() throws {
        let existing = [Light(at: MapPoint(x: 0, y: 0), brightSquares: 6, dimSquares: 7,
                              name: "Light 1")]
        let placed = try XCTUnwrap(AddPlacement.light(at: MapPoint(x: 50, y: 50),
                                                      existing: existing))

        XCTAssertEqual(placed.brightSquares, 6)
        XCTAssertEqual(placed.dimSquares, 7, "dim was re-derived instead of inherited")
    }

    /// A doused torch is a live state, not a property of "the kind of torch I am placing" —
    /// a new Light always burns, or a DM who doused one would place invisible ones after it.
    func testANewLightBurnsEvenIfTheLastOneWasDoused() {
        var doused = Light(at: MapPoint(x: 0, y: 0), brightSquares: 4, name: "Light 1")
        doused.isOn = false
        XCTAssertEqual(AddPlacement.light(at: MapPoint(x: 50, y: 50), existing: [doused])?.isOn,
                       true)
    }

    // MARK: The Face

    private func add(_ kind: PawnKind, after existing: [Pawn]) throws -> Pawn {
        try XCTUnwrap(AddPlacement.pawn(kind: kind, at: MapPoint(x: 100, y: 100),
                                        existing: existing))
    }

    /// The second hand-cut skeleton arrives wearing the first one's Face, with no second
    /// cut: the very same kept file, so nothing is copied twice.
    func testANewCreatureWearsTheLastCreaturesFace() throws {
        let skeleton = pawn("1", kind: .creature, face: "skeleton.png")

        XCTAssertEqual(try add(.creature, after: [skeleton]).face, skeleton.face)
    }

    func testANewPlayerAndTreasureEachWearTheirOwnKindsFace() throws {
        let existing = [pawn("Vex", kind: .player, face: "vex.png"),
                        pawn("Chest", kind: .treasure, face: "chest.png"),
                        pawn("Goblin", kind: .creature, face: "goblin.png")]

        XCTAssertEqual(try add(.player, after: existing).face?.file, "vex.png")
        XCTAssertEqual(try add(.treasure, after: existing).face?.file, "chest.png")
    }

    func testAFaceDoesNotFollowAnotherKindOntoTheMap() throws {
        let existing = [pawn("Goblin", kind: .creature, face: "goblin.png")]

        XCTAssertNil(try add(.player, after: existing).face)
    }

    /// The last skeleton, not any skeleton: the DM removed its Face for a reason.
    func testTheLastOfItsKindWithoutAFaceGivesNone() throws {
        let existing = [pawn("1", kind: .creature, face: "skeleton.png"),
                        pawn("2", kind: .creature)]

        XCTAssertNil(try add(.creature, after: existing).face)
    }

    /// A Player placed with Add after a Stamped one is not that Character: it remembers no
    /// Character, so the Face it takes is its own, as though cut by hand for it.
    func testAFaceFromACharacterPassesOnAsTheNewPawnsOwn() throws {
        var durga = pawn("Durga", kind: .player)
        durga.face = PawnFace(file: "durga.png", origin: .character)

        XCTAssertEqual(try add(.player, after: [durga]).face,
                       PawnFace(file: "durga.png", origin: .hand))
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
        XCTAssertEqual(AddPlacement.light(at: MapPoint(x: 2, y: 0), existing: lights)?.name,
                       "Light 2")
    }

    // MARK: The image bounds

    /// A click outside the image places nothing. `Stamp` already refuses a drop outside
    /// rather than clamping, and `CONTEXT.md` says a Pawn beyond the implicit Walls is
    /// meaningless to Visibility — so this refuses too, rather than silently landing the
    /// token at the edge where the DM did not point.
    func testAClickOutsideTheImagePlacesNothing() {
        // Lights follow the same rule as Pawns. An exemption was tried and was wrong:
        // `LiveHitTest` only reaches what the DM can click, so a Light outside the image
        // could never be selected, edited or deleted again.
        XCTAssertNil(AddPlacement.light(at: MapPoint(x: 500, y: 100),
                                        existing: [], imageSize: imageSize))
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
        XCTAssertNotNil(AddPlacement.light(at: MapPoint(x: 399, y: 299),
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

/// `Add` and the Bestiary: the second gnoll is a gnoll.
///
/// Without this a DM stocking a room opens the Edit Pawn sheet once per Creature, which is
/// the form `Add` exists to avoid (`CONTEXT.md`, **Add**).
final class AddPlacementMonsterTests: XCTestCase {
    private let bestiary = Bestiary(monsters: [Monster(name: "Gnoll Guerriero", hitPoints: 27)])

    private func gnoll(_ label: String) -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 10), label: label, colorHex: "#228B22",
             brightSquares: 6, kind: .creature, monsterName: "Gnoll Guerriero")
    }

    func testTheNextCreatureIsTheSameMonster() throws {
        let placed = try XCTUnwrap(AddPlacement.pawn(kind: .creature, at: MapPoint(x: 5, y: 5),
                                                     existing: [gnoll("GG1")],
                                                     bestiary: bestiary))
        XCTAssertEqual(placed.monsterName, "Gnoll Guerriero")
        XCTAssertEqual(placed.label, "GG2")
    }

    func testAMonsterThatHasLeftTheNotesIsNotInherited() throws {
        // Nothing to copy numbers from, so nothing to claim to be.
        let placed = try XCTUnwrap(AddPlacement.pawn(kind: .creature, at: MapPoint(x: 5, y: 5),
                                                     existing: [gnoll("GG1")],
                                                     bestiary: Bestiary()))
        XCTAssertNil(placed.monsterName)
        XCTAssertEqual(placed.label, "1")
    }

    func testAPlayerNeverInheritsAMonster() throws {
        var ally = gnoll("GG1")
        ally.kind = .player
        let placed = try XCTUnwrap(AddPlacement.pawn(kind: .player, at: MapPoint(x: 5, y: 5),
                                                     existing: [ally], bestiary: bestiary))
        XCTAssertNil(placed.monsterName)
    }
}
