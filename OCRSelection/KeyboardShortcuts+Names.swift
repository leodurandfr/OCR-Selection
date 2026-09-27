import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    #if DEBUG
    // The Debug build (bundle ID `….debug`) often runs next to the installed app; sharing
    // ⌘⇧2 made one keypress start two screencapture sessions, each with its own dialogs.
    static let captureRegion = Self(
        "captureRegion",
        default: .init(.two, modifiers: [.command, .shift, .option])
    )
    #else
    static let captureRegion = Self(
        "captureRegion",
        default: .init(.two, modifiers: [.command, .shift])
    )
    #endif
}
