import XCTest
@testable import MapForge

/// The Encounter Difficulty of the fight the DM has framed, read through the Pawns' advisory
/// references each time it is asked for (ADR-0032): a Creature's Challenge Rating through its
/// Monster, a Player's level through its Character's note.
@MainActor
final class EncounterDifficultyAppStateTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let goblin = Monster(name: "Goblin", challengeRating: "1/4")
    private let boss = Monster(name: "Capo Goblin", challengeRating: "2")
    private let lair = Monster(name: "Drago Nero Adulto", challengeRating: "14 (15 in lair)")

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EncounterDifficultyAppStateTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "MapForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// A Workspace whose notes are read: the goblins in the Bestiary, and Durga, a level-3
    /// Character linked to her note, in the active Party.
    private func makeAppState() throws -> (AppState, PartyCharacter) {
        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory))
        state.beginEvening(in: directory)
        state.mapURL = directory.appendingPathComponent("dungeon.png")
        state.bestiary = Bestiary(monsters: [boss, lair, goblin])
        state.characterNotes = CharacterNotes(notes: [CharacterNote(name: "Durga Pietraferma",
                                                                    level: "3")])
        state.addParty(named: "Lost Boys")
        state.addCharacter(PartyCharacter(name: "Durga", noteName: "Durga Pietraferma"))
        return (state, try XCTUnwrap(state.activeParty?.characters.first))
    }

    private func player(_ character: PartyCharacter?, monsterName: String? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 10), label: "Durga", colorHex: "#FF0000",
             brightSquares: 6, kind: .player, characterID: character?.id, monsterName: monsterName)
    }

    private func creature(_ monster: Monster?, characterID: UUID? = nil) -> Pawn {
        Pawn(at: MapPoint(x: 100, y: 100), label: monster?.name ?? "?", colorHex: "#C81E1E",
             brightSquares: 6, kind: .creature, characterID: characterID,
             monsterName: monster?.name)
    }

    /// The spec's example: four level-3 Players — Durga Stamped four times, since the Pawn
    /// is the unit — against four goblins and their boss.
    private func specsFight(_ durga: PartyCharacter) -> [Pawn] {
        (0..<4).map { _ in player(durga) } + (0..<4).map { _ in creature(goblin) } + [creature(boss)]
    }

    // MARK: The fight before Play

    func testTheFightTickedInIsRated() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga)

        let encounterDifficulty = try XCTUnwrap(state.encounterDifficultyReading.encounterDifficulty)
        XCTAssertEqual(encounterDifficulty.creatureXP, 650)
        XCTAssertEqual(encounterDifficulty.budgets,
                       EncounterDifficulty.Budgets(low: 600, moderate: 900, high: 1_600))
        XCTAssertEqual(encounterDifficulty.band, .moderate)
    }

    func testATreasureAnUntickedCreatureAndACreatureWithNoMonsterChangeNothing() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga)
        let before = state.encounterDifficultyReading.encounterDifficulty

        let chest = Pawn(at: MapPoint(x: 5, y: 5), label: "Chest", colorHex: "#FFD700",
                         brightSquares: 0, kind: .treasure, monsterName: boss.name)
        let unticked = creature(boss)
        let byHand = creature(nil)
        state.fog.pawns += [chest, unticked, byHand]
        state.setInCombat(false, for: unticked.id)

        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty, before)
    }

    func testUntickingACountedCreatureLowersTheTotalAtOnce() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga)
        let theBoss = try XCTUnwrap(state.fog.pawns.last)

        state.setInCombat(false, for: theBoss.id)

        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.creatureXP, 200)
        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.band, .low)
    }

    func testACreatureWhoseChallengeRatingCannotBeReadIsLeftOut() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga) + [creature(lair)]
        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.creatureXP, 650)
    }

    func testAPlayerWithNoCountedLevelGivesNoBudget() throws {
        let (state, durga) = try makeAppState()
        var unlinked = PartyCharacter(name: "Brom")
        state.addCharacter(unlinked)
        unlinked = try XCTUnwrap(state.activeParty?.characters.first { $0.name == "Brom" })
        state.fog.pawns = [player(durga), player(unlinked), player(nil), creature(goblin)]

        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.budgets,
                       EncounterDifficulty.Budgets(low: 150, moderate: 225, high: 400),
                       "Durga's alone: Brom has no note, and the third Player no Character")
    }

    func testEachPawnCountsOnlyAsItsKind() throws {
        // A link outlives the kind it was made for, as `modifierSource(for:)` knows: a
        // Stamped Pawn the DM made a Creature keeps its Character, and is not a Player for it.
        let (state, durga) = try makeAppState()
        state.fog.pawns = [player(durga, monsterName: boss.name),
                           creature(goblin, characterID: durga.id)]

        let encounterDifficulty = try XCTUnwrap(state.encounterDifficultyReading.encounterDifficulty)
        XCTAssertEqual(encounterDifficulty.creatureXP, 50)
        XCTAssertEqual(encounterDifficulty.budgets?.low, 150)
    }

    // MARK: Read live

    func testALevelWrittenInTheNotesReachesThePawnsAlreadyPlaced() throws {
        // Nothing is copied at the Stamp, so the evening a Character levels up in the notes
        // is the evening the budgets follow.
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga)

        state.characterNotes = CharacterNotes(notes: [CharacterNote(name: "Durga Pietraferma",
                                                                    level: "5")])

        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.budgets?.low, 2_000)
    }

    func testAMonsterThatLeftTheNotesTakesItsXPWithIt() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga)

        state.bestiary = Bestiary(monsters: [goblin])

        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.creatureXP, 200)
    }

    // MARK: Uncounted Pawns, named

    func testACreatureWithNoMonsterIsUncounted() throws {
        let (state, durga) = try makeAppState()
        let byHand = creature(nil)
        state.fog.pawns = specsFight(durga) + [byHand]

        XCTAssertEqual(state.encounterDifficultyReading.uncounted,
                       [UncountedPawn(id: byHand.id, label: byHand.label, reason: .noMonster)])
    }

    func testACreatureWhoseMonsterLeftTheBestiaryIsUncounted() throws {
        let (state, durga) = try makeAppState()
        let ogre = creature(Monster(name: "Ogre", challengeRating: "2"))
        state.fog.pawns = specsFight(durga) + [ogre]

        XCTAssertEqual(state.encounterDifficultyReading.uncounted.map(\.reason),
                       [.monsterNotInBestiary(monsterName: "Ogre")])
    }

    func testAChallengeRatingThatCannotBeReadIsQuoted() throws {
        let (state, durga) = try makeAppState()
        let dragon = Monster(name: "Drago Blu Adulto", challengeRating: "10 (13 in lair)")
        state.bestiary = Bestiary(monsters: [boss, goblin, dragon])
        state.fog.pawns = specsFight(durga) + [creature(dragon)]

        XCTAssertEqual(state.encounterDifficultyReading.uncounted.map(\.reason),
                       [.challengeRatingNotCounted("10 (13 in lair)")])
    }

    func testAMonsterWithNoChallengeRatingIsUncounted() throws {
        let (state, durga) = try makeAppState()
        let guardsman = Monster(name: "Guardia Cittadina")
        state.bestiary = Bestiary(monsters: [boss, goblin, guardsman])
        state.fog.pawns = specsFight(durga) + [creature(guardsman)]

        XCTAssertEqual(state.encounterDifficultyReading.uncounted.map(\.reason),
                       [.challengeRatingNotCounted(nil)])
    }

    func testAPlayerWithNoCharacterIsUncounted() throws {
        let (state, durga) = try makeAppState()
        let byHand = player(nil)
        state.fog.pawns = specsFight(durga) + [byHand]

        XCTAssertEqual(state.encounterDifficultyReading.uncounted,
                       [UncountedPawn(id: byHand.id, label: "Durga", reason: .noCharacter)])
    }

    func testAPlayerWhoseCharacterNoLongerExistsIsUncounted() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga) + [player(PartyCharacter(name: "Brom"))]

        XCTAssertEqual(state.encounterDifficultyReading.uncounted.map(\.reason), [.characterGone])
    }

    func testAPlayerWhoseCharacterHasNoNoteIsUncounted() throws {
        let (state, durga) = try makeAppState()
        state.addCharacter(PartyCharacter(name: "Brom"))
        let brom = try XCTUnwrap(state.activeParty?.characters.first { $0.name == "Brom" })
        state.fog.pawns = specsFight(durga) + [player(brom)]

        XCTAssertEqual(state.encounterDifficultyReading.uncounted.map(\.reason), [.noNote])
    }

    func testAPlayerWhoseNoteCannotBeFoundIsUncounted() throws {
        let (state, durga) = try makeAppState()
        state.addCharacter(PartyCharacter(name: "Brom", noteName: "Brom Mezzelfo"))
        let brom = try XCTUnwrap(state.activeParty?.characters.first { $0.name == "Brom" })
        state.fog.pawns = specsFight(durga) + [player(brom)]

        XCTAssertEqual(state.encounterDifficultyReading.uncounted.map(\.reason),
                       [.noteNotFound(noteName: "Brom Mezzelfo")])
    }

    func testALevelThatCannotBeReadIsQuoted() throws {
        let (state, durga) = try makeAppState()
        state.characterNotes = CharacterNotes(notes: [CharacterNote(name: "Durga Pietraferma",
                                                                    level: "Guerriero 3")])
        state.fog.pawns = [player(durga), creature(goblin)]

        XCTAssertEqual(state.encounterDifficultyReading.uncounted.map(\.reason),
                       [.levelNotCounted("Guerriero 3")])
    }

    func testANoteWithNoLevelIsUncounted() throws {
        let (state, durga) = try makeAppState()
        state.characterNotes = CharacterNotes(notes: [CharacterNote(name: "Durga Pietraferma")])
        state.fog.pawns = [player(durga), creature(goblin)]

        XCTAssertEqual(state.encounterDifficultyReading.uncounted.map(\.reason),
                       [.levelNotCounted(nil)])
    }

    func testUncountedPawnsNeverChangeTheTotalsOrTheBudgets() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga)
        let before = state.encounterDifficultyReading.encounterDifficulty

        state.fog.pawns += [creature(nil), creature(lair), player(nil),
                            player(PartyCharacter(name: "Brom"))]

        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty, before)
        XCTAssertEqual(state.encounterDifficultyReading.uncounted.count, 4)
    }

    func testATreasureIsNeverUncounted() throws {
        let (state, durga) = try makeAppState()
        let chest = Pawn(at: MapPoint(x: 5, y: 5), label: "Chest", colorHex: "#FFD700",
                         brightSquares: 0, kind: .treasure)
        state.fog.pawns = specsFight(durga) + [chest]

        XCTAssertEqual(state.encounterDifficultyReading(of: state.fog.pawns).uncounted, [],
                       "Not even when handed one: a Treasure has no numbers to miss")
    }

    func testWithNoCountedPlayerTheCreaturesXPIsGivenWithNoBand() throws {
        let (state, _) = try makeAppState()
        let byHand = player(nil)
        state.fog.pawns = [creature(boss), creature(goblin), creature(goblin), byHand]

        let reading = state.encounterDifficultyReading
        XCTAssertEqual(reading.encounterDifficulty?.creatureXP, 550)
        XCTAssertNil(reading.encounterDifficulty?.budgets)
        XCTAssertNil(reading.encounterDifficulty?.band)
        XCTAssertEqual(reading.uncounted.map(\.id), [byHand.id])
    }

    func testWithNoCountedCreatureNothingIsRatedThoughSomeAreUncounted() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = [player(durga), creature(nil), creature(lair)]

        XCTAssertNil(state.encounterDifficultyReading.encounterDifficulty)
        XCTAssertEqual(state.encounterDifficultyReading.uncounted.count, 2)
    }

    // MARK: The fight while it runs

    func testBenchingACountedCreatureLowersTheTotalByItsXP() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga)
        let theBoss = try XCTUnwrap(state.fog.pawns.last)
        state.startEncounter()
        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.creatureXP, 650)

        state.benchCombatant(theBoss.id)

        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.creatureXP, 200, "650 less the boss's 450")
    }

    func testABenchedCreatureReturningToTheOrderRestoresTheTotal() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga)
        let theBoss = try XCTUnwrap(state.fog.pawns.last)
        state.startEncounter()
        state.benchCombatant(theBoss.id)

        state.unbenchCombatant(theBoss.id)

        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.creatureXP, 650)
    }

    func testAPawnJoiningMidFightCountsThoughItWasNeverTickedIn() throws {
        // A summon, or the barkeep who picks a side: the Order is the fight now, not the roster.
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga)
        let theBoss = try XCTUnwrap(state.fog.pawns.last)
        state.setInCombat(false, for: theBoss.id)
        state.startEncounter()
        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.creatureXP, 200)

        state.unbenchCombatant(theBoss.id)

        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.creatureXP, 650)
    }

    func testBenchingACountedPlayerLowersEachBudgetByThatPlayersShare() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga)
        let aDurga = try XCTUnwrap(state.fog.pawns.first)
        state.startEncounter()

        state.benchCombatant(aDurga.id)

        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.budgets,
                       EncounterDifficulty.Budgets(low: 450, moderate: 675, high: 1_200),
                       "Four level-3 budgets less one: 150, 225 and 400 each")
        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.creatureXP, 650, "the Creatures are untouched")
    }

    func testOnceTheEncounterStopsTheTickedInRosterIsRatedAgain() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga)
        let theBoss = try XCTUnwrap(state.fog.pawns.last)
        state.setInCombat(false, for: theBoss.id)
        state.startEncounter()
        state.unbenchCombatant(theBoss.id)

        state.stopEncounter()

        XCTAssertEqual(state.encounterDifficultyReading.encounterDifficulty?.creatureXP, 200,
                       "the boss joined the fight, not the roster")
    }

    func testRatingARunningFightWritesNothingToItsLog() throws {
        // Reference, never state (ADR-0032): the Combat Log never mentions it.
        let (state, durga) = try makeAppState()
        state.fog.pawns = specsFight(durga)
        state.startEncounter()
        let lines = state.encounter?.lines

        _ = state.encounterDifficultyReading.encounterDifficulty
        state.endTurn()
        _ = state.encounterDifficultyReading.encounterDifficulty

        let ended = try XCTUnwrap(state.encounter?.lines)
        XCTAssertEqual(ended.count, (lines?.count ?? 0) + 1, "only the Turn's own line")
    }

    // MARK: Nothing to rate

    func testWithNoCountedCreatureNothingIsRated() throws {
        let (state, durga) = try makeAppState()
        state.fog.pawns = [player(durga), creature(nil), creature(lair)]
        XCTAssertNil(state.encounterDifficultyReading.encounterDifficulty)
    }
}
