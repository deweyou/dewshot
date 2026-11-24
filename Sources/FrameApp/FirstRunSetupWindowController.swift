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

struct FirstRunSetupView: View {
    let strings: AppStrings
    let screenshotShortcut: ScreenshotShortcut?
    let recordingShortcut: ScreenshotShortcut?
    let icon: NSImage
    let state: FirstRunSetupState
    let onStartCapture: () -> Void

    @State private var primaryActionIsHovered = false
    private let permissionRefresh = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            hero
            optionalPermissions
            TelemetryConsentToggle(strings: strings) { AppTelemetry.setup(granted: state.phase == .ready) }
            primaryButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 22)
        .frame(width: 476)
        .fixedSize()
        .onAppear { AppTelemetry.setup(granted: state.phase == .ready) }
        .onReceive(permissionRefresh) { _ in state.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refresh()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 64, height: 64)
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
        let screenshot = shortcutHint(strings.firstRunScreenshot, icon: "camera.viewfinder", shortcut: screenshotShortcut)
        let recording = shortcutHint(strings.firstRunRecording, icon: "record.circle", shortcut: recordingShortcut)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) {
                screenshot
                recording
            }
            VStack(alignment: .leading, spacing: 8) {
                screenshot
                recording
            }
        }
    }

    private func shortcutHint(_ title: String, icon: String, shortcut: ScreenshotShortcut?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
            if let shortcut {
                HStack(spacing: 6) {
                    ForEach(Array(shortcut.displayName.enumerated()), id: \.offset) { key in
                        Text(String(key.element))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 25)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                }
                .padding(.leading, 2)
            } else {
                Text(strings.firstRunMenuBar)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(shortcut?.keyboardShortcut.displayName ?? strings.firstRunMenuBar)
    }

    private var optionalPermissions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.firstRunOptionalPermissions)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                optionalPermissionRow(
                    .accessibility,
                    title: strings.settingsAccessibilityPermission,
                    purpose: strings.settingsAccessibilityPurpose,
                    icon: "figure.arms.open"
                )
                Divider().padding(.leading, 48)
                optionalPermissionRow(
                    .inputMonitoring,
                    title: strings.settingsInputMonitoringPermission,
                    purpose: strings.settingsInputMonitoringPurpose,
                    icon: "keyboard"
                )
            }
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func optionalPermissionRow(
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
                Text(title).font(.system(size: 13, weight: .medium))
                Text(purpose)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if state.grantedOptionalPermissions.contains(page) {
                Label(strings.settingsPermissionGranted, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.green)
                    .accessibilityLabel("\(title), \(strings.settingsPermissionGranted)")
            } else {
                Button {
                    page.open(guide: strings)
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
        .padding(.vertical, 10)
    }

    private var permissionMessage: String {
        switch state.phase {
        case .needsPermission: strings.firstRunPermissionExplanation
        case .waitingForPermission: strings.firstRunPermissionWaiting
        case .ready: strings.firstRunReady
        }
    }

    private var primaryTitle: String {
        switch state.phase {
        case .needsPermission: strings.screenRecordingGuideTitle
        case .waitingForPermission: strings.settingsOpenSystemSettings
        case .ready: strings.firstRunStartCapture
        }
    }

    private var primaryIcon: String {
        switch state.phase {
        case .needsPermission: "record.circle"
        case .waitingForPermission: "gearshape"
        case .ready: "camera.viewfinder"
        }
    }

    private var primaryButton: some View {
        Button(action: primaryAction) {
            HStack(spacing: 12) {
                Image(systemName: primaryIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text(primaryTitle)
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
        .accessibilityLabel(primaryTitle)
        .accessibilityHint(permissionMessage)
    }

    private func primaryAction() {
        if state.phase == .ready {
            onStartCapture()
        } else {
            state.requestPermission()
        }
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
