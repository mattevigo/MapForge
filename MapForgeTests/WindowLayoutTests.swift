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

    func testRelocationPrefersTheMacsOwnScreenOverAnotherExternal() {
        // Three displays: a Player Display, another external, and the Mac's own screen.
        // "The first other screen" sent the Control Window to whichever external happened
        // to come first — which on a wide multi-display desktop is thousands of points off
        // to the side, where the DM has to go hunting for it and where XCUITest reports
        // every button as not hittable. The Control Window belongs on the Mac's own screen,
        // which is what the Control Window IS: the DM-facing window on the Mac's display.
        let control = CGRect(x: 1800, y: 100, width: 560, height: 480)
        let otherExternal = CGRect(x: 3648, y: 0, width: 1920, height: 1080)
        let moved = WindowLayout.controlWindowRelocation(controlFrame: control,
                                                         playerScreenFrame: playerScreen,
                                                         otherScreenFrames: [otherExternal, builtIn],
                                                         mainScreenFrame: builtIn)
        XCTAssertEqual(moved, CGRect(x: 584, y: 318.5, width: 560, height: 480))
    }

    func testRelocationFallsBackWhenTheMainScreenIsThePlayerDisplay() {
        // The Mac's own screen is presenting, so it is not somewhere to hide from itself.
        let control = CGRect(x: 1800, y: 100, width: 560, height: 480)
        let moved = WindowLayout.controlWindowRelocation(controlFrame: control,
                                                         playerScreenFrame: playerScreen,
                                                         otherScreenFrames: [builtIn],
                                                         mainScreenFrame: playerScreen)
        XCTAssertEqual(moved?.origin.x, 584, "did not fall back to the remaining screen")
    }

    func testTheMainScreenIsPreferredOnlyWhenItIsActuallyAvailable() {
        // The preference has to be looked up among the screens actually on offer. Passing
        // a frame that is not in the candidate list must fall through to the first one
        // rather than returning nothing — the caller names the primary display, which may
        // well be the one presenting.
        let control = CGRect(x: 1800, y: 100, width: 560, height: 480)
        let elsewhere = CGRect(x: -4000, y: 0, width: 1920, height: 1080)
        let moved = WindowLayout.controlWindowRelocation(controlFrame: control,
                                                         playerScreenFrame: playerScreen,
                                                         otherScreenFrames: [builtIn],
                                                         mainScreenFrame: elsewhere)
        XCTAssertEqual(moved?.origin.x, 584, "an unavailable main screen lost the rescue")
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
