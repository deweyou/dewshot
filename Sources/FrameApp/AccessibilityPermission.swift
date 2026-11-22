import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
enum AccessibilityPermission {
    static var hasAccess: Bool {
        AXIsProcessTrusted()
    }

    static func openSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }
}

enum InputMonitoringPermission {
    static var hasAccess: Bool {
        CGPreflightListenEventAccess()
    }

    static func openSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }
    @MainActor
    static func confirmOpeningSettings(strings: AppStrings, above window: NSWindow?) -> Bool {
        let alert = NSAlert()
        alert.messageText = strings.keyboardHintsPermissionTitle
        alert.informativeText = strings.keyboardHintsPermissionMessage
        alert.addButton(withTitle: strings.settingsOpenSystemSettings)
        alert.addButton(withTitle: strings.cancel).keyEquivalent = "\u{1b}"

        if let window {
            // The recording selection covers the screen at screen-saver level.
            alert.window.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
            let frame = window.screen?.visibleFrame ?? window.frame
            alert.window.setFrameOrigin(NSPoint(
                x: frame.midX - alert.window.frame.width / 2,
                y: frame.midY - alert.window.frame.height / 2
            ))
        }

        return alert.runModal() == .alertFirstButtonReturn
    }
}
