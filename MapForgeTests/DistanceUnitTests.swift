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

/// A sight or a Light's radius typed in the Distance Unit (`CONTEXT.md`): stored exactly as
/// typed, never snapped — and a field the DM never touched never rewrites what is stored.
final class DistanceEntryTests: XCTestCase {
    func testDarkvisionLandsOnTwelveSquaresInEitherUnit() {
        XCTAssertEqual(DistanceUnit.feet.squares(entered: 60, replacing: 0), 12, accuracy: 1e-9)
        XCTAssertEqual(DistanceUnit.metres.squares(entered: 18, replacing: 0), 12, accuracy: 1e-9)
    }

    func testAHomebrewSightIsStoredExactlyNotSnapped() {
        XCTAssertEqual(DistanceUnit.feet.squares(entered: 32, replacing: 12), 6.4, accuracy: 1e-9)
    }

    func testTheFieldShowsTheStoredDistanceAsTheUnitSaysIt() {
        XCTAssertEqual(DistanceUnit.feet.roundedDisplay(squares: 12), 60)
        XCTAssertEqual(DistanceUnit.metres.roundedDisplay(squares: 12), 18)
        // 10 m typed at a metric table, read at one in feet: 33.3 ft, said as 33.
        XCTAssertEqual(DistanceUnit.feet.roundedDisplay(squares: 10 / 1.5), 33)
    }

    func testAnUntouchedFieldLeavesARoundedValueExactlyAsStored() {
        // The field shows 33 for 6.667 squares; handing 33 back must not make it 6.6.
        let stored: CGFloat = 10 / 1.5
        XCTAssertEqual(DistanceUnit.feet.squares(entered: 33, replacing: stored), stored)
    }

    func testAnUntouchedMetricFieldLeavesItsSquaresBitIdentical() {
        // 32 ft is 6.4 squares, shown at a metric table as "9.6" — which the field parses
        // back as the Double 9.6, not as 96 × 0.1.
        let stored: CGFloat = 6.4
        XCTAssertEqual(DistanceUnit.metres.squares(entered: 9.6, replacing: stored), stored)
    }

    func testEveryValueTheFieldShowsComesBackAsTheSameStoredSquares() {
        // Through the real formatter, as the field round-trips it: every whole foot from 0 to
        // 199 ft, read in either unit, survives being shown and parsed back untouched.
        let english = Locale(identifier: "en")
        for unit in DistanceUnit.allCases {
            for feet in 0..<200 {
                let stored = CGFloat(feet) / 5
                let text = unit.roundedDisplay(squares: stored)
                    .formatted(.number.grouping(.never).locale(english))
                let parsed = try! Double(text, format: .number.locale(english))
                XCTAssertEqual(unit.squares(entered: parsed, replacing: stored), stored,
                               "\(feet) ft read in \(unit)")
            }
        }
    }
}
