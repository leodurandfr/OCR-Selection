import KeyboardShortcuts
import ServiceManagement
import SwiftData
import SwiftUI

struct PreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("historyMaxCount") private var maxCount: Int = 30
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            generalSection
            Divider()
            shortcutSection
            Divider()
            historySection
            Divider()
            aboutSection
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: launchAtLogin) { _, newValue in
            updateLoginItem(enabled: newValue)
        }
    }

    private var generalSection: some View {
        section("General") {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .help(Text("Start OCR Selection automatically when you log in."))
        }
    }

    private var shortcutSection: some View {
        section("Shortcut") {
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
    }

    private var historySection: some View {
        section("History") {
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
    }

    private var aboutSection: some View {
        section("About") {
            LabeledContent {
                Link(destination: URL(string: "https://leodurand.com")!) {
                    Text(verbatim: "leodurand.com")
                }
            } label: {
                Text("Designed by")
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
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
