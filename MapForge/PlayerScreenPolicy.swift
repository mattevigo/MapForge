import CoreGraphics
import Foundation

/// The stable key for a physical display. `CGDirectDisplayID` is reassigned on replug
/// and across reboots, so it can never key persisted state; the UUID survives both.
/// `name` is carried for the UI and logs only — two identical TVs share it.
struct DisplayIdentity: Equatable, Hashable, Codable {
    var uuid: String
    var name: String
}

/// One screen as the policy sees it: identity plus what the picker needs to describe it.
/// Deliberately value types — no `NSScreen` — so the whole rule is unit-testable.
struct DisplayCandidate: Equatable {
    var identity: DisplayIdentity
    var isBuiltin: Bool
    /// Nil when the display reports no EDID physical size: presentable, but True Scale
    /// is a guess until Calibration. Shown with a warning rather than hidden.
    var metrics: DisplayMetrics?

    var hasKnownPhysicalSize: Bool { metrics != nil }
}

enum PlayerScreenPolicy {
    /// Which screen is the Player Display, in priority order:
    /// an explicit choice that is still connected; else a remembered one that is
    /// connected; else the sole external screen; else none — the picker waits.
    ///
    /// Two or more unrecognised screens never auto-present: that ambiguity is exactly
    /// what the picker exists to resolve, and guessing would put a Map in front of
    /// players on a screen the DM never chose.
    static func resolve(candidates: [DisplayCandidate],
                        explicit: DisplayIdentity?,
                        remembered: DisplayIdentity?) -> DisplayCandidate? {
        // Matched by UUID, never the whole identity: `name` is a label that changes
        // when the display is renamed, and a renamed display is still the same glass.
        if let explicit, let match = candidates.first(where: { $0.identity.uuid == explicit.uuid }) {
            return match
        }
        if let remembered, let match = candidates.first(where: { $0.identity.uuid == remembered.uuid }) {
            return match
        }
        let externals = candidates.filter { !$0.isBuiltin }
        return externals.count == 1 ? externals.first : nil
    }
}
