import XCTest
@testable import MapForge

/// The Encounter Difficulty as the rulebook reckons it (ADR-0032): the Creatures' XP set
/// against the party's three budgets, each a ceiling.
final class EncounterDifficultyTests: XCTestCase {
    private func levels(_ values: Int...) throws -> [CharacterLevel] {
        try values.map { try XCTUnwrap(CharacterLevel(String($0))) }
    }

    private func challengeRatings(_ texts: String...) throws -> [ChallengeRating] {
        try texts.map { try XCTUnwrap(ChallengeRating($0)) }
    }

    // MARK: The reckoning

    func testTheSpecsExampleIsModerate() throws {
        // Four level-3 Players against four goblins and their CR 2 boss.
        let difficulty = EncounterDifficulty(
            levels: try levels(3, 3, 3, 3),
            challengeRatings: try challengeRatings("1/4", "1/4", "1/4", "1/4", "2"))

        XCTAssertEqual(difficulty.creatureXP, 650)
        XCTAssertEqual(difficulty.budgets, EncounterDifficulty.Budgets(low: 600, moderate: 900, high: 1_600))
        XCTAssertEqual(difficulty.band, .moderate)
    }

    // MARK: A budget is a ceiling

    private let party = EncounterDifficulty.Budgets(low: 600, moderate: 900, high: 1_600)

    func testATotalThatSpendsTheWholeLowBudgetIsLow() {
        XCTAssertEqual(EncounterDifficulty.Band(of: 600, within: party), .low)
    }

    func testOneXPOverTheLowBudgetIsModerate() {
        XCTAssertEqual(EncounterDifficulty.Band(of: 601, within: party), .moderate)
    }

    func testATotalThatSpendsTheWholeModerateBudgetIsModerate() {
        XCTAssertEqual(EncounterDifficulty.Band(of: 900, within: party), .moderate)
    }

    func testATotalThatSpendsTheWholeHighBudgetIsHigh() {
        XCTAssertEqual(EncounterDifficulty.Band(of: 1_600, within: party), .high)
    }

    func testOneXPOverTheHighBudgetIsBeyondHigh() {
        XCTAssertEqual(EncounterDifficulty.Band(of: 1_601, within: party), .beyondHigh)
    }

    func testNothingToFightIsStillLowAndNeverBelowIt() throws {
        // There is no band below Low: a fight that spends little of the budget is Low.
        let difficulty = EncounterDifficulty(levels: try levels(3, 3, 3, 3), challengeRatings: [])
        XCTAssertEqual(difficulty.creatureXP, 0)
        XCTAssertEqual(difficulty.band, .low)
    }

    func testThereIsNoMultiplierForHowManyCreaturesThereAre() throws {
        // The 2014 rules multiplied a crowd's XP; the 2024 ones add it up and stop.
        let difficulty = EncounterDifficulty(
            levels: try levels(1),
            challengeRatings: try challengeRatings("1/8", "1/8", "1/8", "1/8"))
        XCTAssertEqual(difficulty.creatureXP, 100)
        XCTAssertEqual(difficulty.band, .high)
    }

    func testWithNoPlayerThereAreNoBudgetsAndNoBand() throws {
        let difficulty = EncounterDifficulty(levels: [], challengeRatings: try challengeRatings("2"))
        XCTAssertEqual(difficulty.creatureXP, 450)
        XCTAssertNil(difficulty.budgets)
        XCTAssertNil(difficulty.band)
    }

    // MARK: Reading a Challenge Rating

    func testAChallengeRatingIsWorthItsXP() {
        XCTAssertEqual(ChallengeRating("0")?.xp, 10, "the rules' default for CR 0 (ADR-0032)")
        XCTAssertEqual(ChallengeRating("1/8")?.xp, 25)
        XCTAssertEqual(ChallengeRating("1/4")?.xp, 50)
        XCTAssertEqual(ChallengeRating("30")?.xp, 155_000)
    }

    func testAChallengeRatingIgnoresTheWhitespaceAroundIt() {
        XCTAssertEqual(ChallengeRating("  1/2 \n")?.xp, 100)
    }

    func testAChallengeRatingTheRulebookDoesNotPrintIsNotCounted() {
        for text in ["31", "10 (13 in lair)", "1/3", "", " ", "-1", "0.25", "CR 2", "02"] {
            XCTAssertNil(ChallengeRating(text), "\"\(text)\"")
        }
        XCTAssertNil(ChallengeRating(nil), "a note with no cr")
    }

    // MARK: Reading a level

    func testALevelCounts() {
        XCTAssertEqual(CharacterLevel("3")?.value, 3)
        XCTAssertEqual(CharacterLevel(" 20 ")?.value, 20)
    }

    func testALevelThatIsNotOneWholeNumberFromOneToTwentyIsNotCounted() {
        for text in ["0", "21", "3/2", "Guerriero 3", "Guerriero 3 / Ladro 2", "+3", "3.0", ""] {
            XCTAssertNil(CharacterLevel(text), "\"\(text)\"")
        }
        XCTAssertNil(CharacterLevel(nil), "a note with no level")
    }

    // MARK: The 2024 tables, as the spec card prints them

    func testEveryChallengeRatingIsWorthWhatTheMonsterManualSays() {
        let table: [(String, Int)] = [
            ("0", 10), ("1/8", 25), ("1/4", 50), ("1/2", 100), ("1", 200), ("2", 450),
            ("3", 700), ("4", 1_100), ("5", 1_800), ("6", 2_300), ("7", 2_900),
            ("8", 3_900), ("9", 5_000), ("10", 5_900), ("11", 7_200), ("12", 8_400),
            ("13", 10_000), ("14", 11_500), ("15", 13_000), ("16", 15_000), ("17", 18_000),
            ("18", 20_000), ("19", 22_000), ("20", 25_000), ("21", 33_000), ("22", 41_000),
            ("23", 50_000), ("24", 62_000), ("25", 75_000), ("26", 90_000), ("27", 105_000),
            ("28", 120_000), ("29", 135_000), ("30", 155_000),
        ]
        XCTAssertEqual(table.count, 34)
        for (text, xp) in table {
            XCTAssertEqual(ChallengeRating(text)?.xp, xp, "CR \(text)")
        }
    }

    func testEveryLevelGivesTheBudgetsTheDungeonMastersGuideSays() {
        let table: [(Int, Int, Int, Int)] = [
            (1, 50, 75, 100), (2, 100, 150, 200), (3, 150, 225, 400), (4, 250, 375, 500),
            (5, 500, 750, 1_100), (6, 600, 1_000, 1_400), (7, 750, 1_300, 1_700),
            (8, 1_000, 1_700, 2_100), (9, 1_300, 2_000, 2_600), (10, 1_600, 2_300, 3_100),
            (11, 1_900, 2_900, 4_100), (12, 2_200, 3_700, 4_700), (13, 2_600, 4_200, 5_400),
            (14, 2_900, 4_900, 6_200), (15, 3_300, 5_400, 7_800), (16, 3_800, 6_100, 9_800),
            (17, 4_500, 7_200, 11_700), (18, 5_000, 8_700, 14_200), (19, 5_500, 10_700, 17_200),
            (20, 6_400, 13_200, 22_000),
        ]
        XCTAssertEqual(table.count, 20)
        for (level, low, moderate, high) in table {
            XCTAssertEqual(CharacterLevel(String(level))?.budgets,
                           EncounterDifficulty.Budgets(low: low, moderate: moderate, high: high),
                           "level \(level)")
        }
    }
}
