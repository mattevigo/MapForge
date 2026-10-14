import XCTest
@testable import MapForge

/// The square the DM cuts from a picture: where it starts, and how it is kept inside the
/// picture however it is dragged or resized. See `CONTEXT.md`, **Face**.
final class FaceCutTests: XCTestCase {
    private let landscape = CGSize(width: 400, height: 300)
    private let portrait = CGSize(width: 200, height: 500)

    func testTheCutStartsAsTheLargestCentredSquare() {
        XCTAssertEqual(FaceCut.centredSquare(in: landscape),
                       CGRect(x: 50, y: 0, width: 300, height: 300))
        XCTAssertEqual(FaceCut.centredSquare(in: portrait),
                       CGRect(x: 0, y: 150, width: 200, height: 200))
    }

    func testMovingPastAnEdgeStopsAtTheEdge() {
        let start = CGRect(x: 50, y: 50, width: 100, height: 100)

        XCTAssertEqual(FaceCut.moved(start, by: CGSize(width: 1000, height: -1000), in: landscape),
                       CGRect(x: 300, y: 0, width: 100, height: 100))
        XCTAssertEqual(FaceCut.moved(start, by: CGSize(width: -1000, height: 1000), in: landscape),
                       CGRect(x: 0, y: 200, width: 100, height: 100))
    }

    func testResizingKeepsTheCentreAndStaysSquare() {
        let start = CGRect(x: 150, y: 100, width: 100, height: 100)

        let resized = FaceCut.resized(start, toSide: 60, in: landscape)

        XCTAssertEqual(resized, CGRect(x: 170, y: 120, width: 60, height: 60))
    }

    func testResizingNearAnEdgeShiftsTheCutBackInside() {
        let inCorner = CGRect(x: 0, y: 0, width: 100, height: 100)

        let resized = FaceCut.resized(inCorner, toSide: 200, in: landscape)

        XCTAssertEqual(resized, CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    func testTheCutIsNeverLargerThanThePictureAllows() {
        let resized = FaceCut.resized(FaceCut.centredSquare(in: landscape), toSide: 5000,
                                      in: landscape)

        XCTAssertEqual(resized.width, 300)
        XCTAssertEqual(resized.height, 300)
        XCTAssertTrue(CGRect(origin: .zero, size: landscape).contains(resized))
    }

    func testTheCutIsNeverSmallerThanTheFloor() {
        let resized = FaceCut.resized(CGRect(x: 100, y: 100, width: 100, height: 100),
                                      toSide: 1, in: landscape)

        XCTAssertEqual(resized.width, FaceCut.minimumSide)
    }

    func testATinyPictureIsCutWhole() {
        // Smaller than the floor: the floor gives way to the picture rather than leaving it.
        let tiny = CGSize(width: 10, height: 8)

        XCTAssertEqual(FaceCut.resized(FaceCut.centredSquare(in: tiny), toSide: 1, in: tiny),
                       CGRect(x: 1, y: 0, width: 8, height: 8))
    }

    func testCutsAreWholePixels() {
        // A cut lands on whole pixels, so the kept square is exactly the square the DM saw.
        let resized = FaceCut.moved(CGRect(x: 10, y: 10, width: 100, height: 100),
                                    by: CGSize(width: 0.4, height: 7.6), in: landscape)

        XCTAssertEqual(resized, CGRect(x: 10, y: 18, width: 100, height: 100))
    }
}
