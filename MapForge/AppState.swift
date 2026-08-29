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
    @Published private(set) var playerScreen: NSScreen?

    private let playerWindow = PlayerWindowController()
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.presentIfPossible() }
        }
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
