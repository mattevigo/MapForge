import CoreGraphics
import Foundation

/// The Walls being traced on a Map, with undo.
///
/// Carries the whole `FogDocument` rather than just its Walls because that is what the
/// preview draws — a DM traces a Wall against the Pawns and Lights standing in the room —
/// but only `walls` is ever mutated here, and only `walls` is taken back out (ADR-0013).
/// Undo is grouped by action: a chain traced with three clicks is one press to take back.
///
/// Mode-local by construction: it starts from the document the mode opened with and cannot
/// unwind past it. Discarding the whole session is Cancel's job, and conflating the two
/// would let undo silently delete fog from an earlier sitting.
struct FogEdits {
    private(set) var document: FogDocument
    /// The document the mode opened with. Cancel restores its **Walls** — not the whole
    /// document, which would revert everything the table changed while the mode was open.
    let original: FogDocument
    /// One entry per undoable action, each holding the document as it was before it.
    private var history: [FogDocument] = []

    init(document: FogDocument) {
        self.document = document
        self.original = document
    }

    var canUndo: Bool { !history.isEmpty }

    mutating func undo() {
        guard let previous = history.popLast() else { return }
        document = previous
    }

    // MARK: Walls

    /// Commit a traced chain. Its spans undo together — a chain is one thing the DM did.
    mutating func addWalls(_ walls: [Wall]) {
        guard !walls.isEmpty else { return }
        record()
        document.walls.append(contentsOf: walls)
    }

    mutating func deleteWall(id: Wall.ID) {
        guard document.walls.contains(where: { $0.id == id }) else { return }
        record()
        document.walls.removeAll { $0.id == id }
    }

    /// Push one undo step. Every mutation routes through here, so the record-then-mutate
    /// sequence exists once rather than per operation.
    private mutating func record() {
        history.append(document)
    }
}
