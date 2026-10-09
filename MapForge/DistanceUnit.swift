import CoreGraphics
import Foundation

/// The unit the table speaks distances in.
///
/// Distances are *stored* in Grid squares — as a `Light`'s radii and a `Pawn`'s sight
/// already are — and converted only when shown. This type is that conversion, kept in one
/// place so a unit is a case rather than a `* 1.5` spread across call sites. The one in
/// force is the DM's, chosen per Mac (`AppState.distanceUnit`, ADR-0027).
///
/// See `CONTEXT.md`'s **Distance Unit**.
enum DistanceUnit: String, CaseIterable, Identifiable {
    /// 1.5 m to the square — the metric 5e convention, so a fireball is 6 m and a
    /// longbow 45 m, which are the numbers on a metric stat block.
    case metres

    /// 5 ft to the square — the convention every English book prints, so a fireball is 20 ft
    /// and a longbow 150 ft. A name for the same square as `metres`, never a conversion of it:
    /// 1.5 m is really 4.92 ft, and no table says so.
    case feet

    var id: String { rawValue }

    /// How much of this unit one Grid square is worth.
    var perSquare: CGFloat {
        switch self {
        case .metres: 1.5
        case .feet: 5
        }
    }

    var symbol: String {
        switch self {
        case .metres: "m"
        // Not translated: no edition outside English is in feet, so there is no book word
        // to use instead (ADR-0022).
        case .feet: "ft"
        }
    }

    /// The finest step a distance is said in: a tenth of a metre, but a whole foot — a
    /// square is 5 of them, and nobody says "37.3 feet" of a Line that does not snap.
    private var roundingStep: CGFloat {
        switch self {
        case .metres: 0.1
        case .feet: 1
        }
    }

    /// The unit a Mac starts in before the DM chooses: feet where the region measures in US
    /// customary units, metres everywhere else — the UK included, whose system is metric
    /// with exceptions, and whose tables are the DM's to switch.
    init(region: Locale) {
        self = region.measurementSystem == .us ? .feet : .metres
    }

    func display(fromSquares squares: CGFloat) -> CGFloat { squares * perSquare }

    func squares(fromDisplay display: CGFloat) -> CGFloat { display / perSquare }

    /// The number a field shows for a stored distance: the one `format` would say, without
    /// the symbol — so "33" for the 6.667 squares a metric table typed as 10 m.
    func entry(squares: CGFloat) -> Double {
        Double((display(fromSquares: squares) / roundingStep).rounded() * roundingStep)
    }

    /// The stored distance once a field hands a number back.
    ///
    /// Exact, never snapped: "sight 32 ft" is 6.4 squares, because the DM typed it and meant
    /// it. But a number equal to what the field was showing is the field being left alone —
    /// tabbing through it, or OK on a sheet the DM opened to change a colour — and leaves
    /// `stored` untouched, or every save would grind a rounded reading back into the file.
    func squares(entered: Double, replacing stored: CGFloat) -> CGFloat {
        entered == entry(squares: stored) ? stored : squares(fromDisplay: CGFloat(entered))
    }

    /// A distance as the DM would say it: "9 m", "7.5 m", "7,5 m" at an Italian table, or
    /// "30 ft".
    ///
    /// A trailing `.0` is dropped because every whole distance is read aloud without it,
    /// while a half square has to keep its fraction — to two places in French, because the
    /// French book writes "1,50 m" (`docs/terminology.md`, Distances). Feet never have one —
    /// see `roundingStep`.
    func format(squares: CGFloat, locale: Locale = .interface) -> String {
        let rounded = entry(squares: squares)
        let places = rounded == rounded.rounded() ? 0
            : locale.language.languageCode == .french ? 2 : 1
        let text = rounded.formatted(.number.precision(.fractionLength(places))
                                         .grouping(.never)
                                         .locale(locale))
        return "\(text) \(symbol)"
    }
}
