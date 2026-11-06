import Foundation
import Yams

/// Reads the Item out of one of the DM's notes, from its frontmatter (ADR-0031).
///
/// An item note has no `statblock` fence — it has no numbers — so it says what it is where
/// every Obsidian note can say something about itself: the YAML between the `---` lines at
/// its top. Two English keys are read, and nothing else: `item: true`, and `image:`, its
/// Portrait. The body is the DM's prose and is never read beyond its first heading.
///
/// Yams reads the YAML, as it reads a fence (ADR-0019); what an Item *is* is decided here.
enum ItemReader {
    enum Reading: Equatable {
        /// No frontmatter, or one that does not say `item: true`. Not worth reporting.
        case notAnItem
        case item(Item)
        /// A note the DM meant as an Item and the app could not read.
        case skipped(reason: String)
    }

    /// The Item `markdown` defines, the note being `file`, relative to the Workspace root.
    static func read(_ markdown: String, file: String) -> Reading {
        guard let split = frontmatter(of: markdown) else { return .notAnItem }
        let fields: [String: Any]
        do {
            guard let loaded = try Yams.load(yaml: split.yaml) as? [String: Any] else {
                return unreadable(split.yaml, reason: String(localized: "the frontmatter is not a list of fields"))
            }
            fields = loaded
        } catch {
            return unreadable(split.yaml, reason: String(localized: "the frontmatter is not valid YAML"))
        }
        guard fields["item"] as? Bool == true else { return .notAnItem }
        var item = Item(name: heading(in: split.body) ?? name(ofFile: file), file: file)
        item.imageLink = StatblockReader.imageLink(fields["image"])
        return .item(item)
    }

    /// A frontmatter YAML cannot read, reported only when it writes an `item:` key anywhere —
    /// on a line of its own, in a list, or in a flow mapping such as `{item: true, …}`.
    ///
    /// Every Obsidian note may have a frontmatter, and the Treasury has no business with a
    /// tavern's broken tag list: only a note that at least *wrote* `item:` was meant as an
    /// Item, and only that one is missed from the search if it goes unreported. `item` as a
    /// word of its own, so `magic-item:` and `items:` are not it. Text the YAML cannot read
    /// cannot be told key from value, so an `item:` inside a value counts too: a note
    /// reported that was not meant is a smaller harm than one dropped in silence.
    private static func unreadable(_ yaml: String, reason: String) -> Reading {
        let mentionsItem = yaml.range(of: #"(?<![\w-])item\s*:"#, options: .regularExpression) != nil
        return mentionsItem ? .skipped(reason: reason) : .notAnItem
    }

    /// "Gemma di Fuoco" for `Homebrew/Gemma_di_Fuoco.md`: DM Realm writes a name's spaces as
    /// underscores in its file names.
    static func name(ofFile file: String) -> String {
        ((file as NSString).lastPathComponent as NSString).deletingPathExtension
            .replacingOccurrences(of: "_", with: " ")
    }

    /// The YAML between the note's opening `---` and the next `---`, and the lines after it.
    /// Nil when the note does not open with one, or never closes it.
    static func frontmatter(of markdown: String) -> (yaml: String, body: [Substring])? {
        // CRLF folded first, as `StatblockReader.fence` does.
        let unixed = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = unixed.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let end = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else { return nil }
        return (lines[1..<end].joined(separator: "\n"), Array(lines[(end + 1)...]))
    }

    /// The text of the first `# ` heading among `lines`, or nil when there is none.
    private static func heading(in lines: [Substring]) -> String? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("# ") else { continue }
            let text = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return text }
        }
        return nil
    }
}
