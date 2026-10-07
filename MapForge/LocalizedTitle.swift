import Foundation

/// A closed set of rulebook terms the UI lists — Skills, Conditions — named in the Interface
/// Language and, where the English list is alphabetical, listed alphabetically in it too.
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
}
