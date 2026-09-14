import Foundation

/// Coalesces a burst of Stat Block edits into one write.
///
/// `FogAutosave`'s rule applied to the other file a Map carries: the DM types hit points
/// digit by digit, and each keystroke must not become a write. The *last* document wins —
/// saving the first of a burst would persist "2" from a monster on its way to 24.
///
/// A sibling of `FogAutosave` rather than a generic version of it. Making the existing type
/// generic would edit working code that every fog edit depends on, to save a file this
/// short.
///
/// Note what this does **not** debounce: the Combat Log. A Turn ending is the durability
/// boundary ADR-0008 is built on, so those lines are written and flushed the moment they
/// exist.
@MainActor
final class StatsAutosave {
    private let delay: TimeInterval
    private let write: (StatsDocument) -> Void
    private var pending: StatsDocument?
    private var timer: Timer?

    init(delay: TimeInterval = 0.5, write: @escaping (StatsDocument) -> Void) {
        self.delay = delay
        self.write = write
    }

    func schedule(_ document: StatsDocument) {
        pending = document
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    /// Write anything still queued, now. Called when a fight stops, a Map closes, or the
    /// app quits.
    func flush() {
        timer?.invalidate()
        timer = nil
        guard let document = pending else { return }
        pending = nil
        write(document)
    }
}
