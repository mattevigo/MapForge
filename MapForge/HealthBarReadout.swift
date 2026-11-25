import SwiftUI

/// A Pawn's hit points as the DM reads them in the Encounter tab's rows: the numbers, or the
/// orange ⚠️ where there are none — a monster with no numbers must not silently drop out of
/// a fight (ADR-0036).
///
/// The exact Health Bar is not drawn here but across the whole row, by `healthBarUnderRow` —
/// under the numbers it was as wide as "13/13", a smudge the DM could not read a fraction
/// from. The Scene tab's rows carry that bar and no numbers.
struct HealthBarReadout: View {
    let kind: PawnKind
    let stats: StatBlock
    /// The Live Toolbar's **Health Bars** switch. No default, for the reason
    /// `PlayerVisibility.showsHealthBarToPlayers` has none: a row that forgot the switch
    /// would tell the DM the table sees a bar it does not.
    let areHealthBarsOn: Bool

    var body: some View {
        if let current = stats.currentHP, let max = stats.maxHP {
            numbers(current: current, max: max)
                .help(HealthBar(kind: kind, stats: stats)
                    .map { Self.tooltip(for: $0.tier,
                                        withholding: PlayerVisibility.healthBarWithholding(
                                            stats: stats, areHealthBarsOn: areHealthBarsOn)) } ?? "")
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("No hit points yet — fill them in below.")
                .accessibilityIdentifier("incomplete-stat-block")
        }
    }

    /// `current+temp/max`, as the Encounter tab has always written it: current in red at 0
    /// or below, temporary in the teal the bar's temporary segment is drawn in.
    private func numbers(current: Int, max: Int) -> some View {
        HStack(spacing: 1) {
            Text("\(current)")
                .foregroundStyle(current <= 0 ? Color.red : .primary)
            if stats.temporaryHP > 0 {
                Text("+\(stats.temporaryHP)").foregroundStyle(HealthBar.temporaryColor)
            }
            Text("/\(max)").foregroundStyle(.secondary)
        }
        .font(.caption)
        .monospacedDigit()
    }

    /// What the table is being shown, in words — so the tier is never told by colour alone,
    /// and a faded bar always says which switch to go and turn back on. One sentence per
    /// case rather than a tier's name spliced in, and the tier as a label after the dash, as
    /// a Condition is shown: a Pawn has no gender for a tier to agree with (ADR-0022).
    ///
    /// A bar neither switch withholds is described *wherever the table can see this Pawn*,
    /// never as one the table sees: the row cannot know that, and does not need to. A hidden,
    /// unlit or switched-out Pawn takes its bar with it, and the eye and the Solo Sight switch
    /// beside the row already say so.
    static func tooltip(for tier: HealthBar.Tier, withholding: PlayerVisibility.HealthBarWithholding?) -> String {
        switch withholding {
        case .allBars:
            return String(localized: "The table sees no Health Bars: the Health Bars switch is off.")
        case .thisPawn:
            return String(localized: "The table does not see this Health Bar: it is withheld in Edit Pawn.")
        case nil:
            switch tier {
            case .healthy:
                return String(localized: "Wherever the table can see this Pawn, it sees this Health Bar — Healthy.")
            case .bloodied:
                return String(localized: "Wherever the table can see this Pawn, it sees this Health Bar — Bloodied.")
            case .critical:
                return String(localized: "Wherever the table can see this Pawn, it sees this Health Bar — Critical.")
            }
        }
    }
}

/// The DM's exact Health Bar, drawn under a whole row of the Control Window's lists: the
/// track runs the row's width less a margin each side, and the fill is current over maximum
/// of that track — so a goblin at half reads as half the row, not half of "13/13" (ADR-0036).
///
/// Under the row rather than in it, so it costs the row's flexible member — the name — not a
/// point of width, only a few points of height. Pinned by `HealthBarReadoutLayoutTests`.
struct HealthBarRowBar: View {
    let bar: HealthBar
    let withholding: PlayerVisibility.HealthBarWithholding?

    /// Thicker than a hairline, so the tier's colour reads at a glance down the list, and
    /// thinner than a control, so it is never mistaken for a slider.
    static let height: CGFloat = 4
    /// Between the row's controls and the bar.
    static let gap: CGFloat = 3
    /// Each side of the track, so it reads as belonging to its row rather than as a rule
    /// across the panel — the Divider between rows is the rule.
    static let margin: CGFloat = 4

    /// A withheld bar is still drawn, faded, rather than replaced by a glyph: the DM keeps
    /// the exact picture, and the tooltip says which switch withholds it.
    static let withheldOpacity: Double = 0.3

    /// The empty part, against the panel rather than a Map: the table's dark track vanished
    /// on the dark appearance, and with it the length the fill is a fraction of.
    static let trackColor = Color.primary.opacity(0.2)

    var body: some View {
        HealthBarStrip(bar: bar, track: Self.trackColor)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .padding(.horizontal, Self.margin)
            .opacity(withholding == nil ? 1 : Self.withheldOpacity)
            .help(HealthBarReadout.tooltip(for: bar.tier, withholding: withholding))
            .accessibilityHidden(true)
    }
}

extension View {
    /// This row with the DM's Health Bar across its foot — nothing at all for a Pawn that
    /// carries none (a Treasure, or no hit points to be a fraction of), so its row is
    /// exactly as it was.
    func healthBarUnderRow(kind: PawnKind, stats: StatBlock, areHealthBarsOn: Bool) -> some View {
        VStack(alignment: .leading, spacing: HealthBarRowBar.gap) {
            self
            if let bar = HealthBar(kind: kind, stats: stats) {
                HealthBarRowBar(bar: bar,
                                withholding: PlayerVisibility.healthBarWithholding(
                                    stats: stats, areHealthBarsOn: areHealthBarsOn))
            }
        }
    }
}
