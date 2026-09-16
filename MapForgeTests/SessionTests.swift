import XCTest
@testable import MapForge

/// The Session's rules, with no disk and no UI present.
///
/// The silence during an Encounter is enforced here rather than by a view disabling a field:
/// a disabled control is a courtesy, this is the guarantee. See ADR-0014.
final class SessionTests: XCTestCase {

    private let when = Date(timeIntervalSince1970: 1_789_000_000)
    private func later(_ seconds: TimeInterval) -> Date { when.addingTimeInterval(seconds) }

    // MARK: Starting

    func testStartProducesOneLineAndALiveSession() {
        let (session, lines) = SessionControl.start(at: when)
        XCTAssertEqual(lines, [.sessionStarted(startedAt: when)])
        XCTAssertEqual(session.startedAt, when)
        XCTAssertFalse(session.isRecordingSuspended)
    }

    // MARK: Comments

    func testACommentIsRecordedWithItsMapAndPawn() {
        var (session, _) = SessionControl.start(at: when)
        let pawn = UUID()
        let lines = SessionControl.comment("the door was trapped",
                                           map: "crypt.png", pawnID: pawn,
                                           at: later(60), in: &session)
        XCTAssertEqual(lines, [.comment(text: "the door was trapped",
                                        map: "crypt.png", pawnID: pawn, at: later(60))])
    }

    func testAnEmptyCommentRecordsNothing() {
        var (session, _) = SessionControl.start(at: when)
        XCTAssertEqual(SessionControl.comment("", map: nil, pawnID: nil,
                                              at: later(60), in: &session), [])
        XCTAssertEqual(SessionControl.comment("   \n  ", map: nil, pawnID: nil,
                                              at: later(60), in: &session), [])
    }

    func testACommentIsTrimmed() {
        var (session, _) = SessionControl.start(at: when)
        let lines = SessionControl.comment("  they fled north  ", map: nil, pawnID: nil,
                                           at: later(60), in: &session)
        XCTAssertEqual(lines, [.comment(text: "they fled north",
                                        map: nil, pawnID: nil, at: later(60))])
    }

    // MARK: Movement

    func testAMovementIsRecorded() {
        var (session, _) = SessionControl.start(at: when)
        let pawn = UUID()
        let lines = SessionControl.pawnMoved(pawnID: pawn, label: "Grix", map: "crypt.png",
                                             from: MapPoint(x: 0, y: 0),
                                             to: MapPoint(x: 50, y: 0),
                                             distanceSquares: 1,
                                             at: later(60), in: &session)
        XCTAssertEqual(lines, [.pawnMoved(pawnID: pawn, label: "Grix", map: "crypt.png",
                                          from: MapPoint(x: 0, y: 0),
                                          to: MapPoint(x: 50, y: 0),
                                          distanceSquares: 1, at: later(60))])
    }

    // MARK: The silence — ADR-0014

    private func suspendedSession() -> Session {
        var (session, _) = SessionControl.start(at: when)
        _ = SessionControl.encounterStarted(map: "crypt.png",
                                            logFile: "2026-09-16T190000Z.jsonl",
                                            at: later(60), in: &session)
        return session
    }

    func testEncounterStartedSuspendsRecordingAndWritesThePointer() {
        var (session, _) = SessionControl.start(at: when)
        let lines = SessionControl.encounterStarted(map: "crypt.png",
                                                    logFile: "2026-09-16T190000Z.jsonl",
                                                    at: later(60), in: &session)
        XCTAssertEqual(lines, [.encounterStarted(map: "crypt.png",
                                                 logFile: "2026-09-16T190000Z.jsonl",
                                                 at: later(60))],
                       "the pointer is what makes the hole in the file legible")
        XCTAssertTrue(session.isRecordingSuspended)
    }

    func testACommentWhileSuspendedRecordsNothing() {
        var session = suspendedSession()
        XCTAssertEqual(SessionControl.comment("mid-fight", map: "crypt.png", pawnID: nil,
                                              at: later(120), in: &session), [],
                       "the Combat Log is the one recorder while a fight runs")
    }

    func testAMovementWhileSuspendedRecordsNothing() {
        var session = suspendedSession()
        XCTAssertEqual(SessionControl.pawnMoved(pawnID: UUID(), label: "Grix", map: "crypt.png",
                                                from: MapPoint(x: 0, y: 0),
                                                to: MapPoint(x: 50, y: 0),
                                                distanceSquares: 1,
                                                at: later(120), in: &session), [],
                       "a drag during a fight belongs to the Combat Log alone")
    }

