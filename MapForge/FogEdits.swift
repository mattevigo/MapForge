import CoreGraphics
import Foundation

/// The fog being authored on a Map, with undo.
///
/// One history over the whole document rather than one per kind: the DM thinks in actions
/// ("undo that torch", "undo that room"), not in which collection an action happened to
/// touch. Undo is grouped by action too — a chain traced with three clicks, or a drag that
/// emitted a position per frame, is one press to take back.
///
/// Mode-local by construction: it starts from the document the mode opened with and cannot
/// unwind past it. Discarding the whole session is Cancel's job, and conflating the two
/// would let undo silently delete fog from an earlier sitting.
struct FogEdits {
    private(set) var document: FogDocument
    /// The document the mode opened with. Cancel restores this wholesale.
    let original: FogDocument
    /// One entry per undoable action, each holding the document as it was before it.
    private var history: [FogDocument] = []
    /// While a drag is in flight, its pre-drag document — so the whole drag is one step.
    private var dragOrigin: FogDocument?

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

    // MARK: Lights

    mutating func addLight(_ light: Light) {
        record()
        document.lights.append(light)
    }

    mutating func deleteLight(id: Light.ID) {
        guard document.lights.contains(where: { $0.id == id }) else { return }
        record()
        document.lights.removeAll { $0.id == id }
    }

    /// Move a Light, keeping its identity — its toggle in the live panel must not jump
    /// around under the DM's cursor as they drag it.
    mutating func moveLight(id: Light.ID, to point: MapPoint) {
        guard let index = document.lights.firstIndex(where: { $0.id == id }) else { return }
        record()
        document.lights[index].at = point
    }

    /// Radii are in Grid squares, and negative is meaningless — both the stepper and the
    /// text field let a DM go past zero. Dim zero is legal: a sharp-edged source.
    mutating func setLightRadii(id: Light.ID, brightSquares: CGFloat, dimSquares: CGFloat) {
        guard let index = document.lights.firstIndex(where: { $0.id == id }) else { return }
        record()
        document.lights[index].brightSquares = max(0, brightSquares)
        document.lights[index].dimSquares = max(0, dimSquares)
    }

    /// Switch a Light on or off. Deliberately *not* undoable: this is a live performance
    /// action a DM takes mid-session, and filling the undo stack with toggles would bury
    /// their actual authoring work behind a row of them.
    mutating func toggleLight(id: Light.ID) {
        guard let index = document.lights.firstIndex(where: { $0.id == id }) else { return }
        document.lights[index].isOn.toggle()
    }

    // MARK: Drags

    /// A drag emits a position per frame; without this each would be an undo step, and
    /// walking back one drag would take dozens of presses.
    mutating func beginLightDrag() {
        guard dragOrigin == nil else { return }
        dragOrigin = document
        history.append(document)
    }

    mutating func endLightDrag() {
        // A drag that changed nothing leaves a history entry identical to the state it was
        // pushed from; drop it rather than making the DM press undo for a no-op. Selecting
        // a Light is exactly this gesture.
        if let origin = dragOrigin, origin == document, history.last == origin {
            history.removeLast()
        }
        dragOrigin = nil
    }

    /// Push one undo step — unless a drag is in flight, where `beginLightDrag` already
    /// pushed the single entry the whole drag undoes to. Every mutation routes through
    /// here, so an edit that lands mid-drag (a delete on ⌫, say) cannot push a second
    /// entry and make one action take two presses to undo.
    private mutating func record() {
        guard dragOrigin == nil else { return }
        history.append(document)
    }
}
