import Foundation

/// The folder a DM keeps their game in: their Maps, arranged however they arrange them, with
/// `.mapforge/` at its root for everything the app knows that is not about a Map.
///
/// A value, not a manager — it is a URL and the paths derived from it. Nothing else in the
/// app concatenates `.mapforge`, so the layout is stated once, here.
///
/// A Workspace is not a campaign. A DM may keep one in it or a dozen; the app draws no line
/// between them, because the DM already draws that line in Finder. See ADR-0011.
struct Workspace: Equatable, Hashable {
    /// The folder the DM chose. Everything else is derived from it.
    let url: URL

    init(url: URL) {
        // Normalised so two spellings of one folder — a trailing slash, a `//`, a `..` — are
        // one Workspace to `Equatable`, and the recents list cannot show the same folder
        // twice. Built from the standardised *path* rather than `standardizedFileURL`, which
        // preserves the trailing slash on a directory URL and so leaves "/Maps" and "/Maps/"
        // unequal.
        self.url = URL(fileURLWithPath: (url.path as NSString).standardizingPath)
    }

    /// The Workspace's name is its folder's name. Nothing is stored, so there is nothing to
    /// drift out of step when the DM renames it in Finder.
    var name: String { url.lastPathComponent }

    var supportDirectory: URL { url.appendingPathComponent(".mapforge") }
    var manifestURL: URL { supportDirectory.appendingPathComponent("workspace.json") }
    var partiesURL: URL { supportDirectory.appendingPathComponent("parties.json") }
    var preferencesURL: URL { supportDirectory.appendingPathComponent("preferences.json") }
}

/// The file whose presence makes a folder a Workspace.
///
/// It records the layout's version and what wrote it, and nothing else. In particular it does
/// **not** record a name: the folder is the name, and a stored one would be a second source of
/// truth that drifts the moment the DM renames the folder.
struct WorkspaceManifest: Codable, Equatable {
    static let current = 1

    var version: Int
    var createdAt: Date
    /// The app's `CFBundleShortVersionString` at creation. Diagnostic only — it answers "what
    /// wrote this?" the first time a DM reports a file the app will not open.
    var createdBy: String

    init(version: Int = WorkspaceManifest.current,
         createdAt: Date = Date(),
         createdBy: String = WorkspaceManifest.appVersion) {
        self.version = version
        self.createdAt = createdAt
        self.createdBy = createdBy
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
    }

    private enum CodingKeys: String, CodingKey {
        case version, createdAt, createdBy
    }

    /// Hand-written for one deliberate difference from `PartyBook`, which defaults a missing
    /// `version` to `current` (`Party.swift`) and so cannot tell a version-less file from a v1
    /// one. Here `version` is a hard decode: a Manifest without a version is not a Manifest
    /// this app wrote, and the picker must refuse rather than guess.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy) ?? "unknown"
    }
}
