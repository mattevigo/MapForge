import AppKit
import XCTest
@testable import MapForge

/// The Session reaching disk: starting, stopping, resuming, and the hand-off to and from the
/// Combat Log.
///
/// The test that matters most is `testADragDuringAnEncounterIsRecordedOnlyInTheCombatLog` —
/// exactly one recorder is live at any instant, which is ADR-0014 in one assertion.
@MainActor
final class AppStateSessionTests: XCTestCase {
    private var directory: URL!
    private var mapURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var workspace: Workspace!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AppStateSessionTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        mapURL = directory.appendingPathComponent("dungeon.png")
        workspace = Workspace(url: directory)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// A 1000-pixel Map declared as 20 squares: 50 image pixels to the square.
    private func makeAppState(withMap: Bool = true, withWorkspace: Bool = true) -> AppState {
        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        if withWorkspace { state.open(workspace) }
        if withMap {
            state.mapURL = mapURL
            state.mapImage = NSImage(size: NSSize(width: 1000, height: 800))
            state.squaresWide = 20
        }
        return state
    }

    private func pawn(_ label: String, at x: CGFloat, kind: PawnKind = .player) -> Pawn {
        Pawn(at: MapPoint(x: x, y: 100), label: label, colorHex: "#C81E1E",
             brightSquares: 6, kind: kind)
    }

    /// The Session Log as it stands on disk.
    private func sessionLines(_ state: AppState) throws -> [SessionLine] {
        guard let url = state.sessionLogURL else { return [] }
        return try SessionLogReader().read(at: url)
    }

    private func comments(_ lines: [SessionLine]) -> [String] {
        lines.compactMap { if case let .comment(text, _, _, _) = $0 { return text } else { return nil } }
    }

    private func moves(_ lines: [SessionLine]) -> [SessionLine] {
        lines.filter { if case .pawnMoved = $0 { return true } else { return false } }
    }

    // MARK: Starting

    func testStartingWithNoWorkspaceRecordsNothing() throws {
        let state = makeAppState(withWorkspace: false)
        state.startSession()
        XCTAssertNil(state.session, "there is nowhere to write without a Workspace")
        XCTAssertNil(state.sessionLogURL)
    }

    func testTheFileIsNamedForTheTimeItsOpeningLineCarries() throws {
        let state = makeAppState()
        state.startSession()

        guard case let .sessionStarted(startedAt) = try sessionLines(state).first else {
            return XCTFail("expected sessionStarted")
        }
        XCTAssertEqual(state.sessionLogURL?.lastPathComponent,
                       SessionLogFile.name(startedAt: startedAt),
                       "one Date(), not three — a second boundary must not split them")
    }

    func testStartingWritesTheOpeningLine() throws {
        let state = makeAppState()
        state.startSession()

        XCTAssertNotNil(state.session)
        let lines = try sessionLines(state)
        XCTAssertEqual(lines.count, 1)
        guard case .sessionStarted = lines.first else {
            return XCTFail("expected sessionStarted, got \(String(describing: lines.first))")
        }
    }

    func testASessionNeedsNoMap() throws {
        // An evening belongs to the Workspace, not to a Map — ADR-0015.
        let state = makeAppState(withMap: false)
        state.startSession()
        state.addComment("party still deciding where to go")

        XCTAssertEqual(comments(try sessionLines(state)), ["party still deciding where to go"])
    }

    // MARK: Comments

    func testACommentIsRecordedWithItsMap() throws {
        let state = makeAppState()
        state.startSession()
        state.addComment("the door was trapped")

        let lines = try sessionLines(state)
        guard case let .comment(text, map, _, _) = lines.last else {
            return XCTFail("expected a comment, got \(String(describing: lines.last))")
        }
        XCTAssertEqual(text, "the door was trapped")
        XCTAssertEqual(map, "dungeon.png", "a line must be readable without the ones above it")
    }

    func testACommentBeforeASessionIsRecordedNowhere() throws {
        let state = makeAppState()
        state.addComment("typed while still laying out walls")
        XCTAssertEqual(try sessionLines(state), [])
    }

