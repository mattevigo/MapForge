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

    /// Name a Light, or clear its name by passing something blank.
    ///
    /// Undoable, beside `setLightRadii` and unlike `toggleLight`: a name is authoring, the way
    /// a radius is, not a live performance action the way dousing one is.
    ///
    /// **One undo step for the whole rename, not one per keystroke.** A `TextField` binding
    /// fires on every character, so recording unconditionally made undoing a seven-letter name
    /// take seven presses — the defect `beginLightDrag`/`endLightDrag` exist to prevent for a
    /// drag. Consecutive edits to the same Light coalesce: the first records, the rest write
    /// over it. Any other edit in between ends the run, so the DM never loses a step they
    /// meant to keep.
    ///
    /// **Not trimmed here.** Trimming per keystroke means a DM cannot type a name with a
    /// space in it and have it survive the pause before the next character — "trapped brazier"
    /// spends a keystroke as "trapped ". `Pawn.setPawnLabel` does not trim either. The blank
    /// check runs on what was typed, so clearing the field still yields nil rather than `""`.
    mutating func setLightName(id: Light.ID, _ name: String) {
        guard let index = document.lights.firstIndex(where: { $0.id == id }) else { return }
        if renamingLight != id {
            record()            // clears `renamingLight`, so the assignment must follow it
            renamingLight = id
        }
        // Blank — empty or whitespace — is stored as nil so "unnamed" has one representation
        // and the roster's positional fallback fires. Anything else is kept exactly as typed,
        // including its spaces: trimming mid-word is what stops a DM typing "trapped brazier".
        document.lights[index].name =
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
    }

    /// The Light whose name is being typed, so consecutive keystrokes share one undo step.
    /// Cleared by every other edit — see `record()`.
    private var renamingLight: Light.ID?

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

    /// Make a Pawn a Creature, a Treasure, or a party member again. Undoable: unlike
    /// hiding, which is a live act at the table, this is an authoring decision about what
    /// the token *is*, and it changes the lighting of the whole Map.
    mutating func setPawnKind(id: Pawn.ID, _ kind: PawnKind) {
        editPawn(id) { $0.kind = kind }
    }

    /// Make a token 2×2, or 1×1 again. Undoable, like every other authoring decision
    /// about what a token is.
    mutating func setPawnIsBig(id: Pawn.ID, _ isBig: Bool) {
        editPawn(id) { $0.isBig = isBig }
    }

    mutating func setPawnColor(id: Pawn.ID, hex: String) {
        editPawn(id) { $0.colorHex = hex }
    }

    /// Set how far a Pawn can see, in Grid squares.
    ///
    /// The one radius a Pawn has. Its dim value is the cosmetic feather from
    /// `Pawn.dimSquares(forSight:)` and is never set independently — a character's sight is
    /// not a light source, and there is no second number to enter. A `Light` still has two,
    /// through `setLightRadii`, because a torch really does.
    mutating func setPawnSight(id: Pawn.ID, squares: CGFloat) {
        editPawn(id) {
            $0.light.brightSquares = max(0, squares)
            $0.light.dimSquares = Pawn.dimSquares(forSight: squares)
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
        renamingLight = nil
        guard dragOrigin == nil else { return }
        history.append(document)
    }
}
