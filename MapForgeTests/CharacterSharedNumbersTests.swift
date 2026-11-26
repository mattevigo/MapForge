import AppKit
import XCTest
@testable import MapForge

/// A Character with a note carries its current and temporary hit points and its exhaustion,
/// and every Player Pawn stamped from it shares them on every Map (ADR-0037).
///
/// Outside a fight only: the Encounter's folded blocks stay authoritative for its Combatants.
@MainActor
final class CharacterSharedNumbersTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    /// Durga as her note writes her.
    private let durgaNote = CharacterNote(name: "Durga Pietraferma", armorClass: 14, maxHP: 48,
                                          initiativeBonus: -1)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CharacterSharedNumbersTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "CharacterSharedNumbersTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeAppState() -> AppState {
        AppState(preferences: DisplayPreferences(defaults: defaults),
                 fogStore: FogStore(),
                 partyStore: PartyStore(directory: directory))
    }

    /// An app with Durga in the active Party, her note read.
    private func makeAppStateWithDurga(noteName: String? = "Durga Pietraferma")
        -> (AppState, PartyCharacter) {
        let app = makeAppState()
        app.characterNotes = CharacterNotes(notes: [durgaNote])
        app.addParty(named: "Eroi")
        let durga = PartyCharacter(name: "Durga", noteName: noteName)
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

    private func hitPoints(of pawn: Pawn, in app: AppState) -> [Int?] {
        let block = app.statBlock(for: pawn.id)
        return [block.currentHP, block.maxHP]
    }

    // MARK: Across Maps

    func testAWoundOnOneMapIsCarriedToEveryOtherAndIntoTheNextStamp() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("street", in: app)
        let onTheStreet = try stamp(durga, in: app)
        try openMap("cellar", in: app)
        let inTheCellar = try stamp(durga, in: app)

        app.editStatBlock(for: inTheCellar.id) { $0.currentHP = 12 }

        try openMap("street", in: app)
        XCTAssertEqual(hitPoints(of: onTheStreet, in: app), [12, 48])
        let stampedAgain = try stamp(durga, in: app, at: CGPoint(x: 200, y: 80))
        XCTAssertEqual(hitPoints(of: stampedAgain, in: app), [12, 48])
    }

    // MARK: On one Map

    func testHealingOneOfTwoPawnsOfACharacterHealsTheOther() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let first = try stamp(durga, in: app)
        let second = try stamp(durga, in: app, at: CGPoint(x: 200, y: 80))
        app.editStatBlock(for: first.id) { $0.currentHP = 12 }

        app.editStatBlock(for: second.id) { $0.currentHP = 30; $0.temporaryHP = 5; $0.exhaustion = 2 }

        let other = app.statBlock(for: first.id)
        XCTAssertEqual([other.currentHP, other.maxHP], [30, 48])
        XCTAssertEqual(other.temporaryHP, 5)
        XCTAssertEqual(other.exhaustion, 2)
    }

    func testConditionsAndConcentrationStayWithThePawnTheyWereSetOn() throws {
        // Prone in the cellar means nothing on the street; they belong to the place and the
        // fight the Pawn is in.
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let first = try stamp(durga, in: app)
        let second = try stamp(durga, in: app, at: CGPoint(x: 200, y: 80))

        app.editStatBlock(for: first.id) {
            $0.conditions = [.prone]
            $0.isConcentrating = true
        }

        XCTAssertEqual(app.statBlock(for: second.id).conditions, [])
        XCTAssertFalse(app.statBlock(for: second.id).isConcentrating)
        XCTAssertEqual(app.statBlock(for: first.id).conditions, [.prone])
    }

    /// What the Player Display draws under the Pawn the DM did not touch.
    func testAHealthBarFollowsAWoundDealtThroughTheCharactersOtherPawn() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let first = try stamp(durga, in: app)
        let second = try stamp(durga, in: app, at: CGPoint(x: 200, y: 80))
        XCTAssertEqual(app.playerHealthBars[second.id]?.tier, .healthy, "precondition")

        app.editStatBlock(for: first.id) { $0.currentHP = 12 }

        XCTAssertEqual(app.playerHealthBars[second.id]?.fill, 0.25)
        XCTAssertEqual(app.playerHealthBars[second.id]?.tier, .critical)
    }

    // MARK: Who does not share

    func testACharacterWithNoNoteStampsAndEditsAsBefore() throws {
        let (app, thorin) = makeAppStateWithDurga(noteName: nil)
        try openMap("cellar", in: app)
        let first = try stamp(thorin, in: app)
        let second = try stamp(thorin, in: app, at: CGPoint(x: 200, y: 80))
        XCTAssertNil(app.statsDocument.blocks[first.id], "a Character with no note stamps no numbers")

        app.setStatBlock(StatBlock(currentHP: 20, maxHP: 30), for: first.id)
        app.setStatBlock(StatBlock(currentHP: 30, maxHP: 30), for: second.id)
        app.editStatBlock(for: first.id) { $0.currentHP = 5 }

        XCTAssertEqual(hitPoints(of: first, in: app), [5, 30])
        XCTAssertEqual(hitPoints(of: second, in: app), [30, 30])
        XCTAssertNil(app.character(id: thorin.id)?.sharedNumbers.currentHP, "the Character took a wound")
    }

    func testACharacterWhoseNoteCannotBeFoundStampsAndEditsAsBefore() throws {
        let (app, durga) = makeAppStateWithDurga(noteName: "Durga la Pietraferma")
        try openMap("cellar", in: app)
        let first = try stamp(durga, in: app)
        let second = try stamp(durga, in: app, at: CGPoint(x: 200, y: 80))
        XCTAssertNil(app.statsDocument.blocks[first.id], "a Character whose note is gone stamps no numbers")

        app.setStatBlock(StatBlock(currentHP: 48, maxHP: 48), for: first.id)
        app.setStatBlock(StatBlock(currentHP: 48, maxHP: 48), for: second.id)
        app.editStatBlock(for: first.id) { $0.currentHP = 12 }

        XCTAssertEqual(hitPoints(of: second, in: app), [48, 48])
        XCTAssertNil(app.character(id: durga.id)?.sharedNumbers.currentHP, "the Character took a wound")
    }

    func testAStampedPawnTheDMMadeACreatureKeepsItsOwnNumbers() throws {
        // Its `characterID` outlives the kind it was made for, and the hero's wounds are not
        // the monster's.
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let hero = try stamp(durga, in: app)
        let impostor = try stamp(durga, in: app, at: CGPoint(x: 200, y: 80))
        let index = try XCTUnwrap(app.fog.pawns.firstIndex { $0.id == impostor.id })
        app.fog.pawns[index].kind = .creature

        app.editStatBlock(for: impostor.id) { $0.currentHP = 3 }

        XCTAssertEqual(hitPoints(of: hero, in: app), [48, 48])
        XCTAssertEqual(hitPoints(of: impostor, in: app), [3, 48])
    }

    // MARK: A Character gone

    func testDeletingTheCharacterLeavesEachPawnAtTheNumbersItLastShowed() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("street", in: app)
        let onTheStreet = try stamp(durga, in: app)
        try openMap("cellar", in: app)
        let inTheCellar = try stamp(durga, in: app)
        app.editStatBlock(for: inTheCellar.id) { $0.currentHP = 12 }
        try openMap("street", in: app)
        XCTAssertEqual(hitPoints(of: onTheStreet, in: app), [12, 48], "precondition")
        app.editStatBlock(for: onTheStreet.id) { $0.currentHP = 20 }
        try openMap("cellar", in: app)
        XCTAssertEqual(hitPoints(of: inTheCellar, in: app), [20, 48], "precondition")

        app.deleteCharacter(id: durga.id)

        XCTAssertEqual(hitPoints(of: inTheCellar, in: app), [20, 48])
        try openMap("street", in: app)
        XCTAssertEqual(hitPoints(of: onTheStreet, in: app), [20, 48])
    }

    // MARK: Before this existed

    func testARosterWrittenBeforeSharedNumbersReadsAtFullAndIsLeftAlone() throws {
        let durgaID = UUID()
        let written = Data("""
        {
          "parties" : [
            {
              "characters" : [
                {
                  "colorHex" : "#C81E1E",
                  "id" : "\(durgaID.uuidString)",
                  "name" : "Durga",
                  "noteName" : "Durga Pietraferma",
                  "sightSquares" : 6
                }
              ],
              "id" : "\(UUID().uuidString)",
              "name" : "Eroi"
            }
          ],
          "version" : 1
        }
        """.utf8)
        let file = PartyStore(directory: directory).fileURL
        try written.write(to: file)

        let app = makeAppState()
        app.characterNotes = CharacterNotes(notes: [durgaNote])
        let durga = try XCTUnwrap(app.character(id: durgaID))
        try openMap("cellar", in: app)
        let pawn = try stamp(durga, in: app)

        XCTAssertEqual(hitPoints(of: pawn, in: app), [48, 48])
        XCTAssertEqual(app.statBlock(for: pawn.id).temporaryHP, 0)
        XCTAssertEqual(app.statBlock(for: pawn.id).exhaustion, 0)
        XCTAssertEqual(try Data(contentsOf: file), written, "rewritten though nothing changed")

        app.editStatBlock(for: pawn.id) { $0.currentHP = 12 }

        let reread = PartyStore(directory: directory).load()
        XCTAssertEqual(reread.parties.first?.characters.first?.sharedNumbers.currentHP, 12)
    }

    // MARK: The Character editor

    func testSavingTheCharacterEditorDoesNotUndoAWoundDealtSinceItOpened() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let pawn = try stamp(durga, in: app)
        var edited = try XCTUnwrap(app.character(id: durga.id))   // the editor's copy

        app.editStatBlock(for: pawn.id) { $0.currentHP = 12 }
        edited.name = "Durga la Rossa"
        app.updateCharacter(edited)

        XCTAssertEqual(hitPoints(of: pawn, in: app), [12, 48])
        XCTAssertEqual(app.character(id: durga.id)?.name, "Durga la Rossa")
    }
}
