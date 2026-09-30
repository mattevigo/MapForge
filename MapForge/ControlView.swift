import SwiftUI

struct ControlView: View {
    @EnvironmentObject private var appState: AppState

    @State private var mode: PreviewMode = .normal
    /// What the DM has typed into the Comment Bar and not yet sent. View-local: an unsent
    /// Comment is a half-finished thought, not part of the evening's record.
    @State private var comment = ""
    /// The Pawn or Light being edited in a sheet, or nil when none is.
    ///
    /// One optional rather than two, because at most one sheet is ever up: the DM reached it
    /// from one right-click on one thing.
    @State private var editing: EditTarget?

    /// The Pawn a Roll is being recorded for, or nil when the sheet is closed. Separate from
    /// `editing` because a Roll is not an edit: it writes to a Log and changes nothing.
    @State private var rolling: RollTarget?

    @State private var fitSquare: GridFitSquare?
    @State private var squaresWideBeforeFit: Double = 0
    /// Whether the Grid was already declared when Grid Fit started. Entering Grid Fit
    /// declares one as a side effect of moving the value, so cancelling has to put back
    /// the claim as well as the number.
    @State private var hadDeclaredGridBeforeFit = false
    /// Whether the Viewport rectangle is showing on the Live View. A toggle, not a mode —
    /// see `ViewportToggle`.
    @State private var isShowingViewport = false
    /// The fog as it was on entering the mode, so Cancel restores it wholesale — the
    /// same revert Grid Fit does with `squaresWideBeforeFit`. `FogEdits` also carries the
    /// undo history, which is mode-local and cannot unwind past this.
    @State private var fogEdits = FogEdits(document: FogDocument())
    /// Which shape the last Measurement took, so the right-click menu opens on it.
    /// Session-local, like the Measurement itself.
    @State private var measurementShape: MeasurementShape = .circle
    /// The shape picked from the right-click menu, waiting for a left-click to say where
    /// it starts. Nil except between those two moments.
    ///
    /// The menu chooses *what* to measure; the click that follows chooses *where*. Taking
    /// the Origin from the right-click itself conflated the two, so the DM had to open the
    /// menu at exactly the point they meant to measure from — a menu is not a precise
    /// instrument.
    /// The Magnifier: the Control Window's zoom and pan. Nil is the plain aspect fit, so the
    /// DM sees the whole Map until they ask for more.
    ///
    /// **One for every mode.** The Live View, the Wall Editor and Grid Fit each used to
    /// carry their own, and the authoring modes reset theirs to the whole Map on entry, so a
    /// DM who zoomed into a room to trace its Walls lost the room the moment they pressed
    /// Edit Fog. Now the DM chooses a magnification once and every mode shows it. Only
    /// opening a different Map, or zooming back out to the floor, ends it — not arming the
    /// Viewport, not a Cancel, not a new Grid: where the DM was looking is not an edit.
    /// Never reaches the Player Display, which is what makes it the DM's alone.
    @State private var magnifier: PreviewTransform?
    /// The transform an ⌥-drag started from. `DragGesture` reports cumulative translation,
    /// so panning from the live value would compound it — the same reason
    /// `GridFitOverlay` and `FogOverlay` each hold one.
    @State private var livePanStart: PreviewTransform?
    /// The transform a middle-button drag started from, for the same reason. One for all
    /// three modes: that drag is attached to the preview itself, not to a mode's overlay.
    @State private var middlePanStart: PreviewTransform?
    /// The transform a pinch started from: `MagnifyGesture` reports cumulative
    /// magnification, so compounding it against the live scale would accelerate. Attached
    /// to the preview, like the middle-button drag, so every mode pinches the same way.
    @State private var pinchStart: PreviewTransform?
    @State private var armedShape: MeasurementShape?
    /// What `Add` is waiting to place, or nil when nothing is armed.
    ///
    /// Beside `armedShape` and mutually exclusive with it: at most one tool is armed at a
    /// time, because a left-click whose meaning depends on which of two armed tools wins is
    /// unguessable. `arm(_:)` and `startMeasurement` each clear the other.
    @State private var armedAdd: AddKind?
    /// Where the cursor last was on the mirror, in the mirror's own coordinates.
    ///
    /// SwiftUI reports this; an `NSEvent`'s `locationInWindow` is NOT convertible into it.
    /// `.global` is neither the window's nor the content view's space — measured on a
    /// plain window, a `GeometryReader` under 80pt of chrome reports its origin at y=120
    /// and its height 88pt short, so converting an AppKit point through the content view
    /// lands hundreds of points out. Right-click therefore reads the *hovered* point
    /// rather than the event's, which is the only figure in the right space.
    @State private var mirrorCursor: CGPoint?
    /// Digits typed towards an exact distance. Empty except between the first digit and
    /// Return, which is also the only window in which the key monitor claims anything.
    @State private var typedDistance = MeasurementTyping.Buffer()
    /// The Character being authored or edited in the Party panel, if any. One at a time: the
    /// panel is 236pt wide and two open editors would leave no room for the roster itself.
    @State private var editedCharacter: PartyCharacter?
    /// Whether `editedCharacter` is new, so Cancel knows whether to leave anything behind.
    @State private var isAddingCharacter = false
    /// The Party being renamed, or created, in the picker's sheet-free inline field.
    @State private var partyNameEdit: PartyNameEdit?

    /// Which half of the live panel is showing. Starts on Scene every launch — see
    /// `PanelTab`.
    @State private var panelTab: PanelTab = .scene

    /// Whether the Log View has the Map's place.
    ///
    /// Its own state rather than a fourth `PreviewMode`: nothing about reading the evening is
    /// exclusive with having Grid Fit armed, and a mode case would grow a branch saying "not
    /// applicable" in every `switch` over the mode in this file. The Viewport set this
    /// precedent — a toggle, not a mode.
    @State private var showingLog = false

    /// The evening as rows, rebuilt on every append. Empty until the Log View is opened.
    @State private var logRows: [LogRow] = []

    /// Held rather than built per reload: its readers are injection points, so a caller that
    /// wants one reader for the session's life can have one.
    @State private var logModel = LogViewModel()

    /// Which row the Combat tab's Stat Block editor is pointed at.
    @State private var selectedCombatant: Pawn.ID?

    /// What `Add` places. A Light, or a Pawn of one Kind — the Kind is settled here, when
    /// the DM picks from the menu, rather than in a sheet afterwards: adding four goblins is
    /// four arms and no forms.
    private enum AddKind: Hashable, CaseIterable {
        case light
        case pawn(PawnKind)

        static var allCases: [AddKind] { [.light] + PawnKind.allCases.map(AddKind.pawn) }

        var title: String {
            switch self {
            case .light: String(localized: "Light")
            case .pawn(let kind): kind.title
            }
        }
    }

    /// What an open Edit sheet is pointed at, with the draft it is editing.
    ///
    /// Carries the draft rather than re-seeding from `appState` on each redraw: the sheet
    /// buffers, so the half-typed state has to live somewhere that a redraw does not reset.
    private enum EditTarget: Equatable, Identifiable {
        case pawn(Pawn.ID, EditPawnDraft)
        case light(Light.ID, EditLightDraft)

        var id: UUID {
            switch self {
            case .pawn(let id, _): id
            case .light(let id, _): id
            }
        }
    }

    /// Which Pawn is rolling, and which of the two Rolls it is.
    ///
    /// Carries the Pawn whole rather than its id: the recorder snapshots the label, and a
    /// Pawn deleted while the sheet is open should still record under the name it had.
    private struct RollTarget: Identifiable {
        let pawn: Pawn
        let kind: RollKind

        /// The Pawn *and* the kind. `.sheet(item:)` re-presents only when the id changes,
        /// and `RollSheet`'s draft is `@State` — so an id of the Pawn alone would let a DM
        /// who asks for an Ability Check right after a Saving Throw on the same Pawn get
        /// the sheet they just closed.
        struct ID: Hashable {
            let pawn: UUID
            let kind: RollKind
        }

        var id: ID { ID(pawn: pawn.id, kind: kind) }
    }

    /// Renaming an existing Party, or naming a new one. A sum type rather than a name plus a
    /// flag, because the two resolve differently and only one of them has an id.
    private enum PartyNameEdit: Equatable {
        case new(String)
        case rename(id: UUID, name: String)

        var name: String {
            switch self {
            case .new(let name): return name
            case .rename(_, let name): return name
            }
        }

        func withName(_ name: String) -> PartyNameEdit {
            switch self {
            case .new: return .new(name)
            case .rename(let id, _): return .rename(id: id, name: name)
            }
        }
    }

    /// Shown whenever there is no Workspace open — which is every launch until the DM picks
    /// one — and on demand when they switch.
    @State private var isPickingWorkspace = false
    /// Set when switching would end a fight, so the DM is asked before it does.
    @State private var confirmSwitchEndsEncounter = false
    /// Set when the DM asks to end the evening, so they are asked before it ends.
    @State private var confirmStopSession = false
    /// Set when the DM asks to set a damaged roster aside and start fresh.
    @State private var confirmNewRoster = false

    private var endEncounterMessage: String {
        guard let map = appState.mapURL?.lastPathComponent else {
            return String(localized: "An Encounter is running. Switching Workspaces will end it. The Combat Log is kept.")
        }
        return String(localized: "An Encounter is running on \(map). Switching Workspaces will end it. The Combat Log is kept.")
    }

    private var stopSessionMessage: String {
        StopSessionPrompt.message(hasEncounter: appState.encounter != nil,
                                  map: appState.mapURL?.lastPathComponent)
    }

    private var migrationTitle: String {
        if case .migrated = appState.migrationOutcome {
            return String(localized: "Your Parties have moved")
        }
        return String(localized: "Couldn't move your Parties")
    }

    private var migrationMessage: String {
        switch appState.migrationOutcome {
        case .migrated(let names, let workspace):
            // Name the destination *and* state the new rule. The second sentence is the one
            // doing the work: a DM who later opens a second workspace and finds no cast must
            // not conclude the app ate it.
            let quoted = names.map { "\u{201C}\($0)\u{201D}" }
            let list = ListFormatter().string(from: quoted) ?? quoted.joined(separator: ", ")
            return names.count == 1
                ? String(localized: "\(list) is now stored in this Workspace, in \u{201C}\(workspace)\u{201D}. Parties live in a Workspace now rather than on this Mac, so another Workspace starts with an empty roster.")
                : String(localized: "\(list) are now stored in this Workspace, in \u{201C}\(workspace)\u{201D}. Parties live in a Workspace now rather than on this Mac, so another Workspace starts with an empty roster.")
        case .failed(let reason):
            return String(localized: "Your existing Parties are still stored on this Mac and weren't changed. MapForge will try again next time you open a Workspace.\n\n\(reason)")
        case .none:
            return ""
        }
    }

    private var workspaceButton: some View {

        Button {
            if appState.switchingWouldEndAnEncounter {
                confirmSwitchEndsEncounter = true
            } else {
                isPickingWorkspace = true
            }
        } label: {
            Label(appState.workspace?.name ?? String(localized: "No Workspace"), systemImage: "folder")
        }
        .accessibilityIdentifier("workspace-switch")
        .help("Switch workspace")
    }

