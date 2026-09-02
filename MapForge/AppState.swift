import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var mapImage: NSImage?
    @Published var mapURL: URL?
    @Published var squaresWide: Double = 30 {
        didSet {
            // Any change to the value is a declaration — typed, stepped, or derived by
            // Grid Fit. The default 30 is a guess so the preview has something to show.
            if squaresWide != oldValue { hasDeclaredGrid = true }
            presentIfPossible()
        }
    }
    /// Whether the DM has actually declared this Map's Grid, as opposed to the default
    /// 30 the app starts with. Light radii are in Grid squares, so an undeclared Grid
    /// renders every Light at a plausible-looking wrong size — the failure issue 03's
    /// scope section requires be visible rather than silent. Not persisted, because
    /// `squaresWide` is not either.
    @Published private(set) var hasDeclaredGrid = false
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
    /// Recomputes Visibility only when the fog actually changes — never on a Viewport pan,
    /// which is drag-rate. See issue 05 and `VisibilityCache`.
    private let visibilityCache = VisibilityCache()
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
        loadMap(image: image, at: url)
        // After loadMap, which clears the declaration for the incoming Map: a test that
        // passes --test-squares has declared this Map's Grid.
        if let sIdx = args.firstIndex(of: "--test-squares"), args.indices.contains(sIdx + 1),
           let squares = Double(args[sIdx + 1]) {
            squaresWide = squares
        }
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
        // A new Map has not had its Grid declared: `squaresWide` carries over from the
        // last one, which is a plausible-looking wrong number for this one.
        hasDeclaredGrid = false
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

    /// Switch a Light on or off from the live panel, outside the fog editing mode.
    /// Takes effect immediately on the Player Display: this is the action a DM performs
    /// mid-session with players watching.
    ///
    /// Takes the value rather than toggling, so a SwiftUI binding that writes the same
    /// state twice — which it does on a state resync — cannot flip the Light twice.
    func setLight(id: Light.ID, isOn: Bool) {
        guard let index = fog.lights.firstIndex(where: { $0.id == id }),
              fog.lights[index].isOn != isOn else { return }
        fog.lights[index].isOn = isOn
    }

    /// Whether players see the Fog Overlay. Off leaves the Map fully visible — with the
    /// Pawns still on it, because turning off fog is not turning off tokens.
    @Published var isFogOverlayOn = true

    /// The lit regions for the current Map, cached against the fog and the Grid.
    ///
    /// Returns nothing when no Grid has been declared: Light radii are in Grid squares, so
    /// without one every region would be sized against a default that is almost certainly
    /// wrong — and darkness in the wrong places is worse than no darkness. The Control
    /// Window says so (see `undeclaredGridWarning`).
    var litRegions: [LitRegion] {
        guard hasDeclaredGrid, let image = mapImage, squaresWide > 0 else { return [] }
        let pixelsPerSquare = image.pixelSize.width / CGFloat(squaresWide)
        return visibilityCache.regions(for: fog, imagePixelSize: image.pixelSize,
                                       pixelsPerSquare: pixelsPerSquare)
    }

    /// A Pawn's light, from the live panel. Same contract as `setLight`.
    func setPawnLight(id: Pawn.ID, isOn: Bool) {
        guard let index = fog.pawns.firstIndex(where: { $0.id == id }),
              fog.pawns[index].light.isOn != isOn else { return }
        fog.pawns[index].light.isOn = isOn
    }

    /// Move a Pawn outside the fog editing mode — the live table action, since the party
    /// moves during play and not during prep.
    func movePawn(id: Pawn.ID, to point: MapPoint) {
        guard let index = fog.pawns.firstIndex(where: { $0.id == id }) else { return }
        fog.pawns[index].at = point
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
