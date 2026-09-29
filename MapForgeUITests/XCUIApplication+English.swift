import XCTest

extension XCUIApplication {
    /// Launches the app speaking English, whatever the Mac speaks.
    ///
    /// These tests find some controls by their English titles, and the scheme's own
    /// `-AppleLanguages` reaches only the test runner, never an app launched from it.
    func launchInEnglish() {
        launchArguments += ["-AppleLanguages", "(en)"]
        launch()
    }
}
