import Foundation

/// A closed set of rulebook terms the UI lists — Abilities, Skills, Conditions — named in the
/// Interface Language and, where the English list is alphabetical, listed alphabetically in it
/// too. Matched back from the DM's notes by the same names, in any language (`named(_:)`).
///
/// A title is a resource rather than a resolved `String` so it can be named in a language other
/// than the one this launch speaks: that is what lets the order be tested in Italian without
/// relaunching in it.
protocol LocalizedTitle: CaseIterable {
    var titleResource: LocalizedStringResource { get }
}

extension LocalizedTitle {
    /// The title in the Interface Language this launch speaks.
    var title: String { title(in: .interface) }

    func title(in locale: Locale) -> String {
        var resource = titleResource
        resource.locale = locale
        return String(localized: resource)
    }

    /// Every case, alphabetical by its title in `locale` and by that language's collation.
    ///
    /// For lists whose English order *is* the alphabet: kept in declaration order they would
    /// stay alphabetical in English alone, and an Italian DM looking for *Furtività* would find
    /// it under S, where Stealth sits.
    static func alphabetical(in locale: Locale = .interface) -> [Self] {
        allCases.sorted {
            $0.title(in: locale).compare($1.title(in: locale), locale: locale) == .orderedAscending
        }
    }

    /// The case a DM's note means by `written` — "Saggezza ●", "wisdom", "Sabiduría" — or nil.
    ///
    /// A note is written in its table's language, not in the one this Mac speaks, so the name
    /// is matched against the title in every language the app ships: those are the rulebook's
    /// own terms (ADR-0022). Case and accents are ignored, and so is the trailing `●` the vault
    /// marks a proficient save with. Nothing else is: an abbreviation is not the rulebook's
    /// name, and a near miss must not quietly become another Ability's bonus (ADR-0029).
    static func named(_ written: String) -> Self? {
        let wanted = rulebookKey(written.replacingOccurrences(of: "●", with: ""))
        guard !wanted.isEmpty else { return nil }
        return allCases.first { candidate in
            Locale.shipped.contains { rulebookKey(candidate.title(in: $0)) == wanted }
        }
    }

    private static func rulebookKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

extension Locale {
    /// Every language the app speaks, from its bundle — "Base" is a folder, not a language.
    static let shipped: [Locale] = Bundle.main.localizations
        .filter { $0 != "Base" }
        .map(Locale.init(identifier:))
}
