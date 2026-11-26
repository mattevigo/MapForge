import AppKit
import XCTest
@testable import MapForge

/// During an Encounter the Combat Log is authoritative (ADR-0008), and the Character of a
/// sharing Player Pawn follows its fold as it moves; a fight resumed after a pause records
/// what happened to its Players' Characters meanwhile (ADR-0037).
@MainActor
final class CharacterFollowsTheFightTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    /// Durga as her note writes her.
    private let durgaNote = CharacterNote(name: "Durga Pietraferma", armorClass: 14, maxHP: 48,
                                          initiativeBonus: -1)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CharacterFollowsTheFightTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "CharacterFollowsTheFightTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// An evening running, with Durga in the active Party and her note read.
    private func makeAppStateWithDurga() -> (AppState, PartyCharacter) {
        let app = AppState(preferences: DisplayPreferences(defaults: defaults),
                           fogStore: FogStore(),
                           partyStore: PartyStore(directory: directory))
        app.beginEvening(in: directory)
        app.characterNotes = CharacterNotes(notes: [durgaNote])
        app.addParty(named: "Eroi")
        let durga = PartyCharacter(name: "Durga", noteName: "Durga Pietraferma")
        app.addCharacter(durga)
        return (app, durga)
    }

    /// The frame every drop lands in: one image pixel to ten points.
    private let frame = CGRect(x: 0, y: 0, width: 400, height: 300)

    /// Opens the Map named `name`, writing its 40×30 image the first time.
    private func openMap(_ name: String, in app: AppState) throws {
        let url = directory.appendingPathComponent("\(name).png")
        let image = NSImage(size: NSSize(width: 40, height: 30))
        if !FileManager.default.fileExists(atPath: url.path) {
            image.lockFocus()
            NSColor.darkGray.setFill()
            NSRect(x: 0, y: 0, width: 40, height: 30).fill()
            image.unlockFocus()
            let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil,
                                                                 context: nil, hints: nil)!)
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        }
        app.loadMap(image: image, at: url)
    }

    /// Stamps `character` and returns the Pawn it placed.
    @discardableResult
    private func stamp(_ character: PartyCharacter, in app: AppState,
                       at point: CGPoint = CGPoint(x: 100, y: 80)) throws -> Pawn {
        XCTAssertTrue(app.stamp(character, at: point, frame: frame))
        return try XCTUnwrap(app.fog.pawns.last)
    }

    private func currentHP(of character: PartyCharacter, in app: AppState) -> Int? {
        app.character(id: character.id)?.currentHP
    }

    // MARK: The Character follows the fold

    func testAHitInAFightReachesTheCharacterBeforeTheFightStops() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("street", in: app)
        let onTheStreet = try stamp(durga, in: app)
        try openMap("cellar", in: app)
        let inTheCellar = try stamp(durga, in: app)
        app.startEncounter()

        app.editStatBlock(for: inTheCellar.id) { $0.currentHP = 20 }   // hit for 28

        XCTAssertNotNil(app.encounter, "precondition: the fight is still running")
        XCTAssertEqual(currentHP(of: durga, in: app), 20)
        XCTAssertEqual(app.encounter?.blocks[inTheCellar.id]?.currentHP, 20)
        app.flushPendingStatWrites()
        try openMap("street", in: app)
        let shown = app.statBlock(for: onTheStreet.id)
        XCTAssertEqual([shown.currentHP, shown.maxHP], [20, 48])
    }

    func testACorrectionThatReducesAnEarlierHitMovesTheCharacterToTheCorrectedValue() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let pawn = try stamp(durga, in: app)
        app.startEncounter()
        app.editStatBlock(for: pawn.id) { $0.currentHP = 20 }   // hit for 28
        app.endTurn()
        XCTAssertEqual(currentHP(of: durga, in: app), 20, "precondition")

        app.stepBackForCorrection()
        XCTAssertEqual(app.encounter?.isCorrecting, true, "precondition: correcting")
        app.editStatBlock(for: pawn.id) { $0.currentHP = 30 }   // it was only 18

        XCTAssertEqual(app.encounter?.blocks[pawn.id]?.currentHP, 30)
        XCTAssertEqual(currentHP(of: durga, in: app), 30)
    }

    func testTemporaryHitPointsAndExhaustionFollowTheFoldToo() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let pawn = try stamp(durga, in: app)
        app.startEncounter()

        app.editStatBlock(for: pawn.id) { $0.temporaryHP = 8; $0.exhaustion = 1 }

        let character = try XCTUnwrap(app.character(id: durga.id))
        XCTAssertEqual(character.temporaryHP, 8)
        XCTAssertEqual(character.exhaustion, 1)
    }

    // MARK: Two Pawns of one Character

    func testAHitOnOnePawnInAFightBringsTheOtherPawnToTheCharactersNumbersInTheLiveTurn() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let first = try stamp(durga, in: app)
        let second = try stamp(durga, in: app, at: CGPoint(x: 200, y: 80))
        app.startEncounter()

        app.editStatBlock(for: first.id) { $0.currentHP = 20 }   // hit for 28

        let encounter = try XCTUnwrap(app.encounter)
        XCTAssertEqual(encounter.blocks[second.id]?.currentHP, 20)
        XCTAssertEqual(encounter.pendingChanges, [
            .hpChanged(combatantID: first.id, from: 48, to: 20),
            .hpChanged(combatantID: second.id, from: 48, to: 20),
        ], "one follow-up, and no follow-up of the follow-up")
        XCTAssertEqual(currentHP(of: durga, in: app), 20)
    }

    func testACorrectionToOnePawnBringsTheOtherPawnAlongInTheLiveTurn() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let first = try stamp(durga, in: app)
        let second = try stamp(durga, in: app, at: CGPoint(x: 200, y: 80))
        app.startEncounter()
        app.editStatBlock(for: first.id) { $0.currentHP = 20 }   // hit for 28
        app.endTurn()
        XCTAssertEqual(app.encounter?.blocks[second.id]?.currentHP, 20, "precondition")

        app.stepBackForCorrection()
        app.editStatBlock(for: first.id) { $0.currentHP = 30 }   // it was only 18

        let encounter = try XCTUnwrap(app.encounter)
        XCTAssertTrue(encounter.isCorrecting, "precondition: still correcting")
        XCTAssertEqual(encounter.blocks[first.id]?.currentHP, 30)
        XCTAssertEqual(encounter.blocks[second.id]?.currentHP, 30)
        XCTAssertEqual(encounter.pendingChanges,
                       [.hpChanged(combatantID: second.id, from: 20, to: 30)],
                       "the follow-up is what happens now, not a Correction to a past Turn")
        XCTAssertEqual(currentHP(of: durga, in: app), 30)
    }

    func testAnEditToAPawnOutsideTheFightBringsHerPawnInItToTheSameNumbers() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let fighting = try stamp(durga, in: app)
        let watching = try stamp(durga, in: app, at: CGPoint(x: 200, y: 80))
        app.setInCombat(false, for: watching.id)
        app.startEncounter()
        XCTAssertNil(app.encounter?.blocks[watching.id], "precondition: a bystander")

        app.editStatBlock(for: watching.id) { $0.currentHP = 31; $0.exhaustion = 1 }

        let encounter = try XCTUnwrap(app.encounter)
        XCTAssertEqual(encounter.blocks[fighting.id]?.currentHP, 31)
        XCTAssertEqual(encounter.blocks[fighting.id]?.exhaustion, 1)
        XCTAssertEqual(currentHP(of: durga, in: app), 31)
    }

    // MARK: Joining and stopping

    func testAPawnJoiningAFightBringsItsCharactersNumbersIntoTheLog() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("street", in: app)
        let onTheStreet = try stamp(durga, in: app)
        app.editStatBlock(for: onTheStreet.id) { $0.currentHP = 20; $0.temporaryHP = 4 }
        try openMap("cellar", in: app)
        let first = try stamp(durga, in: app)
        app.startEncounter()

        let joining = try stamp(durga, in: app, at: CGPoint(x: 200, y: 80))

        XCTAssertEqual(app.encounter?.blocks[first.id]?.currentHP, 20)
        XCTAssertEqual(app.encounter?.blocks[joining.id]?.currentHP, 20)
        XCTAssertEqual(app.encounter?.blocks[joining.id]?.temporaryHP, 4)
    }

    func testStoppingLeavesTheCharacterAndThePawnsOwnBlockAtTheFightsNumbers() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let pawn = try stamp(durga, in: app)
        app.startEncounter()
        app.editStatBlock(for: pawn.id) { $0.currentHP = 20; $0.conditions = [.prone] }

        app.stopEncounter()

        XCTAssertEqual(currentHP(of: durga, in: app), 20)
        XCTAssertEqual(app.statsDocument.blocks[pawn.id]?.currentHP, 20)
        XCTAssertEqual(app.statsDocument.blocks[pawn.id]?.conditions, [.prone])
        XCTAssertEqual(app.statBlock(for: pawn.id).currentHP, 20)
    }

    func testACombatantWhoseCharacterIsDeletedMidFightFightsOnAsBefore() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let pawn = try stamp(durga, in: app)
        app.startEncounter()
        app.deleteCharacter(id: durga.id)

        app.editStatBlock(for: pawn.id) { $0.currentHP = 20 }
        app.stopEncounter()

        XCTAssertNil(app.character(id: durga.id))
        XCTAssertEqual(app.statBlock(for: pawn.id).currentHP, 20)
    }

    // MARK: A fight paused and resumed

    /// Durga at 20 in the cellar's fight, on disk, and another Map open: the fight paused.
    private func pauseAFightWithDurgaAt20() throws -> (AppState, PartyCharacter, Pawn) {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let inTheCellar = try stamp(durga, in: app)
        app.startEncounter()
        app.editStatBlock(for: inTheCellar.id) { $0.currentHP = 20 }   // hit for 28
        app.endTurn()
        try openMap("street", in: app)
        XCTAssertNil(app.encounter, "precondition: the fight is paused")
        return (app, durga, inTheCellar)
    }

    func testAHealOnAnotherMapWhileTheFightIsPausedIsRecordedWhenItResumes() throws {
        let (app, durga, inTheCellar) = try pauseAFightWithDurgaAt20()
        let onTheStreet = try stamp(durga, in: app)
        XCTAssertEqual(app.statBlock(for: onTheStreet.id).currentHP, 20, "precondition")
        app.editStatBlock(for: onTheStreet.id) { $0.currentHP = 48 }

        try openMap("cellar", in: app)

        let encounter = try XCTUnwrap(app.encounter, "the fight did not resume")
        XCTAssertEqual(encounter.blocks[inTheCellar.id]?.currentHP, 48)
        XCTAssertEqual(encounter.pendingChanges,
                       [.hpChanged(combatantID: inTheCellar.id, from: 20, to: 48)])
        XCTAssertEqual(currentHP(of: durga, in: app), 48)
    }

    func testAPausedFightWhoseCharactersDidNotMoveResumesRecordingNothing() throws {
        let (app, durga, inTheCellar) = try pauseAFightWithDurgaAt20()
        try stamp(durga, in: app)

        try openMap("cellar", in: app)

        let encounter = try XCTUnwrap(app.encounter, "the fight did not resume")
        XCTAssertEqual(encounter.blocks[inTheCellar.id]?.currentHP, 20)
        XCTAssertEqual(encounter.pendingChanges, [])
        XCTAssertEqual(currentHP(of: durga, in: app), 20)
    }

    // MARK: What never reaches the Character

    func testAConditionOrConcentrationInAFightLeavesTheCharactersNumbersUntouched() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let pawn = try stamp(durga, in: app)
        app.startEncounter()
        let before = try XCTUnwrap(app.character(id: durga.id))

        app.editStatBlock(for: pawn.id) {
            $0.conditions = [.prone]
            $0.isConcentrating = true
        }

        XCTAssertEqual(app.encounter?.blocks[pawn.id]?.conditions, [.prone], "precondition")
        XCTAssertEqual(app.character(id: durga.id), before)
    }

    func testACreatureCombatantsChangesNeverTouchACharacter() throws {
        // A Stamped Pawn the DM made a Creature keeps Durga's `characterID`, and its wounds
        // are not hers.
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let impostor = try stamp(durga, in: app)
        let index = try XCTUnwrap(app.fog.pawns.firstIndex { $0.id == impostor.id })
        app.fog.pawns[index].kind = .creature
        app.startEncounter()

        app.editStatBlock(for: impostor.id) { $0.currentHP = 3; $0.exhaustion = 2 }

        XCTAssertEqual(app.encounter?.blocks[impostor.id]?.currentHP, 3, "precondition")
        let character = try XCTUnwrap(app.character(id: durga.id))
        XCTAssertNil(character.currentHP)
        XCTAssertEqual(character.exhaustion, 0)
    }
}
