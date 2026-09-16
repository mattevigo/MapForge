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
}
