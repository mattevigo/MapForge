import Foundation

/// The two directions of the Map name a Session Line carries.
///
/// A Line names its Map by a path relative to the Workspace root — `maps/crypt/dungeon.png`.
/// Relative because the Workspace travels and the machine does not (ADR-0012); a path rather
/// than a bare file name because resolving an Encounter's Combat Log goes through this field,
/// and two Maps of one name in different folders are indistinguishable by name alone
/// (ADR-0016).
///
/// Both directions live here so the spelling is stated once: the writer and the Log View's
/// reader cannot drift apart about what a `/` means.
enum SessionMapPath {

    /// A Map's path relative to its Workspace, or its file name when it lies outside one.
    ///
    /// A Map outside the Workspace has no relative path to give, and `../../elsewhere.png`
    /// would be a path that means nothing once the Workspace moves — the bare name at least
    /// reads.
    static func relative(from mapURL: URL, to workspace: Workspace) -> String {
        let root = workspace.url.standardizedFileURL.pathComponents
        let map = mapURL.standardizedFileURL.pathComponents
        guard map.count > root.count, Array(map.prefix(root.count)) == root else {
            return mapURL.lastPathComponent
        }
        return map.dropFirst(root.count).joined(separator: "/")
    }

    /// The Map a Line names, resolved back against the Workspace it was written in.
    ///
    /// Nil when the Line named no Map. The URL is returned whether or not a file is there:
    /// telling a DM their Map has moved is the caller's business, and a caller that wants to
    /// say so needs the path it looked for.
    static func resolve(_ name: String?, in workspace: Workspace) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        return workspace.url.appendingPathComponent(name)
    }
}
