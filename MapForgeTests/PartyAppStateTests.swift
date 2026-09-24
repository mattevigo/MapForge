import AppKit
import XCTest
@testable import MapForge

/// The Party feature where it meets the rest of the app: stamping onto the live document,
/// the roster reaching disk, and the rules that must hold across the seam.
@MainActor
final class PartyAppStateTests: XCTestCase {
    private var directory: URL!
    private var mapURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PartyAppStateTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        mapURL = directory.appendingPathComponent("dungeon.png")
        suiteName = "MapForgeTests.\(UUID().uuidString)"
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

    private let thorin = PartyCharacter(name: "Thorin", colorHex: "#C81E1E",
                                        sightSquares: 6, isBig: false)

    // MARK: The roster reaches disk

    func testACharacterEditReachesDisk() throws {
        // Issue 03: a roster edit is not debounced — it happens when the DM types, which is
        // nothing like drag-rate — so it must be on disk before anything else happens.
        let app = makeAppState()
        app.addParty(named: "Eroi")
        app.addCharacter(thorin)

        let reloaded = PartyStore(directory: directory).load()
        XCTAssertEqual(reloaded.parties.first?.characters.first?.name, "Thorin")
    }

    func testAFirstPartyCanBeCreatedFromNothing() {
        // The regression this exists to prevent: "New Party…" lived only in the picker's
        // menu, the picker needed a Party to name, so a DM with an empty roster could never
        // make their first one. The feature was unreachable on a clean machine and every
        // test passed, because they all started from a roster seeded by hand.
        let app = makeAppState()
        XCTAssertNil(app.activeParty, "precondition: nothing defined yet")

        app.addParty(named: "Eroi")

        XCTAssertEqual(app.activeParty?.name, "Eroi")
        XCTAssertEqual(app.partyBook.parties.count, 1)
    }

    func testTheFirstPartyBecomesActive() {
        // Otherwise the DM creates a Party and the panel still shows nothing to drag.
        let app = makeAppState()
        app.addParty(named: "Eroi")
        app.addParty(named: "Alleati")
        XCTAssertEqual(app.activeParty?.name, "Alleati", "a new Party did not become active")
    }

    func testTheActivePartySurvivesARelaunch() {
        let app = makeAppState()
        app.addParty(named: "Eroi")
        let id = app.activeParty?.id

        XCTAssertEqual(makeAppState().activeParty?.id, id)
    }

