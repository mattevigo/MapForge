import Foundation

/// Coalesces a burst of fog edits into one write.
///
/// Drawing a Wall produces edits at gesture rate — one per vertex, more while a span is
/// dragged — and issue 09 already cost a round of work on drag smoothness, so a file write
/// must never land in the middle of one. Separate from `FogStore` because debouncing is a
/// timing policy, not a storage concern: the store stays a pure read/write seam that tests
/// can call directly with no clock involved.
@MainActor
final class FogAutosave {
    private let delay: TimeInterval
    private let write: (FogDocument) -> Void
    private var pending: FogDocument?
    private var timer: Timer?

    init(delay: TimeInterval = 0.5, write: @escaping (FogDocument) -> Void) {
        self.delay = delay
        self.write = write
    }

    /// Queue a document to be written once the edits stop. The *last* one wins — saving
    /// the first of a burst would persist a half-drawn Wall.
    func schedule(_ document: FogDocument) {
        pending = document
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    /// Write anything still queued, now. Called when a Map closes or the app quits, so a
    /// final edit is never lost to a timer that had not fired yet.
    func flush() {
        timer?.invalidate()
        timer = nil
        guard let document = pending else { return }
        pending = nil
        write(document)
    }
}
