import SwiftUI
import AppKit

/// The app's front door: which game are we running out of tonight?
///
/// A sheet over the Control Window rather than a launch window of its own. The single `Window`
/// scene terminates the app when it closes, and the same sheet has to serve mid-session
/// switching — so a second scene would have nowhere to go the second time it was needed.
struct WorkspacePickerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Whether there is a Workspace behind this sheet. When there is not, the sheet cannot be
    /// dismissed: there is nothing behind it to use.
    var isSwitching: Bool

    @State private var adopting: URL?
    @State private var refusal: String?

    private let store = WorkspaceStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if appState.recentWorkspaces.isEmpty {
                empty
            } else {
                recents
            }

            HStack {
                Button("Choose Workspace…") { choose() }
                    .keyboardShortcut(.defaultAction)
                Spacer()
                if isSwitching {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .alert("Set up this folder as a workspace?",
               isPresented: .init(get: { adopting != nil },
                                  set: { if !$0 { adopting = nil } })) {
            Button("Cancel", role: .cancel) { adopting = nil }
            Button("Set Up") {
                if let url = adopting { adopt(url) }
                adopting = nil
            }
        } message: {
            Text("""
            \(adopting?.lastPathComponent ?? "This folder") isn't a MapForge workspace yet. \
            MapForge will create a “.mapforge” folder inside it for your parties and settings.

            Your maps won't be changed.
            """)
        }
        .alert("Can't open this workspace",
               isPresented: .init(get: { refusal != nil },
                                  set: { if !$0 { refusal = nil } })) {
            Button("OK") { refusal = nil }
        } message: {
            Text(refusal ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Choose a Workspace").font(.headline)
            Text("The folder your maps live in. MapForge keeps your parties and settings there.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var empty: some View {
        Text("No workspaces yet.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(appState.recentWorkspaces, id: \.self) { url in
                row(for: url)
                Divider()
            }
        }
        .frame(maxHeight: 220)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func row(for url: URL) -> some View {
        // An entry whose folder is gone stays listed and unselectable. The DM should see that
        // the drive is unplugged, not that their campaign has disappeared.
        let available = store.isWorkspace(url)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .foregroundStyle(available ? .primary : .secondary)
                Text(available ? url.deletingLastPathComponent().path : "not available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !available {
                Button("Forget") { appState.forgetWorkspace(url) }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("workspace-forget")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if available { openExisting(url) } }
        .accessibilityIdentifier("workspace-recent")
        .accessibilityAddTraits(available ? [.isButton] : [])
    }

    // MARK: - Actions

    /// One gesture. Pick a folder; if it is already a Workspace it opens, and if it is not the
    /// app offers to make it one. The two differ only in whether the folder has been adopted,
    /// which the app can see for itself.
    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        switch store.open(url) {
        case .success(let workspace):
            open(workspace)
        case .failure(.notAWorkspace):
            adopting = url
        case .failure(.unreachable):
            refusal = "That folder couldn't be reached."
        case .failure(.unreadableManifest):
            // Never offer to adopt over it: adoption is a write, and the file we could not
            // read is the one we would destroy.
            refusal = """
            This folder has a damaged MapForge workspace file. MapForge hasn't changed it. \
            Move “.mapforge/workspace.json” aside to set the folder up again.
            """
        case .failure(.newerVersion(_, let found)):
            refusal = """
            This workspace was made by a newer version of MapForge (format \(found)). \
            Update MapForge to open it.
            """
        }
    }

    private func openExisting(_ url: URL) {
        switch store.open(url) {
        case .success(let workspace): open(workspace)
        case .failure: refusal = "That workspace couldn't be opened."
        }
    }

    private func adopt(_ url: URL) {
        guard let workspace = try? store.adopt(url) else {
            refusal = "MapForge couldn't set that folder up."
            return
        }
        open(workspace)
    }

    private func open(_ workspace: Workspace) {
        appState.open(workspace)
        dismiss()
    }
}
