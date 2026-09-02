import XCTest
@testable import MapForge

/// The end-to-end seam issue 01 is judged on: a Map opened twice keeps its fog, and
/// switching Maps never carries one Map's Walls onto another.
@MainActor
final class AppStateFogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AppStateFogTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testReopeningAMapRestoresItsFog() throws {
        let map = try makeMap(named: "dungeon")
        let wall = Wall(from: MapPoint(x: 100, y: 200), to: MapPoint(x: 340, y: 200))
        try FogStore().save(FogDocument(walls: [wall]), forMapAt: map.url)

        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        XCTAssertEqual(appState.fog.walls, [wall])
    }

    func testAMapWithNoFogStartsEmpty() throws {
        let map = try makeMap(named: "blank")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        XCTAssertTrue(appState.fog.isEmpty)
    }

    func testSwitchingMapsDoesNotCarryFogAcross() throws {
        // The failure this guards: opening a second Map and seeing the first Map's Walls
        // on it — then saving them onto the wrong file.
        let dungeon = try makeMap(named: "dungeon")
        let tavern = try makeMap(named: "tavern")
        try FogStore().save(FogDocument(walls: [Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 50, y: 0))]),
                            forMapAt: dungeon.url)

        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: dungeon.image, at: dungeon.url)
        XCTAssertFalse(appState.fog.isEmpty, "precondition: dungeon has fog")

        appState.loadMap(image: tavern.image, at: tavern.url)
        XCTAssertTrue(appState.fog.isEmpty, "the tavern inherited the dungeon's Walls")
    }

    func testAnEditIsPersistedForTheMapItWasDrawnOn() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        let wall = Wall(from: MapPoint(x: 10, y: 10), to: MapPoint(x: 90, y: 10))
        appState.fog.walls = [wall]
        appState.flushPendingFogWrites()

        XCTAssertEqual(FogStore().load(forMapAt: map.url)?.walls, [wall])
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

    /// AppState remembers the Player Display in UserDefaults; tests must not write to the
    /// real domain or they leak into the developer's own app.
    private func isolatedPreferences() -> DisplayPreferences {
        DisplayPreferences(defaults: UserDefaults(suiteName: "AppStateFogTests.\(UUID().uuidString)")!)
    }

    // MARK: Grid declaration

    func testANewMapHasNotDeclaredItsGrid() throws {
        // squaresWide defaults to 30 and carries over between Maps, so "has a value" is
        // not "was declared". Light radii are in Grid squares, and treating the default
        // as declared renders every Light at a plausible-looking wrong size.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        XCTAssertFalse(appState.hasDeclaredGrid)
    }

    func testSettingTheGridDeclaresIt() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        appState.squaresWide = 24
        XCTAssertTrue(appState.hasDeclaredGrid)
    }

    func testSwitchingMapsClearsTheDeclaration() throws {
        // The next Map inherits the number but not the claim that it is right.
        let first = try makeMap(named: "dungeon")
        let second = try makeMap(named: "tavern")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: first.image, at: first.url)
        appState.squaresWide = 24
        appState.loadMap(image: second.image, at: second.url)
        XCTAssertFalse(appState.hasDeclaredGrid, "the new Map inherited a Grid declaration")
    }

    func testDeclaringAGridThatMatchesTheDefaultStillCounts() throws {
        // The default is a guess, not a declaration — but a DM whose Map really is 30
        // squares wide types 30, and the value never changes. Keying the declaration on
        // `didSet` firing means their Lights stay dark and the warning never clears, with
        // the app telling them to do the one thing they just did.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        appState.squaresWide = 30
        XCTAssertTrue(appState.hasDeclaredGrid,
                      "typing the default value did not declare the Grid")
    }

    func testALightLitsSomethingOnceTheGridMatchesTheDefault() throws {
        // The symptom the DM reports: overlay on, Light placed, nothing illuminated.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        appState.fog.lights = [Light(at: MapPoint(x: 20, y: 15), brightSquares: 4)]
        appState.squaresWide = 30

        XCTAssertFalse(appState.litRegions.isEmpty,
                       "a Light on a 30-square Map illuminated nothing")
    }

    func testRestoringAGridDoesNotDeclareOneTheDMNeverChose() throws {
        // Cancelling Grid Fit puts back the number that was there before. Entering the
        // mode moves the value, which declares — so cancel has to put back the claim too,
        // or backing out of Grid Fit leaves the app asserting a Grid nobody set.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        XCTAssertFalse(appState.hasDeclaredGrid, "precondition: a fresh Map has no Grid")

        appState.squaresWide = 42          // as Grid Fit does while dragging
        appState.restoreGrid(squaresWide: 30, wasDeclared: false)

        XCTAssertEqual(appState.squaresWide, 30)
        XCTAssertFalse(appState.hasDeclaredGrid,
                       "cancelling Grid Fit left a Grid declaration behind")
    }

    func testTogglingAPawnsLightChangesWhatIsLit() throws {
        // The live panel's one job. If the toggle does not reach the engine the DM sees
        // the token dim and the darkness unmoved, which is the report from the table.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        appState.squaresWide = 30
        let pawn = Pawn(at: MapPoint(x: 20, y: 15), label: "1",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]
        XCTAssertFalse(appState.litRegions.isEmpty, "precondition: the Pawn lit something")

        appState.setPawnLight(id: pawn.id, isOn: false)
        XCTAssertTrue(appState.litRegions.isEmpty,
                      "dousing the Pawn's light left its region lit")
    }

    func testTogglingALightChangesWhatIsLit() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        appState.squaresWide = 30
        let torch = Light(at: MapPoint(x: 20, y: 15), brightSquares: 4)
        appState.fog.lights = [torch]
        XCTAssertFalse(appState.litRegions.isEmpty, "precondition: the Light lit something")

        appState.setLight(id: torch.id, isOn: false)
        XCTAssertTrue(appState.litRegions.isEmpty,
                      "dousing the Light left its region lit")
    }

    // MARK: The Grid, persisted

    func testReopeningAMapRestoresItsGrid() throws {
        // The complaint that started the feature: re-fitting the Grid on every launch.
        let map = try makeMap(named: "dungeon")
        try FogStore().save(FogDocument(squaresWide: 24), forMapAt: map.url)

        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        XCTAssertEqual(appState.squaresWide, 24)
        XCTAssertTrue(appState.hasDeclaredGrid, "a restored Grid did not count as declared")
    }

    func testAMapWithNoStoredGridStartsUndeclared() throws {
        // A version 1 file, or a Map never fitted. The number carries over from the last
        // Map, but the claim that it is right does not.
        let map = try makeMap(named: "dungeon")
        try FogStore().save(FogDocument(walls: [Wall(from: MapPoint(x: 0, y: 0),
                                                     to: MapPoint(x: 50, y: 0))]),
                            forMapAt: map.url)

        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        XCTAssertFalse(appState.hasDeclaredGrid)
    }

    func testARestoredGridLightsTheMapWithNoWarning() throws {
        // The acceptance criterion, end to end: Lights render at their authored radii
        // straight after a reopen, with no undeclared-Grid warning to clear first.
        let map = try makeMap(named: "dungeon")
        try FogStore().save(FogDocument(squaresWide: 30,
                                        lights: [Light(at: MapPoint(x: 20, y: 15), brightSquares: 4)]),
                            forMapAt: map.url)

        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        XCTAssertFalse(appState.litRegions.isEmpty,
                       "a reopened Map's Lights lit nothing — the Grid did not come back")
    }

    func testDeclaringAGridReachesTheFogDocument() throws {
        // squaresWide's didSet has to reach the autosave, which is driven by `fog`.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        appState.squaresWide = 24

        XCTAssertEqual(appState.fog.squaresWide, 24)
    }

    func testAGridSurvivesAQuitWithNoFogAuthored() throws {
        // The case `isEmpty` decides: a DM who fits the Grid and stops. If the document
        // still counts as empty the file is deleted and the Grid is silently discarded.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        appState.squaresWide = 24
        appState.flushPendingFogWrites()

        XCTAssertEqual(FogStore().load(forMapAt: map.url)?.squaresWide, 24)
    }

    func testRestoringAGridDoesNotDeclareOneInTheDocumentEither() throws {
        // Cancelling Grid Fit restores the previous value and the previous claim. With
        // persistence the document must not keep the cancelled declaration, or the next
        // launch asserts a Grid the DM backed out of.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        appState.squaresWide = 42          // as Grid Fit does while dragging
        appState.restoreGrid(squaresWide: 30, wasDeclared: false)

        XCTAssertNil(appState.fog.squaresWide,
                     "a cancelled Grid Fit left its value in the document")
    }

    func testRestoringADeclaredGridKeepsItInTheDocument() throws {
        // The other half of Cancel: a DM who had already declared a Grid, entered Grid
        // Fit and backed out must keep the Grid they had.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        appState.squaresWide = 24
        appState.squaresWide = 42          // as Grid Fit does while dragging
        appState.restoreGrid(squaresWide: 24, wasDeclared: true)

        XCTAssertEqual(appState.fog.squaresWide, 24)
    }

    func testADragOfTheGridFitSquareWritesOnce() {
        // ControlView writes squaresWide on every drag tick of the Grid Fit square. The
        // debounce absorbs the burst; this asserts it at the autosave seam, because fifty
        // writes per drag would put a file write in the middle of every gesture.
        var writes = 0
        let autosave = FogAutosave { _ in writes += 1 }

        for squares in stride(from: 20.0, through: 40.0, by: 1) {
            autosave.schedule(FogDocument(squaresWide: squares))
        }
        autosave.flush()

        XCTAssertEqual(writes, 1, "a drag produced \(writes) writes")
    }

    func testSwitchingMapsDoesNotCarryAGridDeclarationOntoTheNextFile() throws {
        // The Grid now rides in `fog`, which is replaced wholesale on load — but the
        // in-memory squaresWide carries over. The outgoing Map's number must not be
        // written into the incoming Map's file as a declaration.
        let dungeon = try makeMap(named: "dungeon")
        let tavern = try makeMap(named: "tavern")
        let appState = AppState(preferences: isolatedPreferences())

        appState.loadMap(image: dungeon.image, at: dungeon.url)
        appState.squaresWide = 24
        appState.loadMap(image: tavern.image, at: tavern.url)
        appState.flushPendingFogWrites()

        XCTAssertNil(FogStore().load(forMapAt: tavern.url)?.squaresWide,
                     "the tavern inherited the dungeon's Grid")
    }

    // MARK: Live Pawn renaming

    func testRenamingAPawnDuringPlayReachesTheDocument() throws {
        // The acceptance sentence: mid-session, without leaving the live map, the DM
        // renames a Pawn from "3" to "Goblin B" and the Player Display follows — which it
        // does by reading `fog`, so reaching `fog` is the whole guarantee.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let pawn = Pawn(at: MapPoint(x: 20, y: 15), label: "3",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]

        appState.setPawnLabel(id: pawn.id, "Goblin B")

        XCTAssertEqual(appState.fog.pawns.first?.label, "Goblin B")
    }

    func testARenameDuringPlayIsPersisted() throws {
        // It rides `fog`'s debounce like every other live action — a rename made at the
        // table is still there next session.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let pawn = Pawn(at: MapPoint(x: 20, y: 15), label: "3",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]

        appState.setPawnLabel(id: pawn.id, "Goblin B")
        appState.flushPendingFogWrites()

        XCTAssertEqual(FogStore().load(forMapAt: map.url)?.pawns.first?.label, "Goblin B")
    }

    func testRenamingAPawnThatIsGoneDoesNothing() throws {
        // The live row and the document can disagree for a frame after a delete.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        appState.setPawnLabel(id: UUID(), "Goblin B")

        XCTAssertTrue(appState.fog.pawns.isEmpty)
    }

    // MARK: Fog mode must not clobber live state

    func testApplyingFogEditsKeepsAGridDeclaredDuringTheMode() throws {
        // The Grid field and stepper stay live during fog mode, and `FogEdits` holds a
        // snapshot taken when the mode opened. Pushing that snapshot back wholesale threw
        // away a Grid declared since — and the stale value is what reaches the file, so
        // the Grid was silently lost on relaunch: exactly the defect persistence exists to
        // prevent.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        var edits = FogEdits(document: appState.fog)       // as the mode opens
        appState.squaresWide = 24                          // the DM declares a Grid
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 50, y: 0))])
        appState.applyFogEdits(edits)                      // ...then draws a Wall

        XCTAssertEqual(appState.fog.squaresWide, 24, "the Wall reverted the Grid")
        XCTAssertEqual(appState.squaresWide, 24)
        XCTAssertTrue(appState.hasDeclaredGrid)
    }

    func testApplyingFogEditsKeepsALiveRenameMadeDuringTheMode() throws {
        // The live row renders during fog mode too, and a rename there writes straight to
        // `fog`. The next edit inside the mode must not wipe it — non-undoable was the
        // sanctioned trade-off; silently destroyed by an unrelated action was not.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let pawn = Pawn(at: MapPoint(x: 20, y: 15), label: "3",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]

        var edits = FogEdits(document: appState.fog)       // as the mode opens
        appState.setPawnLabel(id: pawn.id, "Goblin B")     // renamed from the live row
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 50, y: 0))])
        appState.applyFogEdits(edits)                      // ...then a Wall is drawn

        XCTAssertEqual(appState.fog.pawns.first?.label, "Goblin B",
                       "drawing a Wall wiped a rename made at the table")
    }

    func testCancellingFogEditingKeepsAGridDeclaredDuringTheMode() throws {
        // Cancel discards the fog authored in the mode. It must not discard the Grid: the
        // Grid is not part of what the mode was editing, and reverting it while
        // `squaresWide` and `hasDeclaredGrid` keep the new value desyncs them permanently
        // — the UI says a Grid is declared and the file says none is.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        let edits = FogEdits(document: appState.fog)       // as the mode opens
        appState.squaresWide = 24                          // the DM declares a Grid
        appState.cancelFogEditing(edits)

        XCTAssertEqual(appState.fog.squaresWide, 24, "Cancel discarded the Grid")
        XCTAssertTrue(appState.hasDeclaredGrid)
    }

    func testCancellingFogEditingStillDiscardsTheWalls() throws {
        // The part of Cancel that must keep working.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        var edits = FogEdits(document: appState.fog)
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 50, y: 0))])
        appState.applyFogEdits(edits)
        XCTAssertFalse(appState.fog.walls.isEmpty, "precondition: a Wall was drawn")

        appState.cancelFogEditing(edits)

        XCTAssertTrue(appState.fog.walls.isEmpty, "Cancel did not discard the Wall")
    }

    // MARK: Live light toggling

    func testSettingALightStateIsIdempotent() throws {
        // The live row binds a Toggle straight to this. SwiftUI writes the same value
        // twice on a state resync, and a toggle-based setter would flip it back.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let torch = Light(at: MapPoint(x: 10, y: 10), brightSquares: 4)
        appState.fog.lights = [torch]

        appState.setLight(id: torch.id, isOn: false)
        appState.setLight(id: torch.id, isOn: false)
        XCTAssertFalse(appState.fog.lights[0].isOn, "the repeated write flipped it back on")
    }
}