    func testACommentCarriesTheSelectedPawnWhenThereIsOne() throws {
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        state.fog.pawns = [grog]
        state.startSession()
        state.addComment("he looks worried", pawnID: grog.id)

        guard case let .comment(_, _, pawnID, _) = try sessionLines(state).last else {
            return XCTFail("expected a comment")
        }
        XCTAssertEqual(pawnID, grog.id)
    }

    // MARK: Movement — the feature's reason to exist

    func testADragWithNoEncounterIsRecordedInTheSessionLog() throws {
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        state.fog.pawns = [grog]
        state.startSession()

        state.movePawn(id: grog.id, to: MapPoint(x: 250, y: 100))
        state.commitPawnMove(id: grog.id, from: MapPoint(x: 100, y: 100))

        let lines = try sessionLines(state)
        XCTAssertEqual(moves(lines).count, 1, "the corridor walk is what this feature is for")
        guard case let .pawnMoved(id, label, map, _, _, distance, _) = moves(lines).first else {
            return XCTFail("expected pawnMoved")
        }
        XCTAssertEqual(id, grog.id)
        XCTAssertEqual(label, "Grog", "a line read next year must name the Pawn")
        XCTAssertEqual(map, "dungeon.png")
        XCTAssertEqual(distance, 3, accuracy: 0.001)
        XCTAssertNil(state.encounter)
    }

    func testADragWithNoSessionAndNoEncounterIsRecordedNowhere() throws {
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        state.fog.pawns = [grog]

        state.movePawn(id: grog.id, to: MapPoint(x: 250, y: 100))
        state.commitPawnMove(id: grog.id, from: MapPoint(x: 100, y: 100))

        XCTAssertEqual(try sessionLines(state), [])
    }

    func testADragDuringAnEncounterIsRecordedOnlyInTheCombatLog() throws {
        let state = makeAppState()
        let grog = pawn("Grog", at: 100)
        state.fog.pawns = [grog]
        state.startSession()
        state.startEncounter()

        state.movePawn(id: grog.id, to: MapPoint(x: 250, y: 100))
        state.commitPawnMove(id: grog.id, from: MapPoint(x: 100, y: 100))

        // The Combat Log has it.
        let changes = state.encounter?.pendingChanges ?? []
        XCTAssertTrue(changes.contains { if case .moved = $0 { return true } else { return false } },
                      "the fight's own record is unchanged by this feature")
        // The Session Log does not.
        XCTAssertTrue(moves(try sessionLines(state)).isEmpty,
                      "exactly one recorder is live at any instant — ADR-0014")
    }

    // MARK: The hand-off

