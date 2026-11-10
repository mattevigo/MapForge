import XCTest
@testable import MapForge

/// The Encounter Difficulty reads in the table's own language (`docs/terminology.md`,
/// Encounter Difficulty and Numbers): the bands and XP as SRD 5.2.1 prints them, Beyond High
/// as MapForge chose it, and a total grouped the way the book groups its tables.
final class EncounterDifficultyLanguageTests: XCTestCase {
    private func label(_ band: EncounterDifficulty.Band, _ xp: Int, _ language: String) -> String {
        band.label(creatureXP: xp, in: Locale(identifier: language))
    }

    // MARK: The label

    func testTheLabelReadsInEnglish() {
        XCTAssertEqual(label(.moderate, 650, "en"), "Moderate · 650 XP")
    }

    func testTheLabelReadsInItalianInTheBooksOwnWords() {
        // *Media*, not *Moderata*: the Italian book's band, not a rendering of the English.
        XCTAssertEqual(label(.moderate, 650, "it"), "Media · 650 PE")
    }

    func testAFourDigitTotalIsGroupedAsEachBookGroupsIt() {
        XCTAssertEqual(label(.high, 1100, "en"), "High · 1,100 XP")
        // The Italian book prints "1.100 PE", though macOS would leave four digits bare.
        XCTAssertEqual(label(.high, 1100, "it"), "Difficile · 1.100 PE")
        XCTAssertEqual(label(.high, 1100, "de"), "Hoch · 1.100 EP")
        XCTAssertEqual(label(.high, 1100, "fr"), "Élevée · 1\u{202F}100 PX")
    }

    func testTheCreaturesXPAloneReadsInTheBooksAbbreviation() {
        // A CR 4 and a CR 3: 1,100 + 700 XP, with no Player to set them against.
        let difficulty = EncounterDifficulty(levels: [],
                                             challengeRatings: [ChallengeRating("4")!,
                                                                ChallengeRating("3")!])
        XCTAssertEqual(difficulty.creatureXPLabel(in: Locale(identifier: "en")), "1,800 XP")
        XCTAssertEqual(difficulty.creatureXPLabel(in: Locale(identifier: "it")), "1.800 PE")
        XCTAssertEqual(difficulty.creatureXPLabel(in: Locale(identifier: "es")), "1800 PX")
    }

    func testTheBudgetsReadInItalianWithTheirBandsAndGrouping() {
        // Four level 5 Characters: 2,000 / 3,000 / 4,400.
        let budgets = EncounterDifficulty.Budgets(low: 2000, moderate: 3000, high: 4400)
        XCTAssertEqual(budgets.help(in: Locale(identifier: "it")),
                       "Facile fino a 2.000 PE, Media fino a 3.000 PE, Difficile fino a 4.400 PE.")
        XCTAssertEqual(budgets.help(in: Locale(identifier: "en")),
                       "Low up to 2,000 XP, Moderate up to 3,000 XP, High up to 4,400 XP.")
    }

    // MARK: The bands

    func testEachBandIsTheBooksInEveryLanguageAndBeyondHighIsOurs() {
        // `docs/terminology.md`: the SRD 5.2.1 table's header forms, and Beyond High as chosen.
        let bands: [String: [String]] = [
            "en": ["Low", "Moderate", "High", "Beyond High"],
            "it": ["Facile", "Media", "Difficile", "Fuori scala"],
            "de": ["Niedrig", "Mittel", "Hoch", "Über Hoch"],
            "fr": ["Faible", "Modérée", "Élevée", "Hors barème"],
            "es": ["Baja", "Moderada", "Alta", "Fuera de escala"],
            "pt-BR": ["Baixa", "Moderada", "Alta", "Fora da escala"],
            "el": ["Low", "Moderate", "High", "Beyond High"],
        ]
        for (language, titles) in bands {
            XCTAssertEqual(EncounterDifficulty.Band.allCases.map { $0.title(in: Locale(identifier: language)) },
                           titles, language)
        }
    }

    func testGreekKeepsTheBandsAndXPInEnglishAroundAGreekNumber() {
        XCTAssertEqual(label(.low, 650, "el"), "Low · 650 XP")
        XCTAssertEqual(label(.beyondHigh, 2400, "el"), "Beyond High · 2.400 XP")
    }
}
