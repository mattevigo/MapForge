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
    /// **Map Fit**: the whole Map, as large as the Player Display allows in its own
    /// proportions (letterboxed, never cropped), the Grid ignored.
    /// Off is True Scale at the Viewport.
    ///
    /// A live switch, not a setting: never persisted, so every launch starts at True Scale.
    /// It leaves `viewportOrigin` alone, so turning it off returns the table to where the
    /// Viewport was before. It switches itself off when the Player Display goes — see
    /// `playerScreen`.
    @Published var isMapFitOn = false {
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
            // The Selection holds Pawn and Light IDs, so it goes the same way: a deleted
            // member leaves it and the rest stay picked. Skipped while nothing is picked,
            // which is nearly always — this runs at drag rate.
            if !selection.isEmpty {
                let kept = selection.keepingOnly(pawns: Set(fog.pawns.map(\.id)),
                                                 lights: Set(fog.lights.map(\.id)))
                if kept != selection { selection = kept }
            }
            guard fog != oldValue, mapURL != nil else { return }
            fogAutosave.schedule(fog)
        }
    }
    /// Set when a fog file exists but could not be read, so the UI can say so rather than
    /// letting a DM assume their Walls were never there and redraw over them.
    @Published private(set) var fogLoadFailure: FogStore.UnreadableFile?

    /// The fight being run on this Map, or nil when there is none.
    ///
    /// Holds its own Combat Log lines and derives every number from them, so there is no
    /// second copy of the state to drift — see `Encounter` and ADR-0008. Live state, like
    /// Solo Sight and Measurement: never part of `FogEdits`, never undone by the fog Undo
    /// button.
    @Published var encounter: Encounter?

    /// Every Pawn's combat numbers on this Map, as they stand between fights.
    @Published var statsDocument = StatsDocument()

    /// Set when a stats file exists but could not be read.
    @Published var statsLoadFailure: StatsStore.UnreadableFile?

    let statsStore: StatsStore
    var statsAutosave: StatsAutosave!
    /// Open for as long as an Encounter is running. Appends; never rewrites.
    var logWriter: CombatLogWriter?

    /// The evening in progress, enclosing whatever fights happen inside it. Nil until the DM
    /// starts one — before that, a Comment has nowhere to land and the Comment Bar is dead.
    ///
    /// Written only by `AppState+Session.swift`, which cannot be `private(set)` from another
    /// file. Nothing else should assign it: the lines and the flag must move together.
    @Published var session: Session?

    /// Open for as long as a Session is running. Appends; never rewrites.
    var sessionWriter: SessionLogWriter?

    /// Bumped whenever a Line reaches disk, so an open Log View knows to re-read.
    ///
    /// A counter rather than the lines themselves: the file is the truth and the Session
    /// deliberately holds none of it in memory (ADR-0016). Most appends change nothing else
    /// that is `@Published` — a Comment leaves `session` exactly as it found it — so without
    /// this a DM typing into the Comment Bar with the Log open would watch their own Comment
    /// not appear.
    @Published private(set) var sessionLineCount = 0

    /// Called by `AppState+Session.swift` as it writes.
    func noteSessionLineWritten() { sessionLineCount += 1 }

    /// What the one-time migration did, for the picker to report. Nil when nothing happened,
    /// which is every launch after the first.
    @Published var migrationOutcome: WorkspaceMigration.Outcome?
    /// The Workspace a Map the DM picked should have been in, while the Control Window says
    /// so. Set when "Open Map…" is given an image from outside it; see `openMap(at:)`.
    @Published var mapOutsideWorkspace: Workspace?

    /// The Workspace this session is running out of, or nil before the DM has picked one.
    ///
    /// The app is fully alive while this is nil — the Control Window exists behind the picker
    /// sheet — so everything that reads the roster must tolerate its absence rather than
    /// assume a Workspace was there at init.
    @Published private(set) var workspace: Workspace?
    /// The open Workspace's kept Faces, or nil with none open — when every Pawn is drawn in
    /// its colour and the Edit Pawn sheet offers no picture, there being nowhere to keep one.
    /// Set alongside `workspace`, whose change is what redraws the tokens.
    private(set) var faceLibrary: FaceLibrary?
    /// The cut made from each Monster's, Character's note's and Item's picture, as
    /// `note-faces.json` holds it. Empty with no
    /// Workspace open. See `monsterFace(for:)`.
    private(set) var noteFaces = NoteFaces()
    private var noteFacesStore: NoteFacesStore?

    /// The DM's Parties, as they stand in the open Workspace. Empty before one is open.
    /// Written straight through on every edit rather than debounced: a roster changes when
    /// the DM types in it, which is nothing like drag-rate.
    @Published private(set) var partyBook = PartyBook()

    /// Every Monster read from the open Workspace's notes. Read when the Workspace opens and
    /// at no other time, and never written anywhere — see `BestiaryStore` and ADR-0020.
    /// Settable so a test can hand one over without a folder of notes.
    @Published var bestiary = Bestiary.closed

    /// Every Character's note read from the open Workspace, in the same walk as the Bestiary
    /// and on the same terms: never written anywhere (ADR-0024). Empty until it lands.
    /// Settable so a test can hand some over without a folder of notes.
    @Published var characterNotes = CharacterNotes()

    /// Every Item read from the open Workspace's notes, in the same walk as the Bestiary and on
    /// the same terms: read when the Workspace opens and never written anywhere (ADR-0031).
    /// Settable so a test can hand one over without a folder of notes.
    @Published var treasury = Treasury.closed

    /// The read of the notes in flight — the Bestiary, the Characters' notes and the Treasury,
    /// in one walk (`BestiaryStore.read`) — kept so a test can wait for it and a switch can
    /// abandon it.
    private(set) var bestiaryLoad: Task<Void, Never>?
    /// Which Party the panel offers. Remembered in the Workspace, per ADR-0012.
    @Published private(set) var activePartyID: UUID?
    /// Set when the roster exists but could not be read.
    ///
    /// Surfaced *and* obeyed: while this is set the app will not write the roster at all. The
    /// hazard is `FogStore`'s, one step further along — a DM who opens the app, sees no party,
    /// and retypes it would otherwise have the first save overwrite the very file that could
    /// have been recovered. Reporting the failure without refusing the write would leave the
    /// warning true and useless.
    @Published private(set) var partyLoadFailure: PartyStore.UnreadableFile?

    /// The Party the panel should show: the remembered one, or the first, or none.
    var activeParty: Party? { PartyRoster.activeParty(in: partyBook, id: activePartyID) }
    @Published private(set) var playerScreen: NSScreen? {
        // Map Fit without a Player Display would sit on behind a toggle the DM cannot press.
        // Here rather than in the view, so every way the screen goes — unplugged, a Workspace
        // closed, a Map that cannot be presented — puts it away. See `MapFitToggle`.
        didSet {
            if isMapFitOn, !MapFitToggle.staysOn(hasDisplay: playerScreen != nil) {
                isMapFitOn = false
            }
        }
    }
    /// The DM's explicit pick. Nil = let the policy choose (remembered, else sole external).
    @Published private(set) var chosenDisplay: DisplayIdentity?

    private let playerWindow = PlayerWindowController()
    private let preferences: DisplayPreferences
    private let workspaceStore: WorkspaceStore
    private let fogStore: FogStore
    /// Nil until a Workspace is open: the roster's directory is the Workspace's, so there is
    /// no store to have before the DM has chosen one.
    private var partyStore: PartyStore?
    private var workspacePreferences: WorkspacePreferencesStore?
    /// The one-time move out of Application Support, or nil when this session must not
    /// perform it.
    ///
    /// Nil by default and supplied only by `MapForgeApp`. The migration *deletes* the DM's
    /// real roster from a real path, so it must never be something a session acquires by
    /// omission — a test that constructs an `AppState` and opens a temp Workspace would
    /// otherwise migrate and destroy the developer's own party. It did, once.
    private let migration: WorkspaceMigration?
    private let securityScope: SecurityScope
    /// The URL whose security-scoped access the open Workspace holds, if any. One at a time:
    /// opening another Workspace or closing this one gives it back. See ADR-0025.
    private var heldAccess: URL?
    /// This Workspace's own settings, held in memory and written through on change.
    private var settings = WorkspaceSettings()
    /// Recomputes Visibility only when the fog actually changes — never on a Viewport pan,
    /// which is drag-rate. See issue 05 and `VisibilityCache`.
    private let visibilityCache = VisibilityCache()
    private var fogAutosave: FogAutosave!
    private var screenObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    init(preferences: DisplayPreferences = DisplayPreferences(),
         workspaceStore: WorkspaceStore = WorkspaceStore(),
         migration: WorkspaceMigration? = nil,
         fogStore: FogStore = FogStore(),
         partyStore: PartyStore? = nil,
         statsStore: StatsStore = StatsStore(),
         securityScope: SecurityScope = .system) {
        self.preferences = preferences
        self.workspaceStore = workspaceStore
        self.migration = migration
        self.securityScope = securityScope
        self.fogStore = fogStore
        self.statsStore = statsStore
        // No roster is read here. Until the DM picks a Workspace there is no roster to read —
        // which is the shape change this feature turns on, and the reason `partyStore` is a
        // `var` and an Optional. Tests that pass one in get a Workspace-less session with a
        // roster already wired, which is the old behaviour they were written against.
        if let partyStore {
            self.partyStore = partyStore
            partyBook = partyStore.load()
            partyLoadFailure = partyStore.lastLoadFailure
        }
        fogAutosave = FogAutosave { [weak self] document in
            self?.writeFog(document)
        }
        statsAutosave = StatsAutosave { [weak self] document in
            self?.writeStats(document)
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

    /// The value of a `--flag=value` launch argument, or nil when it was not passed.
    ///
    /// **The `=` is load-bearing, and it is why the UI suite runs at all.** The seams below
    /// were once spelled `--test-map <path>`, two arguments — and a bare argument, one that
    /// does not begin with `-`, is not a value as far as AppKit is concerned: it is a
    /// *document to open*. `NSApplication` takes the path, finds no handler for it, and the
    /// app finishes launching having opened nothing and shown nothing. No window, no crash,
    /// no log line. Every UI test then sat waiting five seconds for a control on a window
    /// that was never going to exist, which is the "MapForgeUITests hangs" this app carried
    /// for months.
    ///
    /// Keeping the value welded to its flag keeps every argument flag-shaped, so AppKit reads
    /// none of them as a document. Anything added here must keep that shape.
    static func launchArgumentValue(_ flag: String) -> String? {
        CommandLine.arguments
            .first { $0.hasPrefix("\(flag)=") }
            .map { String($0.dropFirst(flag.count + 1)) }
    }

    /// Test seam: UI tests load a map via `--test-map=<path> [--test-squares=N]`,
    /// bypassing the open panel (NSOpenPanel can't be driven from XCUITest), and pick
    /// the Player Display via `--test-player-screen`.
    /// Opens the Workspace a UI test asked for, so the picker sheet never blocks the suite.
    ///
    /// Two flags, because the tests split in two. `--test-workspace=<path>` names one, for the
    /// tests that exercise Workspaces themselves. `--test-fresh-preferences` — which already
    /// existed to keep a developer's remembered Player Display out of the suite — additionally
    /// adopts a throwaway Workspace in a temp directory, so the many tests that do not care
    /// about Workspaces simply never see the sheet.
    ///
    /// Neither may ever resolve to a folder the developer actually uses. A UI test that opened
    /// a real Workspace would edit a real roster.
    func openWorkspaceFromLaunchArgumentsIfPresent() {
        let args = CommandLine.arguments

        if let path = Self.launchArgumentValue("--test-workspace") {
            let url = URL(fileURLWithPath: path)
            if let workspace = try? WorkspaceStore().adopt(url) { open(workspace) }
            return
        }

        guard args.contains("--test-fresh-preferences") else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MapForgeUITests.\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let workspace = try? WorkspaceStore().adopt(url) { open(workspace) }
    }

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
        guard let path = Self.launchArgumentValue("--test-map") else { return }
        let url = URL(fileURLWithPath: path)
        guard let image = NSImage(contentsOf: url) else { return }
        loadMap(image: image, at: url)
        // After loadMap, which clears the declaration for the incoming Map: a test that
        // passes --test-squares has declared this Map's Grid.
        if let squares = Self.launchArgumentValue("--test-squares").flatMap(Double.init) {
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
        settings.playerDisplay = identity
        writeSettings()
        presentIfPossible()
    }

    var playerMetrics: DisplayMetrics? {
        playerScreen.flatMap { DisplayMetrics(screen: $0) }
    }

    var mapScale: MapScale? {
        mapImage.map { MapScale.grid(squaresWide: squaresWide, imagePixelSize: $0.pixelSize) }
    }

    func openMap() {
        guard let workspace else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.allowsMultipleSelection = false
        // Where the DM's Maps are: the open Map's own folder when it has one in this
        // Workspace, the Workspace otherwise.
        panel.directoryURL = mapURL.flatMap {
            workspace.contains($0) ? $0.deletingLastPathComponent() : nil
        } ?? workspace.url
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openMap(at: url)
    }

    /// Opens the Map the DM picked, if it is inside the open Workspace; says why not if it
    /// is not.
    ///
    /// A Map lives inside the Workspace (ADR-0026). Under the App Sandbox the Workspace's
    /// access is what lets the app write `<map>.fog.json` and `<map>.combat/` beside a Map,
    /// and an image picked from elsewhere would open with every one of those writes failing.
    func openMap(at url: URL) {
        guard let workspace else { return }
        guard workspace.contains(url) else {
            mapOutsideWorkspace = workspace
            return
        }
        guard let image = NSImage(contentsOf: url) else { return }
        loadMap(image: image, at: url)
    }

    /// Switch to a Map, bringing its fog with it. Any edit still sitting in the debounce
    /// belongs to the *outgoing* Map, so it is flushed before `mapURL` moves on.
    func loadMap(image: NSImage, at url: URL) {
        fogAutosave.flush()
        // The outgoing Map's numbers, before `mapURL` moves and `writeStats` would send
        // them to the new Map's folder. A fight left running is flushed, never stopped: a
        // DM closing one Map is taking a break, and inventing an end line would put a lie
        // in the Log.
        statsAutosave.flush()
        encounter = nil
        try? logWriter?.close()
        logWriter = nil
        // Explicitly, before the document changes underneath it. `fog`'s didSet would also
        // drop the ID, but only because Pawn IDs are UUIDs and the incoming Map's will not
        // match — an accident of uniqueness rather than a rule, and it says nothing about a
        // Map opened without a fog reassignment. The mode belongs to the Map it was set on.
        soloSightPawnID = nil
        // Same rule, same reason: a Measurement belongs to the Map it was taken on, and
        // its distance means something different under another Map's Grid.
        measurement = nil
        pinnedMeasurements = []
        // And the Selection, by the rule Solo Sight's line above states: what the DM picked
        // was picked on the outgoing Map.
        selection = Selection()
        mapURL = url
        mapImage = image
        viewportOrigin = nil
        var document = fogStore.load(forMapAt: url) ?? FogDocument()
        // A Pawn a previous version let out of the image comes back to its edge here, or
        // it stays unreachable for good — see `PawnBounds`.
        document.pawns = PawnBounds.clamped(document.pawns, toImage: image.pixelSize)
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
        // The new Map's combat state: what its Pawns are worth, and a fight if one was
        // still running when it was last closed.
        loadStats(forMapAt: url)
        resumeEncounter(forMapAt: url)
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

    private func writeStats(_ document: StatsDocument) {
        guard let url = mapURL else { return }
        // Refuse to write over a file we could not read, the rule `PartyStore`'s failure
        // already follows: a DM who reopens a Map, sees no hit points and retypes them
        // must not have the first save destroy the file that would have recovered them.
        guard statsLoadFailure == nil else { return }
        do {
            try statsStore.save(document, forMapAt: url)
        } catch {
            NSLog("MapForge: could not save stats for \(url.lastPathComponent): \(error)")
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
    /// the DM's authoring undo stack. It mutates no Pawn at all — the mode is derived.
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

    /// The Pawns and Lights the DM has picked in the Live View — see `Selection`.
    ///
    /// Live state beside Solo Sight and the Measurement, and on their terms: never persisted,
    /// never part of `FogEdits`, and a reference into `fog` that `fog` itself invalidates.
    /// Drawn on the Control Window only; nothing the Player Display reads looks at it.
    @Published private(set) var selection = Selection()

    /// ⇧-click on a Pawn with nothing armed. A Pawn not on this Map is refused rather than
    /// remembered: an ID that matches nothing is the stale reference `fog`'s `didSet`
    /// exists to prevent.
    func toggleSelection(pawn id: Pawn.ID) {
        guard fog.pawns.contains(where: { $0.id == id }) else { return }
        selection.toggle(pawn: id)
    }

    /// ⇧-click on a Light Marker with nothing armed, on the same terms as a Pawn's.
    func toggleSelection(light id: Light.ID) {
        guard fog.lights.contains(where: { $0.id == id }) else { return }
        selection.toggle(light: id)
    }

    /// End the Selection: Esc with nothing armed, or a plain click on the bare Map.
    func clearSelection() {
        guard !selection.isEmpty else { return }
        selection = Selection()
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
    /// Whether the Player Display draws the DM's Measurements.
    ///
    /// ADR-0005 put them there and argued it well: a Measurement answers a question the
    /// players are the ones asking, and one only the DM can see answers it for the person
    /// who could already estimate it. That holds for the Measurement taken *for* the table.
    ///
    /// It does not hold for the one a DM takes for themselves — how far the ogre reaches
    /// next turn, whether the ambush is in range — where the distance is precisely the
    /// tactical fact they are deciding whether to reveal. The ADR considered "DM-only" and
    /// rejected it as a global rule, which it still is; this makes it a per-moment choice
    /// instead, defaulting to shown so the ADR's case stays the one that needs no action.
    ///
    /// Live, like the Fog Overlay's switch beside it, and never persisted: it is a decision
    /// about the moment, not about the Map.
    @Published var showsMeasurementsToPlayers = true

    /// What the **Player Display** draws: the DM's Measurements, or none of them.
    ///
    /// Separate from `drawableMeasurements` rather than filtered at the view, so the two
    /// screens cannot drift — the same reason `PlayerVisibility.showsToPlayers` is one
    /// function (ADR-0004). Hiding is about what the table is shown; the DM keeps their own
    /// either way, because they asked the question and the answer is still theirs.
    var playerMeasurements: [(measurement: Measurement, origin: MapPoint)] {
        showsMeasurementsToPlayers ? drawableMeasurements : []
    }

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
    }

    /// Move a Pawn outside the fog editing mode — the live table action, since the party
    /// moves during play and not during prep.
    ///
    /// Held inside the image: a drag past the edge stops at the edge. See `PawnBounds` for
    /// why an off-Map Pawn is not just wrong but unreachable.
    func movePawn(id: Pawn.ID, to point: MapPoint) {
        guard let index = fog.pawns.firstIndex(where: { $0.id == id }) else { return }
        let destination = mapImage.map { PawnBounds.clamp(point, toImage: $0.pixelSize) } ?? point
        guard fog.pawns[index].at != destination else { return }
        fog.pawns[index].at = destination
    }

    /// Move the whole Selection: every member to where it stood as the drag began, plus
    /// `translation` in image pixels — the party walking down the corridor in formation.
    ///
    /// Held inside the image as a whole: the translation stops where the first member
    /// reaches the edge, and nobody is clamped on their own — see `SelectionMove.limited`.
    ///
    /// Live and not undoable, on `movePawn`'s terms. One write to `fog` for the lot, not one
    /// per member: each write runs `fog`'s `didSet` and publishes a change, and at drag rate
    /// a write per member is that work times the party.
    func moveSelection(_ move: SelectionMove, by translation: CGVector) {
        let translation = mapImage.map { move.limited(translation, toImage: $0.pixelSize) }
            ?? translation
        var document = fog
        var moved = false
        for member in move.pawns {
            guard let index = Self.index(of: member, in: document.pawns) else { continue }
            let destination = MapPoint(x: member.origin.x + translation.dx,
                                       y: member.origin.y + translation.dy)
            guard document.pawns[index].at != destination else { continue }
            document.pawns[index].at = destination
            moved = true
        }
        for member in move.lights {
            guard let index = Self.index(of: member, in: document.lights) else { continue }
            let destination = MapPoint(x: member.origin.x + translation.dx,
                                       y: member.origin.y + translation.dy)
            guard document.lights[index].at != destination else { continue }
            document.lights[index].at = destination
            moved = true
        }
        // Asked of the members rather than of the whole document, which `fog`'s `didSet`
        // compares again anyway: a frame that moved no one writes nothing.
        guard moved else { return }
        fog = document
    }

    /// Where `member` stands in `items` now: where it stood as the drag began, unless the
    /// document has changed under the drag, when it is searched for — and nil if it has
    /// gone, so a member deleted mid-drag is left out rather than another moved in its place.
    private static func index<Item: Identifiable>(of member: SelectionMove.Member<Item.ID>,
                                                  in items: [Item]) -> Int? {
        if items.indices.contains(member.index), items[member.index].id == member.id {
            return member.index
        }
        return items.firstIndex { $0.id == member.id }
    }

    /// Move a Light in the Live View — the DM carrying a lantern down a corridor, or nudging
    /// a brazier they placed a square out.
    ///
    /// Beside `movePawn` and on its terms: live, watched by the table as it happens because
    /// the Fog Overlay follows, and **not undoable**. Held inside the image for a sharper
    /// reason than a Pawn is — `LiveHitTest` only reaches what the DM can click, so a Light
    /// dragged past the edge could never be dragged back, edited or deleted (the rule
    /// `AddPlacement.light` already keeps).
    func moveLight(id: Light.ID, to point: MapPoint) {
        guard let index = fog.lights.firstIndex(where: { $0.id == id }) else { return }
        let destination = mapImage.map { PawnBounds.clamp(point, toImage: $0.pixelSize) } ?? point
        guard fog.lights[index].at != destination else { return }
        fog.lights[index].at = destination
    }

    /// A Light's drag has ended: on disk now, not after the debounce.
    ///
    /// Nothing else, unlike `commitPawnMove`. The Logs record what *happened* at the table,
    /// and they are about Pawns; a torch is the room, and where the DM stood it is prep even
    /// when it is done mid-evening.
    func commitLightMove() {
        flushPendingFogWrites()
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
    }

    /// Rename a Light outside the fog editing mode — "Light 3" becomes "trapped brazier"
    /// while the DM is looking at the roster, without entering authoring mode.
    ///
    /// Blank becomes nil, exactly as `FogEdits.setLightName` does: "unnamed" must have one
    /// representation, or the roster's fallback fires for `nil` and not for `""`. What is not
    /// blank is kept as typed — trimming every keystroke is what stops a DM typing a name with
    /// a space in it.
    func setLightName(id: Light.ID, _ name: String) {
        guard let index = fog.lights.firstIndex(where: { $0.id == id }) else { return }
        fog.lights[index].name =
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
    }

    // MARK: Editing in the Live View
    //
    // Adding, editing and deleting a Pawn or a Light, from the right-click menu and the Add
    // button — the only place any of it happens now (ADR-0013). All of it live, beside
    // `movePawn` and `stamp` rather than beside the Wall Editor's `FogEdits`: **not
    // undoable**, because a live performance action does not belong in an authoring undo
    // stack, and the sheets' Cancel is the escape instead.

    /// Apply the Edit Pawn sheet's fields. One write for the whole sheet, so a cancelled
    /// sheet leaves nothing behind.
    func updatePawn(id: Pawn.ID, with draft: EditPawnDraft) {
        guard let index = fog.pawns.firstIndex(where: { $0.id == id }) else { return }
        var edited = draft.applied(to: fog.pawns[index])
        // A Face cut in the sheet is kept only now, on OK, so Cancel leaves nothing in the
        // Workspace.
        edited.face = draft.face.resolved(keepingIn: faceLibrary)
        // "Every one": the definition's cut changes, and so does every Pawn on this Map that
        // took its Face from it — this one included, which keeps its source.
        if draft.recutsEvery, draft.asksWhomToRecut, let source = draft.recutSource,
           let square = draft.face.newCut?.cut, let file = edited.face?.file,
           file != draft.face.kept?.file {
            recutDefinition(source, square: square, file: file)
            fog.pawns[index] = edited
            fog.pawns = FaceRecut.recut(fog.pawns, from: source, to: file, reCutting: id)
            edited = fog.pawns[index]
        }
        // Becoming a Monster or an Item brings its Face, over any Face the old one gave —
        // unless the DM removed or cut one in this same sheet, which is what they meant.
        if !draft.face.isChanged {
            edited.face = definitionFace(over: edited.face, becoming: draft.monsterToStamp,
                                         or: draft.itemToBecome)
        }
        fog.pawns[index] = edited
        // The one thing this sheet does to a Stat Block: a Monster that *changed* is stamped,
        // whole (ADR-0021). Through `editStatBlock`, so mid-fight the stamp is recorded as
        // Changes like any other edit (ADR-0008); the rolled Initiative is not among them,
        // because changing a bonus does not by itself move anyone. A Monster that left the
        // Bestiary while the sheet was open stamps nothing, and the Pawn simply remembers
        // its name.
        if let monster = bestiary.monster(named: draft.monsterToStamp) {
            editStatBlock(for: id) { $0 = MonsterStamp.statBlock(from: monster, over: $0) }
            // OK commits both files, so neither waits out a debounce.
            flushPendingStatWrites()
        }
        // A Treasure has nothing to do on its turn (`CONTEXT.md`, **Combatant**), so a
        // Combatant edited into one leaves the Order — the same removal deleting it does.
        // The Log keeps naming it, which is the rule for any Pawn that stops being one.
        if fog.pawns[index].kind == .treasure {
            benchCombatant(id)
        }
        flushPendingFogWrites()
    }

    /// The picture `source`'s Face is cut from, and the square to start from — for cutting it
    /// again. Only for a Face cut from a note's picture, a Monster's, a Character's or an
    /// Item's: a Face cut by hand keeps no picture, so the DM chooses one again.
    ///
    /// The picture the note names **now** — never the one an older cut was made from, which
    /// the note may since have replaced. It starts from the square last cut when that square
    /// was cut from this very picture, and from the centred square otherwise.
    func recutPicture(for source: FaceSource) -> PendingFaceCut? {
        guard let workspace, let note = notePicture(of: source),
              let picture = FacePicture.load(workspace.url.appendingPathComponent(note.path))
        else { return nil }
        let square = note.cut?.picture == note.path
            ? note.cut!.square : FaceCut.centredSquare(in: picture.pixelSize)
        return PendingFaceCut(picture: picture, cut: square)
    }

    /// Whether `source`'s note names a picture the Workspace holds, so the Edit Pawn sheet can
    /// offer to cut it again — without reading the picture.
    func canRecut(_ source: FaceSource) -> Bool { notePicture(of: source) != nil }

    /// The picture `source`'s note names, and the cut last made for it — or nil when it names
    /// none, or for a Character with a Face of its own, which keeps no picture.
    private func notePicture(of source: FaceSource) -> (path: String, cut: NoteFaces.Cut?)? {
        switch source {
        case .monster(let name):
            guard let path = bestiary.monster(named: name)?.picture?.path else { return nil }
            return (path, noteFaces.monsters[name])
        case .character(let id):
            guard let character = character(id: id), character.face == nil,
                  let path = note(for: character)?.picture?.path else { return nil }
            return (path, noteFaces.characters[id.uuidString])
        case .item(let name):
            guard let path = treasury.item(named: name)?.picture?.path else { return nil }
            return (path, noteFaces.items[name])
        }
    }

    /// The name "every" is offered under — "Every Goblin", "Every Borsa" — or nil when the
    /// Monster, the Character or the Item has gone, and there is no definition left to re-cut.
    func recutName(for source: FaceSource?) -> String? {
        switch source {
        case .monster(let name): bestiary.monster(named: name)?.name
        case .character(let id): character(id: id)?.name
        case .item(let name): treasury.item(named: name)?.name
        case nil: nil
        }
    }

    /// Makes `file`, cut as `square`, the Face of `source` itself: the Monster's or the
    /// Item's cut of its picture, or the Character's own Face, which wins over its note's from
    /// then on. Pawns that take the Face afterwards take this one.
    private func recutDefinition(_ source: FaceSource, square: CGRect, file: String) {
        switch source {
        case .monster(let name):
            // The picture the note names now, which is the one just re-cut: a cut recorded
            // against an older picture would be cut afresh from the centre for the next Pawn.
            guard let path = bestiary.monster(named: name)?.picture?.path else { return }
            noteFaces.monsters[name] = NoteFaces.Cut(picture: path, square: square, file: file)
            saveNoteFaces()
        case .character(let id):
            guard var character = character(id: id) else { return }
            character.face = PawnFace(file: file, origin: .hand)
            updateCharacter(character)
        case .item(let name):
            // As a Monster's, against the picture the note names now.
            guard let path = treasury.item(named: name)?.picture?.path else { return }
            noteFaces.items[name] = NoteFaces.Cut(picture: path, square: square, file: file)
            saveNoteFaces()
        }
    }

    /// The Face a Pawn takes from `monster`: its picture's cut, made now if this is the first
    /// Pawn to take it since the note named that picture — or nil when its note names no
    /// picture the Workspace holds, or no Workspace is open. A new cut is written to disk at
    /// once, as a roster edit is: the next Pawn to take the Face must find it. A write that
    /// fails costs only sharing — the next app launch cuts the picture again, into a new file.
    func monsterFace(for monster: Monster) -> PawnFace? {
        keepingNoteFaces { faces, root, library in
            faces.face(for: monster, in: root, library: library)
        }
    }

    /// The Face a Treasure takes from `item`: its picture's cut, made now if this is the first
    /// Treasure to take it since the note named that picture — or nil when its note names no
    /// picture the Workspace holds, or no Workspace is open. Kept at once, as a Monster's is.
    func itemFace(for item: Item) -> PawnFace? {
        keepingNoteFaces { faces, root, library in
            faces.face(for: item, in: root, library: library)
        }
    }

    /// The Face a Pawn wearing `current` has on becoming the Monster named `monster` or the
    /// Item named `item`: the definition's Face, by `DefinitionStamp`'s rule (ADR-0028,
    /// ADR-0031). `current` itself when neither names one the notes still define.
    func definitionFace(over current: PawnFace?, becoming monster: String?,
                        or item: String?) -> PawnFace? {
        var face = current
        if let monster = bestiary.monster(named: monster) {
            face = DefinitionStamp.face(over: face, from: monsterFace(for: monster))
        }
        if let item = treasury.item(named: item) {
            face = DefinitionStamp.face(over: face, from: itemFace(for: item))
        }
        return face
    }

    /// `body`'s Face from `noteFaces`, written to disk if it made a cut — or nil with no
    /// Workspace open, when there is nowhere to keep one.
    private func keepingNoteFaces(
        _ body: (inout NoteFaces, URL, FaceLibrary) -> PawnFace?
    ) -> PawnFace? {
        guard let workspace, let faceLibrary else { return nil }
        let before = noteFaces
        let face = body(&noteFaces, workspace.url, faceLibrary)
        if noteFaces != before { saveNoteFaces() }
        return face
    }

    private func saveNoteFaces() {
        do {
            try noteFacesStore?.save(noteFaces)
        } catch {
            NSLog("MapForge: could not save the notes' cuts: \(error)")
        }
    }

    /// Apply the Edit Light sheet's fields.
    func updateLight(id: Light.ID, with draft: EditLightDraft) {
        guard let index = fog.lights.firstIndex(where: { $0.id == id }) else { return }
        fog.lights[index] = draft.applied(to: fog.lights[index])
        flushPendingFogWrites()
    }

    /// Place a new Light. The only way one is created — there is no roster to stamp from,
    /// the way a Pawn has.
    func addLight(_ light: Light) {
        fog.lights.append(light)
        flushPendingFogWrites()
    }

    /// Delete a Light. No confirmation: a live action the DM can simply repeat.
    ///
    /// The one thing that holds a `Light.ID` is the Selection, and `fog`'s `didSet` takes a
    /// deleted Light out of it as it takes a deleted Pawn out of Solo Sight — so there is
    /// nothing to invalidate here. `litRegions` recomputes from `fog`, and the roster row
    /// goes with the Light.
    func removeLight(id: Light.ID) {
        guard fog.lights.contains(where: { $0.id == id }) else { return }
        fog.lights.removeAll { $0.id == id }
        flushPendingFogWrites()
    }

    // MARK: The Party

    /// Stamp a Character onto the Map at a drop point on the mirror.
    ///
    /// A **live** action, beside `movePawn` and not beside `FogEdits.addPawn`: placing the
    /// party is what a DM does at the table when the session starts, not while authoring fog.
    /// Gating it behind the editing mode would have replaced one ritual with another, which
    /// is the whole complaint the feature answers. Not undoable, for the same reason a move
    /// is not. See ADR 0007.
    ///
    /// Returns whether anything was placed, so the drop can report a miss to SwiftUI.
    @discardableResult
    func stamp(_ character: PartyCharacter, at droppedPoint: CGPoint, frame: CGRect) -> Bool {
        let note = note(for: character)
        guard let map = mapScale,
              let pawn = Stamp.pawn(from: character, note: note,
                                    noteFace: noteFace(for: character),
                                    droppedAt: droppedPoint,
                                    map: map, frame: frame) else { return false }
        // The combat numbers its note gives, copied at drag time like every other field —
        // ADR-0007's rule reaching more of them (ADR-0024). Before `addPawnToMap`, because
        // joining a running fight reads the Stat Block to snapshot it into the Log. A
        // Character with no note the app could read stamps none.
        if let block = Stamp.statBlock(from: note) {
            setStatBlock(block, for: pawn.id)
        }
        // Through `addPawnToMap` rather than appending here, so a Character Stamped while
        // a fight is running rolls Initiative and joins the Order. It also flushes: a drop
        // is one completed action, not a stream of positions, and should be on disk before
        // the DM's next click, exactly as the end of a drag is.
        addPawnToMap(pawn)
        return true
    }

    /// The note a Character reads its numbers from, when the DM has said which and the
    /// Workspace's notes still hold one of that name.
    func note(for character: PartyCharacter) -> CharacterNote? {
        characterNotes.note(named: character.noteName)
    }

    /// The Pawn `character` would Stamp, for drawing it in the Party panel and under the
    /// cursor. Drawn with its note's Face only once that is cut — when the notes are read, or
    /// the Character is saved — because this is asked while SwiftUI draws, and drawing must
    /// not read a picture or write a file.
    func stampPreview(of character: PartyCharacter) -> Pawn {
        let kept = character.face == nil
            ? note(for: character).flatMap { note in
                faceLibrary.flatMap { noteFaces.keptFace(for: character, note: note, library: $0) }
            }
            : nil
        return Stamp.preview(of: character, note: note(for: character), noteFace: kept)
    }

    /// The cut of the picture `character`'s note names, made now if there is none — or nil
    /// when the Character has a Face of its own, which `Stamp` prefers and so needs no cut,
    /// or its note names no picture the Workspace holds.
    func noteFace(for character: PartyCharacter) -> PawnFace? {
        guard character.face == nil, let note = note(for: character) else { return nil }
        return keepingNoteFaces { faces, root, library in
            faces.face(for: character, note: note, in: root, library: library)
        }
    }

    /// Cuts every Character's note's picture not cut yet, so the Party panel can draw each
    /// with its Face. After the notes are read, and after a Character is saved.
    private func cutNoteFaces() {
        for character in partyBook.parties.flatMap(\.characters) {
            _ = noteFace(for: character)
        }
    }

    /// The page the Combat tab shows for a Pawn Stamped from a Character.
    ///
    /// Looked up live, each time it is drawn, through the Pawn's `characterID` and the
    /// Character's note (ADR-0007, amended) — never from a name copied at the Stamp, so a
    /// Character the DM links tonight reaches the Pawns already on tonight's Map.
    func characterPage(for pawn: Pawn) -> CharacterPage? {
        guard let id = pawn.characterID, let character = character(id: id) else { return nil }
        guard let noteName = character.noteName else {
            return .unlinked(characterName: character.name)
        }
        if let note = characterNotes.note(named: noteName) { return .note(note) }
        if let unavailable = bestiary.unavailable { return .unavailable(unavailable) }
        return .missing(noteName: noteName)
    }

    /// The note the Roll sheet offers `pawn`'s Modifier from (ADR-0029): a Player's Character's,
    /// reached the way `characterPage(for:)` reaches it, or a Creature's Monster's, reached the
    /// way the Combat tab's Monster page reaches it — both live, so a note edited since the
    /// Stamp is the one offered.
    ///
    /// By the Pawn's kind first, because each link outlives the kind it was made for: a Stamped
    /// Pawn the DM made a Creature keeps its `characterID`, and its hero's saves are not its
    /// own. Nil for a Treasure, which has no numbers, and for any Pawn whose note is not read.
    func modifierSource(for pawn: Pawn) -> ModifierSource? {
        switch pawn.kind {
        case .player:
            guard case .note(let note) = characterPage(for: pawn) else { return nil }
            return ModifierSource(note: note)
        case .creature:
            return bestiary.monster(named: pawn.monsterName).map(ModifierSource.init(monster:))
        case .treasure:
            return nil
        }
    }

    /// Whether the roster should say a Character has no note. Not while the notes are still
    /// being read — every Character would flash "no note" each time the Workspace opens —
    /// and the Bestiary is the read's progress, the two coming from one walk.
    func isUnlinked(_ character: PartyCharacter) -> Bool {
        bestiary != .reading && note(for: character) == nil
    }

    /// A Party drag landing on the Map: the pasteboard's payload, resolved and Stamped.
    ///
    /// The Map's `.dropDestination` calls this and nothing else. It is a method rather than
    /// three lines in the view because those three lines were once deleted along with the
    /// view they sat in (`9767de0`, when the cropped mirror went), and the Party could not be
    /// placed for weeks while every test of `stamp` stayed green. A drop handler cannot be
    /// unit-tested; what it *does* can, so as much of it as possible is here.
    ///
    /// `location` and `frame` must share a coordinate space — see `Stamp.pawn`.
    @discardableResult
    func stampDropped(_ payloads: [CharacterDragPayload], at location: CGPoint,
                      frame: CGRect) -> Bool {
        guard let payload = payloads.first,
              let character = character(id: payload.characterID) else { return false }
        return stamp(character, at: location, frame: frame)
    }

    /// The Character a drag is carrying. Searched across every Party, not just the active
    /// one: a drag that began before the DM switched Party is still a drag of a real
    /// Character, and refusing it would be a puzzle rather than a rule.
    func character(id: UUID) -> PartyCharacter? {
        partyBook.parties.lazy.compactMap { party in
            party.characters.first { $0.id == id }
        }.first
    }

    // MARK: - The Interface Language

    /// The language chosen in Settings. It takes effect at the next launch — see
    /// `InterfaceLanguage.nextLaunch`.
    var interfaceLanguage: InterfaceLanguage {
        get { preferences.interfaceLanguage }
        set {
            preferences.interfaceLanguage = newValue
            objectWillChange.send()
        }
    }

    // MARK: - The Distance Unit

    /// The unit the table speaks distances in, chosen in Settings (ADR-0027).
    ///
    /// Live, unlike the Interface Language: every distance is stored in Grid squares and only
    /// formatted when drawn, so a switch re-reads them all on both screens at once —
    /// Measurements, Pinned ones and Log Lines alike — and records nothing.
    var distanceUnit: DistanceUnit {
        get { preferences.distanceUnit }
        set {
            preferences.distanceUnit = newValue
            objectWillChange.send()
        }
    }

    /// The unit to offer a one-click switch to, or nil when there is nothing to offer.
    ///
    /// Offered only when every note in the Workspace that names a unit — Monsters' and
    /// Characters' alike — names this one, and it is not the one in force (ADR-0027). With the
    /// notes mixed, switching would fix nothing, and the caption's list is the useful part.
    var suggestedDistanceUnit: DistanceUnit? {
        let units = bestiary.monsters.map(\.distanceUnits) + characterNotes.notes.map(\.distanceUnits)
        return DistanceUnit.agreed(by: units).flatMap { $0 == distanceUnit ? nil : $0 }
    }

    // MARK: - The Workspace

    /// The Workspaces this Mac has opened, for the picker.
    var recentWorkspaces: [URL] { preferences.recentWorkspaces }

    /// Forget a recent Workspace. The DM's gesture — the app never prunes the list itself.
    func forgetWorkspace(_ url: URL) {
        preferences.forgetWorkspace(url)
        objectWillChange.send()
    }

    /// Whether a recent Workspace can be opened: its folder can be reached, and is still a
    /// Workspace.
    ///
    /// The check is made under the folder's own access. Under the sandbox a path the app holds
    /// no grant for reads as missing, so a check made without it would mark every recent
    /// unavailable.
    func isRecentWorkspaceAvailable(_ url: URL) -> Bool {
        guard let located = preferences.locateWorkspace(url) else { return false }
        return withAccess(to: located) { workspaceStore.isWorkspace(located) }
    }

    /// Opens a recent Workspace through its bookmark, wherever its folder now is.
    func openRecentWorkspace(_ url: URL) -> Result<Workspace, WorkspaceStore.OpenFailure> {
        guard let located = preferences.locateWorkspace(url) else {
            return .failure(.unreachable(Workspace(url: url).url))
        }
        let result = withAccess(to: located) { workspaceStore.open(located) }
        if case .success(let workspace) = result {
            open(workspace, reachedThrough: located, replacing: url)
        }
        return result
    }

    /// Runs `body` with access to `url`, given back as soon as it returns.
    private func withAccess<T>(to url: URL, _ body: () -> T) -> T {
        let started = securityScope.start(url)
        defer { if started { securityScope.stop(url) } }
        return body()
    }

    /// Gives back the access the last Workspace held and takes it for `url`.
    private func holdAccess(to url: URL?) {
        if let heldAccess { securityScope.stop(heldAccess) }
        heldAccess = url.flatMap { securityScope.start($0) ? $0 : nil }
    }

    /// Whether switching Workspaces would end a fight in progress. The picker asks first when
    /// it would: switching is a navigation gesture, and the DM making it is not thinking about
    /// the Encounter.
    /// Also true of a Session: its file lives in the Workspace it started in, so switching
    /// ends the evening as surely as it ends a fight.
    var switchingWouldEndAnEncounter: Bool { encounter != nil || session != nil }


    /// Opens a Workspace: its roster, its settings, and the recents list.
    ///
    /// Everything read here was read at `init` before this feature, which is why it is a
    /// method at all — the DM picks the folder after the window is on screen.
    ///
    /// `url` is the URL the folder was handed over by — the open panel's, or a resolved
    /// bookmark's — and `previous` the recents entry it was opened from; see
    /// `DisplayPreferences.noteWorkspaceOpened`.
    func open(_ workspace: Workspace, reachedThrough url: URL? = nil, replacing previous: URL? = nil) {
        // Switching comes through here rather than through `closeWorkspace`, so the running
        // evening is ended here too: its file lives in the Workspace it started in, and a
        // writer left open would append the next Workspace's lines to the last one's file.
        stopSession()
        // After the Session's last line, which is written into the outgoing Workspace.
        holdAccess(to: url ?? workspace.url)
        faceLibrary = FaceLibrary(directory: workspace.facesDirectory)
        noteFacesStore = NoteFacesStore(directory: workspace.supportDirectory)
        noteFaces = noteFacesStore?.load() ?? NoteFaces()
        self.workspace = workspace
        readBestiary(of: workspace)

        let store = PartyStore(directory: workspace.supportDirectory)
        partyStore = store
        partyBook = store.load()
        // Set from *this* Workspace every time, failure or not. Before Workspaces the latch
        // was set once at init and never cleared, which was safe when a process saw exactly
        // one roster; now a process sees several, and a failure carried in from a previous
        // Workspace would silently suppress writes in a healthy one. See issue 05.
        partyLoadFailure = store.lastLoadFailure

        let preferencesStore = WorkspacePreferencesStore(directory: workspace.supportDirectory)
        workspacePreferences = preferencesStore
        settings = preferencesStore.load()
        activePartyID = settings.activePartyID
        chosenDisplay = nil

        preferences.noteWorkspaceOpened(workspace, reachedThrough: url, replacing: previous)
        // An evening that was running when the app last quit is still running.
        resumeSession(in: workspace)
        migration?.runIfNeeded(into: workspace) { [weak self] outcome in
            self?.migrationOutcome = outcome
            if case .migrated = outcome { self?.reloadRosterAfterMigration() }
        }
        presentIfPossible()
    }

    /// Closes the open Workspace, leaving the app alive with no roster — the state it launches
    /// in. Switching Workspaces goes through here so nothing from the old one leaks into the
    /// new one.
    func closeWorkspace() {
        // Ended on the record rather than abandoned: a Session's file lives in the Workspace
        // it started in, and one that outlived its folder would write into the wrong one.
        stopSession()
        holdAccess(to: nil)
        faceLibrary = nil
        noteFacesStore = nil
        noteFaces = NoteFaces()
        workspace = nil
        bestiaryLoad?.cancel()
        bestiaryLoad = nil
        bestiary = .closed
        characterNotes = CharacterNotes()
        treasury = .closed
        partyStore = nil
        workspacePreferences = nil
        partyBook = PartyBook()
        partyLoadFailure = nil
        activePartyID = nil
        settings = WorkspaceSettings()
        chosenDisplay = nil
        playerWindow.hide()
        playerScreen = nil
    }

    /// Reads the Workspace's Monsters, Characters' notes and Items, off the main thread.
    ///
    /// The one moment the DM's notes are read (ADR-0020): no rescan, no watching. Off the
    /// main thread because it is a walk over a folder of the DM's choosing, and a vault is
    /// not a size the app controls; the search box says "Reading…" until it lands. A read
    /// that finishes after the DM has switched Workspace is dropped rather than shown.
    private func readBestiary(of workspace: Workspace) {
        bestiaryLoad?.cancel()
        bestiary = .reading
        characterNotes = CharacterNotes()
        treasury = .reading
        bestiaryLoad = Task { [weak self] in
            let read = await Task.detached(priority: .userInitiated) {
                BestiaryStore.read(workspace)
            }.value
            guard let self, !Task.isCancelled, self.workspace == workspace else { return }
            self.bestiary = read.bestiary
            self.characterNotes = read.characters
            self.treasury = read.treasury
            self.cutNoteFaces()
        }
    }

    /// Re-reads the roster after a migration wrote one into a Workspace that had none.
    private func reloadRosterAfterMigration() {
        guard let partyStore else { return }
        partyBook = partyStore.load()
        partyLoadFailure = partyStore.lastLoadFailure
        settings = workspacePreferences?.load() ?? settings
        activePartyID = settings.activePartyID
    }

    private func writeSettings() {
        workspacePreferences?.save(settings)
    }

    /// Moves a damaged `parties.json` aside so the DM can work again.
    ///
    /// The only recovery offered, and the DM's to choose. While `partyLoadFailure` is set the
    /// app refuses to write the roster at all — the right rule, since the alternative is a DM
    /// retyping their party over the file that could have been recovered — but it leaves them
    /// with a roster they cannot edit and no way forward. This is the way forward: the bytes
    /// are renamed, never deleted, and an empty roster takes their place.
    func setAsideDamagedRoster() {
        guard let failure = partyLoadFailure else { return }
        let aside = failure.url.appendingPathExtension("damaged")
        try? FileManager.default.removeItem(at: aside)
        do {
            try FileManager.default.moveItem(at: failure.url, to: aside)
        } catch {
            NSLog("MapForge: could not set aside the damaged roster: \(error)")
            return
        }
        partyLoadFailure = nil
        partyBook = PartyBook()
        activePartyID = nil
        settings.activePartyID = nil
        writeSettings()
    }

    /// How many of this Character's Pawns stand on the Map being run.
    func placedCount(of character: PartyCharacter) -> Int {
        PartyRoster.placedCount(of: character, among: fog.pawns)
    }

    func addParty(named name: String) {
        let (book, party) = PartyRoster.addParty(named: name, to: partyBook)
        partyBook = book
        // A Party created mid-session is the one the DM wants to use.
        setActiveParty(party.id)
        writeParties()
    }

    func renameParty(id: UUID, to name: String) {
        partyBook = PartyRoster.renameParty(id: id, to: name, in: partyBook)
        writeParties()
    }

    /// Delete a Party. Pawns Stamped from its Characters stay on their Maps: they hold their
    /// own label, colour and sight and know nothing about the roster.
    func deleteParty(id: UUID) {
        partyBook = PartyRoster.deleteParty(id: id, from: partyBook)
        if activePartyID == id { setActiveParty(partyBook.parties.first?.id) }
        writeParties()
    }

    func setActiveParty(_ id: UUID?) {
        activePartyID = id
        settings.activePartyID = id
        writeSettings()
    }

    /// Add a Character to the active Party. `face`, when the editor gave one, is what the
    /// Character wears: a cut made there is kept in the Workspace only now, on Save, so
    /// Cancel leaves nothing behind.
    func addCharacter(_ character: PartyCharacter, face: FaceDraft? = nil) {
        guard let partyID = activeParty?.id else { return }
        partyBook = PartyRoster.addCharacter(self.character(character, wearing: face),
                                             toPartyWith: partyID, in: partyBook)
        writeParties()
        cutNoteFaces()
    }

    /// Edit a Character in place. Pawns already Stamped from it are deliberately untouched:
    /// a Stamp is a copy taken at the drag, so renaming Thorin today, or giving him another
    /// Face, leaves last week's map exactly as it was run.
    func updateCharacter(_ character: PartyCharacter, face: FaceDraft? = nil) {
        partyBook = PartyRoster.updateCharacter(self.character(character, wearing: face),
                                                in: partyBook)
        writeParties()
        cutNoteFaces()
    }

    /// `character` with the Face its editor left, kept now if it was cut there.
    private func character(_ character: PartyCharacter, wearing face: FaceDraft?) -> PartyCharacter {
        guard let face else { return character }
        var character = character
        character.face = face.resolved(keepingIn: faceLibrary)
        return character
    }

    /// Delete a Character. Its Pawns stay on their Maps, fully functional; they only stop
    /// being counted.
    func deleteCharacter(id: UUID) {
        partyBook = PartyRoster.deleteCharacter(id: id, in: partyBook)
        writeParties()
    }

    private func writeParties() {
        // Never write over a roster we could not read. This is the rule `FogStore` enforces
        // by refusing to overwrite the bytes it failed to parse; here the refusal has to be
        // at the write, because an unreadable roster still leaves the app running with an
        // empty one that the DM may start typing into.
        guard partyLoadFailure == nil, let partyStore else { return }
        do {
            try partyStore.save(partyBook)
        } catch {
            // Non-fatal and deliberately quiet: the roster is a convenience, and a failed
            // write must not interrupt a session in progress. The in-memory book is still
            // correct for as long as the app runs.
            NSLog("MapForge: could not save parties: \(error)")
        }
    }

    /// Push the fog authored inside the editing mode onto the Map.
    ///
    /// Take the Walls the mode has traced, and only those.
    ///
    /// The mode's document is a snapshot taken when it opened, so assigning it back reverts
    /// everything the table changed underneath it. Walls are the only thing the Wall Editor
    /// authors (ADR-0013), so they are the only thing taken from it — the Grid, every Pawn
    /// and every Light stay as `fog` currently has them.
    ///
    /// This replaces `carryLiveState`, which pulled the live values back out of `fog` and
    /// wrote them over the snapshot, property by property, driven by a record of what the
    /// table had touched. Copying one field in the other direction needs no such record and
    /// cannot miss a property: a Light rename, which `carryLiveState` never covered because
    /// it was Pawn-shaped throughout, now survives for free. `WallEditorTests` holds it.
    func applyFogEdits(_ edits: FogEdits) {
        // The mode's document belongs to the Map it opened on. If another Map has been
        // opened since, these are the outgoing Map's Walls and applying them would
        // overwrite the incoming Map's — on screen and, through the autosave, on its file.
        guard isFogEditingCurrentMap else { return }
        fog.walls = edits.document.walls
    }

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
        fogEditingMapURL = mapURL
        // Fog authoring needs the whole Map lit, and an isolated view would fight the
        // inspector it is being authored through.
        soloSightPawnID = nil
        // Measuring is a play action, and the authoring preview is a different surface
        // with a different transform — a Measurement left on it would be drawn wrong.
        measurement = nil
        pinnedMeasurements = []
        // Nothing can be picked in the Wall Editor, so nothing stays picked into it: rings on
        // tokens the DM cannot move there would promise a drag the mode does not have.
        selection = Selection()
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
        // The Walls the mode traced go back to what it opened with; nothing else is
        // touched, for the same reason `applyFogEdits` takes nothing else. A Pawn dragged
        // mid-fight cannot snap back on Cancel because Cancel never had a Pawn to restore.
        fog.walls = edits.original.walls
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
        // The Map's other file. A hit point typed in the last half-second is sitting in
        // the same kind of debounce, and quitting is exactly when it would be lost.
        statsAutosave.flush()
    }

    /// Resolve the Player Display through the policy and present there. With two or more
    /// unrecognised screens nothing is presented — the picker waits for a choice.
    func presentIfPossible() {
        guard mapImage != nil,
              let chosen = PlayerScreenPolicy.resolve(candidates: displayCandidates,
                                                      explicit: chosenDisplay,
                                                      remembered: settings.playerDisplay),
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
