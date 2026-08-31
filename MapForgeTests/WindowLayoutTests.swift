import XCTest
@testable import MapForge

final class WindowLayoutTests: XCTestCase {

    let playerScreen = CGRect(x: 1728, y: 0, width: 1920, height: 1080)
    let builtIn = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    func testControlWindowOnPlayerScreenRelocatesCenteredOnOtherScreen() {
        // Control Window sits on the Player Display: presenting would bury it.
        let control = CGRect(x: 1800, y: 100, width: 560, height: 480)
        let moved = WindowLayout.controlWindowRelocation(controlFrame: control,
                                                         playerScreenFrame: playerScreen,
                                                         otherScreenFrames: [builtIn])
        XCTAssertEqual(moved, CGRect(x: 584, y: 318.5, width: 560, height: 480))
    }

    func testControlWindowElsewhereStays() {
        let control = CGRect(x: 100, y: 100, width: 560, height: 480)
        XCTAssertNil(WindowLayout.controlWindowRelocation(controlFrame: control,
                                                          playerScreenFrame: playerScreen,
                                                          otherScreenFrames: [builtIn]))
    }

    func testNoOtherScreenMeansNowhereToGo() {
        let control = CGRect(x: 1800, y: 100, width: 560, height: 480)
        XCTAssertNil(WindowLayout.controlWindowRelocation(controlFrame: control,
                                                          playerScreenFrame: playerScreen,
                                                          otherScreenFrames: []))
    }

    func testOversizedControlWindowShrinksToFitTargetScreen() {
        // Control Window was full-screen on the 1920×1080 Player Display.
        let control = CGRect(x: 1728, y: 0, width: 1920, height: 1080)
        let moved = WindowLayout.controlWindowRelocation(controlFrame: control,
                                                         playerScreenFrame: playerScreen,
                                                         otherScreenFrames: [builtIn])!
        XCTAssertEqual(moved.width, 1728, accuracy: 1e-9)
        XCTAssertEqual(moved.height, 1080, accuracy: 1e-9)
        XCTAssertTrue(builtIn.contains(moved))
    }
}
