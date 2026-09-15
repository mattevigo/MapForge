import Foundation

/// The settings that belong to one Workspace: which Party the panel offers, and which screen
/// this game presents on.
///
/// The split against `DisplayPreferences` is ADR-0012's: `.mapforge/` holds what the game
/// knows, `UserDefaults` holds what the machine knows. A DM who copies a Workspace to another
/// Mac should get their game and not the first Mac's hardware — so Calibration, when it
/// exists, stays keyed by `DisplayIdentity` on the machine, and these travel with the folder.
struct WorkspaceSettings: Codable, Equatable {
    var activePartyID: UUID?
    var playerDisplay: DisplayIdentity?

    init(activePartyID: UUID? = nil, playerDisplay: DisplayIdentity? = nil) {
        self.activePartyID = activePartyID
        self.playerDisplay = playerDisplay
    }
}

/// Reads and writes `.mapforge/preferences.json`.
///
/// Deliberately gentler than `PartyStore`: these are choices a DM can remake with one click,
/// not a roster typed in by hand. So an unreadable file is *not* a latch that refuses every
/// later write — it starts from defaults and the next choice overwrites it. Losing which
/// screen was picked costs a click; losing the party costs an evening.
final class WorkspacePreferencesStore {
    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    var fileURL: URL { directory.appendingPathComponent("preferences.json") }

    func load() -> WorkspaceSettings {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder.workspace.decode(WorkspaceSettings.self, from: data)
        else { return WorkspaceSettings() }
        return settings
    }

    func save(_ settings: WorkspaceSettings) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder.workspace.encode(settings).write(to: fileURL, options: .atomic)
        } catch {
            // Non-fatal and quiet, matching `AppState.writeParties`: a failed preference write
            // must not interrupt a session, and the in-memory value stays correct for the run.
            NSLog("MapForge: could not save workspace preferences: \(error)")
        }
    }
}
