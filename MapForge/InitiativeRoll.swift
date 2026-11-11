import Foundation

/// The one die MapForge rolls.
///
/// Takes its randomness as a parameter rather than reaching for `Int.random`, so a whole
/// fight can be replayed exactly in a test. Everything else in the feature is deterministic
/// on purpose — ADR-0008 needs it to be, or a Log could not be replayed — and this is the
/// single place chance enters.
enum InitiativeRoll {
    /// 1 through 20, inclusive.
    static func d20<G: RandomNumberGenerator>(using generator: inout G) -> Int {
        Int.random(in: 1...20, using: &generator)
    }

    /// A Combatant's Initiative: 1d20 plus its bonus.
    ///
    /// Nothing clamps the result. Initiative is a comparison, not a die, and a heavily
    /// armoured dwarf who rolls a 2 with a -3 belongs at the bottom of the Order rather
    /// than at 1 alongside everyone else who rolled badly.
    static func roll<G: RandomNumberGenerator>(bonus: Int, using generator: inout G) -> Int {
        d20(using: &generator) + bonus
    }
}
