import XCTest
@testable import MapForge

/// The Log View's four states.
///
/// The one that matters is `testRecordingWithNothingYetIsNotTheSameAsNoSession`: *am I
/// actually recording?* is the question this view exists to answer, and the two states look
/// identical if they share a message.
final class LogViewTests: XCTestCase {

    func testWithoutAWorkspaceItSaysWhereASessionWouldBeWritten() {
        let state = LogViewPolicy.state(hasWorkspace: false, hasSession: false, isEmpty: true)
        XCTAssertEqual(state, .noWorkspace)
        XCTAssertEqual(state.message, "Open a Workspace to record a Session.")
    }

    func testWithoutASessionItNamesTheButtonThatFillsIt() {
        let state = LogViewPolicy.state(hasWorkspace: true, hasSession: false, isEmpty: true)
        XCTAssertEqual(state, .noSession)
        XCTAssertEqual(state.message,
                       "No Session running — press Start Session to begin recording.",
                       "a disabled button teaches nothing; this teaches what fills the pane")
    }

    func testRecordingWithNothingYetIsNotTheSameAsNoSession() {
        let recording = LogViewPolicy.state(hasWorkspace: true, hasSession: true, isEmpty: true)
        let noSession = LogViewPolicy.state(hasWorkspace: true, hasSession: false, isEmpty: true)

        XCTAssertEqual(recording, .recordingNothingYet)
        XCTAssertEqual(recording.message, "Recording. Nothing has happened yet.")
        XCTAssertNotEqual(recording.message, noSession.message,
                          "an empty pane that reads as failure is what four states avoid")
    }

    func testWithLinesThereIsNoEmptyState() {
        let state = LogViewPolicy.state(hasWorkspace: true, hasSession: true, isEmpty: false)
        XCTAssertEqual(state, .lines)
        XCTAssertNil(state.message)
    }

    /// A DM with no Workspace is told about the Workspace: they have not yet done the thing
    /// that makes the rest possible, so reporting the Session would skip a step.
    func testTheStatesAreCheckedOutermostFirst() {
        let state = LogViewPolicy.state(hasWorkspace: false, hasSession: true, isEmpty: false)
        XCTAssertEqual(state, .noWorkspace)
    }

    // MARK: Following the newest Line

    /// At the bottom the content's last pixel is level with the clip's last pixel, so
    /// `contentMaxY` equals the viewport's height — **not** zero. Comparing it against zero
    /// is the bug this test exists to prevent: it is false for every log taller than its
    /// pane, so following latches off exactly when it starts to matter.
    func testTheViewFollowsWhenScrolledToTheBottom() {
        XCTAssertTrue(LogViewPolicy.isFollowing(contentMaxY: 400, viewportHeight: 400),
                      "at the bottom the content's edge is level with the clip's")
    }

    func testTheViewStopsFollowingWhenTheDMScrollsUp() {
        // Scrolled up 300pt: the content's bottom edge is that far below the fold.
        XCTAssertFalse(LogViewPolicy.isFollowing(contentMaxY: 700, viewportHeight: 400),
                       "a DM reading Round 2 must not be yanked away by a Pawn drag")
    }

    func testFollowingSurvivesAFewPixelsOfRubberBanding() {
        XCTAssertTrue(LogViewPolicy.isFollowing(contentMaxY: 410, viewportHeight: 400),
                      "an exact comparison would drop following on a single pixel")
    }

    func testALogShorterThanItsPaneAlwaysFollows() {
        // Nothing to scroll: the content ends well above the clip's bottom edge.
        XCTAssertTrue(LogViewPolicy.isFollowing(contentMaxY: 80, viewportHeight: 400))
    }
}
