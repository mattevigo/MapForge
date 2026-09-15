import Foundation

/// Opens and adopts Workspace folders.
///
/// `PartyStore`'s shape and `PartyStore`'s rules: a concrete class with constructor injection
/// for the test seam, atomic pretty-printed writes, and a file it could not read is reported
/// and left on disk rather than overwritten. Adoption is the one thing it creates, and it
/// creates exactly `.mapforge/` — never a Map, never a sidecar, never anything the DM put in
/// the folder themselves.
final class WorkspaceStore {
    /// Why a folder could not be opened as a Workspace.
    ///
    /// `notAWorkspace` and `unreachable` are deliberately separate: the picker offers to adopt
    /// the first and explains an unplugged drive for the second, and collapsing them would
    /// make a DM whose external disk is missing look like a DM who picked the wrong folder.
    enum OpenFailure: Error, Equatable {
        /// The folder is there and is not a Workspace. Adoptable.
        case notAWorkspace(URL)
        /// The folder is gone, or is not a folder at all.
        case unreachable(URL)
        /// A Manifest exists and could not be read. The bytes are left alone.
        case unreadableManifest(URL)
        /// Written by a newer MapForge than this one. Refused rather than guessed at.
        case newerVersion(URL, found: Int)

        /// Whether a Manifest exists that this app could not use. Adoption must refuse these
        /// rather than write over them; the other two cases are what adoption is *for*.
        var hasAManifest: Bool {
            switch self {
            case .unreadableManifest, .newerVersion: return true
            case .notAWorkspace, .unreachable: return false
            }
        }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Whether this folder has already been adopted. Cheap enough for the picker to call per
    /// row; it stats one file.
    func isWorkspace(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: Workspace(url: url).manifestURL.path)
    }

    /// Opens an adopted folder, or says why it could not.
    ///
    /// This is the app's first real *read* of a version number. `PartyBook.version` is stamped
    /// on every save and inspected by nothing, which makes it decoration; this one decides
    /// whether the folder opens at all.
    func open(_ url: URL) -> Result<Workspace, OpenFailure> {
        let workspace = Workspace(url: url)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: workspace.url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .failure(.unreachable(workspace.url))
        }

        guard fileManager.fileExists(atPath: workspace.manifestURL.path) else {
            return .failure(.notAWorkspace(workspace.url))
        }

        let manifest: WorkspaceManifest
        do {
            let data = try Data(contentsOf: workspace.manifestURL)
            manifest = try JSONDecoder.workspace.decode(WorkspaceManifest.self, from: data)
        } catch {
            return .failure(.unreadableManifest(workspace.url))
        }

        guard manifest.version <= WorkspaceManifest.current else {
            return .failure(.newerVersion(workspace.url, found: manifest.version))
        }

        return .success(workspace)
    }

    /// Makes a folder a Workspace by writing `.mapforge/workspace.json` into it.
    ///
    /// Nothing else in the folder is read, moved or written. A DM adopting a directory full of
    /// Maps with their fog traced gets a `.mapforge` folder and no other change.
    ///
    /// Adopting a folder that is already a Workspace returns it as it stands rather than
    /// stamping a fresh Manifest over it, so re-adopting does not reset `createdAt` — and, more
    /// to the point, does not overwrite a Manifest this version may not understand.
    @discardableResult
    func adopt(_ url: URL) throws -> Workspace {
        let workspace = Workspace(url: url)
        switch open(workspace.url) {
        case .success(let existing):
            return existing
        case .failure(let failure as OpenFailure) where failure.hasAManifest:
            // A Manifest is there and this app cannot read it. Adoption is a write, and
            // writing here would destroy bytes we failed to parse — the rule `PartyStore`
            // and `FogStore` both hold. The picker turns this into a refusal the DM sees.
            throw failure
        case .failure:
            break
        }

        try fileManager.createDirectory(at: workspace.supportDirectory,
                                        withIntermediateDirectories: true)
        let encoder = JSONEncoder.workspace
        let data = try encoder.encode(WorkspaceManifest())
        try data.write(to: workspace.manifestURL, options: .atomic)
        return workspace
    }
}

extension JSONEncoder {
    /// Readable in a text editor and stable in a diff, matching `PartyStore`: a DM who keeps
    /// their game in version control should see a one-line change for a one-line change.
    static var workspace: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var workspace: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
