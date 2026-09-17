import XCTest
@testable import MapForge

/// The reading model: an evening flattened into rows.
///
/// The tests that matter most are `testAnEncountersTurnsAreSplicedIntoItsPointersPlace` —
/// ADR-0016's file-order rule in one assertion — and
/// `testACorrectionIsDrawnBeneathTheTurnItTargets`, the one deliberate departure from it.
final class LogViewModelTests: XCTestCase {
    private var directory: URL!
    private var workspace: Workspace!
    private var mapURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LogViewModelTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        workspace = Workspace(url: directory)
        mapURL = directory.appendingPathComponent("dungeon.png")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: Helpers

    private func writeSessionLog(_ lines: [SessionLine]) throws -> URL {
        let url = directory.appendingPathComponent("session.jsonl")
        let encoder = SessionLogFile.encoder()
        var data = Data()
        for line in lines {
            data.append(try encoder.encode(line))
            data.append(0x0A)
        }
        try data.write(to: url)
        return url
    }

    /// A Combat Log beside the given Map, named as the pointer will name it.
    private func writeCombatLog(_ lines: [LogLine], forMapAt map: URL,
                                named name: String = "fight.jsonl") throws {
        let folder = StatsStore.combatDirectory(forMapAt: map)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = CombatLogFile.encoder()
        var data = Data()
        for line in lines {
            data.append(try encoder.encode(line))
            data.append(0x0A)
        }
        try data.write(to: folder.appendingPathComponent(name))
    }

    private func combatant(_ name: String, id: UUID) -> Combatant {
        Combatant(id: id, name: name, kind: .creature, initiative: 10, block: StatBlock())
    }

    // MARK: The splice

    func testAnEncountersTurnsAreSplicedIntoItsPointersPlace() throws {
        let grix = UUID()
        try writeCombatLog([
            .encounterStarted(startedAt: Date(), order: [grix],
                              combatants: [combatant("Grix", id: grix)]),
            .turn(round: 1, combatantID: grix, changes: [], endedAt: Date()),
            .encounterEnded(endedAt: Date()),
        ], forMapAt: mapURL)

        let url = try writeSessionLog([
            .sessionStarted(startedAt: Date()),
            .comment(text: "before", map: "dungeon.png", pawnID: nil, at: Date()),
            .encounterStarted(map: "dungeon.png", logFile: "fight.jsonl", at: Date()),
            .encounterEnded(map: "dungeon.png", at: Date()),
            .comment(text: "after", map: "dungeon.png", pawnID: nil, at: Date()),
        ])

        let rows = LogViewModel().rows(sessionLogAt: url, workspace: workspace)

        // The fight sits between the two Comments, in file order, with no timestamp compared.
        let shape = rows.map { row -> String in
            switch row {
            case let .comment(text, _): "comment:\(text)"
            case .encounterStarted: "fight"
            case let .roundHeading(round): "round:\(round)"
            case let .turn(name): "turn:\(name)"
            case .encounterEnded: "fightEnd"
            case .sessionStarted: "start"
            default: "other"
            }
        }
        XCTAssertEqual(shape, ["start", "comment:before", "fight", "round:1", "turn:Grix",
                               "fightEnd", "comment:after"])
    }

    func testAPointerToAMissingFileRendersAsUnreadableRatherThanAGap() throws {
        let url = try writeSessionLog([
            .sessionStarted(startedAt: Date()),
            .encounterStarted(map: "dungeon.png", logFile: "gone.jsonl", at: Date()),
        ])

        let rows = LogViewModel().rows(sessionLogAt: url, workspace: workspace)

        XCTAssertTrue(rows.contains { if case .encounterUnreadable = $0 { true } else { false } },
                      "a fight that cannot be read must say so, not vanish")
    }

