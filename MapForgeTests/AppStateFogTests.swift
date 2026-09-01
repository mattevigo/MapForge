import XCTest
@testable import MapForge

/// The end-to-end seam issue 01 is judged on: a Map opened twice keeps its fog, and
/// switching Maps never carries one Map's Walls onto another.
@MainActor
final class AppStateFogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AppStateFogTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testReopeningAMapRestoresItsFog() throws {
        let map = try makeMap(named: "dungeon")
        let wall = Wall(from: MapPoint(x: 100, y: 200), to: MapPoint(x: 340, y: 200))
        try FogStore().save(FogDocument(walls: [wall]), forMapAt: map.url)

        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        XCTAssertEqual(appState.fog.walls, [wall])
    }

    func testAMapWithNoFogStartsEmpty() throws {
        let map = try makeMap(named: "blank")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        XCTAssertTrue(appState.fog.isEmpty)
    }

    func testSwitchingMapsDoesNotCarryFogAcross() throws {
        // The failure this guards: opening a second Map and seeing the first Map's Walls
        // on it — then saving them onto the wrong file.
        let dungeon = try makeMap(named: "dungeon")
        let tavern = try makeMap(named: "tavern")
        try FogStore().save(FogDocument(walls: [Wall(from: MapPoint(x: 0, y: 0), to: MapPoint(x: 50, y: 0))]),
                            forMapAt: dungeon.url)

        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: dungeon.image, at: dungeon.url)
        XCTAssertFalse(appState.fog.isEmpty, "precondition: dungeon has fog")

        appState.loadMap(image: tavern.image, at: tavern.url)
        XCTAssertTrue(appState.fog.isEmpty, "the tavern inherited the dungeon's Walls")
    }

    func testAnEditIsPersistedForTheMapItWasDrawnOn() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)

        let wall = Wall(from: MapPoint(x: 10, y: 10), to: MapPoint(x: 90, y: 10))
        appState.fog.walls = [wall]
        appState.flushPendingFogWrites()

        XCTAssertEqual(FogStore().load(forMapAt: map.url)?.walls, [wall])
    }

    // MARK: Helpers

    private func makeMap(named name: String) throws -> (url: URL, image: NSImage) {
        let url = directory.appendingPathComponent("\(name).png")
        let image = NSImage(size: NSSize(width: 40, height: 30))
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 30).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil,
                                                             context: nil, hints: nil)!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        return (url, image)
    }

    /// AppState remembers the Player Display in UserDefaults; tests must not write to the
    /// real domain or they leak into the developer's own app.
    private func isolatedPreferences() -> DisplayPreferences {
        DisplayPreferences(defaults: UserDefaults(suiteName: "AppStateFogTests.\(UUID().uuidString)")!)
    }
}