    var body: some View {
        // The window splits into two columns at the very top: the live panel on the left,
        // running the full height, and everything else — toolbars, Map, Comment Bar — in a
        // column to its right.
        //
        // The split is the outermost thing in the window rather than a row partway down it
        // because both halves are full-height columns, and a seam that starts below the
        // toolbars is not a split: it is a Map with something beside it. The panel is the
        // one part of this window a DM reads *while* looking at the Map, so it gets a column
        // rather than a corner.
        //
        // Every toolbar row now sits inside the right column, which is why they bound to the
        // Map's width rather than the window's. That is the point: a row of Map controls
        // stretched across the panel too made the window read as one undivided surface with
        // a sidebar bolted on below.
        HStack(alignment: .top, spacing: Self.columnSpacing) {
            livePanel
            mapColumn
        }
        .padding(Self.windowPadding)
        // The launch gate. There is nothing behind this sheet until a Workspace is open, so
        // it is not dismissible then; when switching, Cancel puts the DM back where they were.
        .sheet(isPresented: Binding(
            get: { isPickingWorkspace || appState.workspace == nil },
            set: { isPickingWorkspace = $0 }
        )) {
            WorkspacePickerView(isSwitching: appState.workspace != nil)
                .environmentObject(appState)
                .interactiveDismissDisabled(appState.workspace == nil)
        }
        .sheet(item: $editing) { target in
            switch target {
            case .pawn(let id, let draft):
                EditPawnSheet(draft: draft,
                              hasDeclaredGrid: appState.hasDeclaredGrid,
                              bestiary: appState.bestiary,
                              pawns: appState.fog.pawns,
                              // The fight's copy while one runs: that is the one a stamp
                              // would overwrite, and so the one to ask about.
                              statBlock: appState.encounter?.blocks[id]
                                  ?? appState.statBlock(for: id),
                              onCommit: { appState.updatePawn(id: id, with: $0); editing = nil },
                              onCancel: { editing = nil })
            case .light(let id, let draft):
                EditLightSheet(draft: draft,
                               hasDeclaredGrid: appState.hasDeclaredGrid,
                               onCommit: { appState.updateLight(id: id, with: $0); editing = nil },
                               onCancel: { editing = nil })
            }
        }
        .sheet(item: $rolling) { target in
            RollSheet(draft: RollDraft(pawn: target.pawn, kind: target.kind),
                      onCommit: { draft in
                          record(draft)
                          rolling = nil
                      },
                      onCancel: { rolling = nil })
        }
        .alert("End the encounter and switch workspace?",
               isPresented: $confirmSwitchEndsEncounter) {
            Button("Cancel", role: .cancel) {}
            Button("Switch") {
                appState.stopEncounter()
                isPickingWorkspace = true
            }
        } message: {
            Text(endEncounterMessage)
        }
        .alert(StopSessionPrompt.title, isPresented: $confirmStopSession) {
            Button("Cancel", role: .cancel) {}
            // Not `.destructive`: nothing is destroyed. The Log is closed and kept, which is
            // what the message says and what the colour should not contradict.
            Button("End Session") { appState.stopSession() }
        } message: {
            Text(stopSessionMessage)
        }
        .alert(migrationTitle, isPresented: Binding(
            get: { appState.migrationOutcome != nil },
            set: { if !$0 { appState.migrationOutcome = nil } }
        )) {
            Button("OK") { appState.migrationOutcome = nil }
        } message: {
            Text(migrationMessage)
        }
        // Wide enough for the live panel AND a Map column the toolbars still fit in.
        //
        // This used to be `480 + (livePanelWidth - 236)`, which was the right sum while the
        // toolbars spanned the whole window and only the Map row was shortened by the panel.
        // Once the seam moved to the top the toolbars moved inside the Map column, and that
        // old minimum left them about 215 pt: "Measurements" broke into four stacked lines,
        // every button truncated to a stub, and the mode hint clipped. The window was still
        // "wide enough" by a number that no longer described the thing it constrained.
        //
        // So the minimum is now built the way the layout actually is — what the Map column
        // needs, plus the panel beside it — rather than a window width with a correction
        // bolted on. `SetupToolbarWidthTests` pins `minimumMapColumnWidth` against the real
        // toolbar, so the two cannot drift apart again.
        .frame(minWidth: Self.minimumWindowWidth, minHeight: 400)
        // The Control Window IS the app: its close button kept being hit during mode
        // work (it reads like "exit this mode"), killing the session — every "crash"
        // reported against Grid Fit/panning was this. Minimize stays; quit is ⌘Q.
        .onAppear {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("control") == true }) {
                window.styleMask.remove(.closable)
            }
        }
    }

    /// Everything to the right of the seam: the toolbars, the Map, the Comment Bar.
    ///
    /// `alignment: .leading` plus the preview claiming the remaining height keeps these
    /// controls pinned to the top of the column whether or not a Map is open.
    private var mapColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: Setup Toolbar — what a DM touches before the players arrive.
            //
            // This row and the `modeControls` row below it are the **Setup Toolbar**
            // (`CONTEXT.md`): Open Map, the Player Display picker, the Workspace, Grid Fit,
            // the Wall Editor. Named for the phase it belongs to rather than for what it acts
            // on, so the separation between preparing and playing is visible in the window
            // rather than merely intended. Nothing in it is disabled once a Session starts —
            // a DM sometimes must trace a wall mid-evening, because the party went somewhere
            // never prepared.
            //
            // The screen picker rides here rather than on a line of its own: choosing the
            // Player Display is done once when the cable goes in, and a whole row for it cost
            // height the preview wanted. Everything in the row is width-bounded except the
            // file name, which truncates.
            //
            // The two rows are not adjacent and are not merged: that is a fact about the
            // current layout, and merging them is a height change this has no reason to make.
            HStack {
                Button("Open Map…") { appState.openMap() }
                if let url = appState.mapURL {
                    Text(url.lastPathComponent)
                        .foregroundStyle(.secondary)
                        // Truncated rather than allowed to push the picker off the row: a
                        // long file name is the one thing here with no bound on its width.
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                playerDisplayPicker
                workspaceButton
            }

            // One row now. It was two, because a "Grid squares wide" field shared it with
            // the mode buttons and a single row ran them off the right edge — losing the
            // only way into every mode the app has, with no scrollbar and nothing to say
            // they were there. The field is gone (the Grid is declared by Grid Fit), so the
            // buttons have the row to themselves and the caption rides along in it.
            //
            // The old warning still applies to anything added here: a `Spacer()` makes
            // `ViewThatFits` claim the wide branch fits at any width, so it is always chosen
            // and always clipped. Keep this row short.
            HStack(spacing: 8) {
                modeControls
                Spacer()
                // The one row in this window with a free right edge, which is where the Log
                // goes. It is Setup rather than Live because the line between the two
                // toolbars is the audience: nothing here changes what is on the Player
                // Display, and reading back over the evening is the DM's alone.
                logToggle
            }

            // ONE reserved row, in every mode, whether or not it has anything to say.
            //
            // Each mode used to contribute its own caption — and the Wall Editor a caption
            // plus an inspector row — so entering a mode added height to this stack, stole
            // it from the `GeometryReader` below, and `fitted(container:)` recomputed to a
            // different scale. The Map visibly resized the moment a DM pressed "Wall Editor…",
            // and jumped mid-click inside the mode. Same defect, two symptoms.
            //
            // Reserving a constant height makes the preview's container a fixed point
            // across every mode change, which is the property its arithmetic needs. The
            // hint inside it may change freely; the box may not.
            //
            // Guarded by `ChromeHeightTests` and `PreviewContainerStabilityTests`.
            Text(modeHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(Self.modeHintLineLimit)
                // Wrapped rather than truncated: the Wall Editor's hint is a list of
                // gestures, and a DM who cannot see the last of them cannot use it.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: Self.modeHintRowHeight,
                       maxHeight: Self.modeHintRowHeight, alignment: .topLeading)

            // Warnings only now — the picker moved up beside "Open Map…". This collapses to
            // nothing when there is nothing to warn about, which is the line the move frees.
            playerDisplayStatus

            fogLoadWarning

            undeclaredGridWarning

            // MARK: Live Toolbar — what a DM touches with the players watching.
            //
            // The **Live Toolbar** (`CONTEXT.md`): the switches that change what the table
            // experiences, now. Both govern what the Player Display shows, and stacking them
            // cost a line of height on a window whose vertical space belongs to the preview.
            //
            // The Session control sits here rather than beside the Workspace button because
            // starting an evening is a live act, not setup. It changes label, not height, so
            // the row's reserved height is unaffected.
            // Both the Live Toolbar and the Map give way to the Log View, and they give way
            // together. Every switch in this row changes what the players are looking at, so
            // a row of them above a pane that is not the Map would be a row of controls for
            // something off screen — and a DM reaching for one has already decided to look at
            // the Map again. That includes the Session control: stopping the evening is done
            // where the evening is being run.
            if !showingLog {
                HStack(spacing: 16) {
                    fogSwitch
                    measurementVisibilitySwitch
                    viewportToggle
                    Spacer()
                    sessionToggle
                }

                preview
            } else {
                LogView(rows: logRows, hasWorkspace: appState.workspace != nil,
                        hasSession: appState.session != nil)
            }

            // The Comment Bar, beneath the Map and the width of the Map column — it used to
            // span the whole window, and followed the toolbars inward when the seam moved to
            // the top so that one unbroken edge runs the window's full height.
            // Fixed height in all three of its states: `preview` claims whatever this stack
            // leaves it, so a bar that grew when a fight started would resize the Map
            // mid-click. Guarded by `CommentBarTests`.
            // Not gated on a Map. An evening belongs to the Workspace and crosses whatever
            // Maps the party walks (ADR-0015), so a Comment typed before the crypt is opened
            // is still part of it — and a bar that appeared with the Map would change the
            // stack's height, which is the one thing this row must never do.
            CommentBar(state: commentBarState, text: $comment, onSubmit: sendComment)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: appState.playerScreen) { _, screen in
            // Losing the Player Display mid-pan would strand the mode with no overlay.
            if !ViewportToggle.staysShowing(mapOverflows: mapOverflowsViewport,
                                            hasDisplay: screen != nil) {
                isShowingViewport = false
            }
        }
        .onChange(of: appState.mapURL) { _, _ in
            // Every mode is authored against the Map that was open when it started, and
            // this @State survives the Map changing underneath it. Fog was the damaging
            // one: `fogEdits` still held the outgoing Map's document, so the next edit or
            // Cancel wrote it over the incoming Map's fog file. `AppState` refuses that
            // document now; closing the modes here is what the DM actually sees, instead
            // of a mode whose buttons have quietly stopped doing anything.
            //
            // `fogEdits` is deliberately NOT reset here. It is only ever read with the
            // mode open, and the only way back in is `startFogEditing`, which re-seeds it
            // from the incoming Map's `appState.fog` — after that Map's own fog has been
            // loaded. Seeding an empty document here would just assert, one line above the
            // code that overwrites it, that a Map's editing state starts empty.
            appState.endFogEditing()
            fitSquare = nil
            // `AppState` drops the Measurement itself; the armed tool is view state, and a
            // crosshair left hunting on a Map the DM has closed is the same staleness.
            armedShape = nil
            armedAdd = nil
            // One of the two things that end the Magnifier: the zoom was into the outgoing
            // Map's artwork, and a different image has nothing to anchor it to.
            magnifier = nil
            // An Edit sheet holds the outgoing Map's Pawn or Light by ID. Left up, it would
            // sit over a Map it does not belong to and its OK would silently no-op against
            // the `guard` in `updatePawn` — a sheet whose buttons have quietly stopped doing
            // anything, which is the staleness this whole block exists to prevent.
            editing = nil
            typedDistance.clear()
            mode = .normal
        }
        // The other half: the subject can go while the Map stays — a Pawn deleted from the
        // roster, or from this very menu. Follows the `resolved…` guard pattern
        // (`AppState.swift`, `resolvedSoloSightPawnID`): never hold an ID that matches
        // nothing, rather than checking for staleness at the point of use.
        .onChange(of: appState.fog) { _, fog in
            switch editing {
            case .pawn(let id, _) where !fog.pawns.contains(where: { $0.id == id }):
                editing = nil
            case .light(let id, _) where !fog.lights.contains(where: { $0.id == id }):
                editing = nil
            default:
                break
            }
        }
        .onChange(of: fitSquare) { _, square in
            guard let square, let image = appState.mapImage,
                  let squaresWide = GridFit.squaresWide(imageWidth: image.pixelSize.width,
                                                        squareSide: square.side) else { return }
            appState.squaresWide = Double(squaresWide)
        }
    }

    /// The Map's width in Grid squares — the one number that pins its physical size.
    @ViewBuilder

    // MARK: Preview

    /// The Viewport resolved against the connected Player Display, or nil without one.
    private var resolvedViewport: Viewport? {
        guard let metrics = appState.playerMetrics,
              let screen = appState.playerScreen,
              let map = appState.mapScale else { return nil }
        return ScaleMath.resolvedViewport(map: map, display: metrics,
                                          screenSizePoints: screen.frame.size,
                                          desiredOrigin: appState.viewportOrigin)
    }

    private var mapOverflowsViewport: Bool {
        guard let viewport = resolvedViewport, let map = appState.mapScale else { return false }
        return map.physicalSizeInches.width > viewport.sizeInches.width
            || map.physicalSizeInches.height > viewport.sizeInches.height
    }

    @ViewBuilder
    private var preview: some View {
        if let image = appState.mapImage {
            GeometryReader { geo in
                do {
                    // The container every transform is measured against. Captured once
                    // from the GeometryReader and then FORCED onto the ZStack below: an
                    // unconstrained ZStack grows to hold the zoomed Image, the reader
                    // measures that overflow, and the container feeds back into the next
                    // zoom — the preview spills out of the window instead of zooming, and
                    // snaps back when layout resettles.
                    let previewSize = geo.size
                    // Every mode draws through the Magnifier; without one it is the plain
                    // aspect fit, which is its floor. Re-clamped against this container
                    // because the Magnifier now outlives window resizes as well as modes.
                    let transform = magnifier?.resized(to: previewSize)
                        ?? PreviewTransform.fitted(imagePixelSize: image.pixelSize,
                                                   container: previewSize)
                    let fitted = transform.imageRect
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: fitted.midX, y: fitted.midY)
                            // Zoomed in this frame is far larger than the preview, and an
                            // overflowing Image owns its full frame for hit-testing — the
                            // regression issue 09 hit with the mirror. Pure display; the
                            // overlays handle interaction.
                            .allowsHitTesting(false)
                        if mode == .gridFit {
                            GridFitOverlay(transform: transform,
                                           containerSize: previewSize,
                                           square: $fitSquare) { magnifier = $0 }
                        }
                        if mode == .fog {
                            let fogRegions = appState.litRegions
                            FogOverlay(transform: transform,
                                       containerSize: previewSize,
                                       gridPixels: gridPixels,
                                       edits: $fogEdits,
                                       isDimmed: { isInvisibleToPlayers($0, regions: fogRegions) },
                                       onChange: { applyFogEdits() },
                                       onTransform: { magnifier = $0 })
                        }
                        // Always drawn on the Live View: the rectangle is how the DM knows
                        // what their players are being shown, which is the question the
                        // whole window exists to answer. The toggle decides whether it can
                        // be *dragged* — idle it is a readout with hit-testing off, so the
                        // clicks that drag a Pawn or open the menu pass straight through.
                        if ViewportToggle.drawsRectangle(mode: mode,
                                                         hasViewport: resolvedViewport != nil),
                           let map = appState.mapScale, let viewport = resolvedViewport {
                            ViewportOverlay(fittedRect: fitted,
                                            map: map,
                                            viewportSizeInches: viewport.sizeInches,
                                            originInches: viewport.originInches,
                                            isDraggable: ViewportToggle.isDraggable(
                                                isShowingViewport: isShowingViewport)) { desired in
                                appState.viewportOrigin = desired
                            }
                        }
                        // The DM's own party, on the branch that runs when nothing is
                        // plugged in. Without this the preview is bare artwork whenever
                        // there is no Player Display — the Pawns are in the document and
                        // listed in the Scene tab, and the DM cannot see or drag one.
                        // `PreviewBranch.drawsLiveLayers` is the single statement of when
                        // these are owed; see `.scratch/pawns-not-drawn/`.
                        //
                        // Sized to the artwork and positioned over it, NOT left to fill
                        // the ZStack: `FogCanvas` fills its darkness against its own
                        // `size` while cutting the lit regions against `frame`, so a
                        // greedy canvas tints the letterbox margins as well as the Map.
                        // Given the fitted rect as both, the two agree.
                        if PreviewBranch.drawsLiveLayers(mode: mode),
                           let map = appState.mapScale {
                            liveLayers(map: map, frame: CGRect(origin: .zero, size: fitted.size))
                                .frame(width: fitted.width, height: fitted.height)
                                .position(x: fitted.midX, y: fitted.midY)
                        }
                    }
                    // Pin to the preview and clip. Both are load-bearing: without the
                    // frame the ZStack sizes itself to the zoomed Image and the reader
                    // above measures that instead of the preview; without the clip the
                    // zoomed Image draws over the controls. Together they make
                    // `previewSize` a fixed point rather than a function of the zoom.
                    .frame(width: previewSize.width, height: previewSize.height)
                    .clipped()
                    // The preview has to be hit-testable as a whole for the modifiers below
                    // to see a click at all. The mirror branch got this for free from the
                    // `Color.black` letterbox filling its ZStack; this one is transparent
                    // wherever the artwork is not, so the right-click menu simply never
                    // opened over the margins — and `.clipped()` does not restore a shape.
                    .contentShape(Rectangle())
                    // Everything below was attached to the mirror until the Live View
                    // started showing the whole Map. It moved wholesale rather than being
                    // rewritten: these read against `fitted` instead of `mirrorFrame`, and
                    // nothing else about measuring, stamping or the right-click menu
                    // changed. Gated on `.normal` because the authoring modes own their own
                    // gestures — `FogOverlay` and `GridFitOverlay` are underneath here.
                    .onRightClick { if mode == .normal { rightClick() } }
                    // Stamping a Character: the Party panel's drag lands here. The comment
                    // above says stamping "moved wholesale" with the rest, and it did not —
                    // the mirror's drop target was deleted with the mirror and never
                    // re-attached, so the roster offered a drag nothing would accept.
                    //
                    // `location` arrives in this container's own space, which is the space
                    // `fitted` is expressed in — the pairing `PlayerPlacement.mapPoint`
                    // warns about at length, and the same one `leftClick` relies on. A drop
                    // on the letterbox margin is outside the image and is refused by
                    // `Stamp.pawn`. Refused in the authoring modes too: the Wall Editor draws
                    // Pawns for reference and places none (ADR-0013).
                    .dropDestination(for: CharacterDragPayload.self) { payloads, location in
                        guard mode == .normal else { return false }
                        return appState.stampDropped(payloads, at: location, frame: fitted)
                    }
                    .contextMenu {
                        if mode == .normal, !isChaining, let map = appState.mapScale {
                            measurementMenu(map: map, frame: fitted)
                        }
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if mode == .normal, let map = appState.mapScale {
                                leftClick(map: map, frame: fitted)
                            }
                        },
                        including: mode == .normal && claimsLeftClick ? .all : .subviews
                    )
                    // The wheel zooms and a swipe pans — `ScrollIntent` tells the two apart —
                    // in every mode, on the one Magnifier. The Viewport is untouched even
                    // with the rectangle armed and under the fingers, so the table sees
                    // nothing change: moving what they see is a deliberate primary drag.
                    //
                    // Starts from the stored Magnifier rather than `transform`: a trackpad
                    // sends more than one event per frame, and the render's own value would
                    // drop every event but the last before the view caught up.
                    .onScrollWheel { intent, location in
                        var next = magnifier?.resized(to: previewSize) ?? transform
                        if intent.zoom != 0 {
                            next = next.zoomed(to: next.scale * intent.zoomFactor,
                                               anchoringViewPoint: location,
                                               container: previewSize)
                        }
                        if intent.pan != .zero {
                            next = next.panned(by: intent.pan, container: previewSize)
                        }
                        if next != transform { magnifier = next }
                    }
                    // A trackpad pinch, anchored where it began, as the wheel is anchored at
                    // the cursor. `magnification` is cumulative from the gesture's start, so
                    // it multiplies the scale the pinch began at, not the live one.
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                let start = pinchStart ?? transform
                                pinchStart = start
                                magnifier = start.zoomed(to: start.scale * value.magnification,
                                                         anchoringViewPoint: value.startLocation,
                                                         container: previewSize)
                            }
                            .onEnded { _ in pinchStart = nil }
                    )
                    // ⌥-drag moves the Magnifier, as it does in the Wall Editor and Grid
                    // Fit, whose overlays carry their own so it is not also read as a draw. `.modifiers(.option)` also stops a plain drag matching, so
                    // dragging a Pawn stays unfiltered — that is the live action here.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 2)
                            .modifiers(.option)
                            .onChanged { value in
                                guard mode == .normal else { return }
                                let start = livePanStart ?? transform
                                livePanStart = start
                                magnifier = start.panned(by: value.translation,
                                                         container: previewSize)
                            }
                            .onEnded { _ in livePanStart = nil }
                    )
                    // The middle button pans the Magnifier in every mode, because no mode
                    // uses that button for anything else, so unlike ⌥-drag it needs no
                    // gesture to stay out of the way of. `panned` stops at the artwork's
                    // edges, and at the floor there is nothing to move and nothing is stored.
                    .onMiddleMouseDrag(isOverView: mirrorCursor != nil) { translation in
                        let start = middlePanStart ?? transform
                        middlePanStart = start
                        let panned = start.panned(by: translation, container: previewSize)
                        guard panned != transform else { return }
                        magnifier = panned
                    } onEnded: {
                        middlePanStart = nil
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            // The only reliable cursor position on this surface — every
                            // measuring handler reads it rather than an event's own.
                            mirrorCursor = location
                            if mode == .normal, let map = appState.mapScale {
                                aim(at: location, map: map, frame: fitted)
                            }
                        case .ended:
                            mirrorCursor = nil
                        }
                    }
                    // Digits are claimed only while a Measurement is armed, the cursor is
                    // over the Map, and no text field has focus. See MeasurementTyping.
                    .onMeasurementKeys(isArmed: mode == .normal && claimsLeftClick,
                                       isOverMap: mirrorCursor != nil) {
                        handleMeasurementKey($0)
                    }
                    // The Viewport drag measures itself here. Without this space the
                    // gesture falls back to the dragged rectangle's own coordinates,
                    // which move with it — see ViewportOverlay.dragGesture.
                    .coordinateSpace(name: ViewportOverlay.coordinateSpace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .border(.separator)
            // Named so the UI tests can aim at the Map itself.
            //
            // They used to click fractions of the whole Control Window — `dx: 0.3` was
            // inside the Map only because the Map started at the window's left edge. The
            // live panel now holds that edge, so those fractions land on the Party list,
            // and every test that placed a Wall or a Pawn by coordinate broke at once.
            // An identifier is what makes the aim survive the next layout change too.
            //
            // `children: .contain` is load-bearing. A bare `.accessibilityIdentifier` on a
            // container flattens its subtree into one element, which took the Pawn tokens
            // off the tree — `PawnLayer` sets `pawn-token-<label>` on each, and
            // `PreviewWithoutDisplayUITests` reads them to prove the preview draws a Pawn at
            // all. Naming the container must not cost the names inside it.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("map-preview")
        } else {
            // With no Map open this used to be a bare `Spacer()`, which inside the
            // preview's HStack pushed sideways instead of filling downwards — the controls
            // above it got shoved around rather than staying put at the top of the window.
            // An empty view that claims both axes keeps the header where it is and leaves
            // the space below it blank, which is what "no Map yet" should look like.
            VStack {
                Spacer(minLength: 0)
                Text("No Map open. Choose one with “Open Map…”.")
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Modes

    @ViewBuilder
    private var modeControls: some View {
        switch mode {
        case .normal:
            // In the existing row rather than a new one: anything added above the preview
            // must reserve constant height or the Map jumps mid-click.
            Menu("Add") {
                ForEach(AddKind.allCases, id: \.self) { kind in
                    Button(kind.title) { arm(kind) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            // Disabled with the Log open along with the two beside it: all three act on a Map
            // that is not on screen, and `Add` in particular would arm a click invisibly —
            // the DM would close the Log to find a mode waiting that they had forgotten
            // starting. The mode hint row says why they are off.
            .disabled(appState.mapImage == nil || showingLog)
            .help("Pick what to add, then click the Map to place it. Esc cancels.")
            Button("Grid Fit…") { startGridFit() }
                .disabled(appState.mapImage == nil || showingLog)
                .accessibilityIdentifier("grid-fit")
            Button("Wall Editor…") { startFogEditing() }
                .disabled(appState.mapImage == nil || showingLog)
                .accessibilityIdentifier("wall-editor")
            // A "Zoomed — Reset" button used to appear here while magnified. Zooming back
            // out reaches the same place: `PreviewTransform`'s zoom floor is fit-to-window,
            // so the Map returns to exactly the rect the button restored. The Magnifier
            // never touched the Player Display, so nothing about the table's view depended
            // on it either.
        case .gridFit:
            if fitSquare != nil, let snap = GridFit.snapSuggestion(for: appState.squaresWide) {
                Button("Snap to \(snap)") { applySnap(snap) }
            }
            Button("Cancel") { cancelGridFit() }
                .keyboardShortcut(.cancelAction)
            Button("Done") { endGridFit() }
                .keyboardShortcut(.defaultAction)
        case .fog:
            Text(fogSummary)
                .foregroundStyle(.secondary)
            Button("Undo") { fogEdits.undo(); applyFogEdits() }
                .disabled(!fogEdits.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            Button("Cancel") { cancelFogEditing() }
            Button("Done") { appState.endFogEditing(); mode = .normal }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func startFogEditing() {
        appState.beginFogEditing()
        // `beginFogEditing` drops the Measurement; the armed tool is view state and has to
        // be dropped alongside it, or the crosshair follows the DM into authoring.
        armedShape = nil
        armedAdd = nil
        typedDistance.clear()
        fogEdits = FogEdits(document: appState.fog)
        // The Magnifier is left where it is. This used to open on the whole Map, "the
        // zoomed-out view orients" — but a DM who zoomed into a room before pressing Edit
        // Fog has already oriented, and came here to trace that room.
        mode = .fog
    }

    /// Discard the whole session. `AppState` owns the merge — the Grid and any live Pawn
    /// rename are not what this mode was editing and must survive Cancel.
    private func cancelFogEditing() {
        appState.cancelFogEditing(fogEdits)
        mode = .normal
    }

    /// Push the edited fog onto the Map. Called after every action so the Player Display
    /// and the fog file stay in step with what the DM sees.
    private func applyFogEdits() {
        appState.applyFogEdits(fogEdits)
    }

    /// The Fog tint, the Light Markers, the Pawn tokens and any Measurement — everything
    /// the preview draws *on* the Map rather than as part of it.
    ///
    /// Shared by both branches of `preview` so the mirror and the fitted view cannot drift
    /// apart. They differ only in the frame they pass: the mirror's carries the Viewport's
    /// pan, the fitted branch's is the aspect fit. `PreviewBranch.liveLayerFrame` is the
    /// same choice stated as arithmetic.
    @ViewBuilder
    private func liveLayers(map: MapScale, frame: CGRect) -> some View {
        FogCanvas(regions: appState.litRegions, map: map, frame: frame) {
            FogShading.control($0, isOverlayOn: appState.isFogOverlayOn)
        }
        PawnLayer(map: map,
                  frame: frame,
                  pawns: appState.fog.pawns,
                  lights: appState.fog.lights,
                  // Hoisted, not read per Pawn: `litRegions` is computed, and rebuilding
                  // the cache key for every token every frame of a drag is exactly the
                  // drag-rate work this file's comments record a regression over.
                  isDimmed: { [regions = appState.litRegions] pawn in
                      isInvisibleToPlayers(pawn, regions: regions)
                  },
                  isLightDimmed: { [regions = appState.litRegions] light in
                      PlayerVisibility.isLightMarkerDimmedForDM(
                          light: light, regions: regions,
                          isFogOverlayOn: appState.isFogOverlayOn,
                          hasVisibility: appState.hasDeclaredGrid)
                  },
                  onMove: { appState.movePawn(id: $0, to: $1) },
                  onCommit: { id, origin in
                      appState.commitPawnMove(id: id, from: origin)
                  },
                  onMoveLight: { appState.moveLight(id: $0, to: $1) },
                  onCommitLight: { appState.commitLightMove() })
        // Above the tokens: a Measurement is what the DM is pointing at, and a cone
        // half-hidden behind the party is unreadable.
        if let pixelsPerSquare = appState.pixelsPerSquare {
            ForEach(appState.drawableMeasurements, id: \.measurement.id) {
                MeasurementLayer(measurement: $0.measurement,
                                 origin: $0.origin,
                                 map: map, frame: frame,
                                 pixelsPerSquare: pixelsPerSquare)
            }
        }
    }

    private var fogSummary: String {
        let walls = appState.fog.walls.count
        let lights = appState.fog.lights.count
        let pawns = appState.fog.pawns.count
        // Each count is its own phrase so the catalogue can give it every plural form a
        // language has, where English has two.
        return [String(localized: "\(walls) Walls"),
                String(localized: "\(lights) Lights"),
                String(localized: "\(pawns) Pawns")].joined(separator: ", ")
    }

    /// Whether players currently cannot see this Pawn — a hidden one, a Creature standing
    /// in the dark, or, under Solo Sight, a party member the isolated Pawn's light does not
    /// reach. The DM's surfaces draw it faded rather than dropping it, which is what turns
    /// this mode into a readout: the DM sees Bardo standing just outside Ilyana's reach and
    /// knows the table cannot.
    private func isInvisibleToPlayers(_ pawn: Pawn, regions: [LitRegion]) -> Bool {
        PlayerVisibility.isDimmedForDM(pawn: pawn, regions: regions,
                                       isFogOverlayOn: appState.isFogOverlayOn,
                                       hasVisibility: appState.hasDeclaredGrid,
                                       soloSightPawnID: appState.resolvedSoloSightPawnID)
    }

    /// One Grid square in image pixels, or nil when no Grid has been declared. Nothing
    /// snaps to it any more; it survives because a Pawn token is sized in Grid squares —
    /// a token reads as occupying its square — and the Lights inspector uses its absence
    /// to say that radii have no physical size yet.
    private var gridPixels: CGFloat? {
        guard appState.hasDeclaredGrid,
              let image = appState.mapImage, appState.squaresWide > 0 else { return nil }
        return GridFit.squareSide(imageWidth: image.pixelSize.width,
                                  squaresWide: appState.squaresWide)
    }

    // MARK: Measuring

    /// Left-click on the mirror: settle the Measurement at the distance now shown, so it
    /// stops following the mouse.
    ///
    /// The original requirement — "left click on a point in the screen to see the amount"
    /// — and it is not optional polish. Without it a Measurement rubber-bands forever, so
    /// the DM has to hold the mouse perfectly still to read the number and destroys it by
    /// moving to point at the shape. That is the failure ADR 0005 rejected under another
    /// name: evidence that vanishes the moment the table wants to discuss it.
    ///
    /// A left-click on a settled Measurement dismisses it, because right-click now opens
    /// the shape menu and can no longer double as the dismissal.
    ///
    /// So one button drives the whole life of a Measurement, each click advancing it one
    /// step: place the Origin, settle the distance, clear it. The DM never has to remember
    /// which button does which.
    private func leftClick(map: MapScale, frame: CGRect) {
        // `Add` is armed and waiting for a point. First, and unambiguous: the two armings
        // are mutually exclusive, so this and the Measurement branch below can never both
        // want the same click.
        if let kind = armedAdd {
            placeArmedAdd(kind, map: map, frame: frame)
            return
        }
        // An armed tool is waiting for its Origin, and that comes first: until one is
        // placed there is no Measurement to settle.
        if let shape = armedShape {
            placeOrigin(shape: shape, map: map, frame: frame)
            return
        }
        guard let measurement = appState.resolvedMeasurement else { return }
        typedDistance.clear()

        // A Line being drawn takes another vertex instead of settling: the whole point of
        // a chain is that clicking does not end it. Right-click finishes it.
        if measurement.isChaining {
            guard let cursor = mirrorCursor else { return }
            let point = PlayerPlacement.mapPoint(cursor, map: map, frame: frame)
            appState.setMeasurement(measurement.extended(to: point))
            return
        }

        appState.setMeasurement(measurement.clicked())
    }

    /// The left-click that says where an armed Measurement starts.
    ///
    /// Hit-tests the Pawns itself: a click on a token measures from that token, anything
    /// else from exactly the point clicked.
    private func placeOrigin(shape: MeasurementShape, map: MapScale, frame: CGRect) {
        guard let pixelsPerSquare = appState.pixelsPerSquare,
              let point = mirrorCursor else { return }
        let mapPoint = PlayerPlacement.mapPoint(point, map: map, frame: frame)
        let origin = MeasurementControl.origin(forClickAt: mapPoint,
                                               pawns: appState.fog.pawns,
                                               pixelsPerSquare: pixelsPerSquare)
        armedShape = nil
        typedDistance.clear()
        appState.setMeasurement(Measurement(origin: origin, shape: shape,
                                            distance: 0, direction: 0))
    }

    /// The right-click menu on the Live View: what to do with whatever is under the cursor,
    /// then what to measure.
    ///
    /// One menu with a divider rather than two menus. `Edit…` and `Delete` act on the Pawn
    /// or Light under the cursor and are absent when there is none; the Measurement section
    /// is always offered, because a DM right-clicking a Pawn may well have meant to measure
    /// from it, and hiding the shapes there would make the menu's contents depend on
    /// aim in a way they cannot see.
    ///
    /// Left-click is not available for this. It is already the Pawn drag (`PawnLayer`) and,
    /// while a shape is armed, the Measurement state machine. `.contextMenu` is a modifier
    /// rather than a composed gesture, so it avoids the composition defects this render
    /// layer has a record of.
    @ViewBuilder
    private func measurementMenu(map: MapScale, frame: CGRect) -> some View {
        let target = liveHit(map: map, frame: frame)
        let items = LiveMenu.items(target: target,
                                   measurement: measurementUnderCursor(map: map, frame: frame),
                                   availability: appState.measurementAvailability)

        if let target, items.editsTarget {
            Section {
                Button("Edit…") { beginEditing(target) }
                Button("Delete") { delete(target) }
            }
        }

        if let pin = items.pin {
            Section {
                switch pin {
                case .unpin(let id):
                    Button("Unpin Measurement") { appState.unpinMeasurement(id: id) }
                case .pin:
                    Button("Pin Measurement") { appState.pinMeasurement() }
                }
            }
        }

        if items.shapesOffered {
            Section {
                ForEach(MeasurementShape.allCases, id: \.self) { shape in
                    Button(shape.label) { startMeasurement(shape) }
                }
            }
        }

        if let refusal = items.refusal {
            Text(refusal.explanation)
        }
    }

    /// Open the Edit sheet on whatever the menu was opened over.
    ///
    /// Seeds the draft here, from the object as it stands now — the sheet edits a copy and
    /// commits it whole, so nothing reaches `AppState` until OK.
    private func beginEditing(_ target: LiveHitTest) {
        switch target {
        case .pawn(let id):
            guard let pawn = appState.fog.pawns.first(where: { $0.id == id }) else { return }
            editing = .pawn(id, EditPawnDraft(pawn: pawn))
        case .light(let id):
            guard let light = appState.fog.lights.first(where: { $0.id == id }) else { return }
            editing = .light(id, EditLightDraft(light: light))
        }
    }

    /// Delete whatever the menu was opened over. No confirmation: a live action, and a
    /// dialog in the middle of a fight costs more than the mistake does.
    private func delete(_ target: LiveHitTest) {
        switch target {
        case .pawn(let id): appState.removePawnFromMap(id)
        case .light(let id): appState.removeLight(id: id)
        }
    }

    /// The Pawn or Light under the cursor, if any.
    ///
    /// Reads the cursor from `mirrorCursor` rather than from the `NSEvent`: a right-click
    /// event carries no location this view can use, and `RightClick.swift` records why.
    private func liveHit(map: MapScale, frame: CGRect) -> LiveHitTest? {
        guard let cursor = mirrorCursor else { return nil }
        return LiveHitTest.hit(at: PlayerPlacement.mapPoint(cursor, map: map, frame: frame),
                               pawns: appState.fog.pawns,
                               lights: appState.fog.lights,
                               gridPixels: gridPixels)
    }

    private func measurementUnderCursor(map: MapScale,
                                        frame: CGRect) -> LiveMenu.MeasurementUnderCursor? {
        guard let cursor = mirrorCursor,
              let pixelsPerSquare = appState.pixelsPerSquare else { return nil }
        let point = PlayerPlacement.mapPoint(cursor, map: map, frame: frame)

        for pinned in appState.pinnedMeasurements.reversed() {
            guard let origin = pinned.originPoint(pawnAt: { id in
                appState.fog.pawns.first(where: { $0.id == id })?.at
            }) else { continue }
            if pinned.contains(point, origin: origin, pixelsPerSquare: pixelsPerSquare) {
                return .pinned(pinned.id)
            }
        }

        if let live = appState.resolvedMeasurement,
           let origin = appState.measurementOriginPoint,
           live.contains(point, origin: origin, pixelsPerSquare: pixelsPerSquare) {
            return .live
        }
        return nil
    }

    /// Arm `Add` and wait for the click that says where.
    ///
    /// Clears any Measurement, armed or on screen, for the reason `startMeasurement` clears
    /// the other way: one armed tool at a time, or a left-click means two things at once.
    private func arm(_ kind: AddKind) {
        armedAdd = kind
        armedShape = nil
        typedDistance.clear()
        appState.setMeasurement(nil)
    }

    /// Place what `Add` armed, at the click. Stays armed when the click is refused, so the
    /// DM can simply aim better rather than reopening the menu.
    private func placeArmedAdd(_ kind: AddKind, map: MapScale, frame: CGRect) {
        guard let cursor = mirrorCursor else { return }
        let point = PlayerPlacement.mapPoint(cursor, map: map, frame: frame)

        switch kind {
        case .light:
            guard let light = AddPlacement.light(at: point, existing: appState.fog.lights,
                                                 imageSize: appState.mapImage?.pixelSize)
            else { return }   // outside the image: refused, and still armed
            appState.addLight(light)
        case .pawn(let pawnKind):
            guard let pawn = AddPlacement.pawn(kind: pawnKind, at: point,
                                               existing: appState.fog.pawns,
                                               imageSize: appState.mapImage?.pixelSize,
                                               bestiary: appState.bestiary)
            else { return }   // outside the image: refused, and still armed
            // Through `addPawnToMap` rather than appending here, so a Creature placed while
            // a fight is running rolls Initiative and joins the Order. A Treasure is refused
            // by `joinEncounter` itself, having nothing to do on its turn.
            appState.addPawnToMap(pawn)
        }
        // One click places one thing. The Kind stays on the menu, not on the cursor.
        armedAdd = nil
    }

    /// Arm the tool with a shape and wait for the click that places it.
    ///
    /// Any Measurement already on screen goes now rather than when the Origin is placed:
    /// the DM has said they are measuring something else, and leaving the old shape up
    /// while a crosshair hunts for a new one puts two answers on the table's screen.
    private func startMeasurement(_ shape: MeasurementShape) {
        // Sticky, so the menu opens on the shape the DM last used.
        measurementShape = shape
        armedShape = shape
        // One armed tool at a time — see `arm(_:)`.
        armedAdd = nil
        typedDistance.clear()
        appState.setMeasurement(nil)
    }

    /// Right-click: finish a chain if one is being drawn, otherwise back out of an armed
    /// tool and let the shape menu open.
    private func rightClick() {
        if let measurement = appState.resolvedMeasurement, measurement.isChaining {
            // Frees the cursor: the chain stops following it and stays on screen until the
            // next click, so the DM can read the total and point at the route.
            guard let origin = appState.measurementOriginPoint,
                  let pixelsPerSquare = appState.pixelsPerSquare else { return }
            appState.setMeasurement(measurement.finished(origin: origin,
                                                         pixelsPerSquare: pixelsPerSquare))
            typedDistance.clear()
            return
        }
        armedShape = nil
    }

    /// Whether a Line is mid-chain, which changes what both buttons mean.
    private var isChaining: Bool {
        appState.resolvedMeasurement?.isChaining ?? false
    }

    /// Whether the DM is in the middle of measuring — either waiting to place an Origin,
    /// or with a Measurement on screen. The gate for the **key** handler: digits type a
    /// distance, which only a Measurement has.
    private var isMeasuring: Bool {
        ArmedTool.claimsDigits(hasArmedShape: armedShape != nil,
                               hasMeasurement: appState.measurement != nil)
    }

    /// Whether the left-click belongs to the Map rather than to the Pawn drag underneath.
    ///
    /// Wider than `isMeasuring` by the armed `Add`, and deliberately one predicate rather
    /// than a second condition beside the first: this render layer has four gesture
    /// composition defects on record, and "which of these two flags claimed the click" is
    /// exactly the shape of question that produced them.
    private var claimsLeftClick: Bool {
        ArmedTool.claimsLeftClick(hasArmedAdd: armedAdd != nil,
                                  hasArmedShape: armedShape != nil,
                                  hasMeasurement: appState.measurement != nil)
    }

    /// Follow the cursor: an armed Measurement rubber-bands as the mouse moves, so the
    /// shape is live before it is committed. Distance snaps to whole squares — every DnD
    /// distance is a multiple of one, and nobody reads "8.7 m" off a screen.
    private func aim(at point: CGPoint, map: MapScale, frame: CGRect) {
        guard let measurement = appState.resolvedMeasurement,
              let origin = appState.measurementOriginPoint,
              let pixelsPerSquare = appState.pixelsPerSquare, pixelsPerSquare > 0 else { return }

        let cursor = PlayerPlacement.mapPoint(point, map: map, frame: frame)
        // `aimed` keeps a typed distance and follows the cursor with the aim either way.
        appState.setMeasurement(measurement.aimed(at: cursor, from: origin,
                                                  pixelsPerSquare: pixelsPerSquare))
    }

    /// A keystroke the Map claimed while a Measurement is armed. Which keystrokes those
    /// are is decided by `MeasurementTyping.decide`, not here.
    private func handleMeasurementKey(_ decision: MeasurementTyping.Decision) {
        // An armed tool has no Measurement yet, and the only key that means anything to it
        // is the one that backs out. `Add` arms the same way and Esc backs out of it too.
        if armedAdd != nil {
            if decision == .abandon { armedAdd = nil }
            return
        }
        if armedShape != nil, appState.measurement == nil {
            if decision == .abandon { armedShape = nil }
            return
        }
        guard var measurement = appState.resolvedMeasurement else { return }
        switch decision {
        case .passThrough:
            return
        case .digit(let digit):
            typedDistance.append(digit)
        case .backspace:
            typedDistance.backspace()
            // Back to an empty buffer is back to a dragged Measurement, so the next mouse
            // move sizes it again rather than leaving it frozen at the typed value.
            if typedDistance.isEmpty {
                measurement.isDistanceTyped = false
                measurement.distance = 0
                appState.setMeasurement(measurement)
            }
            return
        case .commit:
            guard let squares = typedDistance.squares(in: DistanceUnit.current) else { return }
            measurement.distance = squares
            measurement.isDistanceTyped = true
            appState.setMeasurement(measurement)
            typedDistance.clear()
            return
        case .abandon:
            // Esc abandons the digits, not the Measurement. Right-click is the one way to
            // dismiss one, and a second dismissal mechanism is what ADR 0005 objected to —
            // a DM who mistypes should not lose the Origin they picked.
            let hadDigits = !typedDistance.isEmpty
            typedDistance.clear()
            guard hadDigits else { return }
            measurement.isDistanceTyped = false
            measurement.distance = 0
            appState.setMeasurement(measurement)
            return
        }

        // Show the buffer as it is typed, so a mis-key is visible before Return rather
        // than after the shape jumps.
        if let squares = typedDistance.squares(in: DistanceUnit.current) {
            measurement.distance = squares
            measurement.isDistanceTyped = true
            appState.setMeasurement(measurement)
        }
    }

    private func startGridFit() {
        squaresWideBeforeFit = appState.squaresWide
        hadDeclaredGridBeforeFit = appState.hasDeclaredGrid
        fitSquare = nil
        // The Magnifier is left where it is, as it is for the Wall Editor: any one square is
        // as good to fit as another, so the one the DM was already looking at will do.
        mode = .gridFit
    }

    private func endGridFit() {
        mode = .normal
        fitSquare = nil
    }

    /// Discard the fit, including anything the autosave debounce already wrote — the Grid
    /// Fit square writes on every drag tick, so a cancelled value is normally already
    /// queued. The explicit flush makes the file correct now rather than half a second
    /// from now, so a quit in between cannot persist a Grid the DM backed out of. Same
    /// tool and same reason as `cancelFogEditing`.
    private func cancelGridFit() {
        appState.restoreGrid(squaresWide: squaresWideBeforeFit,
                             wasDeclared: hadDeclaredGridBeforeFit)
        appState.flushPendingFogWrites()
        endGridFit()
    }

    /// Suggested, never silent: applying the snap also resizes the overlay to match.
    private func applySnap(_ squares: Int) {
        appState.squaresWide = Double(squares)
        if let image = appState.mapImage, var square = fitSquare,
           let side = GridFit.squareSide(imageWidth: image.pixelSize.width,
                                         squaresWide: CGFloat(squares)) {
            square.side = side
            fitSquare = square
        }
    }

    // MARK: Fog

    /// The height the hint row always claims, in every mode, whatever it says.
    ///
    /// A constant rather than an intrinsic height, because "however tall it happens to be"
    /// is exactly what made the preview jump. Two lines at `.caption` — enough for the Wall
    /// Editor's list of gestures to wrap rather than truncate, and no more, since every
    /// point reserved here is a point the preview loses.
    ///
    /// Held against the real SwiftUI layout by `ChromeHeightTests`: a hand-picked number
    /// that clipped the text it reserves room for would be worse than no reservation.
    static let modeHintRowHeight: CGFloat = 30

    /// Two lines. One truncates the Wall Editor's gestures, and a DM who cannot read the
    /// last of them cannot use it; three costs the preview more than the hint is worth.
    static let modeHintLineLimit = 2

    /// What each mode is for. Every mode has one — an empty hint would reserve a shorter row
    /// than a real one and make the height depend on the mode again, which is the defect.
    static let liveViewHint = String(localized:
        "Right-click a Pawn or Light to edit it, or the Map to measure. Add places a new one. Scroll or pinch to zoom; two-finger or middle-drag to pan — the players see none of it.")
    static let gridFitHint = String(localized:
        "Drag a square over one grid square; arrow keys nudge (⇧ resizes).")
    static let wallEditorHint = String(localized:
        "Click to place Wall corners, double-click to end a chain, Esc to cancel. ⇧ frees the angle; corners weld to nearby ends. Click a Wall then ⌫ to delete. Pawns and Lights are shown for reference — edit them from the Map.")
    static let viewportHint = String(localized:
        "Drag the rectangle to choose what the Player Display shows.")
    /// The one text that answers "why can't I press Wall Editor", which is a question a greyed
    /// button raises and cannot itself answer.
    static let logViewHint = String(localized:
        "Reading the Session Log. Close it to edit the Map.")

    /// Every hint the row can hold, so `ChromeHeightTests` can measure the tallest against
    /// the height reserved for it rather than trusting a number.
    static var everyModeHint: [String] {
        [liveViewHint, gridFitHint, wallEditorHint, viewportHint, logViewHint]
    }

    /// What the reserved row says right now.
    ///
    /// The Viewport's caption wins over the Live View's: a DM who has just armed the
    /// rectangle is being told how to use the thing they armed, which is more urgent than
    /// the standing description of the surface.
    private var modeHint: String {
        // The Log wins over every mode's own hint: it is the reason the buttons beside it are
        // greyed, and a hint describing a surface that is not on screen explains nothing.
        if showingLog { return Self.logViewHint }
        switch mode {
        case .gridFit: return Self.gridFitHint
        case .fog: return Self.wallEditorHint
        case .normal: return isShowingViewport ? Self.viewportHint : Self.liveViewHint
        }
    }

    /// The container the preview measures its zoom and pan against.
    ///
    /// Deliberately ignores the mode. The chrome above the preview reserves a constant
    /// height in every mode, so the `GeometryReader`'s size already excludes it and entering
    /// a mode cannot change what the preview is fitted into. Expressed as a function taking
    /// the mode — rather than not taking it — so the rule is testable and stated, instead of
    /// being an invariant that holds only by accident of the layout.
    ///
    /// Held by `PreviewContainerStabilityTests`.
    static func previewContainer(geometry: CGSize, mode: PreviewMode) -> CGSize {
        geometry
    }

    /// Rename a Light from the roster, which is reachable in every mode.
    ///
    /// Straight to `AppState`, in every mode, because a Light is never edited through
    /// `FogEdits` any more (ADR-0013). That also fixes the asymmetry the split created: the
    /// old routing made an in-mode rename undoable and a live one not, and `carryLiveState`
    /// was Pawn-shaped throughout, so a Light renamed from the roster while the mode was
    /// open was silently discarded by Cancel. With one path there is nothing to discard.
    /// `WallEditorTests.testCancellingWallEditsKeepsALiveLightRename` holds it.
    private func setLightName(id: Light.ID, _ name: String) {
        appState.setLightName(id: id, name)
    }

    /// Set a Light's state, from the live row.
    ///
    /// Straight to `AppState` in every mode, beside `setLightName`. This had a fog-mode
    /// branch through `FogEdits` because an in-mode edit used to overwrite `fog` wholesale
    /// from the mode's snapshot and silently revert the toggle; `applyFogEdits` now copies
    /// only Walls, so there is nothing left to revert it.
    /// `WallEditorTests.testDousingALightDuringWallEditingSurvivesTheNextWall` holds it.
    private func setLight(id: Light.ID, isOn: Bool) {
        appState.setLight(id: id, isOn: isOn)
    }

    /// Light radii are in Grid squares, so an undeclared Grid renders every Light at a
    /// plausible-looking wrong size. Shown beside the Lights themselves rather than
    /// buried in the inspector: a DM who relaunches and never selects a Light would
    /// otherwise get no signal at all, which is the silent failure issue 03 forbids.
    @ViewBuilder
    private var undeclaredGridWarning: some View {
        if !(appState.fog.lights.isEmpty && appState.fog.pawns.isEmpty), !appState.hasDeclaredGrid {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("This Map's Grid has not been declared, so Light radii have no real size — run Grid Fit, or set the squares-wide value.")
                    .font(.caption)
            }
            .padding(8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// One Pawn in the live panel: its light toggle, and its label editable in place.
    ///
    /// Renaming lives here — beside the toggle, on the surface that is already the live
    /// control surface — rather than on a double-click on the token in `PawnLayer`. That
    /// layer owns the drag gesture, and gesture composition in this render layer has
    /// produced four defects already; a competing double-click there is the risky option
    /// for a marginal gain in directness.
    ///
    /// The write is `appState.setPawnLabel`, not `FogEdits`: a rename at the table is a
    /// live action and is not undoable, exactly as moving a Pawn is not.
    private func pawnLiveRow(_ pawn: Pawn) -> some View {
        HStack(spacing: 6) {
            // The token, not a switch: it is how the DM finds this row, since it carries
            // the same colour and label as the disc on the Map. Toggling its light is a
            // secondary use of it, so it is the one thing in the row that looks like the
            // Map rather than like a control.
            Toggle(isOn: Binding(
                get: { pawn.light.isOn },
                set: { appState.setPawnLight(id: pawn.id, isOn: $0) }
            )) {
                PawnToken(pawn: pawn, squareSide: 14, scalesWithFootprint: false)
            }
            .toggleStyle(.button)
            // The button's own label is the Pawn's name, which the DM can rename in the
            // very next field. The identifier is what a test should hold on to.
            .accessibilityIdentifier("pawn-light-toggle")
            .help(pawn.isDiscovered
                  // One sentence per kind rather than the kind's title spliced in: the article
                  // before it agrees with its gender in every language but English.
                  ? (pawn.kind == .treasure
                     ? String(localized: "\(pawn.label): a Treasure — emits no Light. Click to douse the light it does not cast.")
                     : String(localized: "\(pawn.label): a Creature — emits no Light. Click to douse the light it does not cast."))
                  : String(localized: "\(pawn.label): sight \(Int(pawn.light.brightSquares)) squares. Click to douse."))

            // Fills the column rather than a fixed 72 pt: names like "Goblin B" need the
            // room, and the panel has a known width to give them.
            TextField("label", text: Binding(
                get: { pawn.label },
                set: { appState.setPawnLabel(id: pawn.id, $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 0)

            // Take it off the Player Display without deleting it. The eye is filled when
            // players can see it and slashed when they cannot, so the DM reads the state
            // rather than the control.
            Toggle(isOn: Binding(
                get: { !pawn.isHidden },
                set: { appState.setPawnHidden(id: pawn.id, isHidden: !$0) }
            )) {
                Image(systemName: pawn.isHidden ? "eye.slash" : "eye")
                    .frame(width: 16)
            }
            .toggleStyle(.button)
            .help(pawn.isHidden
                  ? String(localized: "Hidden from players. Still here, and still yours to move.")
                  : String(localized: "Visible to players where the light reaches. Click to hide."))

            soloSightToggle(pawn)

            combatRosterToggle(pawn)

            rollButtons(pawn)
        }
        // With one Pawn isolated, the rest of the party is switched out of the lighting,
        // and the panel should say so at a glance: a DM who forgets Solo Sight is on will
        // misread the Player Display, in front of players.
        //
        // Deliberately not `PawnLayer`'s 0.4. That one means "the players cannot see this
        // Pawn", and it is already doing its job on the Map beside this panel — a row is
        // dimmed here for the different reason that its *light* is switched out, which is
        // true of a Pawn the table can still plainly see standing in a brazier's glow.
        .opacity(isSwitchedOutBySoloSight(pawn) ? soloSightSwitchedOutOpacity : 1)
    }

    /// Whether this Pawn rolls when the next fight starts.
    ///
    /// Rightmost in the row, past the controls that decide what the *table* sees: this one
    /// decides nothing about the Map, only who the tracker asks for Initiative. Remembered
    /// per Map, so a tavern's innkeeper stays out of every brawl held in it.
    ///
    /// Shown only while no fight is running. Once one is, Pawns come and go through the
    /// tracker's bench — a checkbox that silently meant something different mid-fight would
    /// be the worst of both.
    @ViewBuilder
    private func combatRosterToggle(_ pawn: Pawn) -> some View {
        if pawn.kind != .treasure && appState.encounter == nil {
            let isIn = appState.isInCombat(pawn.id)
            Toggle(isOn: Binding(
                get: { isIn },
                set: { appState.setInCombat($0, for: pawn.id) }
            )) {
                Image(systemName: isIn ? "shield.lefthalf.filled" : "shield.slash")
                    .frame(width: 16)
            }
            .toggleStyle(.button)
            .accessibilityIdentifier("pawn-in-combat")
            .help(isIn
                  ? String(localized: "\(pawn.label) rolls Initiative when an Encounter starts. Click to leave them out.")
                  : String(localized: "\(pawn.label) sits the next Encounter out. Click to put them in."))
        }
    }

    /// Hands a finished draft to the recorder.
    ///
    /// Deliberately without a branch on whether a fight is running: `recordRoll` writes to
    /// the Combat Log while one is and the Session Log while none is, and ADR-0014's rule
    /// that exactly one recorder is live is what makes that safe. A `if appState.encounter`
    /// here would be a second, weaker copy of that rule.
    private func record(_ draft: RollDraft) {
        guard let roll = draft.roll else { return }
        switch draft.kind {
        case .savingThrow:
            guard let ability = draft.ability else { return }
            appState.recordRoll(pawn: draft.pawn, ability: ability, roll: roll)
        case .abilityCheck:
            guard let skill = draft.skill else { return }
            appState.recordRoll(pawn: draft.pawn, skill: skill, roll: roll)
        }
    }

    /// Record a Saving Throw or an Ability Check for this Pawn.
    ///
    /// Buttons rather than Toggles, alone in this row: everything else here shows a state
    /// the symbol reflects, and a Roll has no state — it is an act, and the sheet is where
    /// it happens.
    ///
    /// Omitted for a Treasure, as `combatRosterToggle` is and for the same reason: a chest
    /// makes no Dexterity saves, and conditional visibility costs width rather than height.
    ///
    /// Live during a fight, unlike `combatRosterToggle`, because a Roll is often made by a
    /// Pawn that is not a Combatant at all — the NPC in the corner — and this row is where
    /// that Pawn lives. Which Log it lands in is `recordRoll`'s business, not this row's.
    @ViewBuilder
    private func rollButtons(_ pawn: Pawn) -> some View {
        if pawn.kind != .treasure {
            Button {
                rolling = RollTarget(pawn: pawn, kind: .savingThrow)
            } label: {
                Image(systemName: "bolt.shield").frame(width: 16)
            }
            .accessibilityIdentifier("pawn-saving-throw")
            .help("Record a Saving Throw for \(pawn.label).")

            Button {
                rolling = RollTarget(pawn: pawn, kind: .abilityCheck)
            } label: {
                Image(systemName: "figure.run").frame(width: 16)
            }
            .accessibilityIdentifier("pawn-ability-check")
            .help("Record an Ability Check for \(pawn.label).")
        }
    }

    /// How far a row is faded when Solo Sight has switched its Pawn out of the lighting.
    /// Lighter than `PawnLayer`'s 0.4: this says "not lighting the Map", not "invisible".
    private var soloSightSwitchedOutOpacity: Double { 0.5 }

    /// Whether this row is one of the Pawns Solo Sight has switched out.
    private func isSwitchedOutBySoloSight(_ pawn: Pawn) -> Bool {
        guard let isolated = appState.resolvedSoloSightPawnID else { return false }
        // A hidden Pawn was already off the table's screen and already out of the lighting
        // before the mode started, and its slashed eye says so. Dimming its row too would
        // blame Solo Sight for something the DM did themselves, in the one readout that is
        // meant to tell them exactly who the mode is costing them.
        return pawn.id != isolated && !pawn.isDiscovered && !pawn.isHidden
    }

    /// See the Map as one character alone lights it: every other Pawn's Light goes out, and
    /// the table sees it too. Radio-button semantics — clicking another Pawn's control moves
    /// the isolation, clicking the active one ends it.
    @ViewBuilder
    private func soloSightToggle(_ pawn: Pawn) -> some View {
        let availability = SoloSightControl.availability(
            for: pawn,
            isFogOverlayOn: appState.isFogOverlayOn,
            hasDeclaredGrid: appState.hasDeclaredGrid)
        if availability != .absent {
            let isSolo = appState.resolvedSoloSightPawnID == pawn.id
            Toggle(isOn: Binding(
                get: { isSolo },
                set: { appState.setSoloSight(id: $0 ? pawn.id : nil) }
            )) {
                // Both variants exist, unlike `person.viewfinder`, which does not: the
                // inactive state rendered as an empty button until this was caught by eye.
                // Filled when active and outline when not, so the DM reads the state rather
                // than the control — the same way the eye beside it does.
                Image(systemName: isSolo ? "binoculars.fill" : "binoculars")
                    .frame(width: 16)
            }
            .toggleStyle(.button)
            .disabled(availability != .available)
            .help(soloSightHelp(pawn, availability: availability, isSolo: isSolo))
        }
    }

    private func soloSightHelp(_ pawn: Pawn, availability: SoloSightControl.Availability,
                               isSolo: Bool) -> String {
        if case .disabled(let reason) = availability { return reason.explanation }
        return isSolo
            ? String(localized: "Solo Sight. The table sees only what \(pawn.label)'s own light reaches. Click to end.")
            : String(localized: "Solo Sight: show the Map as \(pawn.label) alone lights it.")
    }

    /// Whether the table sees the DM's Measurements.
    ///
    /// Beside the Fog switch because it is the same kind of control: a live decision about
    /// what the Player Display shows, taken mid-session and never persisted.
    ///
    /// **Always present**, unlike the Fog switch it sits next to. It was conditional on
    /// there being a Measurement to hide, which was wrong twice over. A DM decides whether a
    /// distance is for the table *before* they take it, and a control that appears only once
    /// the shape is already on the big screen offers that choice a moment too late. And a
    /// control that comes and goes is the layout defect this window has been bitten by three
    /// times: it shifts the row beside it and the preview below it.
    ///
    /// Default on: ADR-0005 makes the case that the table should see a Measurement, and that
    /// is the common one. This is the escape for the other kind — the distance a DM takes for
    /// themselves, where the number is the tactical fact they are deciding whether to reveal.
    private var measurementVisibilitySwitch: some View {
        Toggle("Measurements", isOn: $appState.showsMeasurementsToPlayers)
            .toggleStyle(.checkbox)
            // A stable handle for the UI tests, as the Fog switch carries: addressing a
            // control by its rendered label is what goes stale first.
            .accessibilityIdentifier("measurement-visibility-switch")
            .help("Show Measurements on the Player Display. Off, the shape and its distance stay on this window only.")
    }

    /// The Viewport rectangle's toggle, in the Live Toolbar.
    ///
    /// Moved here from `modeControls`, where it sat among Grid Fit and the Wall Editor —
    /// prep controls it has nothing in common with. Moving the Viewport is a live act the
    /// table watches as it happens (`CONTEXT.md`), which is what this row is for.
    ///
    /// A toggle, not a mode: press to show the rectangle, press again to put it away. There
    /// is no Cancel, deliberately — see `ViewportToggle`.
    ///
    /// Drawn only in the Live View, as it was inside `modeControls`' `.normal` case: the
    /// rectangle is not drawn in Grid Fit or the Wall Editor, so a control for dragging it
    /// would act on something invisible.
    ///
    /// Appearing and vanishing with the mode costs this row **width**, not height, so the
    /// preview's container is unchanged and the Map does not resize — the defect
    /// `ChromeHeightTests` guards. `fogSwitch` in the same row already comes and goes this
    /// way. What a width change does cost is the buttons after it shifting sideways, which
    /// is why the `Spacer()` sits between these switches and the Session control: the one
    /// thing on the right stays put.
    @ViewBuilder
    private var viewportToggle: some View {
        if mode == .normal {
            Toggle("Viewport", isOn: $isShowingViewport)
                .toggleStyle(.button)
                .disabled(!ViewportToggle.isAvailable(mapOverflows: mapOverflowsViewport,
                                                      hasDisplay: appState.playerScreen != nil))
                .help("Show the rectangle the players see, and drag it to move their view.")
        }
    }

    // MARK: The Session

    /// Start/Stop Session, in the Live Toolbar.
    ///
    /// Disabled without a Workspace: a Session's log lives in `.mapforge/sessions/`, so there
    /// is nowhere to write without one — the refusal `startEncounter` already makes for a
    /// missing Map.
    ///
    /// Stopping asks first. It did not, on the grounds that "starting again is one click" —
    /// true when a Session was a flag, and false since the Log View, because a restart opens a
    /// new file and the Log View shows only the current one. A misclick now visibly truncates
    /// the evening the DM is reading. Starting is still one click, having nothing to lose.
    /// See `StopSessionPrompt`.
    private var sessionToggle: some View {
        Button(appState.session == nil ? String(localized: "Start Session")
                                       : String(localized: "Stop Session")) {
            if appState.session == nil {
                appState.startSession()
            } else {
                confirmStopSession = true
            }
        }
        .disabled(appState.workspace == nil)
        .accessibilityIdentifier("session-toggle")
        .help(appState.workspace == nil
              ? String(localized: "A Session records into the Workspace. Open one first.")
              : String(localized: "Record this evening's movements and Comments."))
    }

    // MARK: The Log

    /// Opens the Log View in the Map's place.
    ///
    /// Always enabled. Not gated on a Map — an evening belongs to the Workspace and needs no
    /// Map (ADR-0015) — and not gated on a Session either: a disabled button teaches nothing,
    /// where an empty state saying "press Start Session" teaches what fills it.
    ///
    /// Labelled "Log" rather than "Session Log" because this row's own comment warns to keep
    /// it short, and there is nothing else in the window the word could mean. No ellipsis:
    /// in this row it promises a Cancel/Done pair, which a toggle does not have.
    private var logToggle: some View {
        Toggle("Log", isOn: $showingLog)
            .toggleStyle(.button)
            .accessibilityIdentifier("log-toggle")
            .help("Read back over this evening — comments, movements and every Encounter.")
            .onChange(of: showingLog) { _, showing in
                if showing { reloadLog() }
            }
            // Every Line that reaches disk, and every Turn of a live fight — which is held in
            // memory and never touches `sessionLineCount`. Both are no-ops with the Log shut.
            .onChange(of: appState.sessionLineCount) { _, _ in reloadLog() }
            .onChange(of: appState.encounter) { _, _ in reloadLog() }
    }

    /// Rebuilds the evening's rows from the file.
    ///
    /// Wholesale on every append rather than incrementally: the `Session` keeps no lines in
    /// memory — unlike `Encounter` — so the file is the truth, and a Session is a few hundred
    /// lines. Caching finished Encounters is a later optimisation that changes no design
    /// (ADR-0016).
    private func reloadLog() {
        guard showingLog,
              let workspace = appState.workspace,
              let url = appState.sessionLogURL else {
            logRows = []
            return
        }
        logRows = logModel.rows(sessionLogAt: url, workspace: workspace,
                                liveEncounterLines: appState.encounter?.lines ?? [])
    }

    /// `hasEncounter` is read from the Session's own suspension rather than from
    /// `encounter != nil`. The two agree today, but the silence is what the bar is reporting,
    /// and reading it from the flag that enforces it makes the bar a view of the rule instead
    /// of a second computation of the same fact.
    private var commentBarState: CommentBarState {
        CommentBarPolicy.state(
            hasSession: appState.session != nil,
            hasEncounter: appState.session?.isRecordingSuspended == true,
            activeCombatantName: appState.encounter.flatMap { encounter in
                encounter.activeCombatantID.flatMap { encounter.name(of: $0) }
            })
    }

    private func sendComment() {
        guard commentBarState.isEnabled else { return }
        appState.addComment(comment)
        comment = ""
    }

    @ViewBuilder
    private var fogSwitch: some View {
        if !appState.fog.walls.isEmpty || !appState.fog.lights.isEmpty
            || !appState.fog.pawns.isEmpty {
            Toggle("Fog", isOn: $appState.isFogOverlayOn)
                .toggleStyle(.switch)
                // A stable handle for the UI tests. Addressing this by its rendered label
                // is what went stale when the panel was last restructured — and a
                // `.switch` Toggle publishes on macOS as a checkBox, not a switch, which
                // is the other half of why the query missed.
                .accessibilityIdentifier("fog-overlay-switch")
                .help("Hide or reveal the Fog Overlay on the Player Display. Pawns stay visible either way.")
        }
    }

    /// Everything on the Map that can be switched, listed down the side of the preview.
    ///
    /// The panel beside the preview: the Scene as it stands, and the fight being run on it.
    ///
    /// Two tabs rather than one longer scroll, because the two are used at different moments
    /// — the Scene tab is setup and the Combat tab is play — and a DM mid-fight should not
    /// scroll past the roster to reach the Order.
    ///
    /// Both tabs are the same width. A panel that resized when the tab changed would move the
    /// preview beside it, which is the thing `fogInspectorRowHeight` already exists to
    /// prevent; widening once is the calmer answer.
    /// A segmented Picker and a switch rather than a `TabView`.
    ///
    /// `TabView` was the obvious spelling and is the wrong one here: on macOS it disables
    /// its own content in the accessibility tree when it cannot resolve a definite size
    /// from its container, so every control in the panel became unclickable — visibly
    /// present, and inert. The UI tests caught it as "not hittable" at a coordinate that
    /// was plainly inside the window, which is the only reason it was not shipped.
    ///
    /// The segmented Picker is also the control this window already uses to switch the fog
    /// tool, so the panel reads as part of the same app rather than as a document with
    /// tabs.
    @ViewBuilder
    private var livePanel: some View {
        if !appState.fog.lights.isEmpty || !appState.fog.pawns.isEmpty || showsParty {
            VStack(spacing: 8) {
                Picker("", selection: $panelTab) {
                    Label("Scene", systemImage: "map").tag(PanelTab.scene)
                    Label("Encounter", systemImage: "shield.lefthalf.filled").tag(PanelTab.combat)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("panel-tab")

                switch panelTab {
                case .scene: scenePanel
                case .combat: combatPanel
                }
            }
            .frame(width: Self.livePanelWidth)
        }
    }

    /// Which tab the panel is showing.
    ///
    /// Deliberately not persisted: a DM opening MapForge is setting up, not resuming a fight
    /// mid-Turn, so Scene is the right thing to land on every launch.
    enum PanelTab: Hashable {
        case scene
        case combat
    }

    /// Wide enough for an Order row — Initiative, a name, hit points, armour class and a
    /// run of Condition icons — which 236 points could not hold.
    /// 364 rather than 320: the two Roll buttons need about 44 pt, and taking it from the
    /// name column instead would shrink the thing a DM reads fastest in a fight.
    static let livePanelWidth: CGFloat = 364

    /// The narrowest the Map column may get: the width the Setup and Live Toolbars need to
    /// stay on one line each, with a Map worth looking at underneath them.
    ///
    /// 380 was the obvious number — the width `SetupToolbarWidthTests` and `ChromeHeightTests`
    /// have always called "a Control Window narrow enough to be uncomfortable" — and it is
    /// wrong. That figure was only ever checked against the Setup Toolbar's buttons and the
    /// mode hint. The **Live** Toolbar is wider: "Fog", "Measurements", "Viewport" and
    /// "Start Session" are words, and a word that does not fit wraps rather than truncating,
    /// which is how "Measurements" ended up as four stacked lines. It measures 411 pt.
    ///
    /// 420 was that, plus a little room so a Toggle's label growing by a few points does not
    /// immediately re-break the row. Pinned by `testTheLiveToolbarsLabelsFitTheColumnOnOneLine`,
    /// which measures the real row rather than trusting this comment.
    ///
    /// 584 is a larger claim and a different kind of one: not the width a toolbar row stops
    /// wrapping at, but the width below which the Control Window stops being usable for what
    /// it is for — a Map, a live panel and a toolbar at once, while a session runs. It is the
    /// term that carries the window's 1000 pt floor, because it is the term that was
    /// under-specified. See
    /// `docs/adr/0018-the-control-window-has-a-thousand-point-floor.md`.
    static let minimumMapColumnWidth: CGFloat = 584

    /// Both columns, the gap between them and the window's padding.
    ///
    /// Derived rather than typed: a hand-picked total is what let the toolbars and the panel
    /// disagree about how much room there was.
    static let minimumWindowWidth: CGFloat =
        minimumMapColumnWidth + livePanelWidth + columnSpacing + windowPadding * 2

    /// The seam between the panel and the Map column.
    static let columnSpacing: CGFloat = 12

    /// `.padding()`'s default, named so `minimumWindowWidth` can count it.
    static let windowPadding: CGFloat = 20

    /// The Map as it stands: the Party to stamp from, the Lights, and every Pawn on it.
    ///
    /// Vertical and grouped, because the horizontal row this replaces did not survive
    /// contact with a real encounter: a party of four plus a room of goblins ran off the
    /// right-hand edge, and each entry carries a token, a name field and two toggles, so
    /// they are wide. A vertical list gives every row the same shape, lets the names be
    /// read down a column, and turns "which goblin is 3" into a glance.
    ///
    /// The kinds are separated because they are what the DM reasons about separately — the
    /// party is who they are running the world *for*, the Creatures are what they run *at*
    /// them, and the Treasure is what the room is worth. Lights lead because they are the
    /// Map's own furniture rather than anyone's token.
    @ViewBuilder
    private var scenePanel: some View {
        if !appState.fog.lights.isEmpty || !appState.fog.pawns.isEmpty || showsParty {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    // First, above the Lights: it is the palette a session starts from, and
                    // a short drag to the Map is the whole point of it being here rather
                    // than in a window of its own.
                    partyGroup
                    if !appState.fog.lights.isEmpty {
                        liveGroup(String(localized: "Lights"), count: appState.fog.lights.count) {
                            ForEach(Array(appState.fog.lights.enumerated()), id: \.element.id) { index, light in
                                lightLiveRow(light, number: index + 1)
                            }
                        }
                    }
                    // One group per kind, driven by the enum rather than by a filter per
                    // group. Two hand-written filters only partition the array as long as
                    // nobody adds a third kind — which is exactly what happened — and a
                    // Pawn missing from this panel is one the DM cannot hide or rename
                    // mid-fight.
                    ForEach(PawnKind.allCases, id: \.self) { kind in
                        let group = appState.fog.pawns.filter { $0.kind == kind }
                        if !group.isEmpty {
                            liveGroup(kind.pluralTitle, count: group.count) {
                                ForEach(group) { pawnLiveRow($0) }
                            }
                        }
                    }
                }
                .padding(10)
            }
            .frame(width: Self.livePanelWidth)
            // `.controlBackgroundColor` is all but identical to the window's own, so the
            // panel read as text floating beside the Map rather than as a surface. The
            // preview next to it is bordered; this needs to look like its sibling.
            .background(Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        }
    }

    // MARK: Combat

    /// The Initiative Tracker. Its own view rather than another member of this file: it
    /// reads the Encounter and nothing else this window holds, which is the seam issue
    /// 04's Scene extraction turned out not to have.
    private var combatPanel: some View {
        CombatPanel(selection: $selectedCombatant,
                    onRoll: { pawn, kind in rolling = RollTarget(pawn: pawn, kind: kind) })
    }

    // MARK: The Party

    /// Whether the Party group belongs on screen.
    ///
    /// Gated on a Map being open: the roster is a drag source, and offering one with no Map to
    /// drop onto invites a gesture that cannot work. The other groups are already implicitly
    /// gated this way, since fog belongs to a Map.
    ///
    /// Deliberately **not** gated on a Party existing. That is the group's empty state, not a
    /// reason to hide it — hiding it is what made creating a first Party impossible, since the
    /// only way to make one is a button this group draws.
    ///
    /// One property rather than the same condition at the panel and at the group, which have
    /// to agree or the panel draws an empty box beside the preview.
    private var showsParty: Bool { appState.mapURL != nil }

    /// The active Party: its picker, its Characters, and the inline editor.
    ///
    /// Sits above the Lights because it is where a session starts — the DM drags from here
    /// onto the Map rather than clicking the Map and filling in a form.
    ///
    /// Deliberately **not** built with `liveGroup`, which every other group here uses: its
    /// heading is a Menu and an add button rather than a static title, and the roster actions
    /// have nowhere else to live. The body below still matches `liveGroup`'s spacing and
    /// caption weight so the two read as siblings.
    /// Shown in place of the roster when `parties.json` could not be read.
    ///
    /// In place of, not above: while this is up the app refuses to write the roster at all
    /// (`AppState.writeParties`), so a DM who starts typing their party back in is filling a
    /// form that discards every word. Offering the controls anyway is worse than disabling
    /// them, because the DM only finds out at the end of the evening.
    private var damagedRosterWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Your party roster couldn't be read", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(damagedRosterExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Start a New Roster…") { confirmNewRoster = true }
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityIdentifier("party-start-new-roster")
        }
        .accessibilityIdentifier("party-damaged-warning")
    }

    private var damagedRosterExplanation: String {
        guard let path = appState.partyLoadFailure?.url.path else {
            return String(localized: "MapForge hasn't changed the roster file. Changes made here won't be saved until it's fixed or moved aside.")
        }
        return String(localized: "MapForge hasn't changed the file at \(path). Changes made here won't be saved until it's fixed or moved aside.")
    }

    @ViewBuilder
    private var partyGroup: some View {

        if showsParty {
            VStack(alignment: .leading, spacing: 6) {
                if appState.partyLoadFailure != nil {
                    damagedRosterWarning
                } else {
                if let party = appState.activeParty {
                    partyHeader(party)
                } else {
                    emptyPartyHeader
                }
                if let edit = partyNameEdit {
                    partyNameField(edit)
                } else if let party = appState.activeParty {
                    ForEach(party.characters) { character in
                        if editedCharacter?.id == character.id {
                            characterEditor()
                        } else {
                            characterRow(character)
                        }
                    }
                    if isAddingCharacter { characterEditor() }
                }
                }
            }
            .alert("Start a new roster?", isPresented: $confirmNewRoster) {
                Button("Cancel", role: .cancel) {}
                Button("Start New Roster") { appState.setAsideDamagedRoster() }
            } message: {
                Text(newRosterExplanation)
            }
        }
    }

    private var newRosterExplanation: String {
        String(localized: "MapForge will rename the damaged file to “parties.json.damaged” and start an empty roster. Nothing in it is deleted, so you can still open it yourself.")
    }

    /// What the group shows before any Party exists.
    ///
    /// Without this the feature cannot be reached at all: "New Party…" lives in the picker's
    /// menu, the picker is part of `partyHeader`, and `partyHeader` needs a Party — so a DM
    /// with an empty roster had no way to create their first one. The bug was invisible in
    /// testing because every run started from a roster seeded by hand.
    private var emptyPartyHeader: some View {
        HStack(spacing: 6) {
            Text("Party").font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            Button("New Party…") { partyNameEdit = .new("") }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    private func partyHeader(_ party: Party) -> some View {
        HStack(spacing: 6) {
            // A Menu rather than a Picker: it carries the roster actions alongside the
            // choice, and a DM switches Party rarely enough that one control can do both.
            Menu {
                ForEach(appState.partyBook.parties) { candidate in
                    Button {
                        appState.setActiveParty(candidate.id)
                    } label: {
                        // A checkmark rather than a Picker's selection, since this menu also
                        // holds actions and cannot be one.
                        Label(candidate.name,
                              systemImage: candidate.id == party.id ? "checkmark" : "")
                    }
                }
                Divider()
                Button("New Party…") { partyNameEdit = .new("") }
                Button("Rename Party…") {
                    partyNameEdit = .rename(id: party.id, name: party.name)
                }
                Button("Delete Party") { appState.deleteParty(id: party.id) }
            } label: {
                Text(party.name).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 0)
            Text("\(party.characters.count)").font(.caption).foregroundStyle(.secondary)
            Button {
                editedCharacter = PartyCharacter(name: "")
                isAddingCharacter = true
            } label: {
                Image(systemName: "plus").frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help("Add a Character to this Party")
        }
    }

    /// Naming a new Party, or renaming one. Inline rather than a sheet: this app has no
    /// modals, and one text field does not justify introducing the first.
    private func partyNameField(_ edit: PartyNameEdit) -> some View {
        HStack(spacing: 6) {
            TextField("Party name", text: Binding(
                get: { edit.name },
                set: { partyNameEdit = edit.withName($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .onSubmit { commitPartyName() }
            Button("OK") { commitPartyName() }
                .buttonStyle(.borderless)
                .disabled(edit.name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel") { partyNameEdit = nil }
                .buttonStyle(.borderless)
        }
    }

    private func commitPartyName() {
        guard let edit = partyNameEdit else { return }
        let name = edit.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        switch edit {
        case .new: appState.addParty(named: name)
        case .rename(let id, _): appState.renameParty(id: id, to: name)
        }
        partyNameEdit = nil
    }

    /// One Character in the roster: what it looks like on the Map, its name, and how many of
    /// its Pawns are already standing on this one.
    ///
    /// The whole row is the drag source. Dropping it on the Map Stamps a Pawn — see
    /// `Stamp` and ADR 0007.
    private func characterRow(_ character: PartyCharacter) -> some View {
        let placed = appState.placedCount(of: character)
        return HStack(spacing: 6) {
            PawnToken(pawn: Stamp.preview(of: character), squareSide: 14,
                      scalesWithFootprint: false)
            Text(character.name).lineLimit(1)
            Spacer(minLength: 0)
            if placed > 0 {
                // Decoration, never a constraint: duplicates are deliberate, and this is
                // what makes an accidental second drop visible without forbidding a summon.
                Text("×\(placed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("\(placed) on this Map")
            }
        }
        .contentShape(Rectangle())
        .draggable(CharacterDragPayload(characterID: character.id)) {
            // The drag preview, which macOS renders under the cursor. This one DOES scale
            // with the footprint, unlike the row's token: it is headed for the Map, where a
            // Big Pawn's two squares are the thing the DM is judging the drop against.
            PawnToken(pawn: Stamp.preview(of: character), squareSide: 20)
        }
        .contextMenu {
            Button("Edit…") {
                editedCharacter = character
                isAddingCharacter = false
            }
            Button("Delete") { appState.deleteCharacter(id: character.id) }
        }
    }

    /// The inline editor for a Character, new or existing. The same four fields the
    /// `pawnInspector` uses, stacked to fit the panel's 236pt.
    @ViewBuilder
    private func characterEditor() -> some View {
        if let character = editedCharacter {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: bindingForCharacter(\.name))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitCharacter() }
                HStack(spacing: 6) {
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: character.colorHex) ?? .red },
                        set: { editedCharacter?.colorHex = $0.hexString }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    Text("Sight:").font(.caption)
                    // Bridged through Double as `pawnInspector` does: CGFloat is not a
                    // parseable format type.
                    TextField("", value: Binding(
                        get: { Double(character.sightSquares) },
                        set: { editedCharacter?.sightSquares = CGFloat($0) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)
                    Toggle("Big", isOn: bindingForCharacter(\.isBig))
                        .toggleStyle(.checkbox)
                }
                // The combat numbers. A Character has carried these since the Party
                // existed and the Stamp has always copied them, but nothing could type
                // them — so every Stamped Pawn arrived at +0 / AC 10 / no hit points, and
                // the DM filled them in again on the Map at every encounter. That is the
                // exact retyping the Party exists to stop.
                //
                // Only these three. Conditions, exhaustion and temporary hit points are
                // things that happen on a Map, and a Character has never been on one —
                // the split `Stamp.statBlock(from:)` already reasons about.
                HStack(spacing: 6) {
                    Text("Initiative:").font(.caption)
                    TextField("", value: bindingForCharacter(\.initiativeBonus),
                              format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 36)
                        .accessibilityIdentifier("character-initiative-bonus")
                    Text("AC:").font(.caption)
                    TextField("", value: bindingForCharacter(\.armorClass), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 36)
                        .accessibilityIdentifier("character-armor-class")
                    Text("HP:").font(.caption)
                    // The only optional of the three, and it stays optional all the way to
                    // the field: a Character sketched in without hit points has none, and a
                    // 0 there would read as "already unconscious". An empty field means
                    // absent, which is what `.number` gives back for a nil Int?.
                    TextField("", value: bindingForCharacter(\.maxHP), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 44)
                        .accessibilityIdentifier("character-max-hp")
                }
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Button("Cancel") { cancelCharacterEdit() }
                        .buttonStyle(.borderless)
                    Button("Save") { commitCharacter() }
                        .buttonStyle(.borderless)
                        .disabled(character.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private func bindingForCharacter<Value>(
        _ keyPath: WritableKeyPath<PartyCharacter, Value>
    ) -> Binding<Value> {
        Binding(
            get: { editedCharacter?[keyPath: keyPath] ?? PartyCharacter(name: "")[keyPath: keyPath] },
            set: { editedCharacter?[keyPath: keyPath] = $0 }
        )
    }

    private func commitCharacter() {
        guard var character = editedCharacter else { return }
        character.name = character.name.trimmingCharacters(in: .whitespaces)
        guard !character.name.isEmpty else { return }
        if isAddingCharacter {
            appState.addCharacter(character)
        } else {
            appState.updateCharacter(character)
        }
        cancelCharacterEdit()
    }

    private func cancelCharacterEdit() {
        editedCharacter = nil
        isAddingCharacter = false
    }

    /// One titled group in the side panel. The count is in the heading so the DM can see
    /// "Creatures 6" without counting rows.
    private func liveGroup<Content: View>(_ title: String, count: Int,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold))
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
    }

    /// One Light in the side panel. A Light has no label of its own, so it is identified
    /// by its position in the list, exactly as it was in the row this replaces.
    private func lightLiveRow(_ light: Light, number: Int) -> some View {
        HStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { light.isOn },
                set: { setLight(id: light.id, isOn: $0) }
            )) {
                Image(systemName: light.isOn ? "flame.fill" : "flame")
                    .frame(width: 16)
            }
            .toggleStyle(.button)
            // A symbol-only button publishes as its symbol name, which changes as the
            // Light does. The identifier does not.
            .accessibilityIdentifier("light-toggle-\(number)")

            // Editable in place, as a Pawn's label is in its own row. The placeholder is
            // the old positional name, so a Light placed before names existed still reads
            // sensibly — and a DM who clears the field gets that fallback back rather than
            // a blank row.
            // The placeholder is what an unnamed Light is *called*, and the only unnamed
            // Lights are those placed before names existed — so it uses the position, as
            // the roster always did. It is deliberately not `Light.nextName`, which answers
            // a different question: what to call the NEXT Light placed.
            TextField("Light \(number)", text: Binding(
                get: { light.name ?? "" },
                set: { setLightName(id: light.id, $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .lineLimit(1)
            .frame(minWidth: 0)
            Spacer(minLength: 0)
            Text("\(Int(light.brightSquares))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Bright \(Int(light.brightSquares)), dim \(Int(light.dimSquares)) squares")
        }
    }

    /// Shown when a Map's fog file exists but could not be read. Silence here is the
    /// dangerous case: the DM would see a Map with no Walls, assume none were ever drawn,
    /// redraw them, and the next save would overwrite the file that still holds the
    /// originals. The path is spelled out so they can recover it by hand.
    @ViewBuilder
    private var fogLoadWarning: some View {
        if let failure = appState.fogLoadFailure {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Could not read this Map's fog — its Walls and Lights are not shown.")
                    Text("\(failure.url.path) — drawing over this Map will replace it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: Player Display

    /// The screen picker, which rides in the Setup Toolbar's first row beside "Open Map…".
    ///
    /// Split from the warnings below it so it can move without taking them along: they say
    /// "above", and they are only true where they sit — under the row the picker is in.
    /// Choosing the Player Display is setup, done once when the HDMI cable goes in, which is
    /// why it belongs next to opening a Map rather than on a line of its own.
    private var playerDisplayPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: appState.playerScreen == nil ? "tv.slash" : "tv")
                .foregroundStyle(appState.playerScreen == nil ? Color.secondary : Color.green)
            Picker("Player Display", selection: playerDisplaySelection) {
                Text("None — not presenting").tag(DisplayIdentity?.none)
                ForEach(appState.displayCandidates, id: \.identity) { candidate in
                    Text(label(for: candidate)).tag(DisplayIdentity?.some(candidate.identity))
                }
            }
            .labelsHidden()
            .frame(maxWidth: Self.playerDisplayPickerWidth)
        }
    }

    /// Was 420, when the picker had a row to itself.
    ///
    /// Sharing the row with "Open Map…", the file name and the Workspace button, a picker
    /// that wide pushes the rest off a narrow window — the same defect the `modeControls`
    /// row's comment records from when a "Grid squares wide" field shared it. The file name
    /// truncates, so this is the row's one hard width claim.
    static let playerDisplayPickerWidth: CGFloat = 220

    /// What the picker has to warn about, on the line the picker used to occupy.
    @ViewBuilder
    private var playerDisplayStatus: some View {
        // Presented, but EDID reports no physical size: True Scale is a guess until
        // Calibration. Said plainly rather than hiding the screen from the picker.
        if appState.playerScreen != nil, appState.playerMetrics == nil {
            Label("Physical size unknown — True Scale unverified on this display",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if appState.displayCandidates.count > 1,
           appState.displayCandidates.allSatisfy(\.isBuiltin) == false,
           appState.playerScreen == nil {
            // Says what to choose, not where the picker is: "above" went stale the day it moved.
            Label("Multiple displays connected — choose the display that shows the Map to the players",
                  systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var playerDisplaySelection: Binding<DisplayIdentity?> {
        Binding(
            get: { appState.playerScreen?.displayIdentity },
            set: { if let identity = $0 { appState.chooseDisplay(identity) } }
        )
    }

    /// Resolution and physical size, so two identical TVs are told apart by text.
    private func label(for candidate: DisplayCandidate) -> String {
        var parts = [candidate.identity.name]
        if candidate.isBuiltin { parts.append(String(localized: "(built-in)")) }
        if let metrics = candidate.metrics {
            parts.append("— \(Int(metrics.pixelSize.width))×\(Int(metrics.pixelSize.height)) px")
            parts.append("\(Int(metrics.physicalSizeMM.width))×\(Int(metrics.physicalSizeMM.height)) mm")
        } else {
            parts.append(String(localized: "— size unknown"))
        }
        return parts.joined(separator: " ")
    }
}
