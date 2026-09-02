import Foundation

/// The Walls on a Map while the DM is editing them, with undo.
///
/// Undo is grouped by *action*, not by Wall: a chain the DM traced with three clicks is
/// one thing they did, so one press takes all of it back. Without that, undoing a
/// mis-traced room means as many presses as it had corners.
///
/// Mode-local by construction — it starts from the Walls that were on the Map when the
/// mode opened and cannot unwind past them. Discarding the whole session is Cancel's job,
/// and conflating the two would let undo silently delete Walls from an earlier sitting.
struct WallEdits {
    private(set) var walls: [Wall]
    /// The Walls the mode opened with. Cancel restores these wholesale; undo never
    /// reaches past them.
    let originalWalls: [Wall]
    /// One entry per undoable action, each holding the Walls as they were before it.
    private var history: [[Wall]] = []

    init(walls: [Wall]) {
        self.walls = walls
        self.originalWalls = walls
    }

    var canUndo: Bool { !history.isEmpty }

    /// Commit a traced chain. Its spans undo together.
    mutating func add(_ newWalls: [Wall]) {
        guard !newWalls.isEmpty else { return }
        history.append(walls)
        walls.append(contentsOf: newWalls)
    }

    mutating func delete(_ wall: Wall) {
        guard walls.contains(where: { $0.id == wall.id }) else { return }
        history.append(walls)
        walls.removeAll { $0.id == wall.id }
    }

    mutating func undo() {
        guard let previous = history.popLast() else { return }
        walls = previous
    }
}
