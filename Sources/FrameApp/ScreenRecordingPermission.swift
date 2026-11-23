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
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else {
            return
        }

        if NSWorkspace.shared.open(settingsURL), !hasAccess {
            ScreenRecordingPermissionPanel.shared.show(strings: strings)
        }
    }
}
