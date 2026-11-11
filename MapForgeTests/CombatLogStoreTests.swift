import XCTest
@testable import MapForge

final class CombatLogStoreTests: XCTestCase {
    private var directory: URL!
    private var mapURL: URL!
    private let grog = UUID()
    private let at = Date(timeIntervalSince1970: 1_757_600_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CombatLogStoreTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        mapURL = directory.appendingPathComponent("dungeon.png")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testALogRoundTrips() throws {
        // The basic promise: what was written is what comes back.
        let lines: [LogLine] = [
            .encounterStarted(startedAt: at, order: [grog], combatants: [
                Combatant(id: grog, name: "Grog", kind: .player, initiative: 18,
                          block: StatBlock(currentHP: 26, maxHP: 26)),
            ]),
            .turn(round: 1, combatantID: grog,
                  changes: [.hpChanged(combatantID: grog, from: 26, to: 20)], endedAt: at),
        ]
        let writer = try CombatLogWriter(forMapAt: mapURL, startedAt: at)
        for line in lines { try writer.append(line) }
        XCTAssertEqual(try CombatLogReader().read(at: writer.url), lines)
    }

    func testTheLogSitsInTheMapsCombatFolder() throws {
        // Beside stats.json, so a Map's whole combat history is one folder.
        let writer = try CombatLogWriter(forMapAt: mapURL, startedAt: at)
        try writer.append(.encounterEnded(endedAt: at))
        XCTAssertEqual(writer.url.deletingLastPathComponent().lastPathComponent, "dungeon.combat")
        XCTAssertEqual(writer.url.pathExtension, "jsonl")
    }

    func testTheLogIsNamedForWhenTheFightStarted() throws {
        // Not named by the DM: a modal asking "what shall we call this fight?" arrives at
        // the exact moment the table is waiting for initiative.
        let writer = try CombatLogWriter(forMapAt: mapURL, startedAt: at)
        try writer.append(.encounterEnded(endedAt: at))
        XCTAssertEqual(writer.url.lastPathComponent, "2025-09-11T141320Z.jsonl")
    }

    func testEachLineIsOneLine() throws {
        // The format depends on it. Every other store in this app pretty-prints; this one
        // must not, because a newline inside an object would split it across two lines.
        let writer = try CombatLogWriter(forMapAt: mapURL, startedAt: at)
        try writer.append(.turn(round: 1, combatantID: grog,
                                changes: [.hpChanged(combatantID: grog, from: 26, to: 20)],
                                endedAt: at))
        try writer.append(.encounterEnded(endedAt: at))
        let text = try String(contentsOf: writer.url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2)
    }

    func testAppendingDoesNotRewriteWhatIsAlreadyThere() throws {
        // Append-only is the whole design. A writer that rewrote the file would lose
        // everything before it on a crash mid-write.
        let writer = try CombatLogWriter(forMapAt: mapURL, startedAt: at)
        try writer.append(.turn(round: 1, combatantID: grog, changes: [], endedAt: at))
        let afterFirst = try Data(contentsOf: writer.url)
        try writer.append(.turn(round: 2, combatantID: grog, changes: [], endedAt: at))
        let afterSecond = try Data(contentsOf: writer.url)
        XCTAssertEqual(afterSecond.prefix(afterFirst.count), afterFirst)
    }

    func testATruncatedFinalLineCostsOnlyThatLine() throws {
        // The crash case ADR-0008 accepts: a Turn in progress is lost, and refusing to
        // open the file would lose the whole fight to save the last Turn of it.
        let writer = try CombatLogWriter(forMapAt: mapURL, startedAt: at)
        let first = LogLine.turn(round: 1, combatantID: grog, changes: [], endedAt: at)
        try writer.append(first)
        let handle = try FileHandle(forWritingTo: writer.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"line":"turn","round":2,"combat"#.utf8))
        try handle.close()

        XCTAssertEqual(try CombatLogReader().read(at: writer.url), [first])
    }

    func testAnAbsentLogIsEmptyNotAnError() throws {
        // A Map nobody has fought on.
        let missing = directory.appendingPathComponent("nothing.jsonl")
        XCTAssertEqual(try CombatLogReader().read(at: missing), [])
    }

    func testTheNewestLogIsTheOneToResume() throws {
        // Opening a Map has to find the fight that was running when the app quit, and a
        // Map accumulates Encounters over a campaign.
        let older = try CombatLogWriter(forMapAt: mapURL, startedAt: at)
        try older.append(.encounterEnded(endedAt: at))
        let newer = try CombatLogWriter(forMapAt: mapURL,
                                        startedAt: at.addingTimeInterval(3600))
        try newer.append(.turn(round: 1, combatantID: grog, changes: [], endedAt: at))

        // Compared by filename: `contentsOfDirectory` resolves /var to /private/var, and
        // the identity that matters here is which Encounter, not which spelling of /tmp.
        XCTAssertEqual(CombatLogReader().newestLogURL(forMapAt: mapURL)?.lastPathComponent,
                       newer.url.lastPathComponent)
    }

    func testEveryLogForAMapIsListedOldestFirst() throws {
        // A campaign's fights, in the order they happened.
        let first = try CombatLogWriter(forMapAt: mapURL, startedAt: at)
        try first.append(.encounterEnded(endedAt: at))
        let second = try CombatLogWriter(forMapAt: mapURL, startedAt: at.addingTimeInterval(3600))
        try second.append(.encounterEnded(endedAt: at))

        XCTAssertEqual(CombatLogReader().logURLs(forMapAt: mapURL).map(\.lastPathComponent),
                       [first.url.lastPathComponent, second.url.lastPathComponent])
    }
}
