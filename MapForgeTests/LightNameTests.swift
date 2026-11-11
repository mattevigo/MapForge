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
    //
    // Through `AppState`: a Light is renamed in the Live View in every mode (ADR-0013), and
    // the fog-mode path that made a rename undoable is gone with the inspector that offered
    // it. The tests that asserted undo-coalescing went with it; the naming rules did not.

    @MainActor
    func testRenamingALight() {
        let appState = AppState(preferences: isolatedPreferences())
        let torch = light("Light 1")
        appState.fog.lights = [torch]

        appState.setLightName(id: torch.id, "trapped brazier")

        XCTAssertEqual(appState.fog.lights.first?.name, "trapped brazier")
    }

    @MainActor
    func testRenamingAMissingLightDoesNothing() {
        let appState = AppState(preferences: isolatedPreferences())
        appState.setLightName(id: UUID(), "nowhere")
        XCTAssertTrue(appState.fog.lights.isEmpty)
    }

    /// An empty field means "no name", not a Light called "". The roster then falls back to
    /// its position, which is what a Light placed before this feature does.
    @MainActor
    func testClearingTheFieldLeavesNoName() {
        let appState = AppState(preferences: isolatedPreferences())
        let torch = light("Light 1")
        appState.fog.lights = [torch]

        appState.setLightName(id: torch.id, "")

        XCTAssertNil(appState.fog.lights.first?.name,
                     "an empty name should be nil, not an empty string")
    }

    /// The bug a per-keystroke trim causes: a DM typing "trapped brazier" gets as far as
    /// "trapped" and then cannot type the space, because each keystroke trims the field back.
    /// Setting the name once is not the same test — it is how the first version of these
    /// tests passed while the feature was unusable at the keyboard.
    ///
    /// Through `AppState` now rather than `FogEdits`: a Light is renamed in the Live View in
    /// every mode (ADR-0013), so the live path is the only path.
    @MainActor
    func testANameCanContainSpacesAsItIsTyped() {
        let appState = AppState(preferences: isolatedPreferences())
        let torch = light("Light 1")
        appState.fog.lights = [torch]

        // One call per keystroke, as the TextField's binding makes.
        let typed = "trapped brazier"
        for end in 1...typed.count {
            appState.setLightName(id: torch.id, String(typed.prefix(end)))
        }
        XCTAssertEqual(appState.fog.lights.first?.name, "trapped brazier",
                       "the space could not be typed")
    }

    /// Undo-coalescing per keystroke went with the mode that had an undo stack: renaming a
    /// Light is a live action now and is not undoable at all, so there is no run of
    /// keystrokes to collapse. What remains is that the *last* keystroke is what sticks.
    @MainActor
    func testTheNameTypedIsTheNameKept() {
        let appState = AppState(preferences: isolatedPreferences())
        let torch = light("Light 1")
        appState.fog.lights = [torch]

        let typed = "brazier"
        for end in 1...typed.count {
            appState.setLightName(id: torch.id, String(typed.prefix(end)))
        }
        XCTAssertEqual(appState.fog.lights.first?.name, "brazier")
    }

    /// The gap-filling scheme hands out the lowest free number, so deleting a Light in the
    /// middle frees its name for the next one placed — and two Lights never share one.
    @MainActor
    func testDeletingALightFreesItsNameForReuse() {
        let appState = AppState(preferences: isolatedPreferences())
        let first = light("Light 1", x: 0)
        let second = light("Light 2", x: 1)
        appState.fog.lights = [first, second]

        appState.fog.lights.removeAll { $0.id == second.id }
        XCTAssertEqual(appState.fog.lights.map(\.name), ["Light 1"])

        appState.fog.lights.append(light(Light.nextName(after: appState.fog.lights), x: 2))

        XCTAssertEqual(appState.fog.lights.map(\.name), ["Light 1", "Light 2"])
        XCTAssertEqual(Set(appState.fog.lights.compactMap(\.name)).count,
                       appState.fog.lights.count,
                       "two Lights ended up sharing a name")
    }

    /// Whitespace is the same thing typed differently.
    @MainActor
    func testAWhitespaceOnlyNameIsNoName() {
        let appState = AppState(preferences: isolatedPreferences())
        let torch = light("Light 1")
        appState.fog.lights = [torch]

        appState.setLightName(id: torch.id, "   ")

        XCTAssertNil(appState.fog.lights.first?.name,
                     "a name of nothing but spaces should read as unnamed")
    }

    private func isolatedPreferences() -> DisplayPreferences {
        DisplayPreferences(defaults: UserDefaults(suiteName: "LightNameTests.\(UUID().uuidString)")!)
    }
}
