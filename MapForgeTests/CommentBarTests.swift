import SwiftUI
import XCTest
@testable import MapForge

/// The Comment Bar's three states, and the one thing that must not change between them.
///
/// The bar is the only control that enforces the boundary between preparing a Map and
/// running a Session, so which state it is in is a decision worth testing without a window
/// around it — the reason `ViewportToggle` is a policy type too.
final class CommentBarTests: XCTestCase {

    private let when = Date(timeIntervalSince1970: 1_789_000_000)

    private func liveSession() -> Session { Session(startedAt: when) }

    // MARK: The three states

    func testNoSessionBeforeOneIsStarted() {
        XCTAssertEqual(CommentBarPolicy.state(hasSession: false, hasEncounter: false,
                                              activeCombatantName: nil),
                       .noSession)
    }

    func testRecordingDuringASession() {
        XCTAssertEqual(CommentBarPolicy.state(hasSession: true, hasEncounter: false,
                                              activeCombatantName: nil),
                       .recording)
    }

    func testDuringEncounterWhenAFightRunsInsideASession() {
        XCTAssertEqual(CommentBarPolicy.state(hasSession: true, hasEncounter: true,
                                              activeCombatantName: "Grix"),
                       .duringEncounter(activeCombatantName: "Grix"))
    }

    func testAFightWithNoSessionStillReadsAsNoSession() {
        // The honest instruction: starting a Session is what makes the field live, and a
        // fight running outside one does not change that.
        XCTAssertEqual(CommentBarPolicy.state(hasSession: false, hasEncounter: true,
                                              activeCombatantName: "Grix"),
                       .noSession)
    }

    // MARK: What follows from the state

    func testOnlyRecordingIsEnabled() {
        XCTAssertFalse(CommentBarState.noSession.isEnabled)
        XCTAssertTrue(CommentBarState.recording.isEnabled)
        XCTAssertFalse(CommentBarState.duringEncounter(activeCombatantName: "Grix").isEnabled)
    }

    func testEachStateSaysWhichItIs() {
        XCTAssertEqual(CommentBarState.noSession.placeholder, "Start the session to record")
        XCTAssertEqual(CommentBarState.recording.placeholder, "what happened")
        XCTAssertTrue(CommentBarState.duringEncounter(activeCombatantName: "Grix")
            .placeholder.contains("Grix"),
                      "the DM must be told where the live box is")
        XCTAssertTrue(CommentBarState.duringEncounter(activeCombatantName: "Grix")
            .placeholder.contains("Combat tab"))
    }

    func testTheEncounterPlaceholderDegradesWithoutAName() {
        // Between Turns, or before the first one: there is no active Combatant to name.
        let placeholder = CommentBarState.duringEncounter(activeCombatantName: nil).placeholder
        XCTAssertFalse(placeholder.isEmpty)
        XCTAssertTrue(placeholder.contains("Combat tab"))
    }

    // MARK: Height — the Map must never move

    /// The bar as `CommentBar` builds it, at a width a narrow Control Window would give it.
    @MainActor
    private func barHeight(_ state: CommentBarState, width: CGFloat = 520) -> CGFloat {
        let view = CommentBar(state: state, text: .constant(""), onSubmit: {})
            .frame(width: width)
        return NSHostingView(rootView: view).fittingSize.height
    }

    @MainActor
    func testTheBarIsTheSameHeightInEveryState() {
        // `preview` claims every point the stack above and below it leaves. A bar that grew
        // when a fight started would resize the Map mid-click — the defect `ChromeHeightTests`
        // guards above the preview, arriving from below it.
        let heights = [barHeight(.noSession),
                       barHeight(.recording),
                       barHeight(.duringEncounter(activeCombatantName: "Grix"))]
        for height in heights.dropFirst() {
            XCTAssertEqual(height, heights[0], accuracy: 0.5,
                           "the Map must not move when the Session or a fight starts")
        }
    }

    @MainActor
    func testALongPlaceholderDoesNotGrowTheBar() {
        // The longest name a DM might give a Combatant, at the narrowest width.
        let long = CommentBarState.duringEncounter(
            activeCombatantName: "Grixnathaniel the Unfathomably Verbose")
        XCTAssertEqual(barHeight(long, width: 360), barHeight(.recording, width: 360),
                       accuracy: 0.5,
                       "a one-line field stays one line — no `axis: .vertical` here")
    }
}
