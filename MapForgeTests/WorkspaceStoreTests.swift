import XCTest
@testable import MapForge

final class WorkspaceStoreTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorkspaceStoreTests.\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func store() -> WorkspaceStore { WorkspaceStore() }

    // MARK: - Adoption

    func testAdoptingAFolderMakesItAWorkspace() throws {
        let workspace = try store().adopt(root)

        XCTAssertTrue(fileManager.fileExists(atPath: workspace.manifestURL.path))
        XCTAssertTrue(store().isWorkspace(root))
        guard case .success = store().open(root) else {
            return XCTFail("an adopted folder should open")
        }
    }

    func testAdoptingLeavesEverythingElseInTheFolderAlone() throws {
        // The promise made to a DM adopting a directory of maps with their fog traced: the
        // app writes `.mapforge/` and touches nothing they put there themselves.
        let map = root.appendingPathComponent("dungeon.png")
        let fog = root.appendingPathComponent("dungeon.fog.json")
        let combat = root.appendingPathComponent("dungeon.combat")
        try Data("not really a png".utf8).write(to: map)
        try Data(#"{"version":2}"#.utf8).write(to: fog)
        try fileManager.createDirectory(at: combat, withIntermediateDirectories: true)

        try store().adopt(root)

        XCTAssertEqual(try Data(contentsOf: map), Data("not really a png".utf8))
        XCTAssertEqual(try Data(contentsOf: fog), Data(#"{"version":2}"#.utf8))
        XCTAssertTrue(fileManager.fileExists(atPath: combat.path))
    }

    func testReadoptingDoesNotResetTheManifest() throws {
        try store().adopt(root)
        let first = try Data(contentsOf: Workspace(url: root).manifestURL)

        try store().adopt(root)

        // Not merely "createdAt is preserved": re-adopting must not write at all, because the
        // Manifest it would overwrite may be one this version does not understand.
        XCTAssertEqual(try Data(contentsOf: Workspace(url: root).manifestURL), first)
    }

    // MARK: - Opening

    func testAPlainFolderIsNotAWorkspace() {
        guard case .failure(.notAWorkspace) = store().open(root) else {
            return XCTFail("a folder with no manifest is adoptable, not open-able")
        }
        XCTAssertFalse(store().isWorkspace(root))
    }

    func testAMissingFolderIsUnreachableNotMerelyUnadopted() {
        // The distinction the picker depends on: an unplugged drive must not look like a
        // folder the DM should be invited to set up.
        let gone = root.appendingPathComponent("never-existed")

        guard case .failure(.unreachable) = store().open(gone) else {
            return XCTFail("a missing folder is unreachable")
        }
    }

    func testAFileIsNotAWorkspace() throws {
        let file = root.appendingPathComponent("notafolder.txt")
        try Data("hello".utf8).write(to: file)

        guard case .failure(.unreachable) = store().open(file) else {
            return XCTFail("a regular file cannot be a Workspace")
        }
    }

    // MARK: - The version is actually read

    func testANewerVersionIsRefusedRatherThanGuessedAt() throws {
        // The point of having a version at all. `PartyBook.version` is stamped and never
        // inspected; this one decides whether the folder opens.
        try writeManifest(#"{"createdAt":"2026-01-01T00:00:00Z","createdBy":"9.0","version":999}"#)

        guard case .failure(.newerVersion(_, let found)) = store().open(root) else {
            return XCTFail("a manifest from a newer MapForge must be refused")
        }
        XCTAssertEqual(found, 999)
    }

    func testAManifestWithNoVersionIsRefusedUnlikePartyBook() throws {
        // Deliberately unlike `PartyBook`, which defaults a missing version to `current` and
        // so cannot tell a version-less file from a v1 one.
        try writeManifest(#"{"createdAt":"2026-01-01T00:00:00Z","createdBy":"1.2.0"}"#)

        guard case .failure(.unreadableManifest) = store().open(root) else {
            return XCTFail("a manifest without a version is not one this app wrote")
        }
    }

    func testAnOlderManifestStillOpens() throws {
        // Forward-looking: when `current` becomes 2, a v1 folder must keep opening.
        try writeManifest(#"{"createdAt":"2026-01-01T00:00:00Z","createdBy":"1.2.0","version":1}"#)

        guard case .success = store().open(root) else {
            return XCTFail("a manifest at the current version or below opens")
        }
    }

    // MARK: - An unreadable manifest is never overwritten

    func testAnUnreadableManifestIsReportedAndLeftOnDisk() throws {
        // `PartyStore` and `FogStore` both hold this rule: never destroy bytes you could not
        // parse. Adoption is a write, so it must refuse here too.
        let damaged = Data("{ this is not json".utf8)
        try writeManifest(damaged)

        guard case .failure(.unreadableManifest) = store().open(root) else {
            return XCTFail("malformed JSON is an unreadable manifest")
        }
        XCTAssertEqual(try Data(contentsOf: Workspace(url: root).manifestURL), damaged,
                       "the bytes must be left exactly as they were")
    }

    func testAdoptingOverADamagedManifestDoesNotDestroyIt() throws {
        let damaged = Data("{ this is not json".utf8)
        try writeManifest(damaged)

        _ = try? store().adopt(root)

        XCTAssertEqual(try Data(contentsOf: Workspace(url: root).manifestURL), damaged)
    }

    // MARK: - The value

    func testTheWorkspaceIsNamedByItsFolder() {
        let workspace = Workspace(url: URL(fileURLWithPath: "/Users/dm/DM Workspace"))
        XCTAssertEqual(workspace.name, "DM Workspace")
    }

    func testTwoSpellingsOfOneFolderAreOneWorkspace() {
        // So the recents list cannot show the same folder twice.
        let plain = Workspace(url: URL(fileURLWithPath: "/Users/dm/Maps"))
        let trailing = Workspace(url: URL(fileURLWithPath: "/Users/dm/Maps/"))
        let doubled = Workspace(url: URL(fileURLWithPath: "/Users/dm//Maps"))

        XCTAssertEqual(plain, trailing)
        XCTAssertEqual(plain, doubled)
        XCTAssertEqual(Set([plain, trailing, doubled]).count, 1)
    }

    func testTheLayoutIsStatedOnlyOnce() {
        let workspace = Workspace(url: URL(fileURLWithPath: "/Users/dm/Maps"))

        XCTAssertEqual(workspace.supportDirectory.lastPathComponent, ".mapforge")
        XCTAssertEqual(workspace.manifestURL.path, "/Users/dm/Maps/.mapforge/workspace.json")
        XCTAssertEqual(workspace.partiesURL.path, "/Users/dm/Maps/.mapforge/parties.json")
        XCTAssertEqual(workspace.preferencesURL.path,
                       "/Users/dm/Maps/.mapforge/preferences.json")
    }

    func testTheManifestIsReadableAndStableOnDisk() throws {
        try store().adopt(root)

        let text = try String(contentsOf: Workspace(url: root).manifestURL, encoding: .utf8)

        XCTAssertTrue(text.contains("\n"), "pretty-printed, as PartyStore writes")
        // .sortedKeys: createdAt, createdBy, version.
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "createdAt")).lowerBound,
                          try XCTUnwrap(text.range(of: "version")).lowerBound)
    }

    // MARK: - Helpers

    private func writeManifest(_ json: String) throws {
        try writeManifest(Data(json.utf8))
    }

    private func writeManifest(_ data: Data) throws {
        let support = Workspace(url: root).supportDirectory
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try data.write(to: Workspace(url: root).manifestURL)
    }
}
