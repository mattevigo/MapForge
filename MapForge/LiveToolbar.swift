import SwiftUI

/// The **Live Toolbar** (`CONTEXT.md`): the row of switches above the Map that change what the
/// table experiences, now — the Fog, Measurements, Health Bars, the Viewport, Map Fit — and the
/// Session control pushed to its far end.
///
/// Its own view, rather than a stretch of `ControlView`'s body, so that
/// `SetupToolbarWidthTests` can host the row exactly as the window builds it. A hand-built copy
/// of it is what let the Health Bars switch overflow the Map column unnoticed: the copy had
/// no Map Fit, and drew the Fog switch as a checkbox.
struct LiveToolbar: View {
    @EnvironmentObject private var appState: AppState

    /// Whether the preview is in the Live View rather than Grid Fit or the Wall Editor. The
    /// Viewport and Map Fit controls are drawn only there — see `viewportToggle`.
    let isLiveView: Bool
    @Binding var isShowingViewport: Bool
    /// Whether the Map is larger than the screen at True Scale — `ControlView` works it out,
    /// for `ViewportToggle`.
    let mapOverflowsViewport: Bool
    /// Raised to ask before a Session stops; `ControlView` owns the alert.
    @Binding var confirmStopSession: Bool

    var body: some View {
        HStack(spacing: 16) {
            fogSwitch
            measurementVisibilitySwitch
            healthBarVisibilitySwitch
            viewportToggle
            mapFitToggle
            Spacer()
            sessionToggle
        }
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

    /// Whether the table sees any Health Bar (ADR-0036).
    ///
    /// Beside Measurements and built like it, because it is the same kind of decision: what
    /// the Player Display shows right now, never persisted. Always present for the same
    /// reasons — a DM hides the bars before the reveal, not after — and on by default, the
    /// ADR's case. A single Pawn's bar is withheld on its Stat Block instead.
    ///
    /// A glyph, not a word, unlike Measurements: with a "Health Bars" checkbox the row
    /// measured 645 pt against a Map column that can be 584, and that floor is ADR-0018's,
    /// not this switch's to spend. Borderless too, because a bordered glyph still left the
    /// row 9 pt over. So the glyph carries the state on its own — a filled heart in the
    /// accent colour while the table sees the bars, a grey slashed one when it does not —
    /// and the words live on in the tooltip and the accessibility label.
    private var healthBarVisibilitySwitch: some View {
        let isOn = appState.areHealthBarsOn
        return Toggle(isOn: $appState.areHealthBarsOn) {
            Image(systemName: isOn ? "heart.fill" : "heart.slash")
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 16)
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .accessibilityLabel("Health Bars")
        .accessibilityIdentifier("health-bar-visibility-switch")
        .help("Show each Pawn's Health Bar on the Player Display. Off, the table sees no bars.")
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
    /// Unavailable under Map Fit, where the rectangle covers the whole Map and there is
    /// nothing to drag it to; its help says so (`ViewportToggle.explanation`) rather than
    /// leaving the DM to guess why.
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
        if isLiveView {
            Toggle("Viewport", isOn: $isShowingViewport)
                .toggleStyle(.button)
                .disabled(!ViewportToggle.isAvailable(mapOverflows: mapOverflowsViewport,
                                                      hasDisplay: appState.playerScreen != nil,
                                                      isMapFitOn: appState.isMapFitOn))
                .help(ViewportToggle.explanation(isMapFitOn: appState.isMapFitOn).text)
        }
    }

    /// **Map Fit**, beside the Viewport toggle and shown on the same terms: in the Live View
    /// only, so it costs this row width and never height, as `viewportToggle` explains.
    ///
    /// Disabled without a Player Display: there is no screen to fit the Map to, and losing
    /// the screen while fitted switches Map Fit off (`MapFitToggle`). Not persisted — see
    /// `AppState.isMapFitOn`.
    @ViewBuilder
    private var mapFitToggle: some View {
        if isLiveView {
            Toggle("Map Fit", isOn: $appState.isMapFitOn)
                .toggleStyle(.button)
                .disabled(!MapFitToggle.isAvailable(hasDisplay: appState.playerScreen != nil))
                .help("Show the whole Map on the Player Display, as large as it fits, ignoring the Grid.")
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
}
