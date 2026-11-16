@testable import MapForge

/// The lines a Page prints, read off the blocks it draws them in.
///
/// Shared rather than copied into each suite, so a Monster's Page and a Character's are read
/// the one way the view reads them.
extension [PageText.Block] {
    /// AC to Speed, then Skills to CR, in the blocks' order.
    var lines: [PageText.Line] {
        flatMap { block -> [PageText.Line] in
            switch block {
            case .armorClassToSpeed(let lines), .skillsToChallengeRating(let lines): lines
            case .heading, .abilities, .groups: []
            }
        }
    }
}
