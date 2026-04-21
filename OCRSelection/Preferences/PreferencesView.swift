import KeyboardShortcuts
import ServiceManagement
import SwiftData
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
    @Environment(\.modelContext) private var modelContext
    @AppStorage("historyMaxCount") private var maxCount: Int = 30

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { Double(maxCount) },
            set: { maxCount = Int($0) }
        )
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Entries kept: \(maxCount)")
                    Slider(value: sliderBinding, in: 10...50, step: 5) {
                        Text("Entries kept")
                    } minimumValueLabel: {
                        Text(verbatim: "10")
                    } maximumValueLabel: {
                        Text(verbatim: "50")
                    }
                    .labelsHidden()
                }
            }

            Button("Clear History", role: .destructive) {
                clearHistory()
            }
        }
        .formStyle(.grouped)
    }

    private func clearHistory() {
        try? modelContext.delete(model: OCREntry.self)
        try? modelContext.save()
    }
}
