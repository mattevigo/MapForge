import Foundation

/// A note the app read and could not take, and why: a statblock it could not read, a second
/// note of a name, a frontmatter that says `item:` and is not YAML. Reported rather than
/// dropped — a definition missing from the search without a word is the failure a DM cannot
/// diagnose. The same for the Bestiary, the Treasury and the Characters' notes.
struct SkippedNote: Equatable, Identifiable {
    /// Relative to the Workspace root, so it reads as the DM sees it in their vault.
    var file: String
    var reason: String
    var id: String { file }
}

/// Definitions read from the DM's notes that a search box offers — the `Bestiary`'s
/// Monsters, the `Treasury`'s Items — and what the box says about them: what stands in before
/// they are read, whether there is anything to search, and the one line under it.
protocol DefinitionShelf {
    associatedtype Definition
    var definitions: [Definition] { get }
    /// The notes that meant to be one of these and could not be taken.
    var skipped: [SkippedNote] { get }
    /// Why there are no definitions at all, in words for the DM — or nil when they were read.
    var unavailable: String? { get }

    /// A shelf with nothing on it, which says `reason` instead.
    static func empty(because reason: String) -> Self
    /// "Reading the Bestiary…", said while the notes are being read.
    static var whileReading: String { get }
    /// "No Monsters found in this Workspace.", said when the notes hold none.
    static var noneFound: String { get }
    /// "27 Monsters", in the caption beside the skipped notes. From the catalogue, which
    /// knows every plural form a language has.
    static func counted(_ count: Int) -> String
}

extension DefinitionShelf {
    /// What stands in before a Workspace is open.
    static var closed: Self { empty(because: String(localized: "No Workspace is open.")) }

    /// What stands in while the notes are being read, so the search box can say so.
    static var reading: Self { empty(because: whileReading) }

    /// Whether there is anything to search. The search box is disabled without it.
    var isAvailable: Bool { unavailable == nil && !definitions.isEmpty }

    /// The one line under the search box, or nil when there is nothing to say.
    ///
    /// Silent when everything was read, because a caption that is always there is one a DM
    /// stops seeing — and this is the only place a skipped note is ever mentioned.
    var caption: String? {
        if let unavailable { return unavailable }
        if definitions.isEmpty && skipped.isEmpty { return Self.noneFound }
        guard !skipped.isEmpty else { return nil }
        let skippedCount = String(localized: "\(skipped.count) files skipped")
        return "\(Self.counted(definitions.count)) · \(skippedCount)"
    }
}
