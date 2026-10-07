import Foundation

/// Moves the roster that lived in Application Support into the first Workspace opened.
///
/// Four things are being moved, and nothing else ever lived outside a Map's own folder:
/// `~/Library/Application Support/MapForge/parties.json`, and the `activePartyID`,
/// `playerDisplayUUID` and `playerDisplayName` keys in `UserDefaults`.
///
/// **Copy, verify, then delete.** Never load-and-save: `PartyStore.save` deletes the file when
/// the book is empty, so a decode that silently yielded an empty book — a truncation, a schema
/// surprise — would destroy the source while reporting success. A byte copy cannot lose a
/// field this version does not know about, and the verification read is what makes the
/// deletion safe.
///
/// Failure is never destructive: the Workspace opens, the DM is told, nothing is removed, and
/// the next Workspace opened tries again.
struct WorkspaceMigration {
    /// What happened, for the picker to report.
    enum Outcome: Equatable {
        /// The roster moved. Carries the Party names and the Workspace, for the alert.
        case migrated(partyNames: [String], workspaceName: String)
        /// It could not be moved. Nothing was deleted; it will be retried.
        case failed(reason: String)
    }

    /// The pre-Workspace home. Was `PartyStore.defaultDirectory` until this feature.
    static var legacyDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MapForge")
    }

    static var legacyPartiesURL: URL { legacyDirectory.appendingPathComponent("parties.json") }

    private enum LegacyKey {
        static let activePartyID = "activePartyID"
        static let playerDisplayUUID = "playerDisplayUUID"
        static let playerDisplayName = "playerDisplayName"
    }

    let preferences: DisplayPreferences
    var defaults: UserDefaults = .standard
    var fileManager: FileManager = .default

    /// The file to migrate *from*. Required, with no default.
    ///
    /// There was a default once — `legacyPartiesURL`, the real path in Application Support —
    /// and it destroyed the developer's own roster the first time the unit suite ran, because
    /// an `AppState` built in a test opened a temp Workspace and the migration dutifully
    /// found, copied and deleted the real file. A step that deletes a DM's data must be
    /// pointed at its target explicitly, every time, by a caller that means it.
    let legacyURL: URL

    /// Whether the roster is removed once the copy is verified.
    ///
    /// The migration is only finished when the old data is gone — but a caller that wants the
    /// copy without the deletion (a dry run, a test) can have it, and cannot get the deletion
    /// by accident.
    var retiresLegacyData = true

    init(preferences: DisplayPreferences,
         legacyURL: URL,
         defaults: UserDefaults = .standard,
         fileManager: FileManager = .default,
         retiresLegacyData: Bool = true) {
        self.preferences = preferences
        self.legacyURL = legacyURL
        self.defaults = defaults
        self.fileManager = fileManager
        self.retiresLegacyData = retiresLegacyData
    }

    /// The migration as the app performs it, from the real pre-Workspace home.
    ///
    /// The only place `legacyPartiesURL` is used. `MapForgeApp` calls this; nothing else
    /// should.
    static func forThisMac(preferences: DisplayPreferences) -> WorkspaceMigration {
        WorkspaceMigration(preferences: preferences, legacyURL: legacyPartiesURL)
    }

    /// Runs the migration if there is anything to migrate. Calls back only when something
    /// happened, so the common case — every launch after the first — is silent.
    func runIfNeeded(into workspace: Workspace, report: (Outcome) -> Void) {
        // The absence of the source file is the entire guard. No flag in `UserDefaults`, none
        // in the Manifest: the guard and the outcome are the same fact, so they cannot fall
        // out of step — and a DM who restores the file from a backup gets it picked up on the
        // next open, which is what they would want.
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }

        // Never overwrite a roster that is already there. A DM who has been using this
        // Workspace keeps what they have.
        guard !fileManager.fileExists(atPath: workspace.partiesURL.path) else { return }

        let source = PartyStore(directory: legacyURL.deletingLastPathComponent(),
                                fileManager: fileManager)
        let book = source.load()
        if let failure = source.lastLoadFailure {
            return report(.failed(reason: failure.underlying.localizedDescription))
        }
        guard !book.isEmpty else { return }

        do {
            try fileManager.createDirectory(at: workspace.supportDirectory,
                                            withIntermediateDirectories: true)
            try fileManager.copyItem(at: legacyURL, to: workspace.partiesURL)
        } catch {
            return report(.failed(reason: error.localizedDescription))
        }

        // The check that makes the deletion safe: read the copy back through the same store
        // and require it to be the roster we loaded. `PartyBook` is `Equatable`, so this is
        // one comparison.
        let destination = PartyStore(directory: workspace.supportDirectory,
                                     fileManager: fileManager)
        let copied = destination.load()
        guard destination.lastLoadFailure == nil, copied == book else {
            try? fileManager.removeItem(at: workspace.partiesURL)
            return report(.failed(reason: String(localized: "the copied roster did not match the original")))
        }

        carryPreferencesForward(into: workspace)
        if retiresLegacyData { retireLegacyData() }

        report(.migrated(partyNames: book.parties.map(\.name),
                         workspaceName: workspace.name))
    }

    /// Carries the active Party and the Player Display into the Workspace that now owns them.
    private func carryPreferencesForward(into workspace: Workspace) {
        let store = WorkspacePreferencesStore(directory: workspace.supportDirectory,
                                              fileManager: fileManager)
        var settings = store.load()
        if let string = defaults.string(forKey: LegacyKey.activePartyID) {
            settings.activePartyID = UUID(uuidString: string)
        }
        if let uuid = defaults.string(forKey: LegacyKey.playerDisplayUUID) {
            settings.playerDisplay = DisplayIdentity(
                uuid: uuid,
                name: defaults.string(forKey: LegacyKey.playerDisplayName) ?? ""
            )
        }
        store.save(settings)
    }

    /// Retires the old data — and only now, after the copy has been read back and matched.
    ///
    /// The roster is **renamed, not deleted**. "Remove the old data" is satisfied either way as
    /// far as the app is concerned: nothing reads `parties.json.migrated`, it never reappears,
    /// and the DM sees the roster only in its new home. But this is the one file in the app
    /// that is hours of someone's typing, and a few kilobytes is a cheap price for a DM whose
    /// roster went missing to a bug we have not found yet being able to recover it by hand.
    ///
    /// The `UserDefaults` keys are genuinely deleted: they are three small values that the
    /// Workspace now holds, and a stale `playerDisplayUUID` left behind is exactly the kind of
    /// thing a future reader wires back up by mistake.
    ///
    /// The prefs plist itself stays: it holds the recents list, which is machine state by
    /// necessity and the one thing that cannot move into a Workspace.
    private func retireLegacyData() {
        let retired = legacyURL.appendingPathExtension("migrated")
        try? fileManager.removeItem(at: retired)
        do {
            try fileManager.moveItem(at: legacyURL, to: retired)
        } catch {
            // The copy is verified and the Workspace owns the roster now, so the old file
            // merely being stubborn is not a failure of the migration.
            try? fileManager.removeItem(at: legacyURL)
        }
        defaults.removeObject(forKey: LegacyKey.activePartyID)
        defaults.removeObject(forKey: LegacyKey.playerDisplayUUID)
        defaults.removeObject(forKey: LegacyKey.playerDisplayName)

        // The directory stays: it holds the retired roster. It is empty of anything the app
        // reads, which is what "removed" has to mean here.
    }
}