    func testEncounterEndedResumesRecording() {
        var session = suspendedSession()
        let lines = SessionControl.encounterEnded(map: "crypt.png", at: later(180), in: &session)
        XCTAssertEqual(lines, [.encounterEnded(map: "crypt.png", at: later(180))])
        XCTAssertFalse(session.isRecordingSuspended)

        XCTAssertEqual(SessionControl.comment("after the fight", map: "crypt.png", pawnID: nil,
                                              at: later(240), in: &session).count, 1,
                       "the evening resumes where the fight left it")
    }

    func testASecondEncounterStartWhileSuspendedIsANoOp() {
        var session = suspendedSession()
        let lines = SessionControl.encounterStarted(map: "crypt.png",
                                                    logFile: "another.jsonl",
                                                    at: later(120), in: &session)
        XCTAssertEqual(lines, [], "two pointers would describe a fight that never started")
        XCTAssertTrue(session.isRecordingSuspended)
    }

    func testEncounterEndedWhenNotSuspendedIsANoOp() {
        var (session, _) = SessionControl.start(at: when)
        XCTAssertEqual(SessionControl.encounterEnded(map: nil, at: later(60), in: &session), [])
        XCTAssertFalse(session.isRecordingSuspended)
    }

    // MARK: Stopping

    func testStopEndsTheSession() {
        var (session, _) = SessionControl.start(at: when)
        XCTAssertEqual(SessionControl.stop(&session, at: later(3600)),
                       [.sessionEnded(endedAt: later(3600))])
    }

    func testStopWhileSuspendedStillEndsTheSession() {
        var session = suspendedSession()
        XCTAssertEqual(SessionControl.stop(&session, at: later(3600)),
                       [.sessionEnded(endedAt: later(3600))],
                       "a DM who quits mid-fight has ended the evening")
    }

    func testStopLeavesTheSuspensionFlagAsItStands() {
        // An ended Session is discarded, so clearing the flag would change nothing anybody
        // reads — but it would hand an inspecting caller a Session that was never mid-fight.
        var session = suspendedSession()
        _ = SessionControl.stop(&session, at: later(3600))
        XCTAssertTrue(session.isRecordingSuspended)
    }

    // MARK: Resuming

    func testFoldOfAnEndedSessionIsNil() {
        let lines: [SessionLine] = [.sessionStarted(startedAt: when),
                                    .comment(text: "a", map: nil, pawnID: nil, at: later(60)),
                                    .sessionEnded(endedAt: later(120))]
        XCTAssertNil(SessionFold.fold(lines))
    }

    func testFoldOfAnUnterminatedSessionIsLive() {
        let lines: [SessionLine] = [.sessionStarted(startedAt: when),
                                    .comment(text: "a", map: nil, pawnID: nil, at: later(60))]
        let session = SessionFold.fold(lines)
        XCTAssertEqual(session?.startedAt, when)
        XCTAssertEqual(session?.isRecordingSuspended, false)
    }

    func testFoldOfASessionInterruptedMidFightIsSuspended() {
        let lines: [SessionLine] = [.sessionStarted(startedAt: when),
                                    .encounterStarted(map: "crypt.png",
                                                      logFile: "x.jsonl", at: later(60))]
        XCTAssertEqual(SessionFold.fold(lines)?.isRecordingSuspended, true,
                       "a DM who quit mid-fight gets the silence back with the fight")
    }

    func testFoldAfterAFightEndedIsNotSuspended() {
        let lines: [SessionLine] = [.sessionStarted(startedAt: when),
                                    .encounterStarted(map: "c.png", logFile: "x.jsonl",
                                                      at: later(60)),
                                    .encounterEnded(map: "c.png", at: later(120))]
        XCTAssertEqual(SessionFold.fold(lines)?.isRecordingSuspended, false)
    }

    func testFoldOfAnEmptyOrHeadlessFileIsNil() {
        XCTAssertNil(SessionFold.fold([]))
        XCTAssertNil(SessionFold.fold([.comment(text: "orphan", map: nil,
                                                pawnID: nil, at: when)]),
                     "a file with no opening line is not a Session this app wrote")
    }

    func testFoldIgnoresUnrecognisedLines() {
        let lines: [SessionLine] = [.sessionStarted(startedAt: when), .unrecognised]
        XCTAssertEqual(SessionFold.fold(lines)?.startedAt, when,
                       "a later version's line must not end the evening")
    }
}
