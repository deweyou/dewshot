import AppKit
import CoreGraphics

enum ScreenRecordingPermission {
    static var hasAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    @MainActor
    static func openSettings(strings: AppStrings = .current()) {
        PermissionSettingsPage.screenRecording.open(guide: strings)
    }
}
