import AppKit
import Combine
import FrameCore
import Observation
import SwiftUI

enum FirstRunSetupProgress: String {
    case new
    case inProgress
    case finished

    func shouldShowOnLaunch(hasAccess: Bool) -> Bool {
        self == .inProgress || (self == .new && !hasAccess)
    }
}

@MainActor
@Observable
final class FirstRunSetupState {
    enum Phase {
        case needsPermission
        case waitingForPermission
        case ready
    }

    private(set) var phase: Phase
    private(set) var grantedOptionalPermissions: Set<PermissionSettingsPage>
    private let hasAccess: () -> Bool
    private let readOptionalPermissions: () -> Set<PermissionSettingsPage>
    private let requestAccess: () -> Void
    private let openSettings: () -> Void
    private var isRequesting = false

    init(
        hasAccess: @escaping () -> Bool,
        requestAccess: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        readOptionalPermissions: @escaping () -> Set<PermissionSettingsPage> = { [] }
    ) {
        self.hasAccess = hasAccess
        self.requestAccess = requestAccess
        self.openSettings = openSettings
        self.readOptionalPermissions = readOptionalPermissions
        phase = hasAccess() ? .ready : .needsPermission
        grantedOptionalPermissions = readOptionalPermissions()
    }

    func refresh() {
        if hasAccess() {
            if phase != .ready { AppTelemetry.setup(granted: true, transition: true) }
            phase = .ready
        } else if phase == .ready {
            phase = .needsPermission
        }
        grantedOptionalPermissions = readOptionalPermissions()
    }

    func requestPermission() {
        guard !isRequesting else { return }
        refresh()
        guard phase != .ready else { return }
        isRequesting = true
        defer { isRequesting = false }

        if phase == .needsPermission {
            phase = .waitingForPermission
            requestAccess()
            refresh()
        }
        if phase == .waitingForPermission {
            openSettings()
        }
    }
}

@MainActor
final class FirstRunSetupWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(
        strings: AppStrings,
        screenshotShortcut: ScreenshotShortcut?,
        recordingShortcut: ScreenshotShortcut?,
        shortcutControls: FirstRunShortcutControls,
        hasAccess: @escaping () -> Bool,
        onStartCapture: @escaping () -> Void
    ) {
        if let window {
            present(window)
            return
        }

        SettingsStore.setFirstRunSetupProgress(.inProgress)
        let state = FirstRunSetupState(
            hasAccess: hasAccess,
            requestAccess: { _ = ScreenRecordingPermission.requestAccess() },
            openSettings: { ScreenRecordingPermission.openSettings(strings: strings) },
            readOptionalPermissions: {
                Set([PermissionSettingsPage.accessibility, .inputMonitoring].filter(\.hasAccess))
            }
        )
        let view = FirstRunSetupView(
            strings: strings,
            screenshotShortcut: screenshotShortcut,
            recordingShortcut: recordingShortcut,
            icon: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath),
            state: state,
            shortcutControls: shortcutControls,
            onStartCapture: { [weak self] in
                self?.finishIfVisible()
                onStartCapture()
            }
        )
        let host = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: host.view.fittingSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = strings.firstRunTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        window.setContentSize(host.view.fittingSize)
        window.delegate = self
        window.center()
        self.window = window
        present(window)
    }

    func finishIfVisible() {
        guard let window else { return }
        SettingsStore.setFirstRunSetupProgress(.finished)
        window.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        SettingsStore.setFirstRunSetupProgress(.finished)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        PermissionGuidePanel.shared.dismiss()
        window = nil
    }

    private func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor @Observable
final class ShortcutRegistrationStatus {
    var messages: [HotKeyController.HotKeyKind: String] = [:]
}

@MainActor
struct FirstRunShortcutControls {
    var status = ShortcutRegistrationStatus()
    var apply: (HotKeyController.HotKeyKind, ScreenshotShortcut?) -> String? = { _, _ in nil }
    var recordingChanged: (Bool) -> Void = { _ in }
    var configuredShortcuts: (() -> (ScreenshotShortcut, ScreenshotShortcut?))?
}

struct FirstRunSetupView: View {
    let strings: AppStrings
    @State var screenshotShortcut: ScreenshotShortcut?
    @State var recordingShortcut: ScreenshotShortcut?
    let icon: NSImage
    let state: FirstRunSetupState
    var shortcutControls = FirstRunShortcutControls()
    let onStartCapture: () -> Void
    @State private var shortcutErrors: [HotKeyController.HotKeyKind: String] = [:]

