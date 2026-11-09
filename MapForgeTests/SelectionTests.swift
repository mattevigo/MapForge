import XCTest
@testable import MapForge

/// The **Selection**: the Pawns and Lights the DM has picked in the Live View
/// (`CONTEXT.md`, **Selection**).
///
/// Held on `AppState`, in memory only. These tests hold what it is and how long it lasts;
/// which click or keystroke changes it is `SelectionRoutingTests`'s.
@MainActor
final class SelectionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SelectionTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: Picking

    func testTogglingAPawnPicksItAndTogglingAgainLetsItGo() throws {
        let appState = try loadedAppState()
        let rogue = pawn("Rogue")
        appState.fog.pawns = [rogue]

        appState.toggleSelection(pawn: rogue.id)
        XCTAssertTrue(appState.selection.contains(pawn: rogue.id))

        appState.toggleSelection(pawn: rogue.id)
        XCTAssertFalse(appState.selection.contains(pawn: rogue.id))
        XCTAssertTrue(appState.selection.isEmpty)
    }

    func testTogglingALightPicksItAndTogglingAgainLetsItGo() throws {
        let appState = try loadedAppState()
        let lantern = Light(at: MapPoint(x: 20, y: 20), brightSquares: 4, dimSquares: 8,
                            name: "lantern")
        appState.fog.lights = [lantern]

        appState.toggleSelection(light: lantern.id)
        XCTAssertTrue(appState.selection.contains(light: lantern.id))

        appState.toggleSelection(light: lantern.id)
        XCTAssertFalse(appState.selection.contains(light: lantern.id))
        XCTAssertTrue(appState.selection.isEmpty)
    }

    /// What a plain rectangle does (ticket 03): the Pawns inside become the whole Selection,
    /// so a Light picked before it is let go along with every Pawn outside.
    func testReplacingWithPawnsLeavesOnlyThosePawns() {
        let rogue = UUID(), fighter = UUID(), goblin = UUID(), lantern = UUID()
        var selection = Selection()
        selection.toggle(pawn: rogue)
        selection.toggle(light: lantern)

        selection.replace(withPawns: [fighter, goblin])

        XCTAssertEqual(selection.pawnIDs, [fighter, goblin])
        XCTAssertTrue(selection.lightIDs.isEmpty)
    }

    /// What a ⇧-rectangle does (ticket 03): the Pawns inside join, and nobody already picked
    /// is let go — not even one the rectangle also covers, which a toggle would.
    func testAddingPawnsKeepsEveryMemberAlreadyPicked() {
        let rogue = UUID(), fighter = UUID(), lantern = UUID()
        var selection = Selection()
        selection.toggle(pawn: rogue)
        selection.toggle(light: lantern)

        selection.add(pawns: [rogue, fighter])

        XCTAssertEqual(selection.pawnIDs, [rogue, fighter])
        XCTAssertEqual(selection.lightIDs, [lantern])
    }

    // MARK: How long it lasts

    /// A Selection belongs to the Map it was picked on. Not left to the UUIDs failing to
    /// match on the next Map — that would hold only by accident, and only for the Pawns the
    /// incoming document happens not to share.
    func testOpeningAnotherMapEndsTheSelection() throws {
        let appState = try loadedAppState()
        let rogue = pawn("Rogue")
        let lantern = Light(at: MapPoint(x: 20, y: 20), brightSquares: 4, name: "lantern")
        appState.fog.pawns = [rogue]
        appState.fog.lights = [lantern]
        appState.toggleSelection(pawn: rogue.id)
        appState.toggleSelection(light: lantern.id)

        let cave = try makeMap(named: "cave")
        appState.loadMap(image: cave.image, at: cave.url)

        XCTAssertTrue(appState.selection.isEmpty)
    }

    /// Nothing can be picked in the Wall Editor (`CONTEXT.md`, **Wall Editor**), so a
    /// Selection carried into it would be rings on tokens the DM cannot act on.
    func testEnteringTheWallEditorEndsTheSelection() throws {
        let appState = try loadedAppState()
        let rogue = pawn("Rogue")
        appState.fog.pawns = [rogue]
        appState.toggleSelection(pawn: rogue.id)

        appState.beginFogEditing()

        XCTAssertTrue(appState.selection.isEmpty)
    }

    /// Deleting a member takes just that member out — every other member is still picked.
    func testDeletingAPickedPawnTakesOnlyThatPawnOut() throws {
        let appState = try loadedAppState()
        let rogue = pawn("Rogue"), fighter = pawn("Fighter")
        let lantern = Light(at: MapPoint(x: 20, y: 20), brightSquares: 4, name: "lantern")
        appState.fog.pawns = [rogue, fighter]
        appState.fog.lights = [lantern]
        appState.toggleSelection(pawn: rogue.id)
        appState.toggleSelection(pawn: fighter.id)
        appState.toggleSelection(light: lantern.id)

        appState.removePawnFromMap(rogue.id)

        XCTAssertFalse(appState.selection.contains(pawn: rogue.id))
        XCTAssertTrue(appState.selection.contains(pawn: fighter.id))
        XCTAssertTrue(appState.selection.contains(light: lantern.id))
    }

    func testDeletingAPickedLightTakesOnlyThatLightOut() throws {
        let appState = try loadedAppState()
        let rogue = pawn("Rogue")
        let lantern = Light(at: MapPoint(x: 20, y: 20), brightSquares: 4, name: "lantern")
        let brazier = Light(at: MapPoint(x: 40, y: 40), brightSquares: 2, name: "brazier")
        appState.fog.pawns = [rogue]
        appState.fog.lights = [lantern, brazier]
        appState.toggleSelection(pawn: rogue.id)
        appState.toggleSelection(light: lantern.id)
        appState.toggleSelection(light: brazier.id)

        appState.removeLight(id: lantern.id)

        XCTAssertFalse(appState.selection.contains(light: lantern.id))
        XCTAssertTrue(appState.selection.contains(light: brazier.id))
        XCTAssertTrue(appState.selection.contains(pawn: rogue.id))
    }

    /// Arming Add and arming a Measurement each dismiss the Measurement on screen, and a
    /// Measurement placed or an Add landed changes the document — none of it is a reason
    /// to drop what the DM picked.
    func testArmingAddOrAMeasurementKeepsTheSelection() throws {
        let appState = try loadedAppState()
        appState.squaresWide = 20
        let rogue = pawn("Rogue")
        appState.fog.pawns = [rogue]
        appState.toggleSelection(pawn: rogue.id)

        // What arming either tool asks of `AppState`.
        appState.setMeasurement(nil)
        appState.setMeasurement(Measurement(origin: .pawn(rogue.id), shape: .circle,
                                            distance: 3, direction: 0))
        // What an armed Add's click lands.
        appState.addPawnToMap(pawn("Goblin", at: MapPoint(x: 50, y: 50)))
        appState.addLight(Light(at: MapPoint(x: 60, y: 60), brightSquares: 2))

        XCTAssertEqual(appState.selection.pawnIDs, [rogue.id])
    }

    // MARK: Never in the record

    /// A Selection is a way of acting, not a thing in the record: picking and letting go
    /// write nothing — not the fog document, not the sidecar, not the Session Log, not the
    /// Combat Log. Asserted against every byte the Workspace holds, so a file nobody thought
    /// of is covered too.
    func testPickingWritesNothingAnywhere() throws {
        let appState = try loadedAppState()
        appState.beginEvening(in: directory)
        let rogue = pawn("Rogue")
        let lantern = Light(at: MapPoint(x: 20, y: 20), brightSquares: 4, name: "lantern")
        appState.addPawnToMap(rogue)
        appState.addLight(lantern)
        appState.startEncounter()
        appState.flushPendingFogWrites()
        let before = try everyFile(in: directory)
        let linesBefore = appState.sessionLineCount

        appState.toggleSelection(pawn: rogue.id)
        appState.toggleSelection(light: lantern.id)
        appState.flushPendingFogWrites()
        appState.clearSelection()
        appState.flushPendingFogWrites()

        XCTAssertEqual(try everyFile(in: directory), before)
        XCTAssertEqual(appState.sessionLineCount, linesBefore)
    }

    /// The table sees the Pawns move, not that they were picked. Asserted against every
    /// value `PlayerView` reads off `AppState`, so a Selection that leaked into any of them —
    /// a Pawn re-ordered to draw on top, a Light flagged in the document — would show here.
    /// The ring itself is drawn by `PawnLayer`, which only the Control Window builds.
    func testPickingChangesNothingThePlayerDisplayDraws() throws {
        let appState = try loadedAppState()
        appState.squaresWide = 20
        let rogue = pawn("Rogue"), fighter = pawn("Fighter", at: MapPoint(x: 80, y: 80))
        let lantern = Light(at: MapPoint(x: 20, y: 20), brightSquares: 4, name: "lantern")
        appState.fog.pawns = [rogue, fighter]
        appState.fog.lights = [lantern]
        appState.setSoloSight(id: rogue.id)
        let before = playerDisplaysView(of: appState)

        appState.toggleSelection(pawn: fighter.id)
        appState.toggleSelection(light: lantern.id)

        XCTAssertFalse(appState.selection.isEmpty, "precondition: something is picked")
        XCTAssertEqual(playerDisplaysView(of: appState), before)
    }

    private struct PlayerDisplaysView: Equatable {
        let fog: FogDocument
        let litRegions: [LitRegion]
        let measurements: [MapForge.Measurement.ID]
        let soloSight: Pawn.ID?
        let viewportOrigin: CGPoint?
        let isFogOverlayOn: Bool
        let isMapFitOn: Bool
    }

    private func playerDisplaysView(of appState: AppState) -> PlayerDisplaysView {
        PlayerDisplaysView(fog: appState.fog, litRegions: appState.litRegions,
                           measurements: appState.playerMeasurements.map(\.measurement.id),
                           soloSight: appState.resolvedSoloSightPawnID,
                           viewportOrigin: appState.viewportOrigin,
                           isFogOverlayOn: appState.isFogOverlayOn,
                           isMapFitOn: appState.isMapFitOn)
    }

    // MARK: Fixtures

    /// Every file under `root`, by path, with its bytes.
    private func everyFile(in root: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = walk?.nextObject() as? URL {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            files[url.path] = try Data(contentsOf: url)
        }
        return files
    }

    private func pawn(_ label: String, at point: MapPoint = MapPoint(x: 10, y: 10)) -> Pawn {
        Pawn(at: point, label: label, colorHex: Pawn.defaultColorHex, brightSquares: 6)
    }

    private func makeMap(named name: String) throws -> (image: NSImage, url: URL) {
        let url = directory.appendingPathComponent("\(name).png")
        let image = NSImage(size: NSSize(width: 400, height: 300))
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(x: 0, y: 0, width: 400, height: 300).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil,
                                                             context: nil, hints: nil)!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        return (image, url)
    }

    private func loadedAppState() throws -> AppState {
        let map = try makeMap(named: "corridor")
        let appState = AppState(preferences: DisplayPreferences(
            defaults: UserDefaults(suiteName: "SelectionTests.\(UUID().uuidString)")!))
        appState.loadMap(image: map.image, at: map.url)
        return appState
    }
}
