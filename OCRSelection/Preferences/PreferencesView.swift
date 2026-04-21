import KeyboardShortcuts
import ServiceManagement
import SwiftData
import SwiftUI

struct PreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("historyMaxCount") private var maxCount: Int = 30
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }

            Divider()

            Section("Shortcut") {
                LabeledContent("Capture Area") {
                    KeyboardShortcuts.Recorder(for: .captureRegion)
                }
                Button("Reset to Default") {
                    KeyboardShortcuts.reset(.captureRegion)
                }
            }

            Divider()

            Section("History") {
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
                Button("Clear History", role: .destructive) {
                    clearHistory()
                }
            }

            Divider()

            Section("About") {
                LabeledContent {
                    Link(destination: URL(string: "https://leodurand.com")!) {
                        Text(verbatim: "leodurand.com")
                    }
                } label: {
                    Text("Designed by")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 440)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: launchAtLogin) { _, newValue in
            updateLoginItem(enabled: newValue)
        }
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { Double(maxCount) },
            set: { maxCount = Int($0) }
        )
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

    private func clearHistory() {
        try? modelContext.delete(model: OCREntry.self)
        try? modelContext.save()
    }
}
