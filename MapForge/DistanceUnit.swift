import CoreGraphics
import Foundation

/// The unit the table speaks distances in.
///
/// Distances are *stored* in Grid squares — as a `Light`'s radii and a `Pawn`'s sight
/// already are — and converted only when shown. This type is that conversion, and it is an
/// enum rather than a constant because feet is the unit this is meant to become: with the
/// conversion in one place that is a case and a picker, whereas a `* 1.5` spread across
/// call sites is a hunt.
///
/// See `CONTEXT.md`'s **Distance Unit**.
enum DistanceUnit: CaseIterable {
    /// 1.5 m to the square — the metric 5e convention, so a fireball is 6 m and a
    /// longbow 45 m, which are the numbers on a metric stat block.
    case metres

    /// How much of this unit one Grid square is worth.
    var perSquare: CGFloat {
        switch self {
        case .metres: 1.5
        }
    }

    var symbol: String {
        switch self {
        case .metres: "m"
        }
    }

    func display(fromSquares squares: CGFloat) -> CGFloat { squares * perSquare }

    func squares(fromDisplay display: CGFloat) -> CGFloat { display / perSquare }

    /// A distance as the DM would say it: "9 m", "7.5 m".
    ///
    /// A trailing `.0` is dropped because every whole distance is read aloud without it,
    /// while a half square has to keep its fraction.
    func format(squares: CGFloat) -> String {
        let value = display(fromSquares: squares)
        let rounded = (value * 10).rounded() / 10
        let text = rounded == rounded.rounded()
            ? String(Int(rounded.rounded()))
            : String(format: "%.1f", rounded)
        return "\(text) \(symbol)"
    }

    /// The unit in force. A constant, deliberately: no preference surface and nothing
    /// persisted until there is a second case worth choosing between.
    static let current: DistanceUnit = .metres
}
