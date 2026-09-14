import XCTest
@testable import MapForge

/// Naming a Light, and the defect that made it necessary.
///
/// Modelled on `PawnLabelTests`, because this is the same problem one term over: the roster
/// numbered Lights by their position in the list (`ControlView` said so outright — "A Light
/// has no label of its own, so it is identified by its position in the list"), so deleting
/// Light 2 silently renamed Light 3. `Pawn.nextLabel(after:)` exists because `count + 1` had
/// exactly that flaw for Pawns; Lights kept it, for want of anywhere to store an answer.
final class LightNameTests: XCTestCase {

    private func light(_ name: String? = nil, x: CGFloat = 0) -> Light {
        Light(at: MapPoint(x: x, y: 0), brightSquares: 4, name: name)
    }

    // MARK: Auto-naming

    func testTheFirstLightIsNamedOne() {
        XCTAssertEqual(Light.nextName(after: []), "Light 1")
    }

    func testEachNewLightTakesTheNextNumber() {
        let existing = [light("Light 1"), light("Light 2")]
        XCTAssertEqual(Light.nextName(after: existing), "Light 3")
    }

    /// The defect this whole feature is about. With positional naming, deleting Light 2 made
    /// Light 3 *become* "Light 2" — and a `count + 1` scheme would then hand the next Light
    /// that same name again.
    func testANameIsNotReusedAfterADelete() {
        // Three placed, the middle one deleted.
        let remaining = [light("Light 1"), light("Light 3")]
        XCTAssertEqual(Light.nextName(after: remaining), "Light 2",
                       "the next name should fill the gap, not collide with Light 3")
    }

    func testTheNextNameNeverCollidesWithAnExistingOne() {
        let existing = [light("Light 1"), light("Light 2"), light("Light 3")]
        let next = Light.nextName(after: existing)
        XCTAssertFalse(existing.compactMap(\.name).contains(next),
                       "\(next) is already taken")
    }

    /// Unnamed Lights — every one placed before this feature — must not confuse the counter.
    func testUnnamedLightsDoNotAffectTheNextName() {
        let existing = [light(), light(), light("Light 1")]
        XCTAssertEqual(Light.nextName(after: existing), "Light 2")
    }

    /// A DM who renames a Light to something of their own does not get it reused either.
    func testAHandTypedNameIsRespected() {
        let existing = [light("trapped brazier"), light("Light 1")]
        XCTAssertEqual(Light.nextName(after: existing), "Light 2")
    }

    // MARK: Editing

    func testRenamingALightIsUndoable() {
        var edits = FogEdits(document: FogDocument())
        let torch = light("Light 1")
        edits.addLight(torch)
        edits.setLightName(id: torch.id, "trapped brazier")
        XCTAssertEqual(edits.document.lights.first?.name, "trapped brazier")

        edits.undo()
        XCTAssertEqual(edits.document.lights.first?.name, "Light 1",
                       "undo did not put the old name back")
    }

    /// Renaming shares one history with Walls and Lights, so a DM undoing their way out of a
    /// mistake does not have to know which kind of edit they are unwinding.
    func testRenamingJoinsTheSameUndoHistory() {
        var edits = FogEdits(document: FogDocument())
        let torch = light("Light 1")
        edits.addLight(torch)
        edits.setLightName(id: torch.id, "brazier")
        edits.setLightRadii(id: torch.id, brightSquares: 6, dimSquares: 12)

        edits.undo()    // the radii
        XCTAssertEqual(edits.document.lights.first?.name, "brazier")
        edits.undo()    // the name
        XCTAssertEqual(edits.document.lights.first?.name, "Light 1")
    }

    func testRenamingAMissingLightDoesNothing() {
        var edits = FogEdits(document: FogDocument())
        edits.setLightName(id: UUID(), "nowhere")
        XCTAssertTrue(edits.document.lights.isEmpty)
    }

    /// An empty field means "no name", not a Light called "". The roster then falls back to
    /// its position, which is what a Light placed before this feature does.
    func testClearingTheFieldLeavesNoName() {
        var edits = FogEdits(document: FogDocument())
        let torch = light("Light 1")
        edits.addLight(torch)
        edits.setLightName(id: torch.id, "")
        XCTAssertNil(edits.document.lights.first?.name,
                     "an empty name should be nil, not an empty string")
    }

    /// The bug a per-keystroke trim causes: a DM typing "trapped brazier" gets as far as
    /// "trapped" and then cannot type the space, because each keystroke trims the field back.
    /// Setting the name once is not the same test — it is how the first version of these
    /// tests passed while the feature was unusable at the keyboard.
    func testANameCanContainSpacesAsItIsTyped() {
        var edits = FogEdits(document: FogDocument())
        let torch = light("Light 1")
        edits.addLight(torch)

        // One call per keystroke, as the TextField's binding makes.
        let typed = "trapped brazier"
        for end in 1...typed.count {
            edits.setLightName(id: torch.id, String(typed.prefix(end)))
        }
        XCTAssertEqual(edits.document.lights.first?.name, "trapped brazier",
                       "the space could not be typed")
    }

    /// Typing a name is ONE edit to undo, not one per character.
    func testTypingANameIsASingleUndo() {
        var edits = FogEdits(document: FogDocument())
        let torch = light("Light 1")
        edits.addLight(torch)

        let typed = "brazier"
        for end in 1...typed.count {
            edits.setLightName(id: torch.id, String(typed.prefix(end)))
        }
        edits.undo()
        XCTAssertEqual(edits.document.lights.first?.name, "Light 1",
                       "undo unwound one keystroke instead of the whole rename")
    }

    /// Undo then place again: the gap-filling scheme hands out the name the undone Light had,
    /// which is correct — that name is free again. The question is whether a *redo* can then
    /// produce two Lights sharing one name.
    func testUndoingAPlacementFreesItsNameForReuse() {
        var edits = FogEdits(document: FogDocument())
        edits.addLight(Light(at: MapPoint(x: 0, y: 0), brightSquares: 4,
                             name: Light.nextName(after: edits.document.lights)))
        edits.addLight(Light(at: MapPoint(x: 1, y: 0), brightSquares: 4,
                             name: Light.nextName(after: edits.document.lights)))
        XCTAssertEqual(edits.document.lights.map(\.name), ["Light 1", "Light 2"])

        edits.undo()
        XCTAssertEqual(edits.document.lights.map(\.name), ["Light 1"])

        // The freed name is reused, and there is still exactly one of it.
        edits.addLight(Light(at: MapPoint(x: 2, y: 0), brightSquares: 4,
                             name: Light.nextName(after: edits.document.lights)))
        XCTAssertEqual(edits.document.lights.map(\.name), ["Light 1", "Light 2"])
        XCTAssertEqual(Set(edits.document.lights.compactMap(\.name)).count,
                       edits.document.lights.count,
                       "two Lights ended up sharing a name")
    }

    /// Whitespace is the same thing typed differently.
    func testAWhitespaceOnlyNameIsNoName() {
        var edits = FogEdits(document: FogDocument())
        let torch = light("Light 1")
        edits.addLight(torch)
        edits.setLightName(id: torch.id, "   ")
        XCTAssertNil(edits.document.lights.first?.name,
                     "a name of nothing but spaces should read as unnamed")
    }
}
