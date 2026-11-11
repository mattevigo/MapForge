import XCTest
@testable import MapForge

/// Where a Measurement's distance capsule sits beside an aimed shape.
///
/// It is pushed sideways off the far end, perpendicular to the line *as drawn*. At True
/// Scale on square pixels the Map is scaled the same on both axes, so drawn and Map-space
/// directions agree; on a display whose pixels are not square they do not, and a capsule
/// offset perpendicular to the Map-space direction would slide along the drawn line instead
/// of standing beside it.
final class MeasurementReadoutTests: XCTestCase {
    private let gap: CGFloat = 22
    private let image = CGSize(width: 1000, height: 1000)

    private func nudge(direction: CGFloat, frame: CGRect,
                       shape: MeasurementShape = .line) -> CGVector {
        MeasurementLayer.readoutNudge(shape: shape, direction: direction,
                                      map: MapScale(imagePixelSize: image, physicalWidthInches: 20),
                                      frame: frame)
    }

    /// The direction a Map-space line at `direction` is drawn in on `frame`, read off
    /// `PlayerPlacement` rather than computed the way the layer does.
    private func drawnDirection(_ direction: CGFloat, frame: CGRect) -> CGVector {
        let map = MapScale(imagePixelSize: image, physicalWidthInches: 20)
        let a = PlayerPlacement.viewPoint(MapPoint(x: 500, y: 500), map: map, frame: frame)
        let b = PlayerPlacement.viewPoint(MapPoint(x: 500 + cos(direction) * 100,
                                                   y: 500 + sin(direction) * 100),
                                          map: map, frame: frame)
        return CGVector(dx: b.x - a.x, dy: b.y - a.y)
    }

    // MARK: True Scale

    func testAtTrueScaleAHorizontalLineGetsItsNumberStraightAbove() {
        let n = nudge(direction: 0, frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        XCTAssertEqual(n.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(n.dy, -gap, accuracy: 1e-9)
    }

    func testAtTrueScaleADiagonalLineGetsItsNumberOffTheUpperSide() {
        // 45° down-right, drawn at 45° on a uniform frame: the capsule goes up-right.
        let n = nudge(direction: .pi / 4, frame: CGRect(x: -40, y: 10, width: 500, height: 500))
        XCTAssertEqual(n.dx, gap / 2.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(n.dy, -gap / 2.squareRoot(), accuracy: 1e-9)
    }

    // MARK: An uneven scale

    func testUnderAnUnevenScaleTheNumberStandsBesideTheLineAsDrawn() {
        // A square Map scaled 4:1 — 2000×500 pt — draws a 45° line far flatter.
        let frame = CGRect(x: 0, y: 0, width: 2000, height: 500)
        let n = nudge(direction: .pi / 4, frame: frame)
        let drawn = drawnDirection(.pi / 4, frame: frame)

        XCTAssertEqual(n.dx * drawn.dx + n.dy * drawn.dy, 0, accuracy: 1e-9,
                       "the capsule is not perpendicular to the line the table sees")
        XCTAssertEqual((n.dx * n.dx + n.dy * n.dy).squareRoot(), gap, accuracy: 1e-9)
        XCTAssertLessThan(n.dy, 0, "the capsule left the upper side")
    }

    func testARadiusShapeStillGoesStraightUpUnderAnUnevenScale() {
        let n = nudge(direction: .pi / 4, frame: CGRect(x: 0, y: 0, width: 2000, height: 500),
                      shape: .circle)
        XCTAssertEqual(n.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(n.dy, -gap, accuracy: 1e-9)
    }
}
