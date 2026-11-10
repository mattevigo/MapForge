import SwiftUI

/// The Encounter Difficulty as the Combat tab's header draws it: the band and the total in
/// words, over a bar of the party's budgets (ADR-0032).
///
/// The DM's alone. It lives in `CombatPanel`, which only the Control Window shows: the
/// players see the fight, never how hard the DM reckons it.
struct EncounterDifficultyBar: View {
    var creatureXP: Int
    var budgets: EncounterDifficulty.Budgets

    /// The overspent end: fixed, not proportional, so a dragon in a goblin fight does not
    /// squash the three budgets the DM is reading the fill against into the first few points.
    private static let stubWidth: CGFloat = 14
    private static let gap: CGFloat = 2

    private var band: EncounterDifficulty.Band {
        EncounterDifficulty.Band(of: creatureXP, within: budgets)
    }

    var body: some View {
        let layout = Layout(creatureXP: creatureXP, budgets: budgets)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Encounter Difficulty", comment: "The rulebook's term, over the Combat tab's bar")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(band.title) · \(creatureXP) XP",
                     comment: "The Encounter Difficulty's band and the Creatures' total: Moderate · 650 XP")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.caption)
            bar(layout)
                .frame(height: 8)
        }
        .help(String(localized: "Low up to \(budgets.low) XP, Moderate up to \(budgets.moderate) XP, High up to \(budgets.high) XP.",
                     comment: "The party's three budgets, under the Encounter Difficulty's bar"))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("encounter-difficulty")
    }

    private func bar(_ layout: Layout) -> some View {
        GeometryReader { geometry in
            let length = max(geometry.size.width - Self.stubWidth - Self.gap, 0)
            let track = RoundedRectangle(cornerRadius: 2)
            ZStack(alignment: .leading) {
                track.fill(Color.secondary.opacity(0.18))
                    .frame(width: length)
                track.fill(band.tint)
                    .frame(width: length * layout.fill)
                ForEach(layout.marks.indices, id: \.self) { index in
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 1)
                        .offset(x: min(length * layout.marks[index], length - 1))
                }
                // Past the bar's end, as the fight is past its budgets: empty until the total
                // overspends High, then filled whole, however far over it goes.
                track.fill(layout.fillsBeyond ? band.tint : Color.secondary.opacity(0.08))
                    .frame(width: Self.stubWidth)
                    .offset(x: length + Self.gap)
            }
        }
    }

    /// Where the bar puts things, as fractions of its proportional part — 0 is no XP, 1 is
    /// the High budget. Apart from the view so the rule can be held down by a test.
    struct Layout: Equatable {
        /// Low, Moderate and High. They depend on the party alone, so they stand still while
        /// the DM ticks Creatures in and out.
        var marks: [Double]
        /// How much of the proportional part the total fills, never more than all of it.
        var fill: Double
        /// Whether the total overspends High, filling the stub past the bar's end.
        var fillsBeyond: Bool

        init(creatureXP: Int, budgets: EncounterDifficulty.Budgets) {
            // A counted Player's High budget is never below 100, so `high` is never zero
            // here; `max` only keeps a hand-built value from dividing by it.
            let high = Double(max(budgets.high, 1))
            marks = [budgets.low, budgets.moderate, budgets.high].map { Double($0) / high }
            fill = min(Double(creatureXP) / high, 1)
            fillsBeyond = creatureXP > budgets.high
        }
    }
}

extension EncounterDifficulty.Band {
    /// The band's name: Low, Moderate and High as SRD 5.2.1 prints them, and MapForge's own
    /// Beyond High (ADR-0032, `docs/terminology.md`).
    var title: String {
        switch self {
        case .low:
            return String(localized: "Low", comment: "An Encounter Difficulty band, as SRD 5.2.1 names it")
        case .moderate:
            return String(localized: "Moderate", comment: "An Encounter Difficulty band, as SRD 5.2.1 names it")
        case .high:
            return String(localized: "High", comment: "An Encounter Difficulty band, as SRD 5.2.1 names it")
        case .beyondHigh:
            return String(localized: "Beyond High",
                          comment: "The Encounter Difficulty past the High budget: MapForge's own term, not the rulebook's")
        }
    }

    /// Hotter as the fight gets harder. Never the only signal — the label names the band.
    var tint: Color {
        switch self {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .beyondHigh: return .red
        }
    }
}
