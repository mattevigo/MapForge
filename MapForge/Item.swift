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
