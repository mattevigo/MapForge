import AppKit
import XCTest
@testable import MapForge

/// The Party panel's Character rows read the Character's hit points as they stand now: every
/// change to them reaches the row, whichever Pawn made it (ADR-0037).
@MainActor
final class CharacterHitPointsAppStateTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let durgaNote = CharacterNote(name: "Durga Pietraferma", armorClass: 14, maxHP: 48,
                                          initiativeBonus: -1)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CharacterHitPointsAppStateTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "CharacterHitPointsAppStateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// An app with Durga in the active Party, her note read, and a Map open.
    private func makeAppStateWithDurga(noteName: String? = "Durga Pietraferma") throws
        -> (AppState, PartyCharacter) {
        let app = AppState(preferences: DisplayPreferences(defaults: defaults),
                           fogStore: FogStore(),
                           partyStore: PartyStore(directory: directory))
        app.characterNotes = CharacterNotes(notes: [durgaNote])
        app.addParty(named: "Eroi")
        let durga = PartyCharacter(name: "Durga", noteName: noteName)
        app.addCharacter(durga)

        let url = directory.appendingPathComponent("cellar.png")
        let image = NSImage(size: NSSize(width: 40, height: 30))
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 30).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil,
                                                             context: nil, hints: nil)!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        app.loadMap(image: image, at: url)
        return (app, durga)
    }

    private let frame = CGRect(x: 0, y: 0, width: 400, height: 300)

    func testEditingDurgaThroughOneOfHerPawnsUpdatesHerRow() throws {
        let (app, durga) = try makeAppStateWithDurga()
        XCTAssertTrue(app.stamp(durga, at: CGPoint(x: 100, y: 80), frame: frame))
        let pawn = try XCTUnwrap(app.fog.pawns.last)

        app.editStatBlock(for: pawn.id) { $0.currentHP = 24; $0.temporaryHP = 5; $0.exhaustion = 2 }

        // The copy the panel was drawn from before the edit: the row reads the roster's.
        let shown = try XCTUnwrap(app.hitPoints(of: durga))
        XCTAssertEqual(shown.numbers?.text, "24+5/48")
        XCTAssertEqual(shown.bar?.tier, .bloodied)
        XCTAssertEqual(shown.exhaustion?.marker, "E2")
    }

    func testACharacterWithNoNoteShowsNothing() throws {
        let (app, durga) = try makeAppStateWithDurga(noteName: nil)

        XCTAssertNil(app.hitPoints(of: durga))
    }

    /// A note that has left the notes takes the numbers with it, as it takes the Stamp's.
    func testACharacterWhoseNoteCannotBeFoundShowsNothing() throws {
        let (app, durga) = try makeAppStateWithDurga()

        app.characterNotes = CharacterNotes(notes: [])

        XCTAssertNil(app.hitPoints(of: durga))
    }
}
