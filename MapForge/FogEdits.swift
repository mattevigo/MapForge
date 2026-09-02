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

    // MARK: Pawns
    //
    // A Pawn *has* a Light rather than being one, so its range routes through
    // `pawn.light` — but every operation mirrors the Light ones above, because to the DM
    // a Pawn's range and a torch's range are the same idea.

    mutating func addPawn(_ pawn: Pawn) {
        record()
        document.pawns.append(pawn)
    }

    mutating func deletePawn(id: Pawn.ID) {
        guard document.pawns.contains(where: { $0.id == id }) else { return }
        record()
        document.pawns.removeAll { $0.id == id }
    }

    /// Move a Pawn, keeping its identity — the party moves constantly, and a Pawn that
    /// changed identity per drag would lose its selection and its row in the live panel.
    mutating func movePawn(id: Pawn.ID, to point: MapPoint) {
        editPawn(id) { $0.at = point }
    }

    mutating func setPawnLabel(id: Pawn.ID, _ label: String) {
        editPawn(id) { $0.label = label }
    }

    mutating func setPawnColor(id: Pawn.ID, hex: String) {
        editPawn(id) { $0.colorHex = hex }
    }

    /// Set a Pawn's sight, carrying its dim radius with it at the 5e ratio.
    ///
    /// The inspector offers one number, and a Pawn's two radii are derived from it —
    /// `Pawn.init` defaults dim to twice bright for exactly that reason. Writing bright
    /// alone left dim at twice whatever the Pawn was *first* created with, so the outer
    /// circle sat there looking fixed and unrelated to the number being typed. Use
    /// `setPawnRange` where the two are genuinely independent.
    mutating func setPawnSight(id: Pawn.ID, squares: CGFloat) {
        let bright = max(0, squares)
        setPawnRange(id: id, brightSquares: bright, dimSquares: bright * 2)
    }

    mutating func setPawnRange(id: Pawn.ID, brightSquares: CGFloat, dimSquares: CGFloat) {
        editPawn(id) {
            $0.light.brightSquares = max(0, brightSquares)
            $0.light.dimSquares = max(0, dimSquares)
        }
    }

    /// One undoable edit to one Pawn. Every mutation routes through here so the
    /// find-record-mutate sequence exists once rather than per property.
    private mutating func editPawn(_ id: Pawn.ID, _ change: (inout Pawn) -> Void) {
        guard let index = document.pawns.firstIndex(where: { $0.id == id }) else { return }
        record()
        change(&document.pawns[index])
    }

    /// Not undoable, for the same reason a Light's toggle is not: it is a live
    /// performance action, and a character putting out their torch keeps their token.
    mutating func togglePawnLight(id: Pawn.ID) {
        guard let index = document.pawns.firstIndex(where: { $0.id == id }) else { return }
        document.pawns[index].light.isOn.toggle()
    }

    // MARK: Drags

    /// A drag emits a position per frame; without this each would be an undo step, and
    /// walking back one drag would take dozens of presses.
    mutating func beginLightDrag() {
        guard dragOrigin == nil else { return }
        dragOrigin = document
        history.append(document)
    }

    /// Pawn drags share the Light drag's single-snapshot bracket: both emit a position
    /// per frame, and both are one thing the DM did.
    mutating func beginPawnDrag() { beginLightDrag() }
    mutating func endPawnDrag() { endLightDrag() }

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
