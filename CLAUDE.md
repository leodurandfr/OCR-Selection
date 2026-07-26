# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**OCR Selection** is a macOS menu-bar utility (a free TextSniper equivalent): press a global shortcut (default ⌘⇧2), drag-select a screen region, and the recognized text lands on the clipboard. Menu-bar only — `LSUIElement = YES`, so there is no Dock icon or main window. Targets macOS 14.0+. Distributed via **Developer ID** (the native `screencapture` dependency keeps it out of the sandboxed Mac App Store).

## Build / test / run

This is an Xcode project (not SwiftPM). Scheme: `OCRSelection`; test target: `OCRSelectionTests`.

```bash
# Build
xcodebuild -scheme OCRSelection -destination 'platform=macOS' build

# Run all tests
xcodebuild -scheme OCRSelection -destination 'platform=macOS' test

# Run a single test (Swift Testing path: Target/Suite/method)
xcodebuild -scheme OCRSelection -destination 'platform=macOS' test \
  -only-testing:OCRSelectionTests/HistoryServiceTests/pruningEnforcesMaxCount
```

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — *not* XCTest. Match that style for new tests. To run the app interactively, build & run the `OCRSelection` scheme from Xcode (⌘R) — capture and the global shortcut can't be exercised from a headless `xcodebuild` run.

Sole external dependency: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (SwiftPM, 2.4.0+), resolved by Xcode.

## Architecture

`AppDelegate` (wired via `@NSApplicationDelegateAdaptor` in `OCRSelectionApp`) is the composition root: it builds the SwiftData `ModelContainer` (via `HistoryContainer.make()`), constructs the single `HistoryStore` and `CaptureCoordinator`, registers the `historyMaxCount` default, starts `HealthMonitor`, and binds the global shortcut to `coordinator.run()`. The SwiftUI side is just two scenes — `MenuBarExtra` and `Settings` — and **neither touches SwiftData**: both read the `HistoryStore` snapshot. A container failure logs and falls back to an in-memory store rather than `fatalError`.

**The capture pipeline lives entirely in [CaptureCoordinator](OCRSelection/CaptureCoordinator.swift).** Its `run()` is the one place that orchestrates the stateless service structs and owns all error handling, mapping typed errors to user-facing outcomes:

```
ScreenCaptureService → OCRService → PasteboardService → HistoryService → NotificationService
```

Each service is a small `@MainActor struct` conforming to a protocol seam in [OCRSelection/Capture/](OCRSelection/Capture/) (`ScreenCapturing`, `TextRecognizing`, `Pasteboarding`, `Notifying`, `HistoryRecording`, `PermissionPresenting`), so `CaptureCoordinator` can be driven with stubs in `CaptureCoordinatorTests`. Notable behaviors:

- **[ScreenCaptureService](OCRSelection/Services/ScreenCaptureService.swift)** shells out to `/usr/sbin/screencapture -i <tmpfile>` (Apple's native region selection) and decodes the PNG from that temp file, which is deleted on the way out. Outcomes: no file + preflight fails → `CaptureError.permissionDenied`; no file + empty stderr → `userCancelled` (Esc); otherwise success. It deliberately does **not** use `-c`: routing the image through `NSPasteboard` meant deep-copying and restoring the user's entire clipboard on the main thread around every capture (hundreds of MB when a large image was on it), and briefly exposed the screenshot to clipboard managers. This CLI dependency is *why App Sandbox is disabled* — the app ships via Developer ID. A ScreenCaptureKit + custom-overlay migration (needed for the sandboxed App Store) was prototyped and dropped in favour of Apple's superior native selection UI.
- **[OCRService](OCRSelection/Services/OCRService.swift)** runs Vision's `VNRecognizeTextRequest` (`.accurate`, auto language detection + correction). `assembleText` groups observations into lines top-to-bottom by `boundingBox.midY`, then orders each line left-to-right by `minX`, so multi-column / same-line text isn't scrambled.
- **History** is three pieces. [HistoryContainer](OCRSelection/Support/HistoryContainer.swift) builds the store at `~/Library/Application Support/OCRSelection/History.store` (a bare `ModelContainer(for:)` defaults to `default.store` in the *shared* Application Support root; a store found there is migrated once, then deleted) and sets `mainContext.autosaveEnabled = false` — the autosave timer saved on the main thread and was the heaviest stack in a `cpu_resource` report. [HistoryService](OCRSelection/Services/HistoryService.swift) owns every `ModelContext` call; `record` prunes past `historyMaxCount` (a `UserDefaults` key, default 30, user-adjustable 10–50) using `fetchOffset` so only doomed rows are fetched. [HistoryStore](OCRSelection/Services/HistoryStore.swift) is the `@Observable` snapshot of `HistoryItem` values the UI renders. **Do not put `@Query` in the `MenuBarExtra`**: its body is re-evaluated far more often than the menu is opened, and each evaluation meant a SwiftData fetch. `OCREntry` is the lone SwiftData `@Model`.

## Diagnostics

The app is instrumented for after-the-fact debugging of intermittent slowdowns ([PerfLog.swift](OCRSelection/Support/PerfLog.swift)). Everything diagnostic is logged at `.notice` or `.error` — `.info`/`.debug` are not persisted to disk and are useless the next morning. Never log recognised text, only lengths.

```bash
# What the app recorded (per-capture timings + 60s health heartbeat)
log show --last 1d --predicate 'subsystem == "com.leodurand.ocr-selection"' --style compact
```

`HealthMonitor` writes one heartbeat per minute: `mem=` (phys_footprint) exposes a leak, `menuRenders=` exposes a SwiftUI render storm, `lag=` and gaps between heartbeats expose a blocked main thread.

The app can't log while it is wedged, so for anything the heartbeat can't explain, use what macOS collects on its own — `*.cpu_resource.diag` microstackshot reports land in `/Library/Logs/DiagnosticReports/` when a process exceeds 50% CPU over 180s, and `JetsamEvent-*.ips` there records footprints at memory-pressure kills. Live, on a misbehaving process: `sample OCRSelection 10 -f /tmp/ocr.txt` and `footprint OCRSelection` (both work on the Developer ID build without root).

## Conventions

- **Localized strings**: all user-facing text goes through `String(localized:)` / SwiftUI auto-localization, backed by `Localizable.xcstrings`. Supported languages: **EN, FR, ES** — add new strings to all three. Source-comment language is mixed (some French); follow the file you're editing.
- Bundle ID `com.leodurand.ocr-selection`; copyright/about links point at leodurand.com.
- Preferences "Launch at login" uses `SMAppService.mainApp`.
