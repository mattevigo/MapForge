import XCTest
@testable import MapForge

/// The DM's private magnifier over the mirror.
///
/// Zooming the Live View shows the DM more detail and shows the players **nothing new**:
/// the Viewport is untouched, so the Player Display keeps displaying exactly what it was.
/// That is the whole distinction from "Pan Viewport…", which moves what the table sees.
final class MirrorZoomTests: XCTestCase {
    private let mirror = CGRect(x: 0, y: 0, width: 400, height: 300)

    // MARK: The floor

    /// Zoomed out is the mirror itself — a true, unmagnified mirror of the Player Display.
    /// Unlike the fitted branch's floor, which is the whole image, because the mirror's job
    /// is to show what the table sees and nothing beyond it.
    func testTheDefaultIsATrueMirror() {
        let zoom = MirrorZoom()
        XCTAssertEqual(zoom.scale, 1)
        XCTAssertFalse(zoom.isMagnified, "a fresh mirror should not claim to be magnified")
        XCTAssertEqual(zoom.frame(mirroring: mirror, container: mirror.size), mirror)
    }

    func testZoomingOutPastTheMirrorIsRefused() {
        var zoom = MirrorZoom()
        zoom.zoom(by: -10, at: CGPoint(x: 200, y: 150), container: mirror.size)
        XCTAssertEqual(zoom.scale, 1, "the DM zoomed out past what the players can see")
        XCTAssertEqual(zoom.frame(mirroring: mirror, container: mirror.size), mirror)
    }

    // MARK: Magnifying

    func testZoomingInEnlargesTheMirroredFrame() {
        var zoom = MirrorZoom()
        zoom.zoom(by: 50, at: CGPoint(x: 200, y: 150), container: mirror.size)

        XCTAssertGreaterThan(zoom.scale, 1)
        XCTAssertTrue(zoom.isMagnified)
        let framed = zoom.frame(mirroring: mirror, container: mirror.size)
        XCTAssertEqual(framed.width, mirror.width * zoom.scale, accuracy: 0.01)
        XCTAssertEqual(framed.height, mirror.height * zoom.scale, accuracy: 0.01)
    }

    /// The point under the cursor stays under the cursor — the property that makes zooming
    /// feel like a magnifier rather than a jump.
    func testZoomingHoldsThePointUnderTheCursor() {
        var zoom = MirrorZoom()
        let cursor = CGPoint(x: 120, y: 90)

        let before = zoom.frame(mirroring: mirror, container: mirror.size)
        let fractionX = (cursor.x - before.minX) / before.width
        let fractionY = (cursor.y - before.minY) / before.height

        zoom.zoom(by: 60, at: cursor, container: mirror.size)

        let after = zoom.frame(mirroring: mirror, container: mirror.size)
        XCTAssertEqual(after.minX + fractionX * after.width, cursor.x, accuracy: 0.5)
        XCTAssertEqual(after.minY + fractionY * after.height, cursor.y, accuracy: 0.5)
    }

    func testThereIsACeiling() {
        var zoom = MirrorZoom()
        for _ in 0..<200 { zoom.zoom(by: 100, at: CGPoint(x: 200, y: 150), container: mirror.size) }
        XCTAssertLessThanOrEqual(zoom.scale, MirrorZoom.maxScale)
    }

    // MARK: Panning while magnified

    func testPanningIsRefusedWhileUnmagnified() {
        var zoom = MirrorZoom()
        zoom.pan(by: CGSize(width: 50, height: 50), container: mirror.size)
        XCTAssertEqual(zoom.frame(mirroring: mirror, container: mirror.size), mirror,
                       "panning a true mirror would show map the players cannot see")
    }

    /// Magnified, the DM can move the magnifier — but never off the mirrored region, or they
    /// would be looking at map the table is not being shown.
    func testPanningIsHeldInsideTheMirroredRegion() {
        var zoom = MirrorZoom()
        zoom.zoom(by: 60, at: CGPoint(x: 200, y: 150), container: mirror.size)
        zoom.pan(by: CGSize(width: 10_000, height: 10_000), container: mirror.size)

        let framed = zoom.frame(mirroring: mirror, container: mirror.size)
        XCTAssertLessThanOrEqual(framed.minX, mirror.minX + 0.01,
                                 "panned past the left edge of what the players see")
        XCTAssertLessThanOrEqual(framed.minY, mirror.minY + 0.01)
        XCTAssertGreaterThanOrEqual(framed.maxX, mirror.maxX - 0.01)
        XCTAssertGreaterThanOrEqual(framed.maxY, mirror.maxY - 0.01)
    }

    // MARK: Resetting

    func testResettingReturnsToATrueMirror() {
        var zoom = MirrorZoom()
        zoom.zoom(by: 60, at: CGPoint(x: 120, y: 90), container: mirror.size)
        zoom.pan(by: CGSize(width: 30, height: 20), container: mirror.size)

        zoom.reset()

        XCTAssertEqual(zoom.scale, 1)
        XCTAssertFalse(zoom.isMagnified)
        XCTAssertEqual(zoom.frame(mirroring: mirror, container: mirror.size), mirror)
    }
}
