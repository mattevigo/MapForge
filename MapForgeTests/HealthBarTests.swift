import XCTest
@testable import MapForge

/// What a Pawn's Health Bar shows: how full it is, how much of it is temporary hit points, and
/// which of the three tiers colours it (ADR-0036).
///
/// The tier bounds halve — Healthy above ½, Bloodied at ½ or below, Critical at ¼ or below —
/// and they are tested at the exact hit point either side of each line, because a bar that
/// turned Bloodied one hit point late would tell the table something the rulebook does not.
final class HealthBarTests: XCTestCase {
    private func bar(_ current: Int?, of max: Int?, temporary: Int = 0,
                     kind: PawnKind = .creature) -> HealthBar? {
        HealthBar(kind: kind, stats: StatBlock(currentHP: current, maxHP: max, temporaryHP: temporary))
    }

    // MARK: - The tiers

    func testHalfIsBloodied() {
        // The rulebook's own line: half its hit points or fewer.
        XCTAssertEqual(bar(50, of: 100)?.tier, .bloodied)
    }

    func testOneAboveHalfIsHealthy() {
        XCTAssertEqual(bar(51, of: 100)?.tier, .healthy)
    }

    func testAQuarterIsCritical() {
        XCTAssertEqual(bar(25, of: 100)?.tier, .critical)
    }

    func testOneAboveAQuarterIsBloodied() {
        XCTAssertEqual(bar(26, of: 100)?.tier, .bloodied)
    }

    // MARK: - The fill

    func testTheFillIsCurrentOverMax() throws {
        XCTAssertEqual(try XCTUnwrap(bar(30, of: 40)).fill, 0.75, accuracy: 1e-9)
    }

    func testAtZeroTheBarIsEmptyAndCritical() {
        // How the table sees the Pawn is down: an empty bar, not a missing one.
        let down = bar(0, of: 32)
        XCTAssertEqual(down?.fill, 0)
        XCTAssertEqual(down?.tier, .critical)
    }

    func testBelowZeroTheBarIsStillEmptyAndCritical() {
        // A DM who types the damage without stopping at 0 must not get a bar that runs
        // backwards.
        let below = bar(-7, of: 32)
        XCTAssertEqual(below?.fill, 0)
        XCTAssertEqual(below?.tier, .critical)
    }

    func testAboveMaxTheBarIsFull() {
        XCTAssertEqual(bar(40, of: 32)?.fill, 1)
        XCTAssertEqual(bar(40, of: 32)?.tier, .healthy)
    }

    // MARK: - Temporary hit points

    func testTemporaryHitPointsAddASegmentAfterTheFill() throws {
        let shielded = try XCTUnwrap(bar(50, of: 100, temporary: 10))
        XCTAssertEqual(shielded.fill, 0.5, accuracy: 1e-9)
        XCTAssertEqual(shielded.temporary, 0.1, accuracy: 1e-9)
    }

    func testTemporaryHitPointsNeverChangeTheTier() {
        // The rules do not let them stop a creature being Bloodied: 50 of 100 with 30
        // temporary is still at half its hit points.
        XCTAssertEqual(bar(50, of: 100, temporary: 30)?.tier, .bloodied)
        XCTAssertEqual(bar(25, of: 100, temporary: 60)?.tier, .critical)
    }

    func testTheFillAndTheTemporarySegmentAreCutOffAtFull() throws {
        // 90 of 100 with 25 temporary would run past the end; the segment stops at full.
        let shielded = try XCTUnwrap(bar(90, of: 100, temporary: 25))
        XCTAssertEqual(shielded.fill, 0.9, accuracy: 1e-9)
        XCTAssertEqual(shielded.temporary, 0.1, accuracy: 1e-9)
    }

    func testAFullBarHasNoRoomForATemporarySegment() {
        XCTAssertEqual(bar(100, of: 100, temporary: 12)?.temporary, 0)
    }

    func testNoTemporaryHitPointsIsNoSegment() {
        XCTAssertEqual(bar(40, of: 100)?.temporary, 0)
    }

    // MARK: - Who has one

    func testPlayersAndCreaturesBothCarryOne() {
        // One rule for both: the half the table asks about most is the monster.
        XCTAssertNotNil(bar(10, of: 20, kind: .player))
        XCTAssertNotNil(bar(10, of: 20, kind: .creature))
    }

    func testATreasureNeverDoes() {
        // A chest with hit points typed into it is still a chest.
        XCTAssertNil(bar(10, of: 20, kind: .treasure))
    }

    func testNoCurrentHitPointsIsNoBar() {
        // No numbers, no bar — never a guessed one.
        XCTAssertNil(bar(nil, of: 20))
    }

    func testNoMaximumIsNoBar() {
        XCTAssertNil(bar(10, of: nil))
    }

    func testAMaximumOfZeroOrLessIsNoBar() {
        // There is nothing to be a fraction of.
        XCTAssertNil(bar(0, of: 0))
        XCTAssertNil(bar(5, of: -3))
    }
}
