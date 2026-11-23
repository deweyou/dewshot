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

    @MainActor
    static func showMissingPermissionAlert(strings: AppStrings = .current()) {
        let alert = NSAlert()
        alert.messageText = strings.screenRecordingPermissionRequiredTitle
        alert.informativeText = strings.screenRecordingPermissionRequiredMessage
        alert.addButton(withTitle: strings.screenRecordingPermissionContinue)
        alert.addButton(withTitle: strings.cancel)

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            requestAccessAndOpenSettingsIfNeeded(strings: strings)
        }
    }

    @MainActor
    private static func requestAccessAndOpenSettingsIfNeeded(strings: AppStrings) {
        NSLog("dewShot 正在请求屏幕录制权限")
        let didGrantAccess = requestAccess()
        NSLog("dewShot 屏幕录制权限请求结果: \(didGrantAccess)")

        if hasAccess {
            showRestartRequiredAlert(strings: strings)
        } else {
            openSettings(strings: strings)
        }
    }

    @MainActor
    private static func showRestartRequiredAlert(strings: AppStrings) {
        let alert = NSAlert()
        alert.messageText = strings.screenRecordingPermissionGrantedTitle
        alert.informativeText = strings.screenRecordingPermissionRestartMessage
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }
}
