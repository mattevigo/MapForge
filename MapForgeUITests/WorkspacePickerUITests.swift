import XCTest

/// The launch gate.
///
/// Every test here passes a temp folder via `--test-workspace=` or lets
/// `--test-fresh-preferences` adopt a throwaway one. Neither may ever resolve to a folder the
/// developer actually uses: a UI test that opened a real Workspace would edit a real roster.
final class WorkspacePickerUITests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorkspacePickerUITests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func launch(withWorkspace workspace: URL?) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["--test-fresh-preferences"]
        if let workspace {
            args.append("--test-workspace=\(workspace.path)")
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    func testAWorkspaceGivenOnTheCommandLineSkipsThePicker() {
        let app = launch(withWorkspace: root)

        XCTAssertTrue(app.buttons["Open Map…"].waitForExistence(timeout: 5),
                      "the Control Window should be usable straight away")
        XCTAssertFalse(app.staticTexts["Choose a Workspace"].exists)
    }

    func testTheNamedWorkspaceIsAdoptedAndShown() {
        let app = launch(withWorkspace: root)
        XCTAssertTrue(app.buttons["Open Map…"].waitForExistence(timeout: 5))

        // Adoption is what makes the folder a Workspace, and it writes nothing else.
        let manifest = root.appendingPathComponent(".mapforge/workspace.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path))
        XCTAssertTrue(app.buttons["workspace-switch"].exists)
    }

    func testSwitchingOffersThePickerWithACancel() {
        let app = launch(withWorkspace: root)
        XCTAssertTrue(app.buttons["workspace-switch"].waitForExistence(timeout: 5))

        app.buttons["workspace-switch"].click()

        XCTAssertTrue(app.staticTexts["Choose a Workspace"].waitForExistence(timeout: 5))
        // A Workspace is open behind this sheet, so backing out must be possible.
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.buttons["Cancel"].click()
        XCTAssertTrue(app.buttons["Open Map…"].waitForExistence(timeout: 5))
    }

    func testTheRecentsListNamesTheWorkspaceByItsFolder() {
        let named = root.appendingPathComponent("Eroi delle Terre di Confine")
        try? FileManager.default.createDirectory(at: named, withIntermediateDirectories: true)
        let app = launch(withWorkspace: named)
        XCTAssertTrue(app.buttons["workspace-switch"].waitForExistence(timeout: 5))

        app.buttons["workspace-switch"].click()
        XCTAssertTrue(app.staticTexts["Choose a Workspace"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["Eroi delle Terre di Confine"].exists)
    }

    func testAnUnavailableWorkspaceStaysListedRatherThanVanishing() throws {
        // The unplugged-drive case. The DM must see that the folder is missing, not that
        // their campaign has disappeared.
        let removable = root.appendingPathComponent("OnAnExternalDrive")
        try FileManager.default.createDirectory(at: removable, withIntermediateDirectories: true)
        let app = launch(withWorkspace: removable)
        XCTAssertTrue(app.buttons["workspace-switch"].waitForExistence(timeout: 5))

        // The drive is unplugged mid-session.
        try FileManager.default.removeItem(at: removable)

        app.buttons["workspace-switch"].click()
        XCTAssertTrue(app.staticTexts["Choose a Workspace"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["OnAnExternalDrive"].exists,
                      "the entry stays listed")
        XCTAssertTrue(app.staticTexts["not available"].exists,
                      "and says why it cannot be opened")
    }
}
