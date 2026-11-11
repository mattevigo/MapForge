import SwiftUI

/// Which of its three states the Comment Bar is in.
///
/// The bar is the only control that enforces the boundary between preparing a Map and running
/// a Session — nothing in the Setup Toolbar is disabled by a Session, deliberately, because a
/// DM sometimes must trace a wall mid-evening. So this decision carries the whole of that
/// boundary, and it is a value rather than a tangle of `if`s inside a view.
enum CommentBarState: Equatable {
    /// Before a Session: there is nowhere for a Comment to land.
    case noSession
    /// During a Session: the Session Log is open and the field is live.
    case recording
    /// During a fight inside a Session: the Session Log has handed over and the Combat tab's
    /// note box is the live one. See ADR-0014.
    case duringEncounter(activeCombatantName: String?)

    var isEnabled: Bool {
        if case .recording = self { return true }
        return false
    }

    /// What the field says it is. The only text the bar has room for, and the reason the
    /// state needs no caption row of its own — a second row below the Map would cost the
    /// height that `ChromeHeightTests` exists to protect above it.
    var placeholder: String {
        switch self {
        case .noSession:
            return String(localized: "Start the session to record")
        case .recording:
            return String(localized: "what happened")
        case let .duringEncounter(name):
            guard let name else {
                return String(localized: "During an Encounter — use the Encounter tab")
            }
            return String(localized: "Note on \(name)'s Turn — use the Encounter tab")
        }
    }
}

enum CommentBarPolicy {
    /// A fight only silences the bar *inside* a Session. With no Session running, "start the
    /// session" is the honest instruction whether or not a fight happens to be going.
    static func state(hasSession: Bool, hasEncounter: Bool,
                      activeCombatantName: String?) -> CommentBarState {
        guard hasSession else { return .noSession }
        guard hasEncounter else { return .recording }
        return .duringEncounter(activeCombatantName: activeCombatantName)
    }
}

/// The full-width row beneath the Map: one text field, one send button.
///
/// **Fixed height in all three states.** `preview` claims whatever the stack leaves it, so a
/// bar that grew when a fight started would resize the Map mid-click — the defect
/// `ChromeHeightTests` guards for the rows above the preview, arriving from below it. Hence a
/// one-line `TextField` with no `axis: .vertical`, unlike `StatEditor`'s note box which grows
/// to three lines.
///
/// No scrollback, for the same reason: it would either eat vertical space permanently or
/// resize the Map as lines arrived.
struct CommentBar: View {
    let state: CommentBarState
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField(state.placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .accessibilityIdentifier("comment-field")
                .onSubmit(onSubmit)
                .keepsKeyboardOnReturn()
            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("send-comment")
            // Greyed with the field rather than hidden: a disabled button says "this will
            // work later", a missing one says "this does not exist here".
            .disabled(!state.isEnabled || text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .disabled(!state.isEnabled)
    }
}