    func testStartingAnEncounterWritesThePointerToItsCombatLog() throws {
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", at: 100)]
        state.startSession()
        state.startEncounter()

        let lines = try sessionLines(state)
        guard case let .encounterStarted(map, logFile, _) = lines.last else {
            return XCTFail("expected encounterStarted, got \(String(describing: lines.last))")
        }
        XCTAssertEqual(map, "dungeon.png")
        XCTAssertTrue(logFile.hasSuffix(".jsonl"))

        let combatFile = StatsStore.combatDirectory(forMapAt: mapURL)
            .appendingPathComponent(logFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: combatFile.path),
                      "the pointer must name a file that exists")
    }

    func testACommentDuringAnEncounterIsRecordedNowhereInTheSessionLog() throws {
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", at: 100)]
        state.startSession()
        state.startEncounter()

        state.addComment("mid-fight thought")
        XCTAssertEqual(comments(try sessionLines(state)), [])
    }

    func testStoppingAnEncounterResumesTheSessionLog() throws {
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", at: 100)]
        state.startSession()
        state.startEncounter()
        state.stopEncounter()

        state.addComment("they looted the body")

        let lines = try sessionLines(state)
        XCTAssertTrue(lines.contains { if case .encounterEnded = $0 { return true } else { return false } })
        XCTAssertEqual(comments(lines), ["they looted the body"])
    }

    func testStartingAnEncounterWithNoSessionWritesNothing() throws {
        let state = makeAppState()
        state.fog.pawns = [pawn("Grog", at: 100)]
        state.startEncounter()

        XCTAssertNotNil(state.encounter, "a fight does not need a Session to run")
        XCTAssertEqual(try sessionLines(state), [])
    }

    // MARK: Stopping

    func testStoppingWritesTheEndLineAndSilencesTheLog() throws {
        let state = makeAppState()
        state.startSession()
        let url = state.sessionLogURL
        state.stopSession()

        XCTAssertNil(state.session)
        state.addComment("after the evening ended")

        let lines = try SessionLogReader().read(at: XCTUnwrap(url))
        XCTAssertTrue(lines.contains { if case .sessionEnded = $0 { return true } else { return false } })
        XCTAssertEqual(comments(lines), [])
    }

    // MARK: Resuming

    func testReopeningAWorkspaceResumesAnUnfinishedSession() throws {
        let first = makeAppState()
        first.startSession()
        first.addComment("before the laptop slept")
        let url = first.sessionLogURL

        // A second process opening the same Workspace.
        let second = makeAppState()
        XCTAssertNotNil(second.session, "an unterminated file is a Session still running")
        XCTAssertEqual(second.sessionLogURL?.lastPathComponent, url?.lastPathComponent,
                       "it appends to the same file rather than starting a second one")

        second.addComment("after it woke")
        XCTAssertEqual(comments(try sessionLines(second)),
                       ["before the laptop slept", "after it woke"])
    }

    func testReopeningAWorkspaceDoesNotResumeAnEndedSession() throws {
        let first = makeAppState()
        first.startSession()
        first.stopSession()

        let second = makeAppState()
        XCTAssertNil(second.session)
    }

    func testAWorkspaceWithNoSessionsResumesNothing() throws {
        let state = makeAppState()
        XCTAssertNil(state.session)
    }

    // MARK: Switching Workspace

    func testClosingTheWorkspaceEndsTheSession() throws {
        let state = makeAppState()
        state.startSession()
        let url = try XCTUnwrap(state.sessionLogURL)
        state.closeWorkspace()

        XCTAssertNil(state.session, "a Session's file lives in the Workspace it started in")
        let lines = try SessionLogReader().read(at: url)
        XCTAssertTrue(lines.contains { if case .sessionEnded = $0 { return true } else { return false } },
                      "the evening ends on the record, not by being abandoned")
    }

    /// ADR-0016. A bare file name cannot tell two `dungeon.png` apart, and resolving an
    /// Encounter's Combat Log goes through this field.
    func testALineNamesItsMapByWorkspaceRelativePath() throws {
        let nested = directory.appendingPathComponent("maps/crypt", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let state = makeAppState()
        state.mapURL = nested.appendingPathComponent("dungeon.png")
        state.startSession()
        state.addComment("the door is stuck")

        let lines = try SessionLogReader().read(at: try XCTUnwrap(state.sessionLogURL))
        let map = lines.compactMap { line -> String?? in
            if case let .comment(_, map, _, _) = line { return map } else { return nil }
        }.first
        XCTAssertEqual(map, "maps/crypt/dungeon.png",
                       "two Maps of one name in different folders must be told apart")
    }

    /// Relative, never absolute: ADR-0012 keeps the Workspace portable, and an absolute path
    /// is a path that rots the moment the folder is opened on another Mac.
    func testAMapPathIsRelativeToTheWorkspaceAndNotAbsolute() throws {
        let state = makeAppState()
        state.startSession()
        state.addComment("still here")

        let lines = try SessionLogReader().read(at: try XCTUnwrap(state.sessionLogURL))
        let map = lines.compactMap { line -> String?? in
            if case let .comment(_, map, _, _) = line { return map } else { return nil }
        }.first
        XCTAssertEqual(map, "dungeon.png", "a Map at the Workspace root has a bare name")
        XCTAssertFalse((map ?? "")?.hasPrefix("/") ?? false, "an absolute path would rot")
    }

    func testSwitchingWorkspaceWouldEndASession() throws {
        let state = makeAppState()
        XCTAssertFalse(state.switchingWouldEndAnEncounter)
        state.startSession()
        XCTAssertTrue(state.switchingWouldEndAnEncounter,
                      "the picker asks before it takes the evening away")
    }
}
