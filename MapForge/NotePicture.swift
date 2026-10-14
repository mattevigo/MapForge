import Foundation

/// The picture a note's `image:` names, found among the Workspace's files — or why it was not.
///
/// Found exactly or not at all (ADR-0028). A link with a folder in it names the one file whose
/// path ends with it — Obsidian writes the shortest path that is unique, so the folder may be
/// only the last of several; a bare name counts only when one file in the Workspace has it. Obsidian's rule for choosing
/// between two pictures of one name depends on settings the app cannot see, so the app never
/// chooses: two pictures of one name give no Face, and the DM is told why, so a
/// path-qualified link can settle it.
enum NotePicture: Equatable {
    /// Relative to the Workspace root.
    case found(String)
    /// The link as the note wrote it, naming no file in the Workspace.
    case missing(link: String)
    /// The link as the note wrote it, a name or a path more than one file has.
    case ambiguous(link: String)
    /// The link as the note wrote it, naming a file that is no PNG, JPEG or WebP — the
    /// formats a Map accepts, and so the formats a Face is cut from.
    case notAPicture(link: String)

    /// The picture `link` names among `files`, every file in the Workspace outside hidden
    /// folders, relative to its root. Case is ignored, as the Mac's own disks ignore it.
    static func resolve(_ link: String, among files: [String]) -> NotePicture {
        let wanted = link.lowercased()
        let matches = files.filter { file in
            let file = file.lowercased()
            return file == wanted || file.hasSuffix("/" + wanted)
        }
        switch matches.count {
        case 0: return .missing(link: link)
        case 1:
            let type = (matches[0] as NSString).pathExtension.lowercased()
            return pictureTypes.contains(type) ? .found(matches[0]) : .notAPicture(link: link)
        default: return .ambiguous(link: link)
        }
    }

    /// The extensions of `FacePicture.types`.
    private static let pictureTypes: Set<String> = ["png", "jpg", "jpeg", "webp"]

    /// The picture's path, when it was found.
    var path: String? {
        guard case .found(let path) = self else { return nil }
        return path
    }

    /// Why the note's picture gives no Face, in words for the DM — or nil when it was found.
    var problem: String? {
        switch self {
        case .found: nil
        case .missing(let link):
            String(localized: "image: “\(link)” is not in the Workspace")
        case .ambiguous(let link):
            String(localized: "image: “\(link)” matches more than one picture; give its folder too")
        case .notAPicture(let link):
            String(localized: "image: “\(link)” is not a PNG, JPEG or WebP picture")
        }
    }
}
