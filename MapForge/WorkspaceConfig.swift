import Foundation

/// `.mapforge/config.json`: what the DM sets by hand, there being no settings screen.
///
/// One JSON object, one property per setting, every one optional — so the file a DM writes
/// for one setting is not a broken file to the next. The Bestiary's folder is the first.
///
/// **Read, and never written by the app.** That is the whole difference from
/// `preferences.json` (`WorkspaceSettings`), which the app writes and whose store forgives an
/// unreadable file by overwriting it with defaults: right for a file only the app touches,
/// and a way to lose the active Party to one stray comma in a file a DM edits. A typo here
/// costs what the file configures and nothing else. See ADR-0020.
///
/// No `version`: the DM is the only writer, keys the app does not know are ignored, and a
/// setting that ever changes meaning can take a new name.
struct WorkspaceConfig: Decodable, Equatable {
    /// The folder holding the notes the Bestiary is read from, **relative to the Workspace
    /// root** so that it travels with the Workspace (ADR-0012): `"03_Bestiario"`.
    ///
    /// "StatBlock" here is the notes' ```` ```statblock ```` notation — the DM's word for what
    /// the folder holds — and not the domain's **Stat Block**, which is a Pawn's live numbers
    /// (`CONTEXT.md`, **Monster**). The key is spelled as the DM chose it.
    var bestiaryStatBlockPath: String?

    enum Unreadable: Error, Equatable {
        case missing
        case malformed
    }

    /// The Workspace's configuration as it stands on disk.
    static func read(from workspace: Workspace,
                     fileManager: FileManager = .default) -> Result<WorkspaceConfig, Unreadable> {
        guard fileManager.fileExists(atPath: workspace.configURL.path) else {
            return .failure(.missing)
        }
        guard let data = try? Data(contentsOf: workspace.configURL),
              let config = try? JSONDecoder().decode(WorkspaceConfig.self, from: data) else {
            return .failure(.malformed)
        }
        return .success(config)
    }
}
