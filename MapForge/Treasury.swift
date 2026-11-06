import Foundation

/// Every Item the app has read from the Workspace — what a DM searches when saying what a
/// Treasure is. The `Bestiary`'s sibling, read in the same walk (`BestiaryStore`), and like it
/// a reading, never a store (ADR-0020).
struct Treasury: Equatable {
    /// Sorted by name, and unique by it — `BestiaryStore` sees to both.
    var items: [Item] = []

    /// Notes that say they are Items and that the app could not take. Reported rather than
    /// dropped, as the Bestiary's are.
    var skipped: [SkippedNote] = []

    /// Why there is no Treasury at all, in words for the DM — or nil when there is one.
    var unavailable: String?

    init(items: [Item] = [], skipped: [SkippedNote] = [], unavailable: String? = nil) {
        self.items = items
        self.skipped = skipped
        self.unavailable = unavailable
    }

    /// The Item a Treasure remembers. Exact, not a search, as `Bestiary.monster(named:)` is.
    func item(named name: String?) -> Item? {
        guard let name else { return nil }
        return items.first { $0.name == name }
    }

    /// Items whose name contains `query`, ignoring case and accents, those that *start* with
    /// it first. An empty query offers everything.
    func search(_ query: String) -> [Item] {
        NameSearch.matches(query, among: items, name: \.name)
    }

    /// The Items whose note names a picture that gives no Face, and why.
    var pictureProblems: [PictureProblem] { items.pictureProblems }
}

/// What the Item search box says, by the Bestiary's rules: silent when everything was read.
extension Treasury: DefinitionShelf {
    var definitions: [Item] { items }
    static func empty(because reason: String) -> Treasury { Treasury(unavailable: reason) }
    static var whileReading: String { String(localized: "Reading the Items…") }
    static var noneFound: String { String(localized: "No Items found in this Workspace.") }
    static func counted(_ count: Int) -> String { String(localized: "\(count) Items") }
}
