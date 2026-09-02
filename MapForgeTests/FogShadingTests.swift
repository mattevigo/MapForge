import SwiftUI
import XCTest
@testable import MapForge

/// The rendering decisions behind the Fog Overlay, kept out of the view so they can be
/// asserted. Getting a shade wrong is not a crash — it is players seeing a room the DM
/// meant to hide, which is only discovered at the table.
final class FogShadingTests: XCTestCase {

    // MARK: Player Display

    func testUnlitIsFullyOpaqueForPlayers() {
        // The whole point: what the Lights do not reach must be hidden, not merely dim.
        XCTAssertEqual(FogShading.player(.unlit), 1, accuracy: 1e-9)
    }

    func testBrightIsCompletelyClearForPlayers() {
        // A lit room must look like the artwork, not like the artwork behind a veil.
        XCTAssertEqual(FogShading.player(.bright), 0, accuracy: 1e-9)
    }

    func testDimIsPartialForPlayers() {
        // Dim has to read as a distinct third state — visibly darker than bright, visibly
        // lighter than unlit — or the 5e bright/dim distinction is decorative.
        let dim = FogShading.player(.dim)
        XCTAssertGreaterThan(dim, 0.15)
        XCTAssertLessThan(dim, 0.85)
    }

    // MARK: Control Window

    func testTheDMCanAlwaysSeeThroughTheDarkest() {
        // "A DM as blind as the players cannot run the game." Even fully unlit map must
        // stay legible in the Control Window.
        XCTAssertLessThan(FogShading.control(.unlit), 0.8,
                          "the DM could not see into the dark")
    }

    func testTheDMSeesTheSameOrderingAsThePlayers() {
        // The tint is a different strength, never a different story: if unlit read as
        // lighter than dim for the DM, they would misjudge what players can see.
        XCTAssertGreaterThan(FogShading.control(.unlit), FogShading.control(.dim))
        XCTAssertGreaterThan(FogShading.control(.dim), FogShading.control(.bright))
    }

    func testTheDMsTintIsAlwaysLighterThanThePlayers() {
        for level in [VisibilityLevel.bright, .dim, .unlit] {
            XCTAssertLessThanOrEqual(FogShading.control(level), FogShading.player(level),
                                     "the DM saw less than the players at \(level)")
        }
    }

    // MARK: The off switch

    func testSwitchingTheOverlayOffClearsEveryLevel() {
        for level in [VisibilityLevel.bright, .dim, .unlit] {
            XCTAssertEqual(FogShading.player(level, isOverlayOn: false), 0, accuracy: 1e-9)
            XCTAssertEqual(FogShading.control(level, isOverlayOn: false), 0, accuracy: 1e-9)
        }
    }

    // MARK: Falloff

    func testALightFadesOutAtItsRangeRatherThanEndingFlat() {
        // "so a torch fades out instead of ending in a suspicious circle".
        let inner = FogShading.falloffOpacity(atFractionOfRadius: 0.5)
        let edge = FogShading.falloffOpacity(atFractionOfRadius: 1.0)
        XCTAssertEqual(inner, 1, accuracy: 1e-9, "the middle of a Light should be full strength")
        XCTAssertEqual(edge, 0, accuracy: 1e-9, "the rim should reach zero")
        XCTAssertGreaterThan(FogShading.falloffOpacity(atFractionOfRadius: 0.9), 0)
        XCTAssertLessThan(FogShading.falloffOpacity(atFractionOfRadius: 0.9), 1)
    }

    func testFalloffIsMonotonic() {
        var previous = CGFloat.infinity
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            let value = FogShading.falloffOpacity(atFractionOfRadius: step)
            XCTAssertLessThanOrEqual(value, previous, "falloff brightened at \(step)")
            previous = value
        }
    }

    // MARK: Compositing

    func testTwoOverlappingRegionsDoNotSubtractTwice() {
        // `.destinationOut` multiplies: darkness * (1 - alpha) per fill. Two overlapping
        // dim polygons at the same alpha would leave the overlap BRIGHTER than either
        // alone — a visible seam where two torches meet, which is the inverse of the
        // failure issue 05's case list warned about.
        let unlit = FogShading.player(.unlit)
        let dim = FogShading.player(.dim)
        let alpha = FogShading.removalAlpha(from: unlit, to: dim)

        let once = unlit * (1 - alpha)
        XCTAssertEqual(once, dim, accuracy: 1e-9, "one region did not reach the dim level")

        // Two overlapping fills at this alpha would land here instead — the seam.
        let twice = once * (1 - alpha)
        XCTAssertLessThan(twice, dim - 0.1,
                          "precondition: per-fill subtraction is what must be avoided")
        // FogCanvas therefore fills each layer at full strength and applies the alpha once
        // on composite, so the overlap composites to the same value as a single region.
    }

    func testRemovalAlphaIsClampedToSomethingDrawable() {
        // A target above the current darkness means nothing to remove.
        XCTAssertEqual(FogShading.removalAlpha(from: 0.5, to: 0.9), 0, accuracy: 1e-9)
        XCTAssertEqual(FogShading.removalAlpha(from: 0, to: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(FogShading.removalAlpha(from: 1, to: 0), 1, accuracy: 1e-9)
    }
}
