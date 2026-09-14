import AppKit
import XCTest
@testable import MapForge

final class ConditionTests: XCTestCase {
    func testTheConditionsAreTheFourteenOfFiveFiveE() {
        // Exhaustion is deliberately not among them: it is a level from 0 to 6, and a
        // set of booleans cannot hold a level. Concentration is not among them either —
        // it is not a Condition in the rules.
        XCTAssertEqual(Set(Condition.allCases.map(\.rawValue)),
                       ["blinded", "charmed", "deafened", "frightened", "grappled",
                        "incapacitated", "invisible", "paralyzed", "petrified", "poisoned",
                        "prone", "restrained", "stunned", "unconscious"])
    }

    func testEveryConditionSymbolResolves() {
        // `Image(systemName:)` renders an empty frame for a name that does not resolve,
        // with no warning and no crash — the bug `LiveRowSymbolTests` exists to stop
        // recurring. Fourteen Conditions will be shown as icons in a 320-point panel,
        // which is fourteen chances to ship a blank square.
        for condition in Condition.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: condition.symbolName, accessibilityDescription: nil),
                "\(condition.rawValue) names \(condition.symbolName), which does not resolve"
            )
        }
    }

    func testAConditionRoundTripsThroughJSON() throws {
        // Conditions are stored in `stats.json` and named in every Change in a Combat
        // Log, so their spelling on disk is a format commitment.
        let data = try JSONEncoder().encode([Condition.prone, .unconscious])
        XCTAssertEqual(try JSONDecoder().decode([Condition].self, from: data),
                       [.prone, .unconscious])
    }
}
