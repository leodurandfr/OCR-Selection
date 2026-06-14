import Foundation

/// Implementation-agnostic capture outcomes, shared by the current CLI backend
/// (`screencapture -i -c`) and the planned ScreenCaptureKit backend (plan.md phases
/// 13–14), so `CaptureCoordinator` needs no changes if the backend is ever swapped.
enum CaptureError: Error {
    /// The user pressed Esc or released without dragging a usable region.
    case userCancelled
    /// Screen Recording permission is missing or was revoked.
    case permissionDenied
    /// The capture backend failed (no matching display, ScreenCaptureKit error, crop failure).
    case captureFailed(Error?)
}
