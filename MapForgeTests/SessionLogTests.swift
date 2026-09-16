import XCTest
@testable import MapForge

/// The Session Log's format: one JSON object per line, appended and never rewritten.
///
/// The same discipline as the Combat Log and a deliberately separate vocabulary — see
/// `docs/adr/0014-the-session-log-falls-silent-during-an-encounter.md`.
final class SessionLogTests: XCTestCase {

    // MARK: Round-tripping

    private func roundTrip(_ line: SessionLine,
                           file: StaticString = #filePath, line number: UInt = #line) throws {
        let data = try SessionLogFile.encoder().encode(line)
        let back = try SessionLogFile.decoder().decode(SessionLine.self, from: data)
        XCTAssertEqual(back, line, file: file, line: number)
    }

    /// Dates round-trip through ISO-8601 at second precision, so a test date must not
    /// carry sub-second components it will lose on the way back.
    private let when = Date(timeIntervalSince1970: 1_789_000_000)

    func testSessionStartedRoundTrips() throws {
        try roundTrip(.sessionStarted(startedAt: when))
    }

    func testCommentRoundTrips() throws {
        try roundTrip(.comment(text: "the door was trapped",
                               map: "crypt.png",
                               pawnID: UUID(),
                               at: when))
    }

    func testCommentWithNoMapOrPawnRoundTrips() throws {
        // A Comment typed before a Map is open is still part of the evening — ADR-0015.
        try roundTrip(.comment(text: "party still arguing", map: nil, pawnID: nil, at: when))
    }

    func testPawnMovedRoundTrips() throws {
        try roundTrip(.pawnMoved(pawnID: UUID(),
                                 label: "Grix",
                                 map: "crypt.png",
                                 from: MapPoint(x: 10, y: 20),
                                 to: MapPoint(x: 110, y: 20),
                                 distanceSquares: 2,
                                 at: when))
    }

    func testEncounterStartedRoundTrips() throws {
        try roundTrip(.encounterStarted(map: "crypt.png",
                                        logFile: "2026-09-16T190000Z.jsonl",
                                        at: when))
    }

    func testEncounterEndedRoundTrips() throws {
        try roundTrip(.encounterEnded(map: "crypt.png", at: when))
    }

    func testSessionEndedRoundTrips() throws {
        try roundTrip(.sessionEnded(endedAt: when))
    }

    // MARK: The shape on disk

    func testLineIsTaggedByItsKind() throws {
        let data = try SessionLogFile.encoder().encode(SessionLine.sessionStarted(startedAt: when))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"line\":\"sessionStarted\""),
                      "a DM reads this file; the discriminator must name the line. Got: \(text)")
    }

    func testCommentTextIsLegibleInTheFile() throws {
        let data = try SessionLogFile.encoder().encode(
            SessionLine.comment(text: "down the east/west corridor",
                                map: nil, pawnID: nil, at: when))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("down the east/west corridor"),
                      "slashes must not be escaped — a DM's note stays readable. Got: \(text)")
    }

    func testAnEncodedLineHasNoNewlineInIt() throws {
        // One object per line is the whole format. A pretty-printed line would end it.
        let data = try SessionLogFile.encoder().encode(
            SessionLine.comment(text: "a", map: "b.png", pawnID: nil, at: when))
        XCTAssertFalse(data.contains(0x0A))
    }

    // MARK: Forward compatibility

    func testAnUnknownLineKindDecodesAsUnrecognised() throws {
        let json = Data(#"{"line":"somethingLater","at":"2026-09-16T19:00:00Z"}"#.utf8)
        let line = try SessionLogFile.decoder().decode(SessionLine.self, from: json)
        XCTAssertEqual(line, .unrecognised,
                       "a later version's line must not lose the whole file")
    }

    func testUnrecognisedThrowsOnEncode() {
        XCTAssertThrowsError(try SessionLogFile.encoder().encode(SessionLine.unrecognised),
                             "read-only: writing one back would invent a line nobody wrote")
    }

    // MARK: File naming

    func testFileNameHasNoColons() {
        let name = SessionLogFile.name(startedAt: when)
        XCTAssertFalse(name.contains(":"),
                       "legal in POSIX and a lifetime of trouble everywhere else")
        XCTAssertTrue(name.hasSuffix(".jsonl"))
    }

    func testFileNamesSortAsTextInStartOrder() {
        let earlier = SessionLogFile.name(startedAt: when)
        let later = SessionLogFile.name(startedAt: when.addingTimeInterval(3600))
        XCTAssertLessThan(earlier, later)
    }

    func testDirectoryIsSessionsInsideTheWorkspaceSupportFolder() {
        let workspace = Workspace(url: URL(fileURLWithPath: "/tmp/Game"))
        XCTAssertEqual(SessionLogFile.directory(in: workspace).path,
                       "/tmp/Game/.mapforge/sessions")
    }

    // MARK: Writing and reading

    private func makeWorkspace() throws -> (Workspace, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (Workspace(url: root), root)
    }

    func testWriterAppendsOneLinePerCall() throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let writer = try SessionLogWriter(in: workspace, startedAt: when)
        try writer.append(.sessionStarted(startedAt: when))
        try writer.append(.comment(text: "one", map: nil, pawnID: nil, at: when))
        try writer.close()

        let lines = try SessionLogReader().read(at: writer.url)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.first, .sessionStarted(startedAt: when))
    }

    func testReopeningAppendsRatherThanRewriting() throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let writer = try SessionLogWriter(in: workspace, startedAt: when)
        try writer.append(.sessionStarted(startedAt: when))
        try writer.close()

        let reopened = try SessionLogWriter(reopening: writer.url)
        try reopened.append(.comment(text: "after the break", map: nil, pawnID: nil, at: when))
        try reopened.close()

        XCTAssertEqual(try SessionLogReader().read(at: writer.url).count, 2)
    }

    func testReaderDropsATruncatedFinalLine() throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let writer = try SessionLogWriter(in: workspace, startedAt: when)
        try writer.append(.sessionStarted(startedAt: when))
        try writer.close()
        // A crash mid-write: half an object and no newline.
        let handle = try FileHandle(forWritingTo: writer.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"line":"comm"#.utf8))
        try handle.close()

        let lines = try SessionLogReader().read(at: writer.url)
        XCTAssertEqual(lines, [.sessionStarted(startedAt: when)],
                       "losing a whole evening to save its last line is the wrong trade")
    }

    func testAnAbsentFileReadsAsNoLines() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).jsonl")
        XCTAssertEqual(try SessionLogReader().read(at: missing), [])
    }

    func testNewestLogIsTheLatestByName() throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try SessionLogWriter(in: workspace, startedAt: when)
        try first.append(.sessionStarted(startedAt: when))
        try first.close()
        let second = try SessionLogWriter(in: workspace,
                                          startedAt: when.addingTimeInterval(3600))
        try second.append(.sessionStarted(startedAt: when.addingTimeInterval(3600)))
        try second.close()

        // Compared by name, not by URL: `contentsOfDirectory` resolves /var to /private/var
        // and the Workspace's own URL does not, so two spellings of one file are unequal.
        XCTAssertEqual(SessionLogReader().newestLogURL(in: workspace)?.lastPathComponent,
                       second.url.lastPathComponent)
        XCTAssertEqual(SessionLogReader().logURLs(in: workspace).count, 2)
    }

    func testNewestLogIsNilInAWorkspaceWithNoSessions() throws {
        let (workspace, root) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(SessionLogReader().newestLogURL(in: workspace))
    }
}
