import AppKit
import XCTest
@testable import MapForge

/// The Session Log records what the evening does to a Character outside a fight: an edit made
/// through one of its Pawns, and a Long Rest — before and after, never a delta (ADR-0037,
/// `CONTEXT.md`, **Session Log**).
@MainActor
final class CharacterSessionLinesTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let durgaNote = CharacterNote(name: "Durga Pietraferma", armorClass: 14, maxHP: 48,
                                          initiativeBonus: -1)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CharacterSessionLinesTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "CharacterSessionLinesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// An evening under way, with Durga — at 12 of her note's 48 — in the active Party.
    private func makeAppStateWithDurga(sessionRunning: Bool = true) -> (AppState, PartyCharacter) {
        let app = AppState(preferences: DisplayPreferences(defaults: defaults),
                           fogStore: FogStore(),
                           partyStore: PartyStore(directory: directory))
        if sessionRunning {
            app.beginEvening(in: directory)
        } else {
            app.open(Workspace(url: directory))
        }
        app.characterNotes = CharacterNotes(notes: [durgaNote])
        app.addParty(named: "Eroi")
        let durga = PartyCharacter(name: "Durga", noteName: "Durga Pietraferma", sharedNumbers: SharedNumbers(currentHP: 12))
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

    /// The Session Log's Lines about Characters, as they stand on disk.
    private func characterLines(_ app: AppState) throws -> [SessionLine] {
        guard let url = app.sessionLogURL else { return [] }
        return try SessionLogReader().read(at: url).filter {
            switch $0 {
            case .characterChanged, .longRest: true
            default: false
            }
        }
    }

    // MARK: An edit through a Pawn

    func testHealingDurgaBySevenThroughHerPawnWritesOneLineWithHerHitPointsOnly() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("street", in: app)
        let pawn = try stamp(durga, in: app)

        app.editStatBlock(for: pawn.id) { $0.currentHP = 19 }

        let lines = try characterLines(app)
        XCTAssertEqual(lines.count, 1)
        guard case let .characterChanged(numbers, pawnID, label, map, _) = lines.first else {
            return XCTFail("expected a characterChanged Line, got \(lines)")
        }
        XCTAssertEqual(numbers, CharacterNumbersMoved(characterID: durga.id, name: "Durga",
                                                      currentHP: Moved(from: 12, to: 19)))
        XCTAssertEqual(pawnID, pawn.id)
        XCTAssertEqual(label, pawn.label)
        XCTAssertEqual(map, "street.png")
    }

    func testChangingHitPointsAndExhaustionInOneGestureIsOneLineWithBoth() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("street", in: app)
        let pawn = try stamp(durga, in: app)

        app.editStatBlock(for: pawn.id) { $0.currentHP = 5; $0.exhaustion = 1 }

        let lines = try characterLines(app)
        XCTAssertEqual(lines.count, 1)
        guard case let .characterChanged(numbers, _, _, _, _) = lines.first else {
            return XCTFail("expected a characterChanged Line, got \(lines)")
        }
        XCTAssertEqual(numbers, CharacterNumbersMoved(characterID: durga.id, name: "Durga",
                                                      currentHP: Moved(from: 12, to: 5),
                                                      exhaustion: Moved(from: 0, to: 1)))
    }

    func testAnEditThatMovesNoneOfTheSharedNumbersWritesNoLine() throws {
        // Prone and AC are the Pawn's, not the Character's.
        let (app, durga) = makeAppStateWithDurga()
        try openMap("street", in: app)
        let pawn = try stamp(durga, in: app)

        app.editStatBlock(for: pawn.id) { $0.conditions = [.prone]; $0.armorClass = 16 }

        XCTAssertEqual(try characterLines(app), [])
    }

    // MARK: What is not recorded

    func testACreaturesEditWritesNoLine() throws {
        // A Stamped Pawn the DM made a Creature keeps Durga's `characterID`, and its wounds
        // are not hers.
        let (app, durga) = makeAppStateWithDurga()
        try openMap("street", in: app)
        let impostor = try stamp(durga, in: app)
        let index = try XCTUnwrap(app.fog.pawns.firstIndex { $0.id == impostor.id })
        app.fog.pawns[index].kind = .creature

        app.editStatBlock(for: impostor.id) { $0.currentHP = 3 }

        XCTAssertEqual(app.statBlock(for: impostor.id).currentHP, 3, "precondition")
        XCTAssertEqual(try characterLines(app), [])
    }

    func testAPlayerWithNoNoteWritesNoLine() throws {
        let (app, _) = makeAppStateWithDurga()
        let ayla = PartyCharacter(name: "Ayla")
        app.addCharacter(ayla)
        try openMap("street", in: app)
        let pawn = try stamp(ayla, in: app)

        app.editStatBlock(for: pawn.id) { $0.currentHP = 9 }

        XCTAssertEqual(app.statBlock(for: pawn.id).currentHP, 9, "precondition")
        XCTAssertEqual(try characterLines(app), [])
    }

    func testAnEditWithNoSessionRunningIsRecordedNowhere() throws {
        let (app, durga) = makeAppStateWithDurga(sessionRunning: false)
        try openMap("street", in: app)
        let pawn = try stamp(durga, in: app)

        app.editStatBlock(for: pawn.id) { $0.currentHP = 19 }

        XCTAssertEqual(app.character(id: durga.id)?.sharedNumbers.currentHP, 19, "precondition")
        XCTAssertEqual(SessionLogReader().logURLs(in: Workspace(url: directory)), [])
    }

    func testAnEditDuringALiveEncounterWritesNoLine() throws {
        // The Combat Log has it, as a Change.
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let pawn = try stamp(durga, in: app)
        app.startEncounter()

        app.editStatBlock(for: pawn.id) { $0.currentHP = 4 }

        XCTAssertEqual(app.character(id: durga.id)?.sharedNumbers.currentHP, 4, "precondition")
        XCTAssertEqual(try characterLines(app), [])
    }

    func testTheChangesAResumedFightRecordsWriteNoLine() throws {
        // A heal while the fight is paused on another Map: the resumed fight records it as a
        // Change in the Combat Log, and the Session Log stays out of it.
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let inTheCellar = try stamp(durga, in: app)
        app.startEncounter()
        app.editStatBlock(for: inTheCellar.id) { $0.currentHP = 4 }
        app.endTurn()
        try openMap("street", in: app)
        let onTheStreet = try stamp(durga, in: app)
        app.editStatBlock(for: onTheStreet.id) { $0.currentHP = 30 }

        try openMap("cellar", in: app)

        XCTAssertEqual(app.encounter?.pendingChanges,
                       [.hpChanged(combatantID: inTheCellar.id, from: 4, to: 30)], "precondition")
        XCTAssertEqual(try characterLines(app), [])
    }

    func testAnEditAfterTheFightStopsIsRecordedAgain() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let pawn = try stamp(durga, in: app)
        app.startEncounter()
        app.stopEncounter()

        app.editStatBlock(for: pawn.id) { $0.temporaryHP = 5 }

        let lines = try characterLines(app)
        guard case let .characterChanged(numbers, _, _, _, _) = lines.first, lines.count == 1 else {
            return XCTFail("expected one characterChanged Line, got \(lines)")
        }
        XCTAssertEqual(numbers.temporaryHP, Moved(from: 0, to: 5))
    }

    // MARK: A Long Rest

    func testALongRestWritesOneLineListingOnlyTheCharactersItChanged() throws {
        let (app, durga) = makeAppStateWithDurga()
        app.characterNotes = CharacterNotes(notes: [
            durgaNote, CharacterNote(name: "Ayla", maxHP: 30), CharacterNote(name: "Brom", maxHP: 40),
        ])
        let ayla = PartyCharacter(name: "Ayla", noteName: "Ayla", sharedNumbers: SharedNumbers(exhaustion: 2))
        let brom = PartyCharacter(name: "Brom", noteName: "Brom")   // already rested
        let tessa = PartyCharacter(name: "Tessa", sharedNumbers: SharedNumbers(currentHP: 3))     // no note: passed over
        for character in [ayla, brom, tessa] { app.addCharacter(character) }
        let party = try XCTUnwrap(app.activeParty)

        XCTAssertNotNil(app.takeLongRest())

        let lines = try characterLines(app)
        XCTAssertEqual(lines.count, 1, "one Line for the rest, and none for each Character")
        guard case let .longRest(partyID, partyName, characters, _) = lines.first else {
            return XCTFail("expected a longRest Line, got \(lines)")
        }
        XCTAssertEqual(partyID, party.id)
        XCTAssertEqual(partyName, "Eroi")
        XCTAssertEqual(characters, [
            CharacterNumbersMoved(characterID: durga.id, name: "Durga",
                                  currentHP: Moved(from: 12, to: 48)),
            CharacterNumbersMoved(characterID: ayla.id, name: "Ayla",
                                  exhaustion: Moved(from: 2, to: 1)),
        ])
    }

    func testALongRestRefusedWritesNoLine() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        try stamp(durga, in: app)
        app.startEncounter()

        XCTAssertNil(app.takeLongRest(), "precondition: nobody long-rests mid-fight")
        app.stopEncounter()

        XCTAssertEqual(try characterLines(app), [])
    }

    func testALongRestWhileAFightIsPausedOnAnotherMapIsLeftToTheFightsLog() throws {
        // The Session Log is silent from a fight's start to its end, paused or not (ADR-0014):
        // the fight records the rest as Changes when it resumes.
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let inTheCellar = try stamp(durga, in: app)
        app.startEncounter()
        app.endTurn()
        try openMap("street", in: app)

        XCTAssertNotNil(app.takeLongRest(), "precondition: a paused fight does not refuse it")
        try openMap("cellar", in: app)

        XCTAssertEqual(app.encounter?.pendingChanges,
                       [.hpChanged(combatantID: inTheCellar.id, from: 12, to: 48)], "precondition")
        XCTAssertEqual(try characterLines(app), [])
    }
}
