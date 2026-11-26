import AppKit
import XCTest
@testable import MapForge

/// A Long Rest granted to the active Party, as the Party panel asks for it: it reaches every
/// Pawn sharing a rested Character's numbers, on this Map and the next, and is refused while a
/// fight runs on the open Map (ADR-0037).
@MainActor
final class LongRestAppStateTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let durgaNote = CharacterNote(name: "Durga Pietraferma", armorClass: 14, maxHP: 48,
                                          initiativeBonus: -1)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LongRestAppStateTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "LongRestAppStateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// An evening under way, with Durga in the active Party and her note read.
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

    private func hitPoints(of pawn: Pawn, in app: AppState) -> [Int?] {
        let block = app.statBlock(for: pawn.id)
        return [block.currentHP, block.maxHP]
    }

    // MARK: Reaching every Pawn

    func testALongRestReachesTheCharactersPawnOnThisMapAndOnTheNext() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("street", in: app)
        let onTheStreet = try stamp(durga, in: app)
        try openMap("cellar", in: app)
        let inTheCellar = try stamp(durga, in: app)
        app.editStatBlock(for: inTheCellar.id) { $0.currentHP = 12; $0.exhaustion = 2 }

        XCTAssertNotNil(app.takeLongRest())

        XCTAssertEqual(hitPoints(of: inTheCellar, in: app), [48, 48])
        XCTAssertEqual(app.statBlock(for: inTheCellar.id).exhaustion, 1)
        try openMap("street", in: app)
        XCTAssertEqual(hitPoints(of: onTheStreet, in: app), [48, 48])
    }

    // MARK: Refused mid-fight

    func testALongRestIsRefusedWhileAFightRunsOnTheOpenMap() throws {
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let inTheCellar = try stamp(durga, in: app)
        app.editStatBlock(for: inTheCellar.id) { $0.currentHP = 12; $0.exhaustion = 2 }
        app.startEncounter()
        XCTAssertNotNil(app.encounter)

        XCTAssertEqual(app.longRestRefusal, "Nobody long-rests mid-fight.")
        XCTAssertNil(app.takeLongRest())

        XCTAssertEqual(hitPoints(of: inTheCellar, in: app), [12, 48])
        let stored = try XCTUnwrap(app.character(id: durga.id))
        XCTAssertEqual([stored.currentHP, stored.exhaustion], [12, 2])
    }

    func testAFightPausedOnAnotherMapDoesNotRefuseALongRest() throws {
        // That fight meets the rested party when it resumes.
        let (app, durga) = makeAppStateWithDurga()
        try openMap("cellar", in: app)
        let inTheCellar = try stamp(durga, in: app)
        app.editStatBlock(for: inTheCellar.id) { $0.currentHP = 12 }
        app.startEncounter()
        try openMap("street", in: app)
        XCTAssertNil(app.encounter)

        XCTAssertNil(app.longRestRefusal)
        XCTAssertNotNil(app.takeLongRest())

        let stored = try XCTUnwrap(app.character(id: durga.id))
        XCTAssertEqual(stored.sharedNumbers(over: StatBlock(), maxHP: 48).currentHP, 48)
    }

    // MARK: Only the active Party

    func testAPartyThatIsNotActiveIsNotWokenForIt() throws {
        let (app, durga) = makeAppStateWithDurga()
        let eroi = try XCTUnwrap(app.activeParty)
        try openMap("cellar", in: app)
        let inTheCellar = try stamp(durga, in: app)
        app.editStatBlock(for: inTheCellar.id) { $0.currentHP = 12 }
        app.addParty(named: "Altri")
        let thorin = PartyCharacter(name: "Thorin", noteName: "Durga Pietraferma",
                                    currentHP: 5, exhaustion: 3)
        app.addCharacter(thorin)
        app.setActiveParty(eroi.id)

        app.takeLongRest()

        let stillTired = try XCTUnwrap(app.character(id: thorin.id))
        XCTAssertEqual([stillTired.currentHP, stillTired.exhaustion], [5, 3])
        XCTAssertEqual(hitPoints(of: inTheCellar, in: app), [48, 48])
    }

    func testAPartyAlreadyRestedIsNotAskedAgain() {
        let (app, _) = makeAppStateWithDurga()

        XCTAssertEqual(app.longRestRefusal, "The party is already rested.")
        XCTAssertNil(app.takeLongRest())
    }
}
