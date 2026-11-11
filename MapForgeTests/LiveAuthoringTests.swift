import XCTest
@testable import MapForge

/// Adding, editing and deleting a Pawn or a Light in the Live View (ADR-0013).
///
/// All of it live: not undoable, autosaved like any other fog mutation, and available in
/// every mode because the Live View is where the DM already is.
@MainActor
final class LiveAuthoringTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LiveAuthoringTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: Editing a Pawn

    func testEditingAPawnWritesEveryFieldTheSheetOffers() throws {
        let appState = try loadedAppState()
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "3",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]

        var draft = EditPawnDraft(pawn: pawn)
        draft.label = "Ogre"
        draft.kind = .creature
        draft.isBig = true
        draft.sightSquares = 2
        appState.updatePawn(id: pawn.id, with: draft)

        let edited = try XCTUnwrap(appState.fog.pawns.first)
        XCTAssertEqual(edited.label, "Ogre")
        XCTAssertEqual(edited.kind, .creature)
        XCTAssertTrue(edited.isBig)
        XCTAssertEqual(edited.light.brightSquares, 2)
        XCTAssertEqual(edited.at, MapPoint(x: 10, y: 10), "editing moved the Pawn")
    }

    func testEditingAMissingPawnDoesNothing() throws {
        let appState = try loadedAppState()
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "3",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]

        appState.updatePawn(id: UUID(), with: EditPawnDraft(pawn: pawn))

        XCTAssertEqual(appState.fog.pawns.first?.label, "3")
    }

    /// A Treasure is never a Combatant, so changing a Combatant's Kind to Treasure has to
    /// take it out of the Order — the same removal deleting it performs.
    func testMakingACombatantATreasureBenchesIt() throws {
        let appState = try loadedAppState()
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "Goblin",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6, kind: .creature)
        appState.fog.pawns = [pawn]
        appState.startEncounter()
        XCTAssertTrue(appState.encounter?.order.contains(pawn.id) ?? false,
                      "precondition: the Creature joined the Order")

        var draft = EditPawnDraft(pawn: pawn)
        draft.kind = .treasure
        appState.updatePawn(id: pawn.id, with: draft)

        XCTAssertFalse(appState.encounter?.order.contains(pawn.id) ?? true,
                       "a Treasure was left taking Turns")
        // What reaches the Log is `.combatantRemoved` — that the Pawn left the Order, which
        // is what happened. The Kind change itself is not recorded: issue 03's "a Kind
        // change is not a Change" and issue 05's "deleting removes it from the Order"
        // describe one event from two sides, and this is the record issue 05 sanctions.
        // The goblin was the active Combatant, so leaving the Order ended its Turn and the
        // removal is in that Turn's line rather than in the buffer.
        let encounter = try XCTUnwrap(appState.encounter)
        let written = encounter.lines.flatMap { line -> [Change] in
            guard case let .turn(_, _, changes, _) = line else { return [] }
            return changes
        }
        XCTAssertTrue((written + encounter.pendingChanges)
            .contains(.combatantRemoved(combatantID: pawn.id)),
            "leaving the Order went unrecorded")
    }

    /// And a Kind change that does not touch the Order writes nothing at all — the guard in
    /// `EncounterControl.bench` means a Pawn that was never a Combatant is silent.
    func testEditingANonCombatantsKindWritesNoLogLine() throws {
        let appState = try loadedAppState()
        let vex = Pawn(at: MapPoint(x: 20, y: 20), label: "Vex",
                       colorHex: Pawn.defaultColorHex, brightSquares: 6)
        let chest = Pawn(at: MapPoint(x: 10, y: 10), label: "Chest",
                         colorHex: Pawn.defaultColorHex, brightSquares: 6, kind: .treasure)
        appState.fog.pawns = [vex, chest]
        appState.startEncounter()
        let linesBefore = appState.encounter?.lines.count ?? 0

        var draft = EditPawnDraft(pawn: chest)
        draft.label = "Hoard"
        appState.updatePawn(id: chest.id, with: draft)

        XCTAssertEqual(appState.encounter?.lines.count ?? 0, linesBefore,
                       "editing a Treasure wrote to the Combat Log")
    }

    // MARK: Editing a Light

    func testEditingALightWritesEveryFieldTheSheetOffers() throws {
        let appState = try loadedAppState()
        let light = Light(at: MapPoint(x: 50, y: 50), brightSquares: 4, name: "Light 1")
        appState.fog.lights = [light]

        var draft = EditLightDraft(light: light)
        draft.name = "trapped brazier"
        draft.brightSquares = 6
        draft.dimSquares = 9
        draft.isOn = false
        appState.updateLight(id: light.id, with: draft)

        let edited = try XCTUnwrap(appState.fog.lights.first)
        XCTAssertEqual(edited.name, "trapped brazier")
        XCTAssertEqual(edited.brightSquares, 6)
        XCTAssertEqual(edited.dimSquares, 9)
        XCTAssertFalse(edited.isOn)
        XCTAssertEqual(edited.at, MapPoint(x: 50, y: 50), "editing moved the Light")
    }

    // MARK: Deleting

    func testDeletingALightRemovesIt() throws {
        let appState = try loadedAppState()
        let light = Light(at: MapPoint(x: 50, y: 50), brightSquares: 4, name: "Light 1")
        appState.fog.lights = [light]

        appState.removeLight(id: light.id)

        XCTAssertTrue(appState.fog.lights.isEmpty)
    }

    /// The Combat Log names a monster that died in Round 2 whatever the tracker shows now
    /// (`CONTEXT.md`, **Combatant**), so deleting the Pawn takes it out of the Order and
    /// leaves the Log alone.
    func testDeletingACombatantLeavesTheOrderAndKeepsTheLog() throws {
        let appState = try loadedAppState()
        let goblin = Pawn(at: MapPoint(x: 10, y: 10), label: "Goblin",
                          colorHex: Pawn.defaultColorHex, brightSquares: 6, kind: .creature)
        let vex = Pawn(at: MapPoint(x: 20, y: 20), label: "Vex",
                       colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [goblin, vex]
        appState.startEncounter()
        let logLinesBefore = appState.encounter?.lines.count ?? 0

        appState.removePawnFromMap(goblin.id)

        XCTAssertFalse(appState.fog.pawns.contains { $0.id == goblin.id })
        XCTAssertFalse(appState.encounter?.order.contains(goblin.id) ?? true,
                       "a deleted Pawn was left in the Order")
        XCTAssertGreaterThanOrEqual(appState.encounter?.lines.count ?? 0, logLinesBefore,
                                    "deleting a Pawn rewrote the Combat Log")
    }

    /// "A Measurement anchored to a Pawn ends when that Pawn does" (`CONTEXT.md`).
    func testDeletingAPawnEndsAMeasurementAnchoredToIt() throws {
        let appState = try loadedAppState()
        appState.squaresWide = 4
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "Vex",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]
        appState.setMeasurement(Measurement(origin: .pawn(pawn.id), shape: .circle,
                                            distance: 3, direction: 0))

        appState.removePawnFromMap(pawn.id)

        XCTAssertNil(appState.resolvedMeasurement,
                     "a Measurement outlived the Pawn it was anchored to")
    }

    /// Solo Sight already clears itself on a Pawn that is gone; deleting from the menu must
    /// go through the same path rather than round it.
    func testDeletingTheSoloSightSubjectEndsTheMode() throws {
        let appState = try loadedAppState()
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "Vex",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]
        appState.setSoloSight(id: pawn.id)

        appState.removePawnFromMap(pawn.id)

        XCTAssertNil(appState.resolvedSoloSightPawnID)
    }

    /// Issue 05 asks that deleting a Pawn "does not leave the stats file referencing a Pawn
    /// that is gone". It deliberately does — and this records the decision rather than
    /// leaving the question open. `removePawnFromMap` says why: the Combat Log still names a
    /// monster that died in Round 2, and a Log line describing a Pawn whose numbers have
    /// been thrown away describes nothing. The Stat Block outlives the token on purpose.
    func testDeletingAPawnKeepsItsStatBlockForTheLog() throws {
        let appState = try loadedAppState()
        let goblin = Pawn(at: MapPoint(x: 10, y: 10), label: "Goblin",
                          colorHex: Pawn.defaultColorHex, brightSquares: 6, kind: .creature)
        appState.fog.pawns = [goblin]
        appState.setStatBlock(StatBlock(armorClass: 15, currentHP: 7, maxHP: 7),
                              for: goblin.id)

        appState.removePawnFromMap(goblin.id)

        XCTAssertNotNil(appState.statBlock(for: goblin.id),
                        "the Log was left describing a Pawn whose numbers are gone")
    }

    // MARK: A sheet whose subject goes away

    /// The sheet holds its subject by ID, so a commit against a Pawn that is gone must not
    /// resurrect it or write anywhere else. `ControlView` closes the sheet on both paths —
    /// the Map changing and the Pawn being deleted — and this is the model half: even if it
    /// did not, OK writes nothing.
    func testCommittingAgainstADeletedPawnWritesNothing() throws {
        let appState = try loadedAppState()
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "3",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        let other = Pawn(at: MapPoint(x: 90, y: 90), label: "4",
                         colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn, other]

        var draft = EditPawnDraft(pawn: pawn)
        draft.label = "Ogre"
        appState.removePawnFromMap(pawn.id)
        appState.updatePawn(id: pawn.id, with: draft)

        XCTAssertEqual(appState.fog.pawns.map(\.label), ["4"],
                       "a commit against a deleted Pawn changed the Map")
    }

    func testCommittingAgainstADeletedLightWritesNothing() throws {
        let appState = try loadedAppState()
        let light = Light(at: MapPoint(x: 50, y: 50), brightSquares: 4, name: "Light 1")
        appState.fog.lights = [light]

        var draft = EditLightDraft(light: light)
        draft.name = "brazier"
        appState.removeLight(id: light.id)
        appState.updateLight(id: light.id, with: draft)

        XCTAssertTrue(appState.fog.lights.isEmpty,
                      "a commit against a deleted Light put it back")
    }

    // MARK: End to end

    /// What the feature is judged on: a Light can be created again, without leaving the
    /// Live View. Issue 01 removed the only path to one, and this is the path that replaces
    /// it — the reason 04 had to land before the feature shipped.
    func testALightCanBeCreatedAndEditedWithoutLeavingTheLiveView() throws {
        let appState = try loadedAppState()
        XCTAssertTrue(appState.fog.lights.isEmpty)

        appState.addLight(try XCTUnwrap(AddPlacement.light(at: MapPoint(x: 120, y: 80),
                                                           existing: appState.fog.lights)))
        let placed = try XCTUnwrap(appState.fog.lights.first)
        XCTAssertEqual(placed.name, "Light 1")
        XCTAssertEqual(placed.at, MapPoint(x: 120, y: 80))

        var draft = EditLightDraft(light: placed)
        draft.name = "trapped brazier"
        draft.brightSquares = 6
        appState.updateLight(id: placed.id, with: draft)

        XCTAssertEqual(appState.fog.lights.first?.name, "trapped brazier")
        XCTAssertEqual(appState.fog.lights.first?.brightSquares, 6)

        appState.removeLight(id: placed.id)
        XCTAssertTrue(appState.fog.lights.isEmpty)
    }

    /// A Creature placed mid-fight joins the Order, exactly as a Stamped Character does —
    /// the summon case, which is why placement routes through `addPawnToMap`.
    func testACreaturePlacedDuringAFightJoinsTheOrder() throws {
        let appState = try loadedAppState()
        let vex = Pawn(at: MapPoint(x: 20, y: 20), label: "Vex",
                       colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [vex]
        appState.startEncounter()

        let summon = try XCTUnwrap(AddPlacement.pawn(kind: .creature,
                                                     at: MapPoint(x: 100, y: 100),
                                                     existing: appState.fog.pawns,
                                                     imageSize: CGSize(width: 400, height: 300)))
        appState.addPawnToMap(summon)

        XCTAssertTrue(appState.encounter?.order.contains(summon.id) ?? false,
                      "a Creature summoned mid-fight never joined the Order")
    }

    /// And a Treasure does not, having nothing to do on its turn.
    func testATreasurePlacedDuringAFightStaysOutOfTheOrder() throws {
        let appState = try loadedAppState()
        let vex = Pawn(at: MapPoint(x: 20, y: 20), label: "Vex",
                       colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [vex]
        appState.startEncounter()

        let chest = try XCTUnwrap(AddPlacement.pawn(kind: .treasure,
                                                    at: MapPoint(x: 100, y: 100),
                                                    existing: appState.fog.pawns,
                                                    imageSize: CGSize(width: 400, height: 300)))
        appState.addPawnToMap(chest)

        XCTAssertFalse(appState.encounter?.order.contains(chest.id) ?? true,
                       "a Treasure was given a Turn")
    }

    // MARK: Helpers

    private func loadedAppState() throws -> AppState {
        let url = directory.appendingPathComponent("dungeon.png")
        let image = NSImage(size: NSSize(width: 400, height: 300))
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(x: 0, y: 0, width: 400, height: 300).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil,
                                                             context: nil, hints: nil)!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)

        let appState = AppState(preferences: DisplayPreferences(
            defaults: UserDefaults(suiteName: "LiveAuthoringTests.\(UUID().uuidString)")!))
        appState.loadMap(image: image, at: url)
        appState.beginEvening(in: directory)
        return appState
    }
}
