import Foundation

/// Whether the Scene tab's Stat Editor stands down, and the line it shows when it does.
///
/// While the Encounter's correction cursor is on a past Turn, an edit becomes a Correction
/// against that Turn (ADR-0010). The Encounter tab makes the mode impossible to miss with its
/// correcting bar; the Scene tab has no bar and the DM there is placing and lighting, so an
/// edit typed into its editor would amend Round 2 without the DM having seen that it would.
/// The editor is disabled instead, with one line naming the Turn and pointing at the tab
/// that shows it. The Encounter tab's editor is not locked — that is where correcting is
/// done.
enum SceneTabCorrectionLock {
    /// The line naming the Turn being corrected, or nil while there is nothing to correct —
    /// no fight, or the cursor on the live Turn — and the editor is open.
    static func line(for encounter: Encounter?) -> String? {
        guard let encounter, let target = encounter.correctionTarget else { return nil }
        let name = encounter.name(of: target.combatantID) ?? "?"
        return String(localized: "Correcting Round \(target.round), \(name)'s Turn — edit in the Encounter tab")
    }
}
