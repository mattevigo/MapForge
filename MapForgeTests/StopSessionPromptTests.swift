import XCTest
@testable import MapForge

/// What the DM is asked before the evening ends.
///
/// The alert exists because the Log View changed the stakes: a restart opens a new file, and
/// the Log View shows only the current Session, so an evening stopped by accident does not
/// merely split — its earlier half leaves the screen.
final class StopSessionPromptTests: XCTestCase {

    /// The fear the alert answers is "have I just lost tonight". Nothing is deleted by
    /// stopping — the Log is closed, not discarded (ADR-0015) — so the message says so.
    func testAQuietSessionIsToldItsLogIsKept() {
        let text = StopSessionPrompt.message(hasEncounter: false, map: "crypt.png")
        XCTAssertEqual(text, "Tonight's log is kept. Starting again opens a new one.")
    }

    /// A Map is irrelevant when no fight is running: an evening belongs to the Workspace and
    /// crosses whatever Maps the party walks (ADR-0015).
    func testAQuietSessionDoesNotMentionTheMap() {
        let withMap = StopSessionPrompt.message(hasEncounter: false, map: "crypt.png")
        let without = StopSessionPrompt.message(hasEncounter: false, map: nil)
        XCTAssertEqual(withMap, without)
    }

    /// Ending the evening ends the fight inside it, which is a bigger thing to do by accident
    /// and so is named.
    func testAFightIsNamedAlongWithWhereItIsRunning() {
        let text = StopSessionPrompt.message(hasEncounter: true, map: "crypt.png")
        XCTAssertTrue(text.contains("crypt.png"), "a DM mid-fight is told which fight")
        XCTAssertTrue(text.contains("end it too"), "the consequence is stated, not implied")
        XCTAssertTrue(text.contains("Both logs are kept"),
                      "the Combat Log survives too — ADR-0014 keeps it separate")
    }

    /// A Session needs no Map (ADR-0015), so a fight-with-no-Map must still read as a
    /// sentence rather than trailing an empty preposition.
    func testAFightWithNoMapStillReadsAsASentence() {
        let text = StopSessionPrompt.message(hasEncounter: true, map: nil)
        XCTAssertFalse(text.contains(" on "), "no dangling preposition")
        XCTAssertTrue(text.hasPrefix("An encounter is running and"))
    }

    func testTheTitleAsksRatherThanAnnounces() {
        XCTAssertEqual(StopSessionPrompt.title, "End the session?")
    }
}
