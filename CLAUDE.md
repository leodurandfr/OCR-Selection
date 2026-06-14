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

`AppDelegate` (wired via `@NSApplicationDelegateAdaptor` in `OCRSelectionApp`) is the composition root: it builds the SwiftData `ModelContainer`, constructs the single `CaptureCoordinator`, registers the `historyMaxCount` default, and binds the global shortcut to `coordinator.run()`. The SwiftUI side is just two scenes — `MenuBarExtra` and `Settings` — both handed the shared `ModelContainer`.

**The capture pipeline lives entirely in [CaptureCoordinator](OCRSelection/CaptureCoordinator.swift).** Its `run()` is the one place that orchestrates the stateless service structs and owns all error handling, mapping typed errors to user-facing outcomes:

```
ScreenCaptureService → OCRService → PasteboardService → HistoryService → NotificationService
```

Each service is a small `@MainActor struct` conforming to a protocol seam in [OCRSelection/Capture/](OCRSelection/Capture/) (`ScreenCapturing`, `TextRecognizing`, `Pasteboarding`, `Notifying`, `HistoryRecording`, `PermissionPresenting`), so `CaptureCoordinator` can be driven with stubs in `CaptureCoordinatorTests`. Notable behaviors:

- **[ScreenCaptureService](OCRSelection/Services/ScreenCaptureService.swift)** shells out to `/usr/sbin/screencapture -i -c` (Apple's native region selection) and reads the image back off `NSPasteboard`, snapshotting and restoring the user's clipboard around the capture so a cancelled/failed OCR can't clobber it. It distinguishes outcomes by comparing the pasteboard's `changeCount` before/after: unchanged + preflight fails → `CaptureError.permissionDenied`; unchanged + empty stderr → `userCancelled` (Esc); otherwise success. This CLI dependency is *why App Sandbox is disabled* — the app ships via Developer ID. A ScreenCaptureKit + custom-overlay migration (needed for the sandboxed App Store) was prototyped and dropped in favour of Apple's superior native selection UI.
- **[OCRService](OCRSelection/Services/OCRService.swift)** runs Vision's `VNRecognizeTextRequest` (`.accurate`, auto language detection + correction). `assembleText` groups observations into lines top-to-bottom by `boundingBox.midY`, then orders each line left-to-right by `minX`, so multi-column / same-line text isn't scrambled.
- **[HistoryService](OCRSelection/Services/HistoryService.swift)** is `@MainActor` (it touches `container.mainContext`); on each `record` it prunes oldest entries beyond `historyMaxCount` (a `UserDefaults` key, default 30, user-adjustable 10–50). `OCREntry` is the lone SwiftData `@Model`.

## Conventions

- **Localized strings**: all user-facing text goes through `String(localized:)` / SwiftUI auto-localization, backed by `Localizable.xcstrings`. Supported languages: **EN, FR, ES** — add new strings to all three. Source-comment language is mixed (some French); follow the file you're editing.
- Bundle ID `com.leodurand.ocr-selection`; copyright/about links point at leodurand.com.
- Preferences "Launch at login" uses `SMAppService.mainApp`.
