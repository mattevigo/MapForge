import XCTest
@testable import MapForge

final class FogStoreTests: XCTestCase {
    private var directory: URL!
    private var mapURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FogStoreTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        mapURL = directory.appendingPathComponent("dungeon.png")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testFogSurvivesARelaunch() throws {
        // The point of the whole issue: nobody redraws a room's Walls twice.
        let document = FogDocument(walls: [Wall(from: MapPoint(x: 100, y: 200),
                                                to: MapPoint(x: 340, y: 200))])
        try FogStore().save(document, forMapAt: mapURL)
        XCTAssertEqual(FogStore().load(forMapAt: mapURL), document)
    }

    /// The only test that goes through a real file on disk, so it is where a name has to
    /// survive the encoder, the file, and the decoder rather than just a round trip in memory.
    func testALightsNameSurvivesARelaunch() throws {
        var document = FogDocument()
        document.lights = [Light(at: MapPoint(x: 200, y: 200), brightSquares: 4,
                                 name: "trapped brazier"),
                           Light(at: MapPoint(x: 500, y: 500), brightSquares: 2)]
        try FogStore().save(document, forMapAt: mapURL)

        let loaded = FogStore().load(forMapAt: mapURL)
        XCTAssertEqual(loaded?.lights.first?.name, "trapped brazier")
        XCTAssertNil(loaded?.lights.last?.name, "an unnamed Light came back named")
    }

    func testFileSitsBesideTheImage() throws {
        // Moving the image and its fog file together must preserve the Walls, so the
        // fog file has to be a sibling with a predictable name.
        try FogStore().save(FogDocument(walls: [Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 1, y: 1))]),
                            forMapAt: mapURL)
        let expected = directory.appendingPathComponent("dungeon.fog.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
    }

    func testNoFogYetIsNotAnError() {
        // The normal case for every Map that has never been authored.
        XCTAssertNil(FogStore().load(forMapAt: mapURL))
    }

    func testAnEmptyDocumentWritesNoFile() throws {
        // MapForge must not litter the user's map folder with files for Maps whose
        // fog the DM never touched.
        try FogStore().save(FogDocument(), forMapAt: mapURL)
        let path = directory.appendingPathComponent("dungeon.fog.json").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testClearingFogRemovesTheFile() throws {
        // Deleting the last Wall must not leave the previous Walls on disk to
        // reappear at the next launch.
        let store = FogStore()
        try store.save(FogDocument(walls: [Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 1, y: 1))]),
                       forMapAt: mapURL)
        try store.save(FogDocument(), forMapAt: mapURL)
        XCTAssertNil(store.load(forMapAt: mapURL))
    }

    func testAGoodMapDoesNotInheritAnEarlierFailure() throws {
        // One store outlives many Maps. A failure left set from a corrupt Map would
        // attach a stale error to the next good one — and the UI would blame the
        // wrong file.
        let store = FogStore()
        try Data(#"{ truncated"#.utf8).write(to: directory.appendingPathComponent("bad.fog.json"))
        _ = store.load(forMapAt: directory.appendingPathComponent("bad.png"))
        XCTAssertNotNil(store.lastLoadFailure, "precondition: the corrupt Map failed")

        _ = store.load(forMapAt: mapURL)
        XCTAssertNil(store.lastLoadFailure, "a stale failure followed onto a good Map")
    }

    func testMalformedFileIsNotDestroyed() throws {
        // A DM's authored Walls are irreplaceable. If the file cannot be read, the
        // failure must be visible and the bytes must be left alone for recovery —
        // never silently overwritten with an empty document.
        let fogURL = directory.appendingPathComponent("dungeon.fog.json")
        let corrupt = Data(#"{"walls": [ truncated"#.utf8)
        try corrupt.write(to: fogURL)

        let store = FogStore()
        XCTAssertNil(store.load(forMapAt: mapURL))
        XCTAssertEqual(try Data(contentsOf: fogURL), corrupt)
    }
}
