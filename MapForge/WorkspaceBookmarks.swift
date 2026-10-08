import Foundation

/// How a Workspace folder is reached from one launch to the next.
///
/// Under the App Sandbox a folder the DM chose is reachable for the launch it was chosen in
/// and no longer; a security-scoped bookmark is what carries the grant to the next launch.
/// Unsandboxed, the same bookmarks are made and resolved and simply grant nothing extra — so
/// the app reaches its Workspaces one way whether or not the sandbox is on. See ADR-0025.
///
/// A value of closures rather than calls in place, so a test can stand in for the system: a
/// sandbox's refusal cannot be had outside a sandbox.
struct WorkspaceBookmarks {
    /// Bookmark data for a folder the app can reach now. Throws when it cannot: a folder that
    /// is gone, or, under the sandbox, a path the DM has not chosen this launch.
    var make: (URL) throws -> Data

    /// Where a bookmark points now. Follows a folder the DM renamed or moved; throws when the
    /// folder is gone.
    ///
    /// Staleness is not reported. Every open stores a fresh bookmark
    /// (`DisplayPreferences.noteWorkspaceOpened`), which is the refresh a stale one asks for,
    /// done whether or not it asked.
    var resolve: (Data) throws -> URL

    static let securityScoped = WorkspaceBookmarks(
        make: { url in
            try url.bookmarkData(options: .withSecurityScope,
                                 includingResourceValuesForKeys: nil,
                                 relativeTo: nil)
        },
        resolve: { data in
            var isStale = false
            return try URL(resolvingBookmarkData: data,
                           options: .withSecurityScope,
                           relativeTo: nil,
                           bookmarkDataIsStale: &isStale)
        })
}

/// The system's security-scoped access calls, behind a seam so a test can count them.
///
/// Access is counted by the system: every `start` that returned `true` needs exactly one
/// `stop`, or the grant outlives its use.
struct SecurityScope {
    var start: (URL) -> Bool
    var stop: (URL) -> Void

    static let system = SecurityScope(
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() })
}
