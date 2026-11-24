import SwiftUI

/// A Pawn's hit points as the DM reads them in the Control Window's rows: the numbers, and
/// under them the exact Health Bar in the tier the table is being shown (ADR-0036).
///
/// The DM's Map never draws a Health Bar, so this is the only place the DM can check what
/// the table sees. One view for the Scene tab's Pawn rows and the Encounter tab's Order
/// rows, so the two tabs cannot come to show it differently.
///
/// The bar sits *under* the numbers and is exactly as wide as they are. The Order row is
/// already full at the live panel's fixed width, and the column that would give way is the
/// name — the thing a DM reads fastest in a fight. Pinned by `HealthBarReadoutLayoutTests`.
struct HealthBarReadout: View {
    let kind: PawnKind
    let stats: StatBlock
    /// The Live Toolbar's **Health Bars** switch. No default, for the reason
    /// `PlayerVisibility.showsHealthBarToPlayers` has none: a row that forgot the switch
    /// would tell the DM the table sees a bar it does not.
    let areHealthBarsOn: Bool
    /// Whether a Stat Block without hit points gets the orange ⚠️. The Encounter tab's
    /// rows flag it — a monster with no numbers must not silently drop out of a fight —
    /// and the Scene tab's do not, where most Pawns are never given any.
    let flagsIncompleteStatBlock: Bool

    /// Thin, so it adds a few points to the row's height and reads as an underline of the
    /// numbers rather than as a control.
    static let barHeight: CGFloat = 3
    static let barGap: CGFloat = 1

    /// A withheld bar is still drawn, faded, rather than replaced by a glyph: the DM keeps
    /// the exact picture, and the row does not grow a column the name would pay for.
    static let withheldOpacity: Double = 0.3

    var body: some View {
        if let current = stats.currentHP, let max = stats.maxHP {
            // None for a Treasure, which keeps the numbers its rows always had and never
            // carries a bar — `HealthBar` decides, as it does for the table.
            let bar = HealthBar(kind: kind, stats: stats)
            numbers(current: current, max: max)
                .padding(.bottom, bar == nil ? 0 : Self.barHeight + Self.barGap)
                .background(alignment: .bottom) {
                    if let bar {
                        HealthBarStrip(bar: bar)
                            .frame(height: Self.barHeight)
                            .opacity(withholding == nil ? 1 : Self.withheldOpacity)
                    }
                }
                .help(bar.map(help) ?? "")
        } else if flagsIncompleteStatBlock {
            // Flagged, never hidden: a forgotten Stat Block must not silently drop a
            // monster from the fight.
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("No hit points yet — fill them in below.")
                .accessibilityIdentifier("incomplete-stat-block")
        }
    }

    private var withholding: HealthBar.Withholding? {
        PlayerVisibility.healthBarWithholding(stats: stats, areHealthBarsOn: areHealthBarsOn)
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
    private func help(_ bar: HealthBar) -> String {
        switch withholding {
        case .allBars:
            return String(localized: "The table sees no Health Bars: the Health Bars switch is off.")
        case .thisPawn:
            return String(localized: "The table does not see this Health Bar: it is withheld in Edit Pawn.")
        case nil:
            switch bar.tier {
            case .healthy: return String(localized: "The table sees this Health Bar — Healthy.")
            case .bloodied: return String(localized: "The table sees this Health Bar — Bloodied.")
            case .critical: return String(localized: "The table sees this Health Bar — Critical.")
            }
        }
    }
}

/// The bar itself: the track, the fill in its tier's colour, and the temporary hit points
/// straight after it in teal. Fractions come from `HealthBar`, so the DM's bar and the
/// table's are cut at the same point.
private struct HealthBarStrip: View {
    let bar: HealthBar

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                // Drawn at 0 too: an empty track is how a Pawn that is down reads.
                Rectangle().fill(HealthBar.trackColor)
                Rectangle()
                    .fill(HealthBar.temporaryColor)
                    .frame(width: width * (bar.fill + bar.temporary))
                Rectangle()
                    .fill(bar.tier.color)
                    .frame(width: width * bar.fill)
            }
        }
        .clipShape(Capsule())
    }
}
