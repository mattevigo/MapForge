import SwiftUI

/// A Character's numbers and exhaustion as its row in the Party panel writes them, beside its
/// name: the Encounter tab's `current+temp/max` (`HitPointNumbersText`, the same view) and the
/// Encounter tab's exhaustion marker. What to show is `CharacterHitPoints`'s to say; this only
/// draws it. Read-only, like the rest of the roster: it edits nothing when clicked.
struct CharacterHitPointsLabel: View {
    let shown: CharacterHitPoints

    var body: some View {
        HStack(spacing: 4) {
            if let numbers = shown.numbers {
                HitPointNumbersText(numbers: numbers)
                    .help(shown.bar.map { CharacterHitPoints.tooltip(for: $0.tier) } ?? "")
            }
            if let exhaustion = shown.exhaustion {
                Text(exhaustion.marker)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .help(exhaustion.tooltip)
            }
        }
        // Never squeezed: the name beside it is the row's one flexible member, and a number
        // cut to "2…" would be a number the DM misreads.
        .fixedSize()
    }
}

extension View {
    /// This Character's row with the DM's exact Health Bar across its foot, drawn by the same
    /// view and in the same layout as a Pawn's row — and never faded, since whether the table
    /// sees a bar is each Pawn's own switch, not the Character's (ADR-0036). Exactly as it was
    /// when there is no bar to draw.
    func characterHitPointsUnderRow(_ shown: CharacterHitPoints?) -> some View {
        healthBarUnderRow(shown?.bar.map {
            HealthBarRowBar(bar: $0, withholding: nil,
                            tooltip: CharacterHitPoints.tooltip(for: $0.tier))
        })
    }
}
