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

    func display(fromSquares squares: CGFloat) -> CGFloat { squares * perSquare }

    func squares(fromDisplay display: CGFloat) -> CGFloat { display / perSquare }

    /// A distance as the DM would say it: "9 m", "7.5 m", "7,5 m" at an Italian table, or
    /// "30 ft".
    ///
    /// A trailing `.0` is dropped because every whole distance is read aloud without it,
    /// while a half square has to keep its fraction — to two places in French, because the
    /// French book writes "1,50 m" (`docs/terminology.md`, Distances). Feet are always whole:
    /// a square is 5 of them, and nobody says "37.3 feet" of a path that is not.
    func format(squares: CGFloat, locale: Locale = .interface) -> String {
        let value = display(fromSquares: squares)
        let rounded = self == .feet ? Double(value.rounded())
            : Double((value * 10).rounded() / 10)
        let places = rounded == rounded.rounded() ? 0
            : locale.language.languageCode == .french ? 2 : 1
        let text = rounded.formatted(.number.precision(.fractionLength(places))
                                         .grouping(.never)
                                         .locale(locale))
        return "\(text) \(symbol)"
    }
}
