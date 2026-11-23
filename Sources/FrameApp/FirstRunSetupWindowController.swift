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
    private let hasAccess: () -> Bool
    private let requestAccess: () -> Void
    private let openSettings: () -> Void
    private var isRequesting = false

    init(
        hasAccess: @escaping () -> Bool,
        requestAccess: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.hasAccess = hasAccess
        self.requestAccess = requestAccess
        self.openSettings = openSettings
        phase = hasAccess() ? .ready : .needsPermission
    }

    func refresh() {
        if hasAccess() {
            phase = .ready
        } else if phase == .ready {
            phase = .needsPermission
        }
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
            openSettings: { ScreenRecordingPermission.openSettings(strings: strings) }
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
        ScreenRecordingPermissionPanel.shared.dismiss()
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

    private let permissionRefresh = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            hero
            permissionStatus
            Button(primaryTitle, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 22)
        .frame(width: 476)
        .fixedSize()
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
            HStack(spacing: 8) {
                shortcutBadge(
                    strings.firstRunScreenshot,
                    icon: "camera.viewfinder",
                    shortcut: screenshotShortcut
                )
                shortcutBadge(
                    strings.firstRunRecording,
                    icon: "record.circle",
                    shortcut: recordingShortcut
                )
            }
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

    private func shortcutBadge(_ title: String, icon: String, shortcut: ScreenshotShortcut?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer(minLength: 8)
            Text(shortcut?.displayName ?? strings.firstRunMenuBar)
                .font(.system(size: 12, weight: .medium, design: shortcut == nil ? .default : .monospaced))
                .foregroundStyle(shortcut == nil ? .secondary : .primary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(shortcut?.keyboardShortcut.displayName ?? strings.firstRunMenuBar)
    }

    private var permissionStatus: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.phase == .ready ? "checkmark.circle.fill" : "record.circle")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(state.phase == .ready ? Color.green : Color.accentColor)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(strings.settingsScreenRecordingPermission)
                    .font(.system(size: 14, weight: .semibold))
                Text(permissionMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 34, alignment: .topLeading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
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

    private func primaryAction() {
        if state.phase == .ready {
            onStartCapture()
        } else {
            state.requestPermission()
        }
    }
}
