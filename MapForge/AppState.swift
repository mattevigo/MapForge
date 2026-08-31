import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var mapImage: NSImage?
    @Published var mapURL: URL?
    @Published var squaresWide: Double = 30 {
        didSet { presentIfPossible() }
    }
    /// Viewport origin in map inches; nil = centered (the default on map load).
    @Published var viewportOrigin: CGPoint? {
        didSet { presentIfPossible() }
    }
    @Published private(set) var playerScreen: NSScreen?

    private let playerWindow = PlayerWindowController()
    private var screenObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.presentIfPossible() }
        }
        // Closing the Control Window must quit the whole app: otherwise the Player
        // window stays fullscreen on the Player Display with no controls anywhere —
        // the app looks stuck and only the buried Window-menu reopen can recover it.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { note in
            let isControlWindow = (note.object as? NSWindow)?.identifier?.rawValue.hasPrefix("control") ?? false
            guard isControlWindow else { return }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    /// Test seam: UI tests load a map via `--test-map <path> [--test-squares N]`,
    /// bypassing the open panel (NSOpenPanel can't be driven from XCUITest).
    func loadMapFromLaunchArgumentsIfPresent() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--test-map"), args.indices.contains(idx + 1) else { return }
        let url = URL(fileURLWithPath: args[idx + 1])
        guard let image = NSImage(contentsOf: url) else { return }
        if let sIdx = args.firstIndex(of: "--test-squares"), args.indices.contains(sIdx + 1),
           let squares = Double(args[sIdx + 1]) {
            squaresWide = squares
        }
        mapURL = url
        mapImage = image
        viewportOrigin = nil
        presentIfPossible()
    }

    var externalScreens: [NSScreen] { NSScreen.screens.filter { !$0.isBuiltin } }

    var playerMetrics: DisplayMetrics? {
        playerScreen.flatMap { DisplayMetrics(screen: $0) }
    }

    var mapScale: MapScale? {
        mapImage.map { MapScale.grid(squaresWide: squaresWide, imagePixelSize: $0.pixelSize) }
    }

    func openMap() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        mapURL = url
        mapImage = image
        viewportOrigin = nil
        presentIfPossible()
    }

    /// Display policy: auto-present only when exactly one external screen is connected;
    /// with two or more, do nothing until the picker exists (issue 05).
    func presentIfPossible() {
        guard mapImage != nil, externalScreens.count == 1, let screen = externalScreens.first else {
            playerScreen = nil
            playerWindow.hide()
            return
        }
        playerScreen = screen
        playerWindow.present(appState: self, on: screen)
    }
}
