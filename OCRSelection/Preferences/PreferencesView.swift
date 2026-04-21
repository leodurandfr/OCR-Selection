import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ShortcutSettingsView()
                .tabItem {
                    Label("Shortcut", systemImage: "command")
                }

            HistorySettingsView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
        }
        .tabViewStyle(.automatic)
        .frame(width: 480, height: 260)
    }
}

private struct GeneralSettingsView: View {
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: launchAtLogin) { _, newValue in
            updateLoginItem(enabled: newValue)
        }
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Failed to toggle launch at login: \(error.localizedDescription)")
        }
    }
}

private struct ShortcutSettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Capture Area") {
                KeyboardShortcuts.Recorder(for: .captureRegion)
            }

            Button("Reset to Default") {
                KeyboardShortcuts.reset(.captureRegion)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HistorySettingsView: View {
    var body: some View {
        Text(verbatim: "History settings — coming in Phase 9")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
