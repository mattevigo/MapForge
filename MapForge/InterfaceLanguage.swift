import Foundation

extension Locale {
    /// The locale of the Interface Language this launch is actually speaking.
    ///
    /// Numbers follow the words: a DM who reads German on screen reads "1,5 m", whatever
    /// region the Mac is set to. The bundle's resolved localisation is the truth here, not the
    /// preference — a language chosen in Settings applies only after a relaunch, so until then
    /// the words on screen are still the old ones and the numbers must match them.
    static var interface: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}

extension Int {
    /// A whole number as the table's book prints it: "1,100" in English, "1.100" in Italian,
    /// "1 100" in French (`docs/terminology.md`, Numbers).
    ///
    /// macOS's own format for the language, but for Italian: macOS leaves four digits ungrouped
    /// there, while the Italian book's XP tables group them ("1.100 PE"). Italian is grouped
    /// from four digits by a formatter given its own separator, never by hand.
    func grouped(in locale: Locale = .interface) -> String {
        guard locale.language.languageCode == .italian else {
            return formatted(.number.locale(locale))
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.groupingSeparator = locale.groupingSeparator
        return formatter.string(from: self as NSNumber) ?? formatted(.number.locale(locale))
    }
}

/// A language MapForge can speak, or `system` for whichever one macOS picks.
///
/// See `CONTEXT.md`'s **Interface Language**. Each case's raw value is the localisation it
/// selects — the code macOS reads from `AppleLanguages` at launch.
enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case italian = "it"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case portuguese = "pt-BR"
    case greek = "el"

    var id: String { rawValue }

    /// The language the next launch will speak, when it differs from the one this launch is
    /// `running`; `nil` when a relaunch would change nothing.
    ///
    /// `macLanguages` is the Mac's own preference list, which decides for `system`.
    static func nextLaunch(chosen: InterfaceLanguage, running: String,
                           macLanguages: [String]) -> InterfaceLanguage? {
        let next = chosen == .system ? resolved(from: macLanguages) : chosen
        return next == Self(code: running) ? nil : next
    }

    /// What macOS picks from a preference list among the languages MapForge speaks —
    /// English, the development language, when it speaks none of them.
    private static func resolved(from preferences: [String]) -> InterfaceLanguage {
        let spoken = allCases.filter { $0 != .system }.map(\.rawValue)
        return Bundle.preferredLocalizations(from: spoken, forPreferences: preferences)
            .first.flatMap(Self.init(code:)) ?? .english
    }

    /// The language a localisation code selects: exactly, or by its language alone, since
    /// System Settings may write a region the picker does not offer ("it-IT", "pt-PT").
    init?(code: String) {
        if let exact = Self(rawValue: code), exact != .system {
            self = exact
            return
        }
        let language = Locale.Language(identifier: code).languageCode
        guard let match = Self.allCases.first(where: {
            $0 != .system && Locale.Language(identifier: $0.rawValue).languageCode == language
        }) else { return nil }
        self = match
    }
}
