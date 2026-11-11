import XCTest
@testable import MapForge

/// A generator that makes `d20` return the faces a test asks for, so a fight can be
/// replayed exactly in a unit test. Cycles when it runs out, so a test never has to count
/// rolls.
///
/// `Int.random(in:using:)` does not simply take `next()` modulo the range — it draws from
/// the full `UInt64` space and rejects values that would bias the result. The multiplier
/// below lands each scripted face in the middle of its own band, comfortably inside the
/// accepted region, which `testTheScriptedGeneratorRollsWhatItWasToldTo` holds down.
struct ScriptedGenerator: RandomNumberGenerator {
    private var values: [UInt64]
    private var index = 0

    /// Each value is the face `d20` should return, 1 through 20.
    init(d20Rolls: [Int]) {
        // 2^64 / 20, so face n occupies [n·band, (n+1)·band); the half-band offset keeps
        // every scripted value away from both edges.
        let band = UInt64.max / 20
        values = d20Rolls.map { UInt64($0 - 1) * band + band / 2 }
    }

    mutating func next() -> UInt64 {
        defer { index += 1 }
        return values[index % values.count]
    }
}

final class InitiativeRollTests: XCTestCase {
    func testAD20IsBetweenOneAndTwenty() {
        // Exhaustively, because an off-by-one in a die is the kind of bug that hides for
        // a whole campaign as "the rogue is unlucky".
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<2_000 {
            let roll = InitiativeRoll.d20(using: &generator)
            XCTAssertTrue((1...20).contains(roll), "rolled \(roll)")
        }
    }

    func testEveryFaceIsReachable() {
        // A die that can never roll a 1 or a 20 is not a d20.
        var generator = SystemRandomNumberGenerator()
        var seen: Set<Int> = []
        for _ in 0..<2_000 { seen.insert(InitiativeRoll.d20(using: &generator)) }
        XCTAssertEqual(seen, Set(1...20))
    }

    func testTheScriptedGeneratorRollsWhatItWasToldTo() {
        // Every EncounterControl test rests on this, so it is held down here rather than
        // assumed. A scripted generator that silently drifted by one would make a dozen
        // tests assert the wrong thing while still passing.
        var generator = ScriptedGenerator(d20Rolls: Array(1...20))
        XCTAssertEqual((1...20).map { _ in InitiativeRoll.d20(using: &generator) },
                       Array(1...20))
    }

    func testTheScriptedGeneratorCycles() {
        // So a test that rolls more often than it scripted still gets known values.
        var generator = ScriptedGenerator(d20Rolls: [7, 11])
        XCTAssertEqual((0..<4).map { _ in InitiativeRoll.d20(using: &generator) },
                       [7, 11, 7, 11])
    }

    func testInitiativeIsTheRollPlusTheBonus() {
        // 1d20 + initiative bonus, the 5.5e rule and the only arithmetic in the feature.
        var generator = ScriptedGenerator(d20Rolls: [13])
        XCTAssertEqual(InitiativeRoll.roll(bonus: 3, using: &generator), 16)
    }

    func testANegativeBonusCanLowerTheResult() {
        // A heavily armoured dwarf rolls low and stays low; nothing clamps to 1, because
        // initiative is a comparison and not a die.
        var generator = ScriptedGenerator(d20Rolls: [2])
        XCTAssertEqual(InitiativeRoll.roll(bonus: -3, using: &generator), -1)
    }
}
