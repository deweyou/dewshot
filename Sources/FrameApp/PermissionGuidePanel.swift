import AppKit
import SwiftUI

@MainActor
enum PermissionSettingsPage {
    case screenRecording
    case accessibility
    case inputMonitoring

    var hasAccess: Bool {
        switch self {
        case .screenRecording: ScreenRecordingPermission.hasAccess
        case .accessibility: AccessibilityPermission.hasAccess
        case .inputMonitoring: InputMonitoringPermission.hasAccess
        }
    }

    func open(guide strings: AppStrings? = nil) {
        let anchor = switch self {
        case .screenRecording: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"),
              NSWorkspace.shared.open(url),
              let strings,
              !hasAccess else { return }

        let title = switch self {
        case .screenRecording: strings.screenRecordingGuideTitle
        case .accessibility: strings.settingsAccessibilityPermission
        case .inputMonitoring: strings.settingsInputMonitoringPermission
        }
        PermissionGuidePanel.shared.show(title: title, strings: strings, hasAccess: { hasAccess })
    }
}

@MainActor
final class PermissionGuidePanel {
    static let shared = PermissionGuidePanel()
    private static let settingsBundleID = "com.apple.systempreferences"

    private var panel: NSPanel?
    private var followTask: Task<Void, Never>?

    func show(title: String, strings: AppStrings, hasAccess: @escaping () -> Bool) {
        dismiss()
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "dewShot"
        let icon = NSWorkspace.shared.icon(forFile: bundle.bundleURL.path)
        let card = PermissionGuideCard(
            title: title,
            strings: strings,
            appName: appName,
            bundleURL: bundle.bundleURL,
            icon: icon,
            dismiss: { [weak self] in self?.dismiss() }
        )
        let host = NSHostingView(rootView: card)
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.contentView = host
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.panel = panel

        followTask = Task { [weak self] in
            // A macOS permission prompt can delay activation while Settings is already running.
            var settingsWasRunning = false
            let launchDeadline = ContinuousClock.now + .seconds(5)
            while !Task.isCancelled, let self {
                if hasAccess() {
                    self.dismiss()
                    return
                }

                let settings = NSWorkspace.shared.frontmostApplication
                if settings?.bundleIdentifier == Self.settingsBundleID, let settings {
                    settingsWasRunning = true
                    self.position(panel, beside: settings.processIdentifier)
                    if !panel.isVisible {
                        panel.orderFrontRegardless()
                    }
                } else {
                    let settingsIsRunning = !NSRunningApplication.runningApplications(
                        withBundleIdentifier: Self.settingsBundleID
                    ).isEmpty
                    if !settingsIsRunning && (settingsWasRunning || ContinuousClock.now >= launchDeadline) {
                        self.dismiss()
                        return
                    }
                    settingsWasRunning = settingsIsRunning
                    if panel.isVisible {
                        panel.orderOut(nil)
                    }
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    func dismiss() {
        followTask?.cancel()
        followTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func position(_ panel: NSPanel, beside settingsPID: pid_t) {
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        let settingsWindow = windows.lazy
            .filter {
                ($0[kCGWindowOwnerPID as String] as? pid_t) == settingsPID
                    && ($0[kCGWindowLayer as String] as? Int) == 0
            }
            .compactMap(WindowCandidateProvider.cocoaRect(forWindowInfo:))
            .first { $0.width > 150 && $0.height > 150 }
        let screen = settingsWindow.flatMap { window in
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: window.midX, y: window.midY)) }
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let origin = Self.origin(for: panel.frame.size, beside: settingsWindow, in: screen.visibleFrame)
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
    }

    static func origin(for size: CGSize, beside window: CGRect?, in visibleFrame: CGRect) -> CGPoint {
        let gap: CGFloat = 12
        let inset = visibleFrame.insetBy(dx: gap, dy: gap)
        guard let window else {
            return CGPoint(x: max(inset.minX, inset.maxX - size.width), y: inset.minY)
        }

        let y = min(max(window.maxY - size.height, inset.minY), max(inset.minY, inset.maxY - size.height))
        let x = min(max(window.midX - size.width / 2, inset.minX), max(inset.minX, inset.maxX - size.width))
        let placements = [
            CGPoint(x: window.maxX + gap, y: y),
            CGPoint(x: window.minX - gap - size.width, y: y),
            CGPoint(x: x, y: window.minY - gap - size.height),
            CGPoint(x: x, y: window.maxY + gap),
        ]

        return placements.first { inset.contains(CGRect(origin: $0, size: size)) }
            ?? CGPoint(x: inset.minX, y: inset.minY)
    }
}

private struct PermissionGuideCard: View {
    let title: String
    let strings: AppStrings
    let appName: String
    let bundleURL: URL
    let icon: NSImage
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(strings.quickAccessClose)
            }

            Text(strings.permissionGuideMessage(appName: appName))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(appName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(strings.permissionGuideDrag)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            .padding(9)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                PermissionAppDragSource(bundleURL: bundleURL, icon: icon)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(16)
        .frame(width: 310)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .fixedSize()
    }
}

private struct PermissionAppDragSource: NSViewRepresentable {
    let bundleURL: URL
    let icon: NSImage

    func makeNSView(context: Context) -> PermissionAppDragView {
        PermissionAppDragView(bundleURL: bundleURL, icon: icon)
    }

    func updateNSView(_ view: PermissionAppDragView, context: Context) {}
}

final class PermissionAppDragView: NSView, NSDraggingSource {
    let bundleURL: URL
    private let icon: NSImage

    init(bundleURL: URL, icon: NSImage) {
        self.bundleURL = bundleURL
        self.icon = icon
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let item = NSDraggingItem(pasteboardWriter: bundleURL as NSURL)
        item.setDraggingFrame(CGRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
