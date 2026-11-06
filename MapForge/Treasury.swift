import Foundation

/// A thing the DM's notes define and a Treasure can be said to be — a Borsa, a Gemma di Fuoco.
/// To a Treasure what a `Monster` is to a Creature: a definition, never on a Map.
///
/// A note is an Item when its frontmatter says `item: true` (ADR-0031). Read from the notes
/// each time the Workspace opens, and written nowhere.
struct Item: Equatable, Identifiable {
    /// The note's first `#` heading, else its file name with `_` read as spaces. What a
    /// Treasure remembers its Item by. Unique within the `Treasury`.
    var name: String

    /// The note it was read from, relative to the Workspace root.
    var file = ""
    /// The picture the frontmatter's `image:` links to, as the link names it, or nil when it
    /// names none — read exactly as a fence's `image:` is (ADR-0028). The body's embeds are
    /// never read.
    var imageLink: String?
    /// That picture found among the Workspace's files, or why it was not. Nil with no
    /// `image:`. What the Item's Face is cut from.
    var picture: NotePicture?

    var id: String { name }
}

extension Item: PicturedNote {}

/// Every Item the app has read from the Workspace — what a DM searches when saying what a
/// Treasure is. The `Bestiary`'s sibling, read in the same walk (`BestiaryStore`), and like it
/// a reading, never a store (ADR-0020).
struct Treasury: Equatable {
    /// Sorted by name, and unique by it — `BestiaryStore` sees to both.
    var items: [Item] = []

    /// Notes that say they are Items and that the app could not take. Reported rather than
    /// dropped, as the Bestiary's are.
    var skipped: [Bestiary.Skipped] = []

    /// Why there is no Treasury at all, in words for the DM — or nil when there is one.
    var unavailable: String?

    init(items: [Item] = [], skipped: [Bestiary.Skipped] = [], unavailable: String? = nil) {
        self.items = items
        self.skipped = skipped
        self.unavailable = unavailable
    }

    /// What stands in before a Workspace is open.
    static var closed: Treasury { Treasury(unavailable: String(localized: "No Workspace is open.")) }

    /// What stands in while the notes are being read, so the search box can say so.
    static var reading: Treasury { Treasury(unavailable: String(localized: "Reading the Items…")) }

    /// Whether there is anything to search. The search box is disabled without it.
    var isAvailable: Bool { unavailable == nil && !items.isEmpty }

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

    /// The one line under the search box, or nil when there is nothing to say — silent when
    /// everything was read, as the Bestiary's is.
    var caption: String? {
        if let unavailable { return unavailable }
        if items.isEmpty && skipped.isEmpty { return String(localized: "No Items found in this Workspace.") }
        guard !skipped.isEmpty else { return nil }
        let itemCount = String(localized: "\(items.count) Items")
        let skippedCount = String(localized: "\(skipped.count) files skipped")
        return "\(itemCount) · \(skippedCount)"
    }
}
