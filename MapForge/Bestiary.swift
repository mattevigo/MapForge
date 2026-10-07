import Foundation

/// Every Monster the app has read from the Workspace — what a DM searches when saying what a
/// Creature is.
///
/// A reading, never a store: it is rebuilt from the DM's notes each time the Workspace opens
/// and is written nowhere (ADR-0020). A value, so the sheet searching it and the scan
/// replacing it never share anything mutable.
struct Bestiary: Equatable {
    /// Sorted by name, and unique by it — `BestiaryStore` sees to both.
    var monsters: [Monster] = []

    /// Notes that hold a statblock the app could not take. Reported rather than dropped: a
    /// Monster missing from the search without a word is the failure a DM cannot diagnose.
    var skipped: [Skipped] = []

    /// Why there is no Bestiary at all, in words for the DM — or nil when there is one.
    var unavailable: String?

    struct Skipped: Equatable, Identifiable {
        /// Relative to the Workspace root, so it reads as the DM sees it in their vault.
        var file: String
        var reason: String
        var id: String { file }
    }

    init(monsters: [Monster] = [], skipped: [Skipped] = [], unavailable: String? = nil) {
        self.monsters = monsters
        self.skipped = skipped
        self.unavailable = unavailable
    }

    /// What stands in before a Workspace is open.
    static var closed: Bestiary { Bestiary(unavailable: String(localized: "No Workspace is open.")) }

    /// What stands in while the notes are being read, so the search box can say so.
    static var reading: Bestiary { Bestiary(unavailable: String(localized: "Reading the Bestiary…")) }

    /// Whether there is anything to search. The search box is disabled without it.
    var isAvailable: Bool { unavailable == nil && !monsters.isEmpty }

    /// The Monster a Pawn remembers. Exact, not a search: a remembered name either still
    /// names a note or it does not, and a near miss must not quietly become a different
    /// creature's actions in the middle of a fight.
    func monster(named name: String?) -> Monster? {
        guard let name else { return nil }
        return monsters.first { $0.name == name }
    }

    /// Monsters whose name contains `query`, ignoring case and accents, those that *start*
    /// with it first. An empty query offers everything.
    func search(_ query: String) -> [Monster] {
        let needle = Self.folded(query.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else { return monsters }
        let matches = monsters.filter { Self.folded($0.name).contains(needle) }
        // A stable partition rather than a sort, so each half keeps the Bestiary's own
        // alphabetical order.
        return matches.filter { Self.folded($0.name).hasPrefix(needle) }
            + matches.filter { !Self.folded($0.name).hasPrefix(needle) }
    }

    /// The one line under the search box, or nil when there is nothing to say.
    ///
    /// Silent when everything was read, because a caption that is always there is one a DM
    /// stops seeing — and this is the only place a skipped note is ever mentioned.
    var caption: String? {
        if let unavailable { return unavailable }
        if monsters.isEmpty && skipped.isEmpty { return String(localized: "No Monsters found in this Workspace.") }
        guard !skipped.isEmpty else { return nil }
        // Plurals come from the catalogue, which knows every form a language has.
        let monsterCount = String(localized: "\(monsters.count) Monsters")
        let skippedCount = String(localized: "\(skipped.count) files skipped")
        return "\(monsterCount) · \(skippedCount)"
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
