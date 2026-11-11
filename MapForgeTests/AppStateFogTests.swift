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

    // MARK: The reported bug

    func testOpeningAMapWhileEditingFogDoesNotOverwriteItWithThePreviousMapsFog() throws {
        // The DM's report: a Map is open in the fog editing mode, they open another Map,
        // and the new Map is overwritten with the previous Map's fog.
        let dungeon = try makeMap(named: "dungeon")
        let tavern = try makeMap(named: "tavern")
        let tavernWall = Wall(from: MapPoint(x: 5, y: 5), to: MapPoint(x: 35, y: 5))
        try FogStore().save(FogDocument(walls: [tavernWall]), forMapAt: tavern.url)

        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: dungeon.image, at: dungeon.url)

        // Enter the fog editing mode on the dungeon and trace a Wall, exactly as
        // ControlView.startFogEditing does.
        appState.beginFogEditing()
        var edits = FogEdits(document: appState.fog)
        let dungeonWall = Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 40, y: 0))
        edits.addWalls([dungeonWall])
        appState.applyFogEdits(edits)

        // Without leaving the mode, open another Map. `mode` is ControlView @State and
        // stays .fog; `edits` stays the dungeon's snapshot.
        appState.loadMap(image: tavern.image, at: tavern.url)
        XCTAssertEqual(appState.fog.walls, [tavernWall], "precondition: the tavern's own fog loaded")

        // The mode is still open, so the next in-mode action pushes the DUNGEON's
        // document onto the tavern.
        appState.applyFogEdits(edits)
        appState.flushPendingFogWrites()

        XCTAssertEqual(appState.fog.walls, [tavernWall],
                       "the tavern's fog was replaced by the dungeon's")
        XCTAssertEqual(FogStore().load(forMapAt: tavern.url)?.walls, [tavernWall],
                       "the dungeon's Walls were written onto the tavern's fog file")
    }

    func testCancellingFogEditingAfterOpeningAnotherMapDoesNotOverwriteIt() throws {
        // The same crossing through Cancel rather than an edit: Cancel restores the
        // snapshot the mode opened with, which belongs to the OUTGOING Map.
        let dungeon = try makeMap(named: "dungeon")
        let tavern = try makeMap(named: "tavern")
        let dungeonWall = Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 40, y: 0))
        try FogStore().save(FogDocument(walls: [dungeonWall]), forMapAt: dungeon.url)
        let tavernWall = Wall(from: MapPoint(x: 5, y: 5), to: MapPoint(x: 35, y: 5))
        try FogStore().save(FogDocument(walls: [tavernWall]), forMapAt: tavern.url)

        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: dungeon.image, at: dungeon.url)
        appState.beginFogEditing()
        let edits = FogEdits(document: appState.fog)

        appState.loadMap(image: tavern.image, at: tavern.url)
        appState.cancelFogEditing(edits)

        XCTAssertEqual(appState.fog.walls, [tavernWall],
                       "Cancel restored the dungeon's fog onto the tavern")
        XCTAssertEqual(FogStore().load(forMapAt: tavern.url)?.walls, [tavernWall],
                       "Cancel wrote the dungeon's Walls onto the tavern's fog file")
    }

    func testFogEditingStillAppliesOnTheMapItWasOpenedOn() throws {
        // The guard above must refuse only the crossing, not the ordinary path: an edit
        // on the Map the mode opened on still reaches the document and the file.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        appState.beginFogEditing()
        var edits = FogEdits(document: appState.fog)
        let wall = Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 40, y: 0))
        edits.addWalls([wall])
        appState.applyFogEdits(edits)
        appState.flushPendingFogWrites()

        XCTAssertEqual(appState.fog.walls, [wall])
        XCTAssertEqual(FogStore().load(forMapAt: map.url)?.walls, [wall])
    }

    func testTheModelGuardIsTheURLSoTheViewMustCloseTheModeOnAnyMapChange() throws {
        // Records the limit of the model-side guard, so it is not mistaken for the whole
        // fix. Re-opening the SAME Map is still a reload — `loadMap` re-reads the file and
        // replaces `fog` — but the URL is unchanged, so the stamp still matches and the
        // stale snapshot applies. What makes that safe is `ControlView` closing the mode
        // on ANY `mapURL` change; the guard is the backstop for the cross-Map case.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        appState.beginFogEditing()
        var edits = FogEdits(document: appState.fog)
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 40, y: 0))])

        // ControlView closes the mode on any mapURL change; the same Map re-opened does
        // not change the URL, so the view keeps the mode and the model must still be
        // correct on its own terms — the snapshot matches this Map, so it applies.
        appState.applyFogEdits(edits)
        XCTAssertEqual(appState.fog.walls.count, 1)
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

        appState.beginFogEditing()                         // as the mode opens
        var edits = FogEdits(document: appState.fog)
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

        appState.beginFogEditing()                         // as the mode opens
        var edits = FogEdits(document: appState.fog)
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

        appState.beginFogEditing()                         // as the mode opens
        let edits = FogEdits(document: appState.fog)
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

        appState.beginFogEditing()
        var edits = FogEdits(document: appState.fog)
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 50, y: 0))])
        appState.applyFogEdits(edits)
        XCTAssertFalse(appState.fog.walls.isEmpty, "precondition: a Wall was drawn")

        appState.cancelFogEditing(edits)

        XCTAssertTrue(appState.fog.walls.isEmpty, "Cancel did not discard the Wall")
    }

    func testCancellingFogEditingCannotRevertAPawnAtAll() throws {
        // Was `testCancellingFogEditingDiscardsARenameMadeInsideTheMode`, which asserted
        // that an in-mode inspector rename was discarded by Cancel. There is no in-mode
        // inspector any more (ADR-0013): a Pawn is only ever renamed live, so the rule it
        // held has no case left to apply to. What replaces it is the stronger statement
        // that made the old one moot — Cancel touches the Walls and nothing else, so a
        // Pawn cannot be reverted by it however it was edited.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let pawn = Pawn(at: MapPoint(x: 20, y: 15), label: "3",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]

        appState.beginFogEditing()
        var edits = FogEdits(document: appState.fog)
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 50, y: 0))])
        appState.applyFogEdits(edits)
        appState.setPawnLabel(id: pawn.id, "Goblin B")

        appState.cancelFogEditing(edits)

        XCTAssertEqual(appState.fog.pawns.first?.label, "Goblin B")
        XCTAssertTrue(appState.fog.walls.isEmpty, "Cancel still discards the mode's Walls")
    }

    // MARK: Moving a Light

    /// A Light is dragged in the Live View, as a Pawn is: the DM carries the lantern down the
    /// corridor and the table watches the dark move with it.
    func testALightMovesWhereItIsDragged() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let brazier = Light(at: MapPoint(x: 10, y: 10), brightSquares: 4)
        let sconce = Light(at: MapPoint(x: 30, y: 20), brightSquares: 2)
        appState.fog.lights = [brazier, sconce]

        appState.moveLight(id: brazier.id, to: MapPoint(x: 25, y: 12))

        XCTAssertEqual(appState.fog.lights.first?.at, MapPoint(x: 25, y: 12))
        XCTAssertEqual(appState.fog.lights.last?.at, MapPoint(x: 30, y: 20), "the other Light moved")
        // Everything that is not where it stands comes through untouched.
        XCTAssertEqual(appState.fog.lights.first?.brightSquares, 4)
        XCTAssertEqual(appState.fog.lights.first?.id, brazier.id)
    }

    func testALightDraggedPastTheEdgeStopsAtTheEdge() throws {
        // As a Pawn does, and for a sharper reason: a Light beyond the image can never be
        // clicked again, so it could not be dragged back, edited or deleted.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        // Read back rather than assumed: `lockFocus` draws at the screen's scale, so the
        // fixture's 40 points are 80 pixels on a Retina Mac and 40 on a CI box.
        let width = try XCTUnwrap(appState.mapImage?.pixelSize.width)
        let brazier = Light(at: MapPoint(x: 10, y: 10), brightSquares: 4)
        appState.fog.lights = [brazier]

        appState.moveLight(id: brazier.id, to: MapPoint(x: width + 500, y: -20))

        XCTAssertEqual(appState.fog.lights.first?.at, MapPoint(x: width, y: 0))
    }

    func testMovingALightNobodyHasIsNothing() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        appState.moveLight(id: UUID(), to: MapPoint(x: 5, y: 5))
        XCTAssertEqual(appState.fog.lights, [])
    }

    func testADraggedLightReachesDiskWhenTheDragEnds() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let brazier = Light(at: MapPoint(x: 10, y: 10), brightSquares: 4)
        appState.addLight(brazier)

        appState.moveLight(id: brazier.id, to: MapPoint(x: 25, y: 12))
        appState.commitLightMove()

        let onDisk = try XCTUnwrap(FogStore().load(forMapAt: map.url))
        XCTAssertEqual(onDisk.lights.first?.at, MapPoint(x: 25, y: 12))
    }

    func testApplyingFogEditsKeepsALivePawnMoveAndTorchToggle() throws {
        // Dragging a Pawn stays live during fog mode (PawnLayer), and `setPawnLight` has
        // no in-mode special case, so both write straight to `fog`. An in-mode edit must
        // not snap the token back to where the mode opened or relight a doused torch.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let pawn = Pawn(at: MapPoint(x: 20, y: 15), label: "3",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]

        appState.beginFogEditing()                     // as the mode opens
        var edits = FogEdits(document: appState.fog)
        // Inside the 40×30 Map on any display: on a 1× screen the image is 40×30 pixels,
        // and a move past its edge is clamped.
        appState.movePawn(id: pawn.id, to: MapPoint(x: 35, y: 25))
        appState.setPawnLight(id: pawn.id, isOn: false)
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 50, y: 0))])
        appState.applyFogEdits(edits)

        XCTAssertEqual(appState.fog.pawns.first?.at, MapPoint(x: 35, y: 25),
                       "drawing a Wall snapped the Pawn back")
        XCTAssertEqual(appState.fog.pawns.first?.light.isOn, false,
                       "drawing a Wall relit a doused torch")
    }

    func testFogEditsCannotMoveAPawn() throws {
        // Was `testAnInModePawnMoveStillApplies`. The Pawn tool is gone, so `FogEdits` has
        // no `movePawn` to call — the guarantee is now that the mode's document cannot
        // reach a Pawn at all, which is what lets `applyFogEdits` copy only Walls.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let pawn = Pawn(at: MapPoint(x: 20, y: 15), label: "3",
                        colorHex: Pawn.defaultColorHex, brightSquares: 6)
        appState.fog.pawns = [pawn]

        appState.beginFogEditing()
        var edits = FogEdits(document: appState.fog)
        edits.addWalls([Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 50, y: 0))])
        appState.applyFogEdits(edits)

        XCTAssertEqual(appState.fog.pawns.first?.at, MapPoint(x: 20, y: 15),
                       "the Wall Editor moved a Pawn")
        XCTAssertEqual(appState.fog.walls.count, 1)
    }

    func testRestoringAGridNeverPublishesTheCancelledValue() throws {
        // `restoreGrid` assigns squaresWide first, whose didSet declares and publishes.
        // Correct only because the debounce coalesces — and cancelGridFit flushes right
        // after, so the window is real. The cancelled value must never reach `fog` at all.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        appState.squaresWide = 42                       // as Grid Fit does while dragging
        appState.restoreGrid(squaresWide: 30, wasDeclared: false)

        XCTAssertNil(appState.fog.squaresWide)
        appState.flushPendingFogWrites()
        XCTAssertNil(FogStore().load(forMapAt: map.url)?.squaresWide,
                     "a cancelled Grid Fit reached the file")
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

    // MARK: - Solo Sight

    func testIsolatingAPawnRecordsIt() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "Ilyana",
                        colorHex: "#FF0000", brightSquares: 6)
        appState.fog.pawns = [pawn]

        appState.setSoloSight(id: pawn.id)

        XCTAssertEqual(appState.soloSightPawnID, pawn.id)
    }

    func testSwitchingMapsEndsSoloSight() throws {
        // The `be14e58` bug class: the ID is a reference into a document that just changed
        // underneath it, and the next render would isolate a Pawn from the outgoing Map.
        let dungeon = try makeMap(named: "dungeon")
        let tavern = try makeMap(named: "tavern")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: dungeon.image, at: dungeon.url)
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "Ilyana",
                        colorHex: "#FF0000", brightSquares: 6)
        appState.fog.pawns = [pawn]
        appState.setSoloSight(id: pawn.id)

        appState.loadMap(image: tavern.image, at: tavern.url)

        XCTAssertNil(appState.soloSightPawnID, "Solo Sight outlived the Map it was set on")
    }

    func testDeletingTheIsolatedPawnEndsSoloSight() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "Ilyana",
                        colorHex: "#FF0000", brightSquares: 6)
        appState.fog.pawns = [pawn]
        appState.setSoloSight(id: pawn.id)

        appState.fog.pawns = []

        XCTAssertNil(appState.soloSightPawnID, "Solo Sight survived the Pawn it was isolating")
    }

    func testBeginningFogEditingEndsSoloSight() throws {
        // Fog authoring needs the whole Map lit, and the mode would fight the inspector.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "Ilyana",
                        colorHex: "#FF0000", brightSquares: 6)
        appState.fog.pawns = [pawn]
        appState.setSoloSight(id: pawn.id)

        appState.beginFogEditing()

        XCTAssertNil(appState.soloSightPawnID)
    }

    func testAStaleSoloSightIDResolvesToNothing() throws {
        // The mode must go inert rather than hiding the whole party behind a Pawn that is
        // no longer there. `showsToPlayers` sees one Pawn at a time and cannot tell a stale
        // ID from a Pawn that is simply somewhere else, so an unresolved stale ID would
        // empty the Player Display of the entire party while the fog stayed lit — the worst
        // failure this mode has. Resolving at the caller is what prevents it.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let ilyana = Pawn(at: MapPoint(x: 10, y: 10), label: "Ilyana",
                          colorHex: "#FF0000", brightSquares: 6)
        let bardo = Pawn(at: MapPoint(x: 90, y: 90), label: "Bardo",
                         colorHex: "#00FF00", brightSquares: 6)
        appState.fog.pawns = [ilyana, bardo]
        appState.setSoloSight(id: ilyana.id)

        appState.fog.pawns = [bardo]

        XCTAssertNil(appState.resolvedSoloSightPawnID)
    }

    func testHidingTheIsolatedPawnEndsSoloSight() throws {
        // Found by review. The eye takes a Pawn out of the lighting, so hiding the isolated
        // one left the mode pointing at a Pawn that emits nothing: the fog fell back to
        // lighting the Map with every torch, while the token rule kept the rest of the
        // party under the discovery test. The table would have seen a fully lit Map with
        // most of the party missing from it — and the control is disabled on a hidden Pawn,
        // so the DM could not click their way back out.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let ilyana = Pawn(at: MapPoint(x: 10, y: 10), label: "Ilyana",
                          colorHex: "#FF0000", brightSquares: 6)
        appState.fog.pawns = [ilyana]
        appState.setSoloSight(id: ilyana.id)

        appState.setPawnHidden(id: ilyana.id, isHidden: true)

        XCTAssertNil(appState.soloSightPawnID)
    }

    func testHidingAnotherPawnLeavesSoloSightAlone() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let ilyana = Pawn(at: MapPoint(x: 10, y: 10), label: "Ilyana",
                          colorHex: "#FF0000", brightSquares: 6)
        let bardo = Pawn(at: MapPoint(x: 90, y: 90), label: "Bardo",
                         colorHex: "#00FF00", brightSquares: 6)
        appState.fog.pawns = [ilyana, bardo]
        appState.setSoloSight(id: ilyana.id)

        appState.setPawnHidden(id: bardo.id, isHidden: true)

        XCTAssertEqual(appState.soloSightPawnID, ilyana.id)
    }

    func testSoloSightWritesNoFogFile() throws {
        // Derived, never persisted: reopening this Map tomorrow must not find the table
        // still looking through one character's eyes.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let ilyana = Pawn(at: MapPoint(x: 10, y: 10), label: "Ilyana",
                          colorHex: "#FF0000", brightSquares: 6)
        appState.fog.pawns = [ilyana]
        appState.flushPendingFogWrites()
        let onDisk = try? Data(contentsOf: FogStore.fogURL(forMapAt: map.url))

        appState.setSoloSight(id: ilyana.id)
        appState.flushPendingFogWrites()

        XCTAssertEqual(try? Data(contentsOf: FogStore.fogURL(forMapAt: map.url)), onDisk,
                       "Solo Sight reached the fog file")
    }

    func testSoloSightIsNotUndoable() throws {
        // A live performance action, exactly as hiding is: it must not bury the DM's
        // authoring work under a row of toggles, and it must not write a fog file.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let pawn = Pawn(at: MapPoint(x: 10, y: 10), label: "Ilyana",
                        colorHex: "#FF0000", brightSquares: 6)
        appState.fog.pawns = [pawn]
        let before = appState.fog

        appState.setSoloSight(id: pawn.id)

        XCTAssertEqual(appState.fog, before, "Solo Sight mutated the document")
    }
}
