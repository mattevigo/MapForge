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
        let encounterDifficulty = EncounterDifficulty(
            levels: [], challengeRatings: [ChallengeRating("4")!, ChallengeRating("3")!])
        XCTAssertEqual(encounterDifficulty.creatureXPLabel(in: Locale(identifier: "en")), "1,800 XP")
        XCTAssertEqual(encounterDifficulty.creatureXPLabel(in: Locale(identifier: "it")), "1.800 PE")
        XCTAssertEqual(encounterDifficulty.creatureXPLabel(in: Locale(identifier: "es")), "1800 PX")
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

    // MARK: The Pawns not counted

    private func reading(creatures: Int, players: Int) -> EncounterDifficultyReading {
        let uncounted = Array(repeating: UncountedPawn.Reason.noMonster, count: creatures)
            + Array(repeating: UncountedPawn.Reason.noCharacter, count: players)
        return EncounterDifficultyReading(
            encounterDifficulty: nil,
            uncounted: uncounted.map { UncountedPawn(id: UUID(), label: "GG", reason: $0) })
    }

    private func note(creatures: Int, players: Int, _ language: String) -> String? {
        reading(creatures: creatures, players: players).uncountedNote(in: Locale(identifier: language))
    }

    func testTheNoteAgreesWithItsCountsInItalian() {
        XCTAssertEqual(note(creatures: 1, players: 0, "it"), "1 creatura non contata")
        XCTAssertEqual(note(creatures: 2, players: 0, "it"), "2 creature non contate")
        XCTAssertEqual(note(creatures: 0, players: 1, "it"), "1 giocatore non contato")
        XCTAssertEqual(note(creatures: 0, players: 3, "it"), "3 giocatori non contati")
        XCTAssertEqual(note(creatures: 2, players: 1, "it"), "2 creature, 1 giocatore non contati")
    }

    func testTheNoteCountsEachSideInItsOwnPluralInEveryLanguage() {
        let both: [String: String] = [
            "en": "1 Creature, 2 Players not counted",
            "de": "1 Kreatur, 2 Spieler nicht gezählt",
            "fr": "1 créature, 2 joueurs non comptés",
            "es": "1 criatura, 2 jugadores no contados",
            "pt-BR": "1 criatura, 2 jogadores não contados",
            "el": "1 πλάσμα, 2 παίκτες δεν μετρήθηκαν",
        ]
        for (language, text) in both {
            XCTAssertEqual(note(creatures: 1, players: 2, language), text, language)
        }
    }

    func testEveryReasonIsTranslatedInEveryLanguage() {
        // Greek included: only the mechanics stay English there, and every reason has Greek
        // words around them.
        let reasons: [UncountedPawn.Reason] = [
            .noMonster, .monsterNotInBestiary(monsterName: "Ogre"),
            .challengeRatingNotCounted("10 (13 in lair)"), .challengeRatingNotCounted(nil),
            .noCharacter, .characterGone, .noNote, .noteNotFound(noteName: "Brom"),
            .levelNotCounted("Guerriero 3"), .levelNotCounted(nil),
        ]
        let english = reasons.map { $0.title(in: Locale(identifier: "en")) }
        for language in ["it", "de", "fr", "es", "pt-BR", "el"] {
            let translated = reasons.map { $0.title(in: Locale(identifier: language)) }
            for (index, text) in translated.enumerated() {
                XCTAssertNotEqual(text, english[index], "\(language): \(english[index])")
            }
        }
    }

    func testTheHoverReadsInItalian() {
        let reading = EncounterDifficultyReading(encounterDifficulty: nil, uncounted: [
            UncountedPawn(id: UUID(), label: "GG3", reason: .challengeRatingNotCounted("14 (15 in tana)")),
            UncountedPawn(id: UUID(), label: "Durga", reason: .levelNotCounted(nil)),
        ])
        XCTAssertEqual(reading.uncountedHelp(in: Locale(identifier: "it")),
                       "GG3: il grado di sfida “14 (15 in tana)” non si può contare\nDurga: la nota non indica il livello")
    }

    func testGreekKeepsTheBandsAndXPInEnglishAroundAGreekNumber() {
        XCTAssertEqual(label(.low, 650, "el"), "Low · 650 XP")
        XCTAssertEqual(label(.beyondHigh, 2400, "el"), "Beyond High · 2.400 XP")
    }
}