    func testAnUnreadableRosterIsNeverOverwritten() throws {
        // The FogStore hazard one step on: a DM who opens the app, sees no party and retypes
        // it must not have that first save destroy the file that could have been recovered.
        let corrupt = Data(#"{"parties": [ truncated"#.utf8)
        try corrupt.write(to: PartyStore(directory: directory).fileURL)

        let app = makeAppState()
        XCTAssertNotNil(app.partyLoadFailure, "the failure was not surfaced")
        app.addParty(named: "Eroi")

        XCTAssertEqual(try Data(contentsOf: PartyStore(directory: directory).fileURL), corrupt)
    }

    // MARK: Stamping

    /// Opens a Map and returns a frame to drop into.
    ///
    /// The image is 40×30 pixels, as `AppStateFogTests` builds them, so the frame below maps
    /// one image pixel to ten points and a drop at (100, 80) lands at pixel (10, 8).
    @discardableResult
    private func openMap(_ app: AppState) throws -> CGRect {
        let image = NSImage(size: NSSize(width: 40, height: 30))
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 30).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil,
                                                             context: nil, hints: nil)!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: mapURL)
        app.loadMap(image: image, at: mapURL)
        return CGRect(x: 0, y: 0, width: 400, height: 300)
    }

    func testStampingAddsAPawnToTheLiveDocument() throws {
        let app = makeAppState()
        let frame = try openMap(app)
        XCTAssertTrue(app.stamp(thorin, at: CGPoint(x: 100, y: 80), frame: frame))
        XCTAssertEqual(app.fog.pawns.count, 1)
        XCTAssertEqual(app.fog.pawns.first?.label, "Thorin")
        XCTAssertEqual(app.fog.pawns.first?.characterID, thorin.id)
    }

    // MARK: The drop

    /// What the Map's drop target hands over: the pasteboard's payload, not a Character.
    ///
    /// This door exists because the drop target was once deleted along with the view it was
    /// attached to (`9767de0`), and nothing noticed: `stamp` kept all its tests, having lost
    /// its only caller. The part of a drop that can be tested is the part kept out of the
    /// view, so as much of it as possible lives here.
    func testADroppedPayloadStampsTheCharacterItNames() throws {
        let app = makeAppState()
        let frame = try openMap(app)
        app.addParty(named: "Heroes")
        app.addCharacter(thorin)

        XCTAssertTrue(app.stampDropped([CharacterDragPayload(characterID: thorin.id)],
                                       at: CGPoint(x: 100, y: 80), frame: frame))
        XCTAssertEqual(app.fog.pawns.map(\.label), ["Thorin"])
    }

    func testAPayloadNamingNobodyIsRefused() throws {
        // A drag that outlived its Character: deleted mid-drag, or from another Workspace.
        let app = makeAppState()
        let frame = try openMap(app)
        XCTAssertFalse(app.stampDropped([CharacterDragPayload(characterID: UUID())],
                                        at: CGPoint(x: 100, y: 80), frame: frame))
        XCTAssertFalse(app.stampDropped([], at: CGPoint(x: 100, y: 80), frame: frame))
        XCTAssertEqual(app.fog.pawns, [])
    }

    func testStampingIsNotUndoable() throws {
        // Issue 04: stamping follows movePawn, not FogEdits.addPawn. It is a live table
        // action, so there is no mode-local history for it to land in and undo must not
        // reach back past it.
        let app = makeAppState()
        let frame = try openMap(app)
        app.stamp(thorin, at: CGPoint(x: 100, y: 80), frame: frame)

        var edits = FogEdits(document: app.fog)
        XCTAssertFalse(edits.canUndo, "the stamp entered the fog undo history")
        edits.undo()
        XCTAssertEqual(edits.document.pawns.count, 1, "undo removed a Stamped Pawn")
    }

    func testTheStampReachesDiskWithoutWaitingOutTheDebounce() throws {
        // A drop is one completed action, not a stream of positions, so it flushes as the
        // end of a drag does. Read the file back with no delay: waiting would pass either
        // way and prove nothing.
        let app = makeAppState()
        let frame = try openMap(app)
        app.stamp(thorin, at: CGPoint(x: 100, y: 80), frame: frame)

        let saved = FogStore().load(forMapAt: mapURL)
        XCTAssertEqual(saved?.pawns.first?.label, "Thorin")
    }

    func testADropOutsideTheMapChangesNothing() throws {
        let app = makeAppState()
        let frame = try openMap(app)
        XCTAssertFalse(app.stamp(thorin, at: CGPoint(x: -5, y: 50), frame: frame))
        XCTAssertTrue(app.fog.pawns.isEmpty)
    }

    func testStampingWithNoMapOpenChangesNothing() {
        // The panel is gated on a Map being open, but the command must hold the rule itself:
        // a Pawn has nowhere to be without a Map to be on.
        let app = makeAppState()
        XCTAssertFalse(app.stamp(thorin, at: CGPoint(x: 10, y: 10),
                                 frame: CGRect(x: 0, y: 0, width: 500, height: 400)))
        XCTAssertTrue(app.fog.pawns.isEmpty)
    }

    // MARK: Deleting a Character never touches its Pawns

    func testDeletingACharacterLeavesItsPawnStanding() throws {
        // ADR 0007: the Stamp is a copy. Deleting the Character it came from must leave the
        // Pawn fully functional, and only stop it being counted.
        let app = makeAppState()
        let frame = try openMap(app)
        app.addParty(named: "Eroi")
        app.addCharacter(thorin)
        app.stamp(thorin, at: CGPoint(x: 100, y: 80), frame: frame)

        app.deleteCharacter(id: thorin.id)

        XCTAssertEqual(app.fog.pawns.count, 1, "deleting a Character deleted its Pawn")
        XCTAssertEqual(app.fog.pawns.first?.label, "Thorin")
        XCTAssertEqual(app.fog.pawns.first?.light.brightSquares, 6)
        // The Pawn keeps the id of a Character that no longer exists, which is exactly what
        // makes the back-pointer advisory: it dangles harmlessly. The count vanishes from
        // the panel because the roster no longer has a row to draw it against, not because
        // the Pawn stopped matching — so the panel is what is asserted here.
        XCTAssertTrue(app.partyBook.parties.allSatisfy { $0.characters.isEmpty },
                      "the Character outlived its deletion in the roster")
    }

    func testRenamingACharacterLeavesItsPawnAlone() throws {
        let app = makeAppState()
        let frame = try openMap(app)
        app.addParty(named: "Eroi")
        app.addCharacter(thorin)
        app.stamp(thorin, at: CGPoint(x: 100, y: 80), frame: frame)

        var renamed = thorin
        renamed.name = "Thorin the Bold"
        app.updateCharacter(renamed)

        XCTAssertEqual(app.fog.pawns.first?.label, "Thorin", "a rename reached a placed Pawn")
        // Still counted: identity is the id, which a rename does not change.
        XCTAssertEqual(app.placedCount(of: renamed), 1)
    }
}
