import AppKit
import SwiftUI

/// MapForge › Settings… (⌘,): what this Mac prefers, whichever Workspace is open.
///
/// Tabbed from the start although General is its only tab: Distance Unit belongs here when it
/// becomes a choice, and a window that grows a tab bar later moves every control in it.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 440)
    }
}

/// The Interface Language, and the relaunch it waits for.
///
/// A choice applies at the next launch rather than live: the app's words are resolved once, at
/// launch, and a relaunch loses nothing — a Session and an Encounter both survive quitting.
private struct GeneralSettings: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Picker("Language", selection: $appState.interfaceLanguage) {
                ForEach(InterfaceLanguage.allCases) { language in
                    Text(language.name).tag(language)
                }
            }
            .accessibilityIdentifier("interface-language")

            if let next = InterfaceLanguage.nextLaunch(chosen: appState.interfaceLanguage,
                                                       running: runningLanguage,
                                                       macLanguages: macLanguages) {
                HStack {
                    Text("MapForge will use \(next.name) the next time it opens.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Relaunch Now", action: relaunch)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The localisation this launch resolved to — what is on screen now.
    private var runningLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// The Mac's own language list, from the global domain: through `UserDefaults.standard`
    /// the app's own choice would answer instead.
    private var macLanguages: [String] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[
            "AppleLanguages"] as? [String] ?? Locale.preferredLanguages
    }

    /// Opens a fresh instance and quits this one, through the same path ⌘Q takes.
    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

extension InterfaceLanguage {
    /// How the picker names it: each language in itself, so a DM who cannot read the current
    /// one can still find their own. Only "System" is translated.
    var name: String {
        switch self {
        case .system: String(localized: "System")
        case .english: "English"
        case .italian: "Italiano"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        case .portuguese: "Português (Brasil)"
        case .greek: "Ελληνικά"
        }
    }
}
