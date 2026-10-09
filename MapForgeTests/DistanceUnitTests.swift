import XCTest
@testable import MapForge

/// A distance is written the way the table's own book writes it (`docs/terminology.md`,
/// Distances): every edition MapForge speaks is metric at 1,5 m to the square, and they differ
/// only in how a fraction is printed.
final class DistanceUnitTests: XCTestCase {
    private func format(_ squares: CGFloat, _ language: String) -> String {
        DistanceUnit.metres.format(squares: squares, locale: Locale(identifier: language))
    }

    func testEnglishWritesAFractionWithAPoint() {
        XCTAssertEqual(format(5, "en"), "7.5 m")
    }

    func testEveryOtherLanguageWritesOneSquareAsOneAndAHalfMetres() {
        for language in ["it", "de", "es", "pt-BR", "el"] {
            XCTAssertEqual(format(1, language), "1,5 m", language)
        }
    }

    func testAWholeDistanceIsBareInEveryLanguageFrenchIncluded() {
        // "9 m", never "9,00 m": the French book pads only a fraction.
        for language in ["en", "it", "de", "fr", "es", "pt-BR", "el"] {
            XCTAssertEqual(format(6, language), "9 m", language)
        }
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

/// Feet name the same Grid square at 5 ft (`CONTEXT.md`, **Distance Unit**): never a conversion
/// of the metres, and always a whole number, because no table says "37.3 feet".
final class FeetFormattingTests: XCTestCase {
    private func format(_ squares: CGFloat, _ language: String) -> String {
        DistanceUnit.feet.format(squares: squares, locale: Locale(identifier: language))
    }

    func testFourSquaresAreTwentyFeetNotTheTapeMeasuresNineteenPointSeven() {
        XCTAssertEqual(format(4, "en"), "20 ft")
    }

    func testAnUnsnappedLineIsRoundedToTheWholeFoot() {
        // 7.46 squares is 37.3 ft.
        XCTAssertEqual(format(7.46, "en"), "37 ft")
    }

    func testEveryLanguageWritesFtAndNoFraction() {
        // No official edition outside English is in feet, so the symbol stays English
        // (ADR-0022) — and French pads only a fraction, which feet never have.
        for language in ["en", "it", "de", "fr", "es", "pt-BR", "el"] {
            XCTAssertEqual(format(1.5, language), "8 ft", language)
        }
    }

    func testThirtyTypedFeetAreSixSquares() {
        XCTAssertEqual(DistanceUnit.feet.squares(fromDisplay: 30), 6, accuracy: 1e-9)
    }

    func testALongDistanceIsNotGrouped() {
        XCTAssertEqual(format(240, "en"), "1200 ft")
    }
}