    func testAMapInASubfolderResolvesItsCombatLog() throws {
        let nested = directory.appendingPathComponent("maps/crypt", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let nestedMap = nested.appendingPathComponent("dungeon.png")
        let grix = UUID()
        try writeCombatLog([
            .encounterStarted(startedAt: Date(), order: [grix],
                              combatants: [combatant("Grix", id: grix)]),
            .turn(round: 1, combatantID: grix, changes: [], endedAt: Date()),
        ], forMapAt: nestedMap)

        let url = try writeSessionLog([
            .encounterStarted(map: "maps/crypt/dungeon.png", logFile: "fight.jsonl", at: Date()),
        ])

        let rows = LogViewModel().rows(sessionLogAt: url, workspace: workspace)

        XCTAssertTrue(rows.contains { if case .turn = $0 { true } else { false } },
                      "a relative path is what makes this join unambiguous")
    }

    // MARK: Corrections

    func testACorrectionIsDrawnBeneathTheTurnItTargets() throws {
        let grix = UUID()
        let rows = LogViewModel.combatRows([
            .encounterStarted(startedAt: Date(), order: [grix],
                              combatants: [combatant("Grix", id: grix)]),
            .turn(round: 1, combatantID: grix,
                  changes: [.hpChanged(combatantID: grix, from: 22, to: 15)], endedAt: Date()),
            .turn(round: 2, combatantID: grix, changes: [], endedAt: Date()),
            // Appended at the end of the file, targeting Round 1.
            .correction(targetRound: 1, targetCombatantID: grix,
                        changes: [.hpChanged(combatantID: grix, from: 15, to: 18)],
                        recordedAt: Date()),
        ])

        let names = rows.map { row -> String in
            switch row {
            case let .roundHeading(round): "round:\(round)"
            case .turn: "turn"
            case .change: "change"
            case .correction: "correction"
            case .correctionChange: "correctionChange"
            default: "other"
            }
        }
        // The Correction follows Round 1's Turn, not the end of the file. ADR-0010.
        XCTAssertEqual(names, ["round:1", "turn", "change", "correction", "correctionChange",
                               "round:2", "turn"])
    }

    func testACorrectionNamingNoKnownTurnIsDrawnAsAnOrphan() throws {
        let grix = UUID()
        let rows = LogViewModel.combatRows([
            .encounterStarted(startedAt: Date(), order: [grix],
                              combatants: [combatant("Grix", id: grix)]),
            .correction(targetRound: 9, targetCombatantID: grix, changes: [], recordedAt: Date()),
        ])

        XCTAssertTrue(rows.contains { if case .orphanCorrection = $0 { true } else { false } },
                      "the fold ignores these; reading history must not")
    }

    // MARK: Grouping

    func testRoundsGroupTheirTurnsAndAHeadingAppearsOncePerRound() throws {
        let a = UUID(), b = UUID()
        let rows = LogViewModel.combatRows([
            .encounterStarted(startedAt: Date(), order: [a, b],
                              combatants: [combatant("Grix", id: a), combatant("Ogre", id: b)]),
            .turn(round: 1, combatantID: a, changes: [], endedAt: Date()),
            .turn(round: 1, combatantID: b, changes: [], endedAt: Date()),
            .turn(round: 2, combatantID: a, changes: [], endedAt: Date()),
        ])

        let headings = rows.filter { if case .roundHeading = $0 { true } else { false } }
        XCTAssertEqual(headings.count, 2, "one heading per Round, not per Turn")
    }

    func testATurnWithNoChangesStillAppears() throws {
        let grix = UUID()
        let rows = LogViewModel.combatRows([
            .encounterStarted(startedAt: Date(), order: [grix],
                              combatants: [combatant("Grix", id: grix)]),
            .turn(round: 1, combatantID: grix, changes: [], endedAt: Date()),
        ])

        XCTAssertTrue(rows.contains { if case .turn = $0 { true } else { false } },
                      "a run of empty Turns is the answer to when somebody stopped acting")
    }

    func testAChangeIsNamedForItsOwnTargetNotTheTurnsCombatant() throws {
        let grix = UUID(), ogre = UUID()
        let rows = LogViewModel.combatRows([
            .encounterStarted(startedAt: Date(), order: [grix, ogre],
                              combatants: [combatant("Grix", id: grix),
                                           combatant("Ogre", id: ogre)]),
            // Grix's Turn, but the damage lands on the Ogre.
            .turn(round: 1, combatantID: grix,
                  changes: [.hpChanged(combatantID: ogre, from: 30, to: 23)], endedAt: Date()),
        ])

        let changeName = rows.compactMap { row -> String? in
            if case let .change(_, name) = row { return name } else { return nil }
        }.first
        XCTAssertEqual(changeName, "Ogre", "a Turn records what happened during it, not to whom")
    }

    // MARK: Map separators

    func testAMapChangeDrawsASeparator() throws {
        let url = try writeSessionLog([
            .sessionStarted(startedAt: Date()),
            .comment(text: "in the crypt", map: "crypt.png", pawnID: nil, at: Date()),
            .comment(text: "in the cavern", map: "cavern.png", pawnID: nil, at: Date()),
        ])

        let rows = LogViewModel().rows(sessionLogAt: url, workspace: workspace)

        let separators = rows.compactMap { row -> String? in
            if case let .mapSeparator(path) = row { return path } else { return nil }
        }
        XCTAssertEqual(separators, ["cavern.png"],
                       "the first Line establishes the Map; the second announces a change")
    }

    /// `sessionStarted` carries no Map field at all, so it is not a Line that disagrees about
    /// the Map — it is a Line with no opinion. A change either side of one is still a change.
    func testALineWithNoMapDoesNotBreakTheAdjacency() throws {
        let url = try writeSessionLog([
            .comment(text: "in the crypt", map: "crypt.png", pawnID: nil, at: Date()),
            .sessionStarted(startedAt: Date()),
            .comment(text: "in the cavern", map: "cavern.png", pawnID: nil, at: Date()),
        ])

        let rows = LogViewModel().rows(sessionLogAt: url, workspace: workspace)

        let separators = rows.compactMap { row -> String? in
            if case let .mapSeparator(path) = row { return path } else { return nil }
        }
        XCTAssertEqual(separators, ["cavern.png"],
                       "a Line with no Map neither announces a change nor hides one")
    }

    func testTheFirstMapDoesNotDrawASeparator() throws {
        let url = try writeSessionLog([
            .sessionStarted(startedAt: Date()),
            .comment(text: "here", map: "crypt.png", pawnID: nil, at: Date()),
        ])

        let rows = LogViewModel().rows(sessionLogAt: url, workspace: workspace)

        XCTAssertFalse(rows.contains { if case .mapSeparator = $0 { true } else { false } },
                       "a separator above the first Line would be a change from nothing")
    }

    // MARK: What must not vanish

    func testAnUnreadableLineKeepsItsPlace() throws {
        // Written by hand: an `unrecognised` line cannot be encoded, by design.
        let url = directory.appendingPathComponent("session.jsonl")
        let text = """
        {"line":"sessionStarted","startedAt":"2026-09-16T19:00:00Z"}
        {"line":"somethingFromTheFuture","at":"2026-09-16T19:05:00Z"}
        {"line":"sessionEnded","endedAt":"2026-09-16T23:00:00Z"}
        """
        try text.write(to: url, atomically: true, encoding: .utf8)

        let rows = LogViewModel().rows(sessionLogAt: url, workspace: workspace)

        let shape = rows.map { row -> String in
            switch row {
            case .sessionStarted: "start"
            case .unreadableLine: "unreadable"
            case .sessionEnded: "end"
            default: "other"
            }
        }
        XCTAssertEqual(shape, ["start", "unreadable", "end"],
                       "position is the only fact an unreadable Line has left")
    }

    // MARK: A live fight

    func testALiveEncounterIsReadFromMemoryAndMarked() throws {
        let grix = UUID()
        let url = try writeSessionLog([
            .sessionStarted(startedAt: Date()),
            // No `encounterEnded`: the fight is still running.
            .encounterStarted(map: "dungeon.png", logFile: "fight.jsonl", at: Date()),
        ])

        let live: [LogLine] = [
            .encounterStarted(startedAt: Date(), order: [grix],
                              combatants: [combatant("Grix", id: grix)]),
            .turn(round: 1, combatantID: grix, changes: [], endedAt: Date()),
        ]
        let rows = LogViewModel().rows(sessionLogAt: url, workspace: workspace,
                                       liveEncounterLines: live)

        let isLive = rows.contains { if case .encounterStarted(_, true) = $0 { true } else { false } }
        XCTAssertTrue(isLive, "the running fight is marked in progress")
        XCTAssertTrue(rows.contains { if case .turn = $0 { true } else { false } },
                      "its Turns come from memory — the file may not have them yet")
    }

    /// The Turns above it are the ones that have *ended*. Without this row the Combatant
    /// currently acting is the one person the log does not mention.
    func testALiveEncounterNamesWhoseTurnItIsNow() throws {
        let grix = UUID(), ogre = UUID()
        let url = try writeSessionLog([
            .encounterStarted(map: "dungeon.png", logFile: "fight.jsonl", at: Date()),
        ])

        let live: [LogLine] = [
            .encounterStarted(startedAt: Date(), order: [grix, ogre],
                              combatants: [combatant("Grix", id: grix),
                                           combatant("Ogre", id: ogre)]),
            // Grix has acted; the Ogre is up.
            .turn(round: 1, combatantID: grix, changes: [], endedAt: Date()),
        ]
        let rows = LogViewModel().rows(sessionLogAt: url, workspace: workspace,
                                       liveEncounterLines: live)

        let liveTurn = rows.compactMap { row -> String? in
            if case let .liveTurn(_, name) = row { return name } else { return nil }
        }
        XCTAssertEqual(liveTurn, ["Ogre"], "the fold decides whose Turn it is, here as everywhere")
        XCTAssertEqual(rows.last, .liveTurn(round: 1, combatantName: "Ogre"),
                       "it sits at the foot of the fight")
    }

    /// A fight the DM stopped before anyone acted wrote a real file with nothing in it.
    /// Reporting that as unreadable would be the silent drop this view exists to avoid.
    func testAnEmptyButValidCombatLogIsNotReportedAsUnreadable() throws {
        try writeCombatLog([], forMapAt: mapURL)
        let url = try writeSessionLog([
            .encounterStarted(map: "dungeon.png", logFile: "fight.jsonl", at: Date()),
        ])

        let rows = LogViewModel().rows(sessionLogAt: url, workspace: workspace)

        XCTAssertFalse(rows.contains { if case .encounterUnreadable = $0 { true } else { false } },
                       "empty is not the same as unreadable")
        XCTAssertTrue(rows.contains { if case .encounterStarted = $0 { true } else { false } })
    }

    /// The live pointer is the one nothing closes. Asking "is there any close after me"
    /// answers correctly only for a file whose opens and closes alternate perfectly.
    func testAStrayCloseDoesNotMakeTheLivePointerLookFinished() throws {
        let grix = UUID()
        let url = try writeSessionLog([
            .encounterStarted(map: "dungeon.png", logFile: "first.jsonl", at: Date()),
            .encounterEnded(map: "dungeon.png", at: Date()),
            // The live fight, followed by a close that belongs to nothing.
            .encounterStarted(map: "dungeon.png", logFile: "second.jsonl", at: Date()),
        ])

        let live: [LogLine] = [
            .encounterStarted(startedAt: Date(), order: [grix],
                              combatants: [combatant("Grix", id: grix)]),
            .turn(round: 1, combatantID: grix, changes: [], endedAt: Date()),
        ]
        let rows = LogViewModel().rows(sessionLogAt: url, workspace: workspace,
                                       liveEncounterLines: live)

        XCTAssertTrue(rows.contains { if case .encounterStarted(_, true) = $0 { true } else { false } },
                      "the last unclosed pointer is the fight happening now")
    }

    func testAFinishedEncounterIsReadFromTheFileEvenWhileAnotherRunsLive() throws {
        let grix = UUID()
        try writeCombatLog([
            .encounterStarted(startedAt: Date(), order: [grix],
                              combatants: [combatant("Grix", id: grix)]),
            .turn(round: 1, combatantID: grix, changes: [], endedAt: Date()),
            .encounterEnded(endedAt: Date()),
        ], forMapAt: mapURL, named: "first.jsonl")

        let url = try writeSessionLog([
            .encounterStarted(map: "dungeon.png", logFile: "first.jsonl", at: Date()),
            .encounterEnded(map: "dungeon.png", at: Date()),
            .encounterStarted(map: "dungeon.png", logFile: "second.jsonl", at: Date()),
        ])

        let ogre = UUID()
        let live: [LogLine] = [
            .encounterStarted(startedAt: Date(), order: [ogre],
                              combatants: [combatant("Ogre", id: ogre)]),
            .turn(round: 1, combatantID: ogre, changes: [], endedAt: Date()),
        ]
        let rows = LogViewModel().rows(sessionLogAt: url, workspace: workspace,
                                       liveEncounterLines: live)

        let names = rows.compactMap { row -> String? in
            if case let .turn(name) = row { return name } else { return nil }
        }
        XCTAssertEqual(names, ["Grix", "Ogre"],
                       "the finished fight comes off disk, the live one out of memory")
    }
}
