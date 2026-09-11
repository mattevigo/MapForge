import AppKit
import XCTest
@testable import MapForge

/// One fight, driven through `AppState` exactly as the panel drives it, with the resulting
/// file read back as a DM would read it.
///
/// The nearest thing to running the app that a test can be, and — while Pawn tokens are not
/// drawn on the preview (`.scratch/pawns-not-drawn/`) — the only way this path can be
/// exercised at all.
@MainActor
final class MovementEndToEndTests: XCTestCase {
    func testAWholeTurnReadsBackAsWhatHappened() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MovementEndToEnd.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mapURL = directory.appendingPathComponent("dungeon.png")
        let suite = "MapForgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = AppState(preferences: DisplayPreferences(defaults: defaults),
                             fogStore: FogStore(),
                             partyStore: PartyStore(directory: directory),
                             statsStore: StatsStore())
        state.mapURL = mapURL
        state.mapImage = NSImage(size: NSSize(width: 1000, height: 800))
        state.squaresWide = 20

        let grog = Pawn(at: MapPoint(x: 100, y: 100), label: "Grog",
                        colorHex: "#C81E1E", brightSquares: 6, kind: .player)
        let goblin = Pawn(at: MapPoint(x: 600, y: 100), label: "Goblin",
                          colorHex: "#1E90C8", brightSquares: 6, kind: .creature)
        state.fog.pawns = [grog, goblin]
        state.setStatBlock(StatBlock(armorClass: 16, currentHP: 26, maxHP: 26), for: grog.id)
        state.setStatBlock(StatBlock(armorClass: 15, currentHP: 7, maxHP: 7), for: goblin.id)

        state.startEncounter()
        let active = try XCTUnwrap(state.encounter?.activeCombatantID)

        // Grog walks four squares and hits the goblin, which drops and falls unconscious.
        state.movePawn(id: grog.id, to: MapPoint(x: 300, y: 100))
        state.commitPawnMove(id: grog.id, from: MapPoint(x: 100, y: 100))
        state.editStatBlock(for: goblin.id) { $0.currentHP = 0 }
        state.addNote("Grog closed and dropped it in one swing")
        state.endTurn()

        let reader = CombatLogReader()
        let url = try XCTUnwrap(reader.newestLogURL(forMapAt: mapURL))
        let lines = try reader.read(at: url)

        guard case let .turn(round, combatantID, changes, _)? = lines.first(where: {
            if case .turn = $0 { return true } else { return false }
        }) else { return XCTFail("no Turn in the Log") }

        XCTAssertEqual(round, 1)
        XCTAssertEqual(combatantID, active)
        XCTAssertEqual(changes.count, 4, "move, hit points, unconscious, note")

        guard case let .moved(_, _, _, distance) = changes[0] else {
            return XCTFail("the Turn should open with the move")
        }
        XCTAssertEqual(distance, 4, accuracy: 0.001, "200 pixels at 50 to the square")
        XCTAssertEqual(changes[1], .hpChanged(combatantID: goblin.id, from: 7, to: 0))
        XCTAssertEqual(changes[2], .conditionAdded(combatantID: goblin.id, condition: .unconscious))
        XCTAssertEqual(changes[3], .noteAdded(combatantID: goblin.id == active ? goblin.id : active,
                                              text: "Grog closed and dropped it in one swing"))

        // And the file folds back to what the tracker was showing.
        let folded = CombatLogFold.fold(lines)
        XCTAssertEqual(folded.blocks[goblin.id]?.currentHP, 0)
        XCTAssertTrue(folded.blocks[goblin.id]?.conditions.contains(.unconscious) ?? false)
    }
}
