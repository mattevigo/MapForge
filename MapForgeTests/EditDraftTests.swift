import XCTest
@testable import MapForge

/// The Edit Pawn and Edit Light sheets' buffered fields.
///
/// A draft is what makes OK/Cancel mean anything: Live View edits are not undoable
/// (ADR-0013), so Cancel *is* the undo and has to actually discard. Seeding from the object
/// and committing back are the two halves, and both are testable without a sheet.
final class EditDraftTests: XCTestCase {

    // MARK: Pawn

    private func pawn() -> Pawn {
        Pawn(at: MapPoint(x: 10, y: 20), label: "Goblin A", colorHex: "#C81E1E",
             brightSquares: 6, kind: .creature, isBig: true)
    }

    func testAPawnDraftSeedsFromThePawn() {
        let draft = EditPawnDraft(pawn: pawn())
        XCTAssertEqual(draft.label, "Goblin A")
        XCTAssertEqual(draft.colorHex, "#C81E1E")
        XCTAssertEqual(draft.sightSquares, 6)
        XCTAssertEqual(draft.kind, .creature)
        XCTAssertTrue(draft.isBig)
    }

    func testCommittingAPawnDraftWritesEveryField() {
        var draft = EditPawnDraft(pawn: pawn())
        draft.label = "Ogre"
        draft.colorHex = "#1E88C8"
        draft.sightSquares = 3
        draft.kind = .player
        draft.isBig = false

        let edited = draft.applied(to: pawn())

        XCTAssertEqual(edited.label, "Ogre")
        XCTAssertEqual(edited.colorHex, "#1E88C8")
        XCTAssertEqual(edited.light.brightSquares, 3)
        XCTAssertEqual(edited.kind, .player)
        XCTAssertFalse(edited.isBig)
    }

    /// A Pawn has one radius; its dim value is the cosmetic feather derived from sight, and
    /// the sheet offers no second field for it. Committing must move it too, or the halo
    /// stays at whatever the Pawn was created with — the defect `CreatureTests` records.
    func testCommittingASightChangeMovesTheFeatheredEdge() {
        var draft = EditPawnDraft(pawn: pawn())
        draft.sightSquares = 3

        let edited = draft.applied(to: pawn())

        XCTAssertEqual(edited.light.brightSquares, 3)
        XCTAssertEqual(edited.light.dimSquares, 4, "the feather did not follow the sight")
    }

    /// Everything the sheet does not offer is left exactly as it was — position, identity,
    /// the torch, the eye, and which Character it was stamped from.
    func testCommittingAPawnDraftTouchesNothingTheSheetDoesNotOffer() {
        var original = pawn()
        original.isHidden = true
        original.light.isOn = false
        original.characterID = UUID()

        var draft = EditPawnDraft(pawn: original)
        draft.label = "Ogre"
        let edited = draft.applied(to: original)

        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.at, original.at)
        XCTAssertTrue(edited.isHidden)
        XCTAssertFalse(edited.light.isOn)
        XCTAssertEqual(edited.characterID, original.characterID)
    }

    func testANegativeSightIsClampedToZero() {
        var draft = EditPawnDraft(pawn: pawn())
        draft.sightSquares = -4
        XCTAssertEqual(draft.applied(to: pawn()).light.brightSquares, 0)
    }

    // MARK: Light

    private func light() -> Light {
        Light(at: MapPoint(x: 50, y: 50), brightSquares: 4, dimSquares: 8, name: "Light 1")
    }

    func testALightDraftSeedsFromTheLight() {
        let draft = EditLightDraft(light: light())
        XCTAssertEqual(draft.name, "Light 1")
        XCTAssertEqual(draft.brightSquares, 4)
        XCTAssertEqual(draft.dimSquares, 8)
        XCTAssertTrue(draft.isOn)
    }

    func testCommittingALightDraftWritesEveryField() {
        var draft = EditLightDraft(light: light())
        draft.name = "trapped brazier"
        draft.brightSquares = 6
        draft.dimSquares = 9
        draft.isOn = false

        let edited = draft.applied(to: light())

        XCTAssertEqual(edited.name, "trapped brazier")
        XCTAssertEqual(edited.brightSquares, 6)
        XCTAssertEqual(edited.dimSquares, 9)
        XCTAssertFalse(edited.isOn)
    }

    /// The trap the issue calls out. `Light`'s initialiser defaults dim to twice bright, so
    /// a draft that re-derived it would silently double a dim the DM had deliberately set
    /// equal to bright. The draft carries the stored value and writes it back untouched.
    func testADimEqualToBrightIsNotSilentlyDoubled() {
        let deliberate = Light(at: MapPoint(x: 0, y: 0), brightSquares: 4, dimSquares: 4)
        var draft = EditLightDraft(light: deliberate)
        draft.name = "renamed"

        XCTAssertEqual(draft.applied(to: deliberate).dimSquares, 4,
                       "the sheet doubled a dim radius the DM had set by hand")
    }

    /// Blank is "no name", exactly as `AppState.setLightName` treats it: "unnamed" must have
    /// one representation or the roster's positional fallback fires for nil and not for "".
    func testABlankNameIsNoName() {
        var draft = EditLightDraft(light: light())
        draft.name = "   "
        XCTAssertNil(draft.applied(to: light()).name)
    }

    func testANegativeRadiusIsClampedToZero() {
        var draft = EditLightDraft(light: light())
        draft.brightSquares = -2
        draft.dimSquares = -5
        let edited = draft.applied(to: light())
        XCTAssertEqual(edited.brightSquares, 0)
        XCTAssertEqual(edited.dimSquares, 0)
    }

    func testCommittingALightDraftKeepsItsIdentityAndPosition() {
        let original = light()
        var draft = EditLightDraft(light: original)
        draft.name = "moved?"
        let edited = draft.applied(to: original)

        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.at, original.at)
    }
}