    @State private var primaryActionIsHovered = false
    private let permissionRefresh = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hero
            permissions
            TelemetryConsentToggle(strings: strings) { AppTelemetry.setup(granted: state.phase == .ready) }
            primaryButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(width: 476)
        .fixedSize()
        .onAppear { AppTelemetry.setup(granted: state.phase == .ready) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if let shortcuts = shortcutControls.configuredShortcuts?() {
                screenshotShortcut = shortcuts.0
                recordingShortcut = shortcuts.1
            }
        }
        .onReceive(permissionRefresh) { _ in state.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refresh()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.13), radius: 12, y: 4)
                .accessibilityHidden(true)
            Text(strings.firstRunTitle)
                .font(.system(size: 29, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(strings.firstRunIntroduction)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            shortcutHints
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.linearGradient(
                            colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
        }
    }

    private var shortcutHints: some View {
        HStack(alignment: .top, spacing: 16) {
            shortcutEditor(.screenshot, title: strings.firstRunScreenshot)
            shortcutEditor(.recording, title: strings.firstRunRecording)
        }
    }

    private func shortcutEditor(_ kind: HotKeyController.HotKeyKind, title: String) -> some View {
        let isScreenshot = kind == .screenshot
        let current = isScreenshot ? screenshotShortcut : recordingShortcut
        let message = shortcutErrors[kind] ?? shortcutControls.status.messages[kind]
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold))
            ShortcutRecorderControl(
                strings: strings, accessibilityLabel: title, shortcut: current,
                allowsEmptyShortcut: !isScreenshot, reservedShortcuts: [],
                duplicateShortcut: isScreenshot ? recordingShortcut : screenshotShortcut,
                onShortcutChange: { value in
                    if let error = shortcutControls.apply(kind, value) {
                        shortcutErrors[kind] = error
                        return false
                    }
                    if isScreenshot { screenshotShortcut = value } else { recordingShortcut = value }
                    shortcutErrors[kind] = nil
                    return true
                },
                onValidationFailure: { failure in
                    if let failure { shortcutErrors[kind] = strings.settingsShortcutRecorderError(failure) }
                },
                onRecordingChange: { active in
                    if active { shortcutErrors[kind] = nil }
                    shortcutControls.recordingChanged(active)
                }
            ).fixedSize()
            if let message {
                Text(message).foregroundStyle(.red).font(.caption).fixedSize(horizontal: false, vertical: true)
            } else if current != nil {
                Text(strings.language == .zhHans ? "可用" : "Available").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.settingsPermissions)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                permissionRow(.screenRecording, title: strings.settingsScreenRecordingPermission,
                                      purpose: strings.language == .zhHans ? "用于截图和录屏" : "For screenshots and recordings", icon: "record.circle")
                Divider().padding(.leading, 48)
                permissionRow(
                    .accessibility,
                    title: strings.settingsAccessibilityPermission,
                    purpose: strings.settingsAccessibilityPurpose,
                    icon: "figure.arms.open"
                )
                Divider().padding(.leading, 48)
                permissionRow(
                    .inputMonitoring,
                    title: strings.settingsInputMonitoringPermission,
                    purpose: strings.settingsInputMonitoringPurpose,
                    icon: "keyboard"
                )
            }
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func permissionRow(
        _ page: PermissionSettingsPage,
        title: String,
        purpose: String,
        icon: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(page == .screenRecording
                         ? (strings.language == .zhHans ? "必需" : "Required")
                         : (strings.language == .zhHans ? "可选" : "Optional"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(purpose)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if page == .screenRecording ? state.phase == .ready : state.grantedOptionalPermissions.contains(page) {
                Label(strings.settingsPermissionGranted, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.green)
                    .accessibilityLabel("\(title), \(strings.settingsPermissionGranted)")
            } else {
                Button {
                    if page == .screenRecording { state.requestPermission() } else { page.open(guide: strings) }
                } label: {
                    Text(strings.settingsOpenSystemSettings)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.primary.opacity(0.065), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(strings.settingsOpenSystemSettings)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var permissionMessage: String {
        switch state.phase {
        case .needsPermission: strings.firstRunPermissionExplanation
        case .waitingForPermission: strings.firstRunPermissionWaiting
        case .ready: strings.firstRunReady
        }
    }

    private var primaryButton: some View {
        Button(action: onStartCapture) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text(strings.firstRunStartCapture)
                        .font(.system(size: 14, weight: .semibold))
                    Text(permissionMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 27, height: 27)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                    .frame(width: 36)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(minHeight: 76)
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(FirstRunActionButtonStyle(isHovered: primaryActionIsHovered))
        .onHover { primaryActionIsHovered = $0 }
        .keyboardShortcut(.defaultAction)
        .disabled(state.phase != .ready)
        .accessibilityLabel(strings.firstRunStartCapture)
        .accessibilityHint(permissionMessage)
    }
}

private struct FirstRunActionButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let card = RoundedRectangle(cornerRadius: 13)
        let isHighlighted = isHovered || configuration.isPressed
        return configuration.label
            .foregroundStyle(.primary)
            .background {
                card
                    .fill(Color.accentColor.opacity(isHighlighted ? 0.11 : 0.055))
                    .overlay {
                        card.strokeBorder(Color.accentColor.opacity(isHighlighted ? 0.42 : 0.24), lineWidth: 1)
                    }
            }
    }
}
