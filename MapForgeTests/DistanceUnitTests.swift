import XCTest
@testable import MapForge

/// A distance is written the way the table's own book writes it (`docs/terminology.md`,
/// Distances): every edition MapForge speaks is metric at 1,5 m to the square, and they differ
/// only in how a fraction is printed.
final class DistanceUnitTests: XCTestCase {
    private func format(_ squares: CGFloat, _ language: String) -> String {
        DistanceUnit.metres.format(squares: squares, locale: Locale(identifier: language))
    }

    func testItalianWritesHalfASquareWithADecimalComma() {
        XCTAssertEqual(format(5, "it"), "7,5 m")
    }

    func testFrenchWritesAFractionToTwoDecimalsAsItsBookDoes() {
        // *Manuel des joueurs*: "une Émanation de 1,50 m", "4,50 m".
        XCTAssertEqual(format(1, "fr"), "1,50 m")
        XCTAssertEqual(format(3, "fr"), "4,50 m")
    }
}
