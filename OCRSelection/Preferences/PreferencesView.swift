import KeyboardShortcuts
import ServiceManagement
import SwiftData
import SwiftUI

struct PreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.historyMaxCountKey) private var maxCount: Int = AppSettings.historyMaxCountDefault
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .help(Text("Start OCR Selection automatically when you log in."))
            }

            Section("Shortcut") {
                LabeledContent("Capture Area") {
                    KeyboardShortcuts.Recorder(for: .captureRegion)
                }
                .help(Text("Global keyboard shortcut to start a capture from anywhere."))
                HStack {
                    Spacer()
                    Button("Reset to Default") {
                        KeyboardShortcuts.reset(.captureRegion)
                    }
                    .help(Text("Restore the default shortcut (⌘⇧2)."))
                }
            }

            Section("History") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Entries kept: \(maxCount)")
                    Slider(
                        value: sliderBinding,
                        in: Double(AppSettings.historyMaxCountRange.lowerBound)...Double(AppSettings.historyMaxCountRange.upperBound),
                        step: Double(AppSettings.historyMaxCountStep)
                    ) {
                        Text("Entries kept")
                    } minimumValueLabel: {
                        Text(verbatim: "\(AppSettings.historyMaxCountRange.lowerBound)")
                    } maximumValueLabel: {
                        Text(verbatim: "\(AppSettings.historyMaxCountRange.upperBound)")
                    }
                    .labelsHidden()
                    .accessibilityLabel(Text("Entries kept"))
                    .accessibilityValue(Text("\(maxCount)"))
                    .help(Text("Maximum number of captures kept in history."))
                }
                HStack {
                    Spacer()
                    Button("Clear History", role: .destructive) {
                        clearHistory()
                    }
                    .help(Text("Remove all captures from history."))
                }
            }

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
        .frame(width: 480, height: 500)
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
