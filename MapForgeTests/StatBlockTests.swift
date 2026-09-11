import XCTest
@testable import MapForge

final class StatBlockTests: XCTestCase {
    func testAStatBlockWithNoHitPointsIsIncomplete() {
        // A Creature stamped and not yet filled in has no hit points, and zero is a
        // meaningful value that must not stand in for absent: a monster at 0 is
        // unconscious, a monster with no number typed yet is waiting for the DM.
        XCTAssertFalse(StatBlock().isComplete)
    }

    func testAStatBlockWithBothHitPointTotalsIsComplete() {
        // The tracker flags the incomplete ones; this is what it stops flagging.
        XCTAssertTrue(StatBlock(currentHP: 14, maxHP: 32).isComplete)
    }

    func testAStatBlockAtZeroHitPointsIsStillComplete() {
        // The distinction the optional exists for: 0 is a number the DM typed.
        XCTAssertTrue(StatBlock(currentHP: 0, maxHP: 32).isComplete)
    }

    func testExhaustionCannotExceedSix() {
        // There is no seventh level of exhaustion; a 7 would be a number the rules
        // cannot answer questions about.
        var block = StatBlock()
        block.exhaustion = 9
        XCTAssertEqual(block.exhaustion, 6)
    }

    func testExhaustionCannotGoBelowZero() {
        // Subtracting a level from an unexhausted Combatant leaves it unexhausted.
        var block = StatBlock()
        block.exhaustion = -3
        XCTAssertEqual(block.exhaustion, 0)
    }

    func testExhaustionIsClampedWhenInitialised() {
        // Both doors into the value must clamp, not just the one a test happened to use.
        XCTAssertEqual(StatBlock(exhaustion: 9).exhaustion, 6)
    }

    func testAStatBlockRoundTripsThroughJSON() throws {
        // Everything the DM typed has to come back after a relaunch.
        let block = StatBlock(initiativeBonus: 3,
                              armorClass: 17,
                              currentHP: 14,
                              maxHP: 32,
                              temporaryHP: 5,
                              conditions: [.prone, .poisoned],
                              exhaustion: 2,
                              isConcentrating: true)
        let data = try JSONEncoder().encode(block)
        XCTAssertEqual(try JSONDecoder().decode(StatBlock.self, from: data), block)
    }

    func testExhaustionIsClampedOnDecode() throws {
        // `stats.json` is a file a DM can open and edit, so a level out of range can
        // arrive from disk as easily as from the editor. `didSet` does not fire during
        // decoding, so this needs its own guard and its own test.
        let json = Data("""
        {"initiativeBonus":0,"armorClass":10,"temporaryHP":0,\
        "conditions":[],"exhaustion":99,"isConcentrating":false}
        """.utf8)
        XCTAssertEqual(try JSONDecoder().decode(StatBlock.self, from: json).exhaustion, 6)
    }

    func testAbsentHitPointsSurviveTheRoundTrip() throws {
        // The incomplete Stat Block is the one most likely to be written to disk — a
        // monster placed during prep — and "no number yet" must not come back as 0.
        let data = try JSONEncoder().encode(StatBlock())
        let decoded = try JSONDecoder().decode(StatBlock.self, from: data)
        XCTAssertNil(decoded.currentHP)
        XCTAssertNil(decoded.maxHP)
    }
}
