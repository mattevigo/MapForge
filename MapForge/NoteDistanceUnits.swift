import Foundation

/// Which Distance Unit the DM's notes are written in — read, never rewritten (ADR-0027).
///
/// The Workspace holds no Distance Unit of its own: its unit is whatever its notes say. A note
/// is judged by its Speed and Senses alone, because every Monster's note has them and they are
/// short and predictable; the prose of a trait or an action is neither, and an "m" in it is as
/// likely to be a typo as a metre.
extension DistanceUnit {
    /// The Distance Units these texts name, each a number followed by the unit's word.
    ///
    /// The words are every Interface Language's, whatever language the app is in: a DM's notes
    /// are in the DM's language, which need not be the one on screen. A word that only starts
    /// with a unit ("9 mani", "30 feral") is not one.
    static func named(in texts: [String?]) -> Set<DistanceUnit> {
        var found: Set<DistanceUnit> = []
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for unit in allCases where unit.pattern.firstMatch(in: text, range: range) != nil {
                found.insert(unit)
            }
        }
        return found
    }

    /// A number, then this unit's word, then anything but another letter.
    private var pattern: NSRegularExpression {
        switch self {
        case .metres: Self.metresPattern
        case .feet: Self.feetPattern
        }
    }

    private static let metresPattern = unitPattern([
        "m", "mt", "metri", "metro", "metres", "metre", "meters", "meter", "metern", "mètres",
        "mètre", "metros", "μέτρα", "μέτρο", "μ",
    ])

    private static let feetPattern = unitPattern([
        "ft", "feet", "foot", "piedi", "piede", "fuß", "fuss", "pieds", "pied", "pies", "pie",
        "pés", "pé", "πόδια", "πόδι",
    ])

    private static func unitPattern(_ words: [String]) -> NSRegularExpression {
        let alternatives = words.map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        // Force-unwrapped: the pattern is built from the literals above, so a failure here is
        // a typo in this file, caught by the first test that runs.
        return try! NSRegularExpression(
            pattern: #"\d+(?:[.,]\d+)?\s*(?:"# + alternatives + #")(?!\p{L})"#,
            options: [.caseInsensitive])
    }
}

/// A note the DM wrote that gives distances: a Monster's, or a Character's.
protocol DistanceNote {
    var name: String { get }
    var file: String { get }
    /// What its Speed and Senses name, as read when the Workspace opened.
    var distanceUnits: Set<DistanceUnit> { get }
}

extension DistanceNote {
    /// Whether it names the unit not in force — wholly, or beside the one that is.
    func isFlagged(current: DistanceUnit) -> Bool { distanceUnits.contains(current.other) }

    /// What its reference page says when the note is in the unit not in force, or nil. Read
    /// mid-fight, where a "9 m" at a table speaking feet is the number most likely to be
    /// misread aloud.
    func warning(current: DistanceUnit) -> String? {
        guard isFlagged(current: current) else { return nil }
        switch current.other {
        case .metres: return String(localized: "This note gives distances in metres.")
        case .feet: return String(localized: "This note gives distances in feet.")
        }
    }
}

extension Monster: DistanceNote {}
extension CharacterNote: DistanceNote {}

extension DistanceUnit {
    /// The one unit every note that names a unit names, or nil when they disagree or name
    /// none. Only then is a one-click switch worth offering: with the notes mixed, switching
    /// fixes nothing, and the list of them is the useful part.
    static func agreed(by units: [Set<DistanceUnit>]) -> DistanceUnit? {
        let named = units.reduce(into: Set<DistanceUnit>()) { $0.formUnion($1) }
        return named.count == 1 ? named.first : nil
    }
}

/// The notes that give their distances in the unit the Mac is not set to — what the caption
/// under the Monster search and the Character note box counts, and lists on a click.
///
/// It only informs (ADR-0027): a flagged Monster is still found and still Stamped, because
/// armour class, hit points and initiative have no unit, and its note is never rewritten.
struct OtherUnitNotes: Equatable {
    struct Note: Equatable, Identifiable {
        var name: String
        var file: String
        var id: String { name }
    }

    /// The unit the flagged notes are in: the one not in force.
    let unit: DistanceUnit
    /// In the order they were given — the Bestiary's, by name.
    let notes: [Note]

    /// Nil when there is nothing to say, so the caption stays silent as the skipped count
    /// does. A note naming both units is flagged: half of it is in the other one.
    init?(_ notes: [some DistanceNote], current: DistanceUnit) {
        let flagged = notes.filter { $0.isFlagged(current: current) }
        guard !flagged.isEmpty else { return nil }
        unit = current.other
        self.notes = flagged.map { Note(name: $0.name, file: $0.file) }
    }

    /// "3 notes in feet". One sentence per unit rather than the unit's word spliced in, so
    /// each language can decline it.
    var caption: String {
        switch unit {
        case .metres: String(localized: "\(notes.count) notes in metres")
        case .feet: String(localized: "\(notes.count) notes in feet")
        }
    }
}
