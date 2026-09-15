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
        return appState
    }
}
