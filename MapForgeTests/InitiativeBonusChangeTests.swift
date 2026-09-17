import XCTest
@testable import MapForge

/// An initiative bonus moving mid-fight is a Change like any other number (ADR-0008).
///
/// It had no Change until a Monster could be stamped mid-Encounter (ADR-0021): nothing in the
/// tracker edits a bonus, so nothing needed to record one. Without it the fold — which
/// `stats.json` follows — kept the old bonus, and every later roll used it.
final class InitiativeBonusChangeTests: XCTestCase {
    private let gnoll = UUID()

    func testItSurvivesTheLog() throws {
        let change = Change.initiativeBonusChanged(combatantID: gnoll, from: 1, to: 2)
        let decoded = try JSONDecoder().decode(Change.self, from: JSONEncoder().encode(change))
        XCTAssertEqual(decoded, change)
        XCTAssertEqual(decoded.combatantID, gnoll)
    }

    func testItIsReadableInTheFile() throws {
        let data = try JSONEncoder().encode(
            Change.initiativeBonusChanged(combatantID: gnoll, from: 1, to: 2))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["type"] as? String, "initiativeBonusChanged")
        XCTAssertEqual(object?["to"] as? Int, 2)
    }

    @MainActor func testAStatBlockEditRecordsIt() {
        let changes = AppState.changes(for: gnoll,
                                       from: StatBlock(initiativeBonus: 1),
                                       to: StatBlock(initiativeBonus: 2))
        XCTAssertEqual(changes, [.initiativeBonusChanged(combatantID: gnoll, from: 1, to: 2)])
    }

    func testTheLogSaysItInWords() {
        XCTAssertEqual(
            LogRowText.describe(.initiativeBonusChanged(combatantID: gnoll, from: 1, to: -2),
                                combatantName: "GG1"),
            "GG1 — initiative bonus +1 → −2")
    }
}
