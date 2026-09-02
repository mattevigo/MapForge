import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var mapImage: NSImage?
    @Published var mapURL: URL?
    @Published var squaresWide: Double = 30 {
        didSet {
            // Setting the value at all is a declaration — typed, stepped, or derived by
            // Grid Fit. Deliberately NOT `squaresWide != oldValue`: a DM whose Map really
            // is the default 30 squares wide types 30, the value never moves, and keying
            // the declaration on a change left their Lights dark while the warning told
            // them to do the one thing they had just done. Restoring a value the DM did
            // not choose goes through `restoreGrid` instead.
            hasDeclaredGrid = true
            publishGridToFog()
            presentIfPossible()
        }
    }
    /// Whether the DM has actually declared this Map's Grid, as opposed to the default
    /// 30 the app starts with. Light radii are in Grid squares, so an undeclared Grid
    /// renders every Light at a plausible-looking wrong size — the failure the fog spec
    /// requires be visible rather than silent.
    ///
    /// The in-memory half of `fog.squaresWide`, which is the persisted one: a declared
    /// Grid is a non-nil value there. Kept as a separate property because `squaresWide`
    /// always has a number to render and draw with, declared or not.
    @Published private(set) var hasDeclaredGrid = false

    /// Put back a value the DM did not choose — cancelling Grid Fit restores what was
    /// there before, which must not count as declaring a Grid they never asserted, and
    /// must not leave the cancelled value on disk.
    func restoreGrid(squaresWide squares: Double, wasDeclared: Bool) {
        // The declaration goes first. `squaresWide`'s didSet declares and publishes
        // unconditionally, so assigning it first would push the value being *cancelled*
        // into `fog` and schedule a write of it, before the next line took the declaration
        // back. The debounce happens to coalesce that away — but `cancelGridFit` flushes
        // immediately afterwards, so the window is real, not theoretical.
        hasDeclaredGrid = wasDeclared
        squaresWide = squares
        // didSet set it back to true; the restore is what decides.
        hasDeclaredGrid = wasDeclared
        publishGridToFog()
    }

    /// Viewport origin in map inches; nil = centered (the default on map load).
    @Published var viewportOrigin: CGPoint? {
        didSet { presentIfPossible() }
    }
    /// The Walls, Lights and Pawns authored on the current Map, and its Grid. Edits are
    /// debounced to disk. The Grid rides here rather than being persisted separately so
    /// that Light radii — which are in Grid squares — travel with their unit (ADR 0003);
    /// `squaresWide` mirrors into it through `publishGridToFog`.
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
        //
        // This only decides the screen. What made the suite unrunnable was the *remembered*
        // display leaking in from real use: see `DisplayPreferences.forThisLaunch`.
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
        let document = fogStore.load(forMapAt: url) ?? FogDocument()
        // Assign the fog BEFORE restoring the Grid: `restoreGrid` writes back into `fog`,
        // and doing it the other way round would push the outgoing Map's Grid into the
        // incoming Map's document — then onto its file.
        fog = document
        // The Map's own Grid if it has one on disk, otherwise undeclared: `squaresWide`
        // carries over from the last Map, which is a plausible-looking wrong number for
        // this one. `restoreGrid`, not `squaresWide =`, because a value read from a file
        // is not the DM declaring it now — the declaration is what the file records.
        restoreGrid(squaresWide: document.squaresWide ?? squaresWide,
                    wasDeclared: document.squaresWide != nil)
        fogLoadFailure = fogStore.lastLoadFailure
        presentIfPossible()
    }

    /// Mirror the Grid into `fog`, which is what the autosave watches. Only a *declared*
    /// Grid is written: the default 30 is a guess, and persisting it would make every Map
    /// claim a Grid nobody set — and light every one of them at a wrong size.
    private func publishGridToFog() {
        let declared = hasDeclaredGrid ? squaresWide : nil
        guard fog.squaresWide != declared else { return }
        fog.squaresWide = declared
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
        recordLiveEdit(.torch, on: id)
    }

    /// Move a Pawn outside the fog editing mode — the live table action, since the party
    /// moves during play and not during prep.
    func movePawn(id: Pawn.ID, to point: MapPoint) {
        guard let index = fog.pawns.firstIndex(where: { $0.id == id }) else { return }
        fog.pawns[index].at = point
        recordLiveEdit(.position, on: id)
    }

    /// Rename a Pawn outside the fog editing mode — "3" becomes "Goblin B" in the middle
    /// of a fight, without leaving the table for authoring mode.
    ///
    /// The one deliberate crossing of the authoring/play line, and it follows `movePawn`
    /// exactly: **not undoable**. A label is not geometry, and renaming is the same kind of
    /// live, small, immediate act as moving a token. The fog undo stack is mode-local and
    /// cannot unwind past what the mode opened with, so a live edit has no stack to land in
    /// anyway. The in-mode `pawnInspector` path stays undoable through `FogEdits` — two
    /// paths with different undo semantics is the pattern here, not an inconsistency.
    func setPawnLabel(id: Pawn.ID, _ label: String) {
        guard let index = fog.pawns.firstIndex(where: { $0.id == id }) else { return }
        fog.pawns[index].label = label
        recordLiveEdit(.label, on: id)
    }

    /// Push the fog authored inside the editing mode onto the Map.
    ///
    /// Merges the mode's **geometry** rather than assigning its document wholesale. The
    /// document `FogEdits` carries is a snapshot taken when the mode opened, and two kinds
    /// of live state can change while the mode is open: the Grid, whose field and stepper
    /// stay enabled, and a Pawn's label, renamed from the live row that also stays on
    /// screen. Assigning the snapshot back reverted both — and for the Grid the stale value
    /// is what reached the file, silently losing it on the next relaunch.
    func applyFogEdits(_ edits: FogEdits) {
        var merged = edits.document
        merged.squaresWide = fog.squaresWide
        merged.pawns = merged.pawns.map { carryLiveState(onto: $0) }
        fog = merged
    }

    /// Carry the table's live edits onto a Pawn coming out of the fog editing mode.
    ///
    /// Three of a Pawn's properties stay editable at the table while the mode is open: its
    /// label (the live row's field), its position (`PawnLayer` dragging, deliberately live)
    /// and its torch (`setPawnLight`, which has no in-mode special case). All three write
    /// straight to `fog`, so assigning the mode's snapshot back would revert them — a Pawn
    /// dragged mid-fight would snap back the moment the DM drew a Wall.
    ///
    /// Driven by `liveEdits`, which records what the table actually touched, rather than by
    /// comparing documents. Comparison cannot work: `applyFogEdits` writes the mode's
    /// values into `fog` too, so by the time Cancel runs, "the live value" and "a value the
    /// mode wrote" are the same bytes and no diff distinguishes them.
    private func carryLiveState(onto edited: Pawn) -> Pawn {
        var pawn = edited
        guard let live = fog.pawns.first(where: { $0.id == pawn.id }),
              let touched = liveEdits[pawn.id] else { return pawn }
        if touched.contains(.label) { pawn.label = live.label }
        if touched.contains(.position) { pawn.at = live.at }
        if touched.contains(.torch) { pawn.light.isOn = live.light.isOn }
        if touched.contains(.hidden) { pawn.isHidden = live.isHidden }
        return pawn
    }

    /// What the table edited on each Pawn while the fog mode has been open.
    ///
    /// Cleared when the mode opens. A live edit is not undoable and must survive both an
    /// in-mode edit and Cancel; an in-mode edit is undoable and must not survive Cancel.
    /// Only recording the live writes as they happen tells the two apart.
    struct LivePawnEdit: OptionSet {
        let rawValue: Int
        static let label = LivePawnEdit(rawValue: 1 << 0)
        static let position = LivePawnEdit(rawValue: 1 << 1)
        static let torch = LivePawnEdit(rawValue: 1 << 2)
        static let hidden = LivePawnEdit(rawValue: 1 << 3)
    }

    private var liveEdits: [Pawn.ID: LivePawnEdit] = [:]

    /// Called as the fog editing mode opens: from here, live edits are the ones to keep.
    func beginFogEditing() {
        liveEdits = [:]
    }

    private func recordLiveEdit(_ edit: LivePawnEdit, on id: Pawn.ID) {
        liveEdits[id, default: []].insert(edit)
    }

    /// Discard the fog authored in the editing mode, including anything the autosave
    /// debounce already wrote: restoring the Walls re-triggers `fog`'s didSet, and the
    /// explicit flush makes the file correct now rather than half a second from now, so a
    /// quit in between cannot persist Walls the DM cancelled.
    ///
    /// The Grid and live Pawn labels survive Cancel for the same reason they survive an
    /// edit: they are not what the mode was editing. Reverting the Grid here while
    /// `squaresWide` and `hasDeclaredGrid` kept the new value left the two permanently
    /// disagreeing — the UI asserting a Grid the file did not have.
    func cancelFogEditing(_ edits: FogEdits) {
        var restored = edits.original
        restored.squaresWide = fog.squaresWide
        // Same reconciliation as an edit: the table's edits survive Cancel because they
        // were never part of what the mode was editing, while a rename made through the
        // in-mode inspector goes through `FogEdits` and is discarded like any other in-mode
        // edit.
        restored.pawns = restored.pawns.map { carryLiveState(onto: $0) }
        fog = restored
        flushPendingFogWrites()
    }

    /// Take a Pawn off the Player Display without deleting it, from the live row.
    ///
    /// Not undoable, exactly as `setPawnLight` is not and for the same stated reason: this
    /// is a live performance action taken mid-session, and filling the undo stack with
    /// toggles would bury the DM's authoring work behind a row of them.
    ///
    /// Takes the value rather than toggling, so a SwiftUI binding that writes the same
    /// state twice — which it does on a state resync — cannot flip it back.
    func setPawnHidden(id: Pawn.ID, isHidden: Bool) {
        guard let index = fog.pawns.firstIndex(where: { $0.id == id }),
              fog.pawns[index].isHidden != isHidden else { return }
        fog.pawns[index].isHidden = isHidden
        recordLiveEdit(.hidden, on: id)
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
