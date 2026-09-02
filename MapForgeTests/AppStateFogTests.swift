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

    // MARK: Grid declaration

    func testANewMapHasNotDeclaredItsGrid() throws {
        // squaresWide defaults to 30 and carries over between Maps, so "has a value" is
        // not "was declared". Light radii are in Grid squares, and treating the default
        // as declared renders every Light at a plausible-looking wrong size.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        XCTAssertFalse(appState.hasDeclaredGrid)
    }

    func testSettingTheGridDeclaresIt() throws {
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        appState.squaresWide = 24
        XCTAssertTrue(appState.hasDeclaredGrid)
    }

    func testSwitchingMapsClearsTheDeclaration() throws {
        // The next Map inherits the number but not the claim that it is right.
        let first = try makeMap(named: "dungeon")
        let second = try makeMap(named: "tavern")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: first.image, at: first.url)
        appState.squaresWide = 24
        appState.loadMap(image: second.image, at: second.url)
        XCTAssertFalse(appState.hasDeclaredGrid, "the new Map inherited a Grid declaration")
    }

    func testDeclaringAGridThatMatchesTheDefaultStillCounts() throws {
        // The default is a guess, not a declaration — but a DM whose Map really is 30
        // squares wide types 30, and the value never changes. Keying the declaration on
        // `didSet` firing means their Lights stay dark and the warning never clears, with
        // the app telling them to do the one thing they just did.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        appState.squaresWide = 30
        XCTAssertTrue(appState.hasDeclaredGrid,
                      "typing the default value did not declare the Grid")
    }

    func testALightLitsSomethingOnceTheGridMatchesTheDefault() throws {
        // The symptom the DM reports: overlay on, Light placed, nothing illuminated.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        appState.fog.lights = [Light(at: MapPoint(x: 20, y: 15), brightSquares: 4)]
        appState.squaresWide = 30

        XCTAssertFalse(appState.litRegions.isEmpty,
                       "a Light on a 30-square Map illuminated nothing")
    }

    func testRestoringAGridDoesNotDeclareOneTheDMNeverChose() throws {
        // Cancelling Grid Fit puts back the number that was there before. Entering the
        // mode moves the value, which declares — so cancel has to put back the claim too,
        // or backing out of Grid Fit leaves the app asserting a Grid nobody set.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        XCTAssertFalse(appState.hasDeclaredGrid, "precondition: a fresh Map has no Grid")

        appState.squaresWide = 42          // as Grid Fit does while dragging
        appState.restoreGrid(squaresWide: 30, wasDeclared: false)

        XCTAssertEqual(appState.squaresWide, 30)
        XCTAssertFalse(appState.hasDeclaredGrid,
                       "cancelling Grid Fit left a Grid declaration behind")
    }

    // MARK: Live light toggling

    func testSettingALightStateIsIdempotent() throws {
        // The live row binds a Toggle straight to this. SwiftUI writes the same value
        // twice on a state resync, and a toggle-based setter would flip it back.
        let map = try makeMap(named: "dungeon")
        let appState = AppState(preferences: isolatedPreferences())
        appState.loadMap(image: map.image, at: map.url)
        let torch = Light(at: MapPoint(x: 10, y: 10), brightSquares: 4)
        appState.fog.lights = [torch]

        appState.setLight(id: torch.id, isOn: false)
        appState.setLight(id: torch.id, isOn: false)
        XCTAssertFalse(appState.fog.lights[0].isOn, "the repeated write flipped it back on")
    }
}
