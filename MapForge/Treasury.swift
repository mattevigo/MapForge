import Foundation

/// A thing the DM's notes define and a Treasure can be said to be — a Bag, a Gemma di Fuoco.
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

    /// The Items whose note names a picture that gives no Face, and why.
    var pictureProblems: [PictureProblem] { items.pictureProblems }
}
