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
            // Solo Sight holds a Pawn ID, and this is every way a document can lose one:
            // a deletion, a Cancel that restores a snapshot from before the Pawn existed,
            // and the wholesale replacement `loadMap` does when another Map opens. Clearing
            // it here rather than at each call site is why the mode cannot outlive its
            // subject — the `be14e58` bug class, whose lesson was that a reference into a
            // document needs the document to be the thing that invalidates it.
            if let id = soloSightPawnID, !fog.pawns.contains(where: { $0.id == id }) {
                soloSightPawnID = nil
            }
            // A Measurement anchored to a Pawn is a reference into this document too, and
            // invalidates for the same reason and in the same place. Pinned ones hold the
            // same kind of reference and go the same way — a pin does not make a stale
            // anchor any less stale.
            if case .pawn(let id) = measurement?.origin,
               !fog.pawns.contains(where: { $0.id == id }) {
                measurement = nil
            }
            pinnedMeasurements.removeAll { pinned in
                if case .pawn(let id) = pinned.origin {
                    return !fog.pawns.contains(where: { $0.id == id })
                }
                return false
            }
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
        // Explicitly, before the document changes underneath it. `fog`'s didSet would also
        // drop the ID, but only because Pawn IDs are UUIDs and the incoming Map's will not
        // match — an accident of uniqueness rather than a rule, and it says nothing about a
        // Map opened without a fog reassignment. The mode belongs to the Map it was set on.
        soloSightPawnID = nil
        // Same rule, same reason: a Measurement belongs to the Map it was taken on, and
        // its distance means something different under another Map's Grid.
        measurement = nil
        pinnedMeasurements = []
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

    /// The Pawn under **Solo Sight**, or nil when the table is seeing the Map normally.
    ///
    /// One optional ID, not a set: at most one Pawn is isolated at a time, and `Pawn.ID?`
    /// is a strict subset of `Set<Pawn.ID>` if isolating a scouting pair is ever wanted.
    ///
    /// Not persisted, like `isFogOverlayOn` and unlike the eye — nobody wants to reopen a
    /// Map tomorrow and find the table still looking through one character's eyes. See
    /// ADR 0004 for why the mode is derived and mutates no Pawn.
    @Published private(set) var soloSightPawnID: Pawn.ID?

    /// Isolate a Pawn, or pass nil to end Solo Sight.
    ///
    /// Not undoable, exactly as `setPawnHidden` and `setPawnLight` are not, and for the
    /// same stated reason: a live performance action taken mid-session does not belong in
    /// the DM's authoring undo stack. It records no live edit either, because it changes no
    /// Pawn — there is nothing for `carryLiveState` to carry.
    func setSoloSight(id: Pawn.ID?) {
        guard soloSightPawnID != id else { return }
        soloSightPawnID = id
    }

    /// The isolated Pawn's ID, but only while that Pawn is actually on the Map.
    ///
    /// Every render path asks for this rather than `soloSightPawnID`, because an ID that
    /// matches no Pawn is worse than no mode at all: the fog falls back to lighting
    /// everything while the token rule puts the whole party through a discovery test
    /// against a Pawn that is not there, and the table watches the party disappear from a
    /// fully lit Map. Resolving it once here is what makes a stale ID inert instead.
    ///
    /// `fog`'s `didSet` already clears the ID when its Pawn goes, so this is the belt to
    /// that braces — the states it covers are the ones between a mutation and its
    /// observer.
    var resolvedSoloSightPawnID: Pawn.ID? {
        guard let id = soloSightPawnID,
              fog.pawns.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// The **Measurement** being taken, or nil when nothing is being measured.
    ///
    /// One at a time, still: this is the shape the DM is actively drawing or has just
    /// settled, and the clicks that drive it need an unambiguous subject. Measurements
    /// that outlive it are **pinned** instead — see `pinnedMeasurements`.
    ///
    /// Not persisted, like `isFogOverlayOn` and `soloSightPawnID` — a Measurement is a
    /// question asked during a turn, not something to reopen a Map and find still on it.
    @Published private(set) var measurement: Measurement?

    /// Measurements the DM has parked on the Map, which stay until unpinned.
    ///
    /// Retires the "at most one Measurement" rule this feature shipped with. That rule was
    /// reasoned from Solo Sight's `Pawn.ID?` (ADR 0004) and it held while every Measurement
    /// was transient — but a DM comparing two spell areas, or holding a route on screen
    /// while measuring the next one, needs both on the Map at once. The live slot above is
    /// unchanged: pinning is what makes a Measurement outlive the next click.
    ///
    /// Not persisted either. A pin survives the next click, not the next session.
    @Published private(set) var pinnedMeasurements: [Measurement] = []

    /// Park the settled Measurement on the Map and free the live slot for the next one.
    ///
    /// Only a settled Measurement pins: one still following the cursor is not yet an
    /// answer, and pinning it would park whatever the DM happened to be dragging.
    func pinMeasurement() {
        guard let measurement, measurement.isDistanceSettled else { return }
        pinnedMeasurements.append(measurement)
        self.measurement = nil
    }

    func unpinMeasurement(id: Measurement.ID) {
        pinnedMeasurements.removeAll { $0.id == id }
    }

    /// Start a Measurement, or pass nil to dismiss it.
    ///
    /// Not undoable, exactly as `setSoloSight` and `movePawn` are not: a live performance
    /// action taken mid-session does not belong in the DM's authoring undo stack. It
    /// changes no Pawn, so there is no live edit to record either.
    func setMeasurement(_ measurement: Measurement?) {
        guard self.measurement != measurement else { return }
        self.measurement = measurement
    }

    /// The Measurement, but only while its Origin still exists.
    ///
    /// Every render path asks for this rather than `measurement`, for the reason
    /// `resolvedSoloSightPawnID` exists: an anchor ID that matches no Pawn would otherwise
    /// draw the shape at the Map's origin — a confident wrong answer, which is the one
    /// thing a measuring tool must not give.
    var resolvedMeasurement: Measurement? {
        guard let measurement else { return nil }
        if case .pawn(let id) = measurement.origin,
           !fog.pawns.contains(where: { $0.id == id }) { return nil }
        return measurement
    }

    /// Where the on-screen Measurement currently starts, in image pixels. Follows an
    /// anchoring Pawn as it moves, which is why this is resolved rather than stored.
    var measurementOriginPoint: MapPoint? {
        resolvedMeasurement?.originPoint { id in
            fog.pawns.first(where: { $0.id == id })?.at
        }
    }

    /// Every Measurement that should be drawn, paired with where it starts: the pinned
    /// ones and then the live one on top.
    ///
    /// One list so both screens draw from the same answer — two lists is how the Control
    /// Window and the Player Display drift, which is the divergence `PawnToken` and
    /// `PlayerVisibility.showsToPlayers` exist to prevent.
    var drawableMeasurements: [(measurement: Measurement, origin: MapPoint)] {
        var drawable = pinnedMeasurements.compactMap { pinned -> (Measurement, MapPoint)? in
            guard let origin = pinned.originPoint(pawnAt: { id in
                fog.pawns.first(where: { $0.id == id })?.at
            }) else { return nil }
            return (pinned, origin)
        }
        if let measurement = resolvedMeasurement, let origin = measurementOriginPoint {
            drawable.append((measurement, origin))
        }
        return drawable
    }

    /// Whether measuring is offered at all on the current Map.
    var measurementAvailability: MeasurementControl.Availability {
        MeasurementControl.availability(hasDeclaredGrid: hasDeclaredGrid,
                                        hasMap: mapImage != nil)
    }

    /// How many image pixels one Grid square spans, or nil without a declared Grid.
    /// The conversion every Measurement needs to turn squares into pixels.
    var pixelsPerSquare: CGFloat? {
        guard hasDeclaredGrid, let image = mapImage, squaresWide > 0 else { return nil }
        return image.pixelSize.width / CGFloat(squaresWide)
    }

    /// The lit regions for the current Map, cached against the fog and the Grid.
    ///
    /// Returns nothing when no Grid has been declared: Light radii are in Grid squares, so
    /// without one every region would be sized against a default that is almost certainly
    /// wrong — and darkness in the wrong places is worse than no darkness. The Control
    /// Window says so (see `undeclaredGridWarning`).
    var litRegions: [LitRegion] {
        guard let image = mapImage, let pixelsPerSquare else { return [] }
        return visibilityCache.regions(for: fog, imagePixelSize: image.pixelSize,
                                       pixelsPerSquare: pixelsPerSquare,
                                       soloSightPawnID: resolvedSoloSightPawnID)
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
        // The mode's document belongs to the Map it opened on. If another Map has been
        // opened since, this is the outgoing Map's fog and applying it would overwrite
        // the incoming Map's — on screen and, through the autosave, on its file.
        guard isFogEditingCurrentMap else { return }
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

    /// The Map the fog editing mode was opened on, or nil when the mode is closed.
    ///
    /// The mode's document is a snapshot taken when it opened, and `ControlView` holds it
    /// in `@State` that no Map change reaches. Opening another Map mid-mode therefore left
    /// a live `FogEdits` carrying the *outgoing* Map's fog, and the next in-mode action —
    /// an edit, an Undo, or Cancel — pushed it onto the incoming Map and autosaved it over
    /// that Map's fog file. Stamping the Map here lets both `applyFogEdits` and
    /// `cancelFogEditing` refuse a document that belongs to a Map no longer open.
    private(set) var fogEditingMapURL: URL?

    /// Called as the fog editing mode opens: from here, live edits are the ones to keep.
    func beginFogEditing() {
        liveEdits = [:]
        fogEditingMapURL = mapURL
        // Fog authoring needs the whole Map lit, and an isolated view would fight the
        // inspector it is being authored through.
        soloSightPawnID = nil
        // Measuring is a play action, and the authoring preview is a different surface
        // with a different transform — a Measurement left on it would be drawn wrong.
        measurement = nil
        pinnedMeasurements = []
    }

    /// Called as the fog editing mode closes, by Done as well as Cancel.
    func endFogEditing() {
        fogEditingMapURL = nil
    }

    /// Whether a document authored in the fog mode still belongs to the Map that is open.
    /// False once another Map has been opened underneath the mode.
    private var isFogEditingCurrentMap: Bool {
        fogEditingMapURL != nil && fogEditingMapURL == mapURL
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
        // Same crossing as `applyFogEdits`, and worse: `edits.original` is the outgoing
        // Map's fog as it stood before any editing, so restoring it onto another Map
        // replaces that Map's fog wholesale. Closing the mode is still correct.
        guard isFogEditingCurrentMap else {
            endFogEditing()
            return
        }
        var restored = edits.original
        restored.squaresWide = fog.squaresWide
        // Same reconciliation as an edit: the table's edits survive Cancel because they
        // were never part of what the mode was editing, while a rename made through the
        // in-mode inspector goes through `FogEdits` and is discarded like any other in-mode
        // edit.
        restored.pawns = restored.pawns.map { carryLiveState(onto: $0) }
        fog = restored
        flushPendingFogWrites()
        endFogEditing()
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
        // The eye takes a Pawn out of the lighting, so hiding the isolated one strands Solo
        // Sight on a Pawn that emits nothing: the fog falls back to lighting the Map with
        // every torch while the token rule keeps the rest of the party under the discovery
        // test, and the table sees a lit Map with most of the party missing from it. The
        // control is disabled on a hidden Pawn, so the DM cannot click their way back out
        // either. Hiding the subject ends the mode instead.
        if isHidden, soloSightPawnID == id { soloSightPawnID = nil }
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
