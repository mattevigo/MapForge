import AppKit
import XCTest
@testable import MapForge

/// A Pawn never leaves the Map.
///
/// The defect this pins: a token dragged past the image edge landed in the mirror's clipped
/// margin, drawn nowhere the DM could click — it could not be dragged back, and it could not
/// be selected in the fog mode to be deleted. Stamping already refused an off-Map drop; a
/// drag cannot be refused, so it is clamped, and a file that already holds a stranded Pawn
/// gets it back when the Map opens.
@MainActor
final class PawnBoundsTests: XCTestCase {
    private let image = CGSize(width: 40, height: 30)

    // MARK: The rule

    func testAPointInsideTheImageIsLeftAlone() {
        let point = PawnBounds.clamp(MapPoint(x: 12, y: 7), toImage: image)
        XCTAssertEqual(point, MapPoint(x: 12, y: 7))
    }

    func testTheEdgesThemselvesAreOnTheMap() {
        // A character with their back to the wall is the ordinary case, and `Stamp` accepts
        // the same closed range — the two rules must agree on where the Map ends.
        XCTAssertEqual(PawnBounds.clamp(MapPoint(x: 0, y: 0), toImage: image), MapPoint(x: 0, y: 0))
        XCTAssertEqual(PawnBounds.clamp(MapPoint(x: 40, y: 30), toImage: image), MapPoint(x: 40, y: 30))
    }

    func testAPointPastTheFarEdgesStopsAtThem() {
        let point = PawnBounds.clamp(MapPoint(x: 95, y: 31), toImage: image)
        XCTAssertEqual(point, MapPoint(x: 40, y: 30))
    }

    func testAPointBeforeTheOriginStopsAtIt() {
        let point = PawnBounds.clamp(MapPoint(x: -3, y: -400), toImage: image)
        XCTAssertEqual(point, MapPoint(x: 0, y: 0))
    }

    func testEachAxisIsClampedOnItsOwn() {
        // Off the right edge but well inside vertically: only x moves.
        let point = PawnBounds.clamp(MapPoint(x: 60, y: 10), toImage: image)
        XCTAssertEqual(point, MapPoint(x: 40, y: 10))
    }

    func testAnImageWithNoSizeClampsToTheOrigin() {
        // The only point such an image has; never a negative range.
        let point = PawnBounds.clamp(MapPoint(x: 5, y: 5), toImage: .zero)
        XCTAssertEqual(point, MapPoint(x: 0, y: 0))
    }

    func testClampingAListMovesTokensAndNothingElse() {
        let stranded = Pawn(at: MapPoint(x: 70, y: -2), label: "Thorin", colorHex: "#1E90C8",
                            brightSquares: 9, kind: .creature, isHidden: true, isBig: true)
        let home = Pawn(at: MapPoint(x: 5, y: 5), label: "2", colorHex: "#C81E1E", brightSquares: 6)

        let clamped = PawnBounds.clamped([stranded, home], toImage: image)

        XCTAssertEqual(clamped[0].at, MapPoint(x: 40, y: 0))
        XCTAssertEqual(clamped[0].id, stranded.id, "clamping replaced the Pawn instead of moving it")
        XCTAssertEqual(clamped[0].label, "Thorin")
        XCTAssertEqual(clamped[0].kind, .creature)
        XCTAssertTrue(clamped[0].isHidden)
        XCTAssertTrue(clamped[0].isBig)
        XCTAssertEqual(clamped[1], home, "a Pawn already on the Map was touched")
    }

    // MARK: Where the app applies it

    private var directory: URL!
    private var mapURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PawnBoundsTests.\(UUID().uuidString)")
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

    /// A 40×30 point Map, as `AppStateFogTests` builds them. Its *pixel* size depends on
    /// the machine's backing scale, so the tests below read it rather than assume it.
    private func makeMapImage() throws -> NSImage {
        let image = NSImage(size: NSSize(width: 40, height: 30))
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 30).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil,
                                                             context: nil, hints: nil)!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: mapURL)
        return image
    }

    func testALiveDragStopsAtTheImageEdge() throws {
        // The `PawnLayer` path: the party moves during play, through `AppState.movePawn`.
        let app = makeAppState()
        let image = try makeMapImage()
        app.loadMap(image: image, at: mapURL)
        let pawn = Pawn(at: MapPoint(x: 20, y: 15), label: "1", colorHex: "#C81E1E", brightSquares: 6)
        app.fog.pawns = [pawn]

        app.movePawn(id: pawn.id, to: MapPoint(x: image.pixelSize.width + 60, y: -5))

        XCTAssertEqual(app.fog.pawns.first?.at, MapPoint(x: image.pixelSize.width, y: 0))
    }

    func testAStrandedPawnComesBackWhenTheMapOpens() throws {
        // A file written before the rule existed: the token is on the Map again, at the
        // nearest edge, rather than unreachable for good.
        let image = try makeMapImage()
        let stranded = Pawn(at: MapPoint(x: image.pixelSize.width + 500, y: 12),
                            label: "1", colorHex: "#C81E1E", brightSquares: 6)
        try FogStore().save(FogDocument(pawns: [stranded]), forMapAt: mapURL)

        let app = makeAppState()
        app.loadMap(image: image, at: mapURL)

        XCTAssertEqual(app.fog.pawns.first?.id, stranded.id)
        XCTAssertEqual(app.fog.pawns.first?.at, MapPoint(x: image.pixelSize.width, y: 12))
    }
}
