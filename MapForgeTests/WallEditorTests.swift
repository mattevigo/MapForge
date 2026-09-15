import XCTest
@testable import MapForge

/// The Wall Editor authors Walls and nothing else.
///
/// The invariant these tests hold is the one that lets `carryLiveState` and `LivePawnEdit`
/// be deleted: because the mode never touches a Pawn or a Light, the table's edits to them
/// survive Cancel *structurally* rather than by being carried back over the restored
/// document. There is nothing to reconcile, so there is nothing to get wrong.
///
/// See `.scratch/live-authoring/issues/01-the-wall-editor-loses-its-tools.md` and
/// ADR-0013.
@MainActor
final class WallEditorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WallEditorTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: Cancel keeps the table's Pawn edits, with nothing carrying them

    /// The defect `carryLiveState` was written to prevent, asserted against the structure
    /// that replaces it: a Pawn dragged mid-session must not snap back when the DM cancels
    /// out of tracing a Wall.
    func testCancellingWallEditsKeepsAPawnWhereTheTableMovedIt() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let pawn = Pawn(at: MapPoint(x: 5, y: 5), label: "Ilyana",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]

        appState.beginFogEditing()
        var edits = FogEdits(document: appState.fog)
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 10, y: 0))])
        appState.applyFogEdits(edits)

        // The table moves the Pawn while the mode is open — a live action.
        appState.movePawn(id: pawn.id, to: MapPoint(x: 20, y: 12))
        appState.cancelFogEditing(edits)

        XCTAssertEqual(appState.fog.pawns.first?.at, MapPoint(x: 20, y: 12))
        XCTAssertTrue(appState.fog.walls.isEmpty, "Cancel discards the Walls the mode traced")
    }

    /// The same for the other three live edits, together, so no one property is carried
    /// while another is dropped.
    func testCancellingWallEditsKeepsEveryLivePawnEdit() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let pawn = Pawn(at: MapPoint(x: 5, y: 5), label: "3",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]

        appState.beginFogEditing()
        let edits = FogEdits(document: appState.fog)

        appState.setPawnLabel(id: pawn.id, "Goblin B")
        appState.setPawnLight(id: pawn.id, isOn: false)
        appState.setPawnHidden(id: pawn.id, isHidden: true)
        appState.cancelFogEditing(edits)

        let restored = try XCTUnwrap(appState.fog.pawns.first)
        XCTAssertEqual(restored.label, "Goblin B")
        XCTAssertFalse(restored.light.isOn)
        XCTAssertTrue(restored.isHidden)
    }

    /// A Light renamed from the live roster while the mode is open survives Cancel too.
    /// `carryLiveState` never covered Lights — it was Pawn-shaped throughout — so this is
    /// behaviour the deletion *gains* rather than preserves.
    func testCancellingWallEditsKeepsALiveLightRename() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let light = Light(at: MapPoint(x: 8, y: 8), brightSquares: 4, name: "Light 1")
        appState.fog.lights = [light]

        appState.beginFogEditing()
        let edits = FogEdits(document: appState.fog)

        appState.setLightName(id: light.id, "trapped brazier")
        appState.cancelFogEditing(edits)

        XCTAssertEqual(appState.fog.lights.first?.name, "trapped brazier")
    }

    /// Cancel still does its own job: the Walls traced in the mode go.
    func testCancellingWallEditsDiscardsTheWalls() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let existing = Wall(from: MapPoint(x: 1, y: 1), to: MapPoint(x: 9, y: 1))
        appState.fog.walls = [existing]

        appState.beginFogEditing()
        var edits = FogEdits(document: appState.fog)
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 5), to: MapPoint(x: 10, y: 5))])
        appState.applyFogEdits(edits)
        appState.cancelFogEditing(edits)

        XCTAssertEqual(appState.fog.walls, [existing])
    }

    /// The reason `ControlView.setLight` had a fog-mode special case: an in-mode edit used
    /// to overwrite `fog` wholesale from the mode's snapshot and revert the toggle. With
    /// `applyFogEdits` copying only Walls it cannot, so the live path is safe in every mode.
    func testDousingALightDuringWallEditingSurvivesTheNextWall() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let light = Light(at: MapPoint(x: 8, y: 8), brightSquares: 4, name: "Light 1")
        appState.fog.lights = [light]

        appState.beginFogEditing()
        var edits = FogEdits(document: appState.fog)

        appState.setLight(id: light.id, isOn: false)
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 10, y: 0))])
        appState.applyFogEdits(edits)

        XCTAssertEqual(appState.fog.lights.first?.isOn, false,
                       "drawing a Wall relit a doused Light")
    }

    // MARK: The mode touches only Walls

    /// Issue 01 asks that `⌫` with no Wall selected deletes no Pawn and no Light. The mode
    /// has no Pawn or Light selection left to make, so this asserts the reachable half: the
    /// only deletion `FogEdits` can perform is a Wall's.
    func testTheModeCanOnlyDeleteWalls() {
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "Vex",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        let torch = Light(at: MapPoint(x: 50, y: 50), brightSquares: 4, name: "Light 1")
        let wall = Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 10, y: 0))
        var edits = FogEdits(document: FogDocument(walls: [wall], lights: [torch],
                                                   pawns: [pawn]))

        edits.deleteWall(id: wall.id)

        XCTAssertTrue(edits.document.walls.isEmpty)
        XCTAssertEqual(edits.document.pawns, [pawn], "a Pawn went with the Wall")
        XCTAssertEqual(edits.document.lights, [torch], "a Light went with the Wall")
    }

    /// Tracing a Wall across a token must work. The mode draws Pawns and Lights with
    /// `allowsHitTesting(false)`, so a click on one reaches the Wall layer underneath — that
    /// is view wiring no unit test reaches, but the model half is that a Wall placed on a
    /// Pawn's exact position is an ordinary Wall.
    func testAWallCanBeTracedAcrossAPawn() {
        let pawn = Pawn(at: MapPoint(x: 25, y: 25), label: "Vex",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        var edits = FogEdits(document: FogDocument(pawns: [pawn]))

        let across = Wall(from: MapPoint(x: 20, y: 25), to: MapPoint(x: 30, y: 25))
        edits.addWalls([across])

        XCTAssertEqual(edits.document.walls, [across])
        XCTAssertEqual(edits.document.pawns, [pawn])
    }

    // MARK: Helpers

    private func makeMap(named name: String) throws -> (url: URL, image: NSImage) {
        let url = directory.appendingPathComponent("\(name).png")
        let image = NSImage(size: NSSize(width: 40, height: 30))
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 30).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil,
                                                             context: nil, hints: nil)!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        return (url, image)
    }

    private func isolatedPreferences() -> DisplayPreferences {
        DisplayPreferences(defaults: UserDefaults(suiteName: "WallEditorTests.\(UUID().uuidString)")!)
    }
}
