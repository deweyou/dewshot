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
    @Environment(\.colorScheme) private var colorScheme
    let state: FirstRunSetupState
    var shortcutControls = FirstRunShortcutControls()
    let onStartCapture: () -> Void
    @State private var shortcutErrors: [HotKeyController.HotKeyKind: String] = [:]

    @State private var editingShortcut = false
    private let permissionRefresh = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            hero
            shortcutHints.padding(.top, 22)
            permissions.padding(.top, 24)
            TelemetryConsentToggle(strings: strings, expandsLabel: true) {
                AppTelemetry.setup(granted: state.phase == .ready)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
            Divider()
            primaryButton.padding(.top, 16)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(width: 476)
        .fixedSize()
        .background {
            Rectangle().fill(.regularMaterial)
                .overlay {
                    LinearGradient(colors: [.accentColor.opacity(0.16), .accentColor.opacity(0.025)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .ignoresSafeArea()
        }
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
        VStack(spacing: 8) {
            WelcomeBrandMark()
                .fill(colorScheme == .dark ? Color.white : Color.black)
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text(strings.firstRunWelcome)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: "Dew").italic()
                    Text(verbatim: "Shot")
                }
                .font(.system(size: 29, weight: .semibold, design: .serif))
                .tracking(-0.8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(strings.firstRunTitle)
            .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
    }

    private var shortcutHints: some View {
        VStack(spacing: 8) {
            shortcutEditor(.screenshot, title: strings.firstRunScreenshot)
            shortcutEditor(.recording, title: strings.firstRunRecording)
        }
        .frame(width: 214)
    }

    private func shortcutEditor(_ kind: HotKeyController.HotKeyKind, title: String) -> some View {
        let isScreenshot = kind == .screenshot
        let current = isScreenshot ? screenshotShortcut : recordingShortcut
        let message = shortcutErrors[kind] ?? shortcutControls.status.messages[kind]
        return HStack(spacing: 8) {
            Text(title).font(.callout.weight(.medium))
            Spacer(minLength: 10)
            ShortcutRecorderControl(
                strings: strings, accessibilityLabel: title, shortcut: current,
                validationMessage: message,
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
                    editingShortcut = active
                    if active { shortcutErrors[kind] = nil }
                    shortcutControls.recordingChanged(active)
                }
            ).fixedSize()
            .overlay {
                if message != nil {
                    RoundedRectangle(cornerRadius: SettingsShortcutRecorderMetrics.cornerRadius)
                        .strokeBorder(Color(nsColor: .systemRed).opacity(0.85), lineWidth: 1)
                        .overlay(alignment: .trailing) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 10)).foregroundStyle(Color(nsColor: .systemRed))
                                .padding(.trailing, 5)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
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
                                      purpose: strings.settingsScreenRecordingPurpose, icon: "record.circle")
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
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if page != .screenRecording {
                        Text(strings.language == .zhHans ? "可选" : "Optional")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.primary.opacity(0.065), in: Capsule())
                    }
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

    var canStartCapture: Bool {
        state.phase == .ready && screenshotShortcut != nil && recordingShortcut != nil
            && screenshotShortcut != recordingShortcut && !editingShortcut
            && shortcutErrors.isEmpty && shortcutControls.status.messages.isEmpty
    }

    private var permissionMessage: String {
        switch state.phase {
        case .needsPermission: strings.firstRunPermissionExplanation
        case .waitingForPermission: strings.firstRunPermissionWaiting
        case .ready: canStartCapture ? strings.firstRunReady : (strings.language == .zhHans ? "请设置两组可用的快捷键。" : "Set two available shortcuts to continue.")
        }
    }

    private var primaryButton: some View {
        Button {
            if canStartCapture { onStartCapture() }
        } label: {
            Label(strings.firstRunStartCapture, systemImage: "viewfinder")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 20)
                .frame(minHeight: 36)
        }
        .buttonStyle(FirstCaptureButtonStyle())
        .keyboardShortcut(.defaultAction)
        .disabled(!canStartCapture)
        .help(permissionMessage)
        .accessibilityHint(permissionMessage)
    }
}

private struct FirstCaptureButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let ink = colorScheme == .dark ? Color.white : Color.black
        let paper = colorScheme == .dark ? Color.black : Color.white
        return configuration.label
            .foregroundStyle(isEnabled ? paper : Color.secondary)
            .background(ink.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 0.92) : 0.07),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct WelcomeBrandMark: Shape {
    func path(in rect: CGRect) -> Path {
        // Trace the app icon's stepped silhouette independently of its white tile.
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0.5))
        path.addLine(to: CGPoint(x: 0.36, y: 0.5))
        path.addQuadCurve(to: CGPoint(x: 0.5, y: 0.36), control: CGPoint(x: 0.5, y: 0.5))
        path.addLine(to: CGPoint(x: 0.5, y: 0.14))
        path.addQuadCurve(to: CGPoint(x: 0.64, y: 0), control: CGPoint(x: 0.5, y: 0))
        path.addLine(to: CGPoint(x: 0.86, y: 0))
        path.addQuadCurve(to: CGPoint(x: 1, y: 0.14), control: CGPoint(x: 1, y: 0))
        path.addLine(to: CGPoint(x: 1, y: 0.86))
        path.addQuadCurve(to: CGPoint(x: 0.86, y: 1), control: CGPoint(x: 1, y: 1))
        path.addLine(to: CGPoint(x: 0.14, y: 1))
        path.addQuadCurve(to: CGPoint(x: 0, y: 0.86), control: CGPoint(x: 0, y: 1))
        path.closeSubpath()
        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width, y: rect.height))
    }
}
