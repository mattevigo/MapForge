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
    /// The Walls, Lights and Pawns authored on the current Map. Edits are debounced to
    /// disk; the Map's Grid, by contrast, is still in-memory only (see FogDocument).
    @Published var fog = FogDocument() {
        didSet {
            guard fog != oldValue, mapURL != nil else { return }
            fogAutosave.schedule(fog)
        }
    }
    /// Set when a fog file exists but could not be read, so the UI can say so rather than
    /// letting a DM assume their Walls were never there and redraw over them.
    @Published private(set) var fogLoadFailure: FogStore.UnreadableFile?
    @Published private(set) var playerScreen: NSScreen?
    /// The DM's explicit pick. Nil = let the policy choose (remembered, else sole external).
    @Published private(set) var chosenDisplay: DisplayIdentity?

    private let playerWindow = PlayerWindowController()
    private let preferences: DisplayPreferences
    private let fogStore: FogStore
    private var fogAutosave: FogAutosave!
    private var screenObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    init(preferences: DisplayPreferences = DisplayPreferences(),
         fogStore: FogStore = FogStore()) {
        self.preferences = preferences
        self.fogStore = fogStore
        fogAutosave = FogAutosave { [weak self] document in
            self?.writeFog(document)
        }
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
            // Flush before terminating: a Wall drawn in the last half-second is still
            // sitting in the debounce, and quitting is exactly when it would be lost.
            Task { @MainActor [weak self] in
                self?.flushPendingFogWrites()
                NSApp.terminate(nil)
            }
        }
    }

    /// Test seam: UI tests load a map via `--test-map <path> [--test-squares N]`,
    /// bypassing the open panel (NSOpenPanel can't be driven from XCUITest), and pick
    /// the Player Display via `--test-player-screen auto`.
    func loadMapFromLaunchArgumentsIfPresent() {
        let args = CommandLine.arguments
        // Removes the "requires a connected Player Display" constraint: the tests pick a
        // screen explicitly instead of relying on there happening to be exactly one
        // external. Prefer a screen the Control Window is NOT on — presenting onto it
        // would relocate it mid-test and every click would miss — and fall back to the
        // only screen there is, where the Map yields below the controls instead.
        if args.contains("--test-player-screen") {
            let controlScreen = NSApp.windows.first(where: {
                $0.identifier?.rawValue.hasPrefix("control") == true
            })?.screen ?? NSScreen.main
            let away = NSScreen.screens.first { $0 != controlScreen }
            chosenDisplay = (away ?? NSScreen.screens.first)?.displayIdentity
        }
        guard let idx = args.firstIndex(of: "--test-map"), args.indices.contains(idx + 1) else { return }
        let url = URL(fileURLWithPath: args[idx + 1])
        guard let image = NSImage(contentsOf: url) else { return }
        if let sIdx = args.firstIndex(of: "--test-squares"), args.indices.contains(sIdx + 1),
           let squares = Double(args[sIdx + 1]) {
            squaresWide = squares
        }
        loadMap(image: image, at: url)
    }

    /// Every connected screen, built-in included: presenting on the built-in is how the
    /// app is exercised without a TV attached.
    var displayCandidates: [DisplayCandidate] { NSScreen.screens.compactMap(\.displayCandidate) }

    /// Pick the Player Display explicitly. Remembered for later sessions, and Blackout
    /// would engage here so the switch never flashes a Map at players (issue 07).
    func chooseDisplay(_ identity: DisplayIdentity) {
        chosenDisplay = identity
        preferences.rememberedPlayerDisplay = identity
        presentIfPossible()
    }

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
        loadMap(image: image, at: url)
    }

    /// Switch to a Map, bringing its fog with it. Any edit still sitting in the debounce
    /// belongs to the *outgoing* Map, so it is flushed before `mapURL` moves on.
    func loadMap(image: NSImage, at url: URL) {
        fogAutosave.flush()
        mapURL = url
        mapImage = image
        viewportOrigin = nil
        fog = fogStore.load(forMapAt: url) ?? FogDocument()
        fogLoadFailure = fogStore.lastLoadFailure
        presentIfPossible()
    }

    /// Write fog for the Map it was authored on. A failed write must be visible: silently
    /// dropping a traced room is the one outcome this feature cannot have.
    private func writeFog(_ document: FogDocument) {
        guard let url = mapURL else { return }
        do {
            try fogStore.save(document, forMapAt: url)
        } catch {
            NSLog("MapForge: could not save fog for \(url.lastPathComponent): \(error)")
        }
    }

    /// Flush any pending fog edit. Called as the app terminates.
    func flushPendingFogWrites() {
        fogAutosave.flush()
    }

    /// Resolve the Player Display through the policy and present there. With two or more
    /// unrecognised screens nothing is presented — the picker waits for a choice.
    func presentIfPossible() {
        guard mapImage != nil,
              let chosen = PlayerScreenPolicy.resolve(candidates: displayCandidates,
                                                      explicit: chosenDisplay,
                                                      remembered: preferences.rememberedPlayerDisplay),
              let screen = NSScreen.screens.first(where: { $0.displayIdentity?.uuid == chosen.identity.uuid })
        else {
            playerScreen = nil
            playerWindow.hide()
            return
        }
        playerScreen = screen
        playerWindow.present(appState: self, on: screen)
    }
}
