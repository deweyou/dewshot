import AppKit
import Carbon
import FrameCore
import Observation
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var settingsViewController: SettingsContentViewController?
    private let launchAtLoginService: any LaunchAtLoginServicing

    init(launchAtLoginService: any LaunchAtLoginServicing = LaunchAtLoginService()) {
        self.launchAtLoginService = launchAtLoginService
    }

    func show(
        strings: AppStrings,
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onRecordingShortcutChange: @escaping @MainActor (ScreenshotShortcut?) -> Bool = { _ in true },
        onShortcutRecordingChange: @escaping @MainActor (Bool) -> Void = { _ in },
        onLanguageChange: @escaping @MainActor (AppLanguage) -> Void,
        onChooseScreenshotDirectory: @escaping @MainActor () -> URL?,
        onResetScreenshotDirectory: @escaping @MainActor () -> Void,
        onClearCaptureHistory: @escaping @MainActor () throws -> Void
    ) {
        if let window {
            settingsViewController?.update(strings: strings)
            centerOnActiveScreen(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsViewController = SettingsContentViewController(
            strings: strings,
            onShortcutChange: onShortcutChange,
            onRecordingShortcutChange: onRecordingShortcutChange,
            onShortcutRecordingChange: onShortcutRecordingChange,
            onLanguageChange: onLanguageChange,
            onChooseScreenshotDirectory: onChooseScreenshotDirectory,
            onResetScreenshotDirectory: onResetScreenshotDirectory,
            onClearCaptureHistory: onClearCaptureHistory,
            launchAtLoginService: launchAtLoginService
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsWindowLayout.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = strings.settingsTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = NSToolbar(identifier: "FrameSettings")
        window.toolbarStyle = .unifiedCompact
        window.minSize = SettingsWindowLayout.minimumSize
        window.isReleasedWhenClosed = false
        window.contentViewController = settingsViewController
        window.minSize = SettingsWindowLayout.minimumSize
        window.setFrame(NSRect(origin: window.frame.origin, size: SettingsWindowLayout.defaultSize), display: false)
        centerOnActiveScreen(window)

        self.window = window
        self.settingsViewController = settingsViewController
        window.makeKeyAndOrderFront(nil)
        window.minSize = SettingsWindowLayout.minimumSize
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(strings: AppStrings) {
        window?.title = strings.settingsTitle
        settingsViewController?.update(strings: strings)
    }

    func selectSection(_ section: SettingsSection) {
        settingsViewController?.selectSection(section)
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? window.screen

        guard let visibleFrame = targetScreen?.visibleFrame else {
            window.center()
            return
        }

        window.setFrame(SettingsWindowLayout.centeredFrame(
            windowSize: window.frame.size,
            visibleFrame: visibleFrame
        ), display: false)
    }
}

enum SettingsWindowLayout {
    static let defaultSize = CGSize(width: 752, height: 556)
    static let minimumSize = CGSize(width: 688, height: 460)

    static func centeredFrame(windowSize: CGSize, visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case capture
    case history
    case permissions

    var id: String { rawValue }

    func title(strings: AppStrings) -> String {
        switch self {
        case .general: strings.settingsGeneral
        case .capture: strings.settingsCapture
        case .history: strings.settingsHistory
        case .permissions: strings.settingsPrivacyAndPermissions
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .capture: "viewfinder"
        case .history: "clock.arrow.circlepath"
        case .permissions: "lock"
        }
    }
}

@MainActor
@Observable
private final class SettingsPresentation {
    var strings: AppStrings
    var section: SettingsSection = .general

    init(strings: AppStrings) {
        self.strings = strings
    }
}

@MainActor
private final class SettingsContentViewController: NSSplitViewController {
    private let presentation: SettingsPresentation

    init(
        strings: AppStrings,
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onRecordingShortcutChange: @escaping @MainActor (ScreenshotShortcut?) -> Bool,
        onShortcutRecordingChange: @escaping @MainActor (Bool) -> Void,
        onLanguageChange: @escaping @MainActor (AppLanguage) -> Void,
        onChooseScreenshotDirectory: @escaping @MainActor () -> URL?,
        onResetScreenshotDirectory: @escaping @MainActor () -> Void,
        onClearCaptureHistory: @escaping @MainActor () throws -> Void,
        launchAtLoginService: any LaunchAtLoginServicing
    ) {
        let presentation = SettingsPresentation(strings: strings)
        self.presentation = presentation
        super.init(nibName: nil, bundle: nil)

        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(
            rootView: SettingsSidebar(presentation: presentation)
        ))
        sidebar.minimumThickness = 176
        sidebar.maximumThickness = 200
        sidebar.preferredThicknessFraction = 0.24
        sidebar.canCollapse = false
        sidebar.allowsFullHeightLayout = true

        let detail = NSSplitViewItem(viewController: NSHostingController(
            rootView: SettingsDetailView(
                presentation: presentation,
                onShortcutChange: onShortcutChange,
                onRecordingShortcutChange: onRecordingShortcutChange,
                onShortcutRecordingChange: onShortcutRecordingChange,
                onLanguageChange: onLanguageChange,
                onChooseScreenshotDirectory: onChooseScreenshotDirectory,
                onResetScreenshotDirectory: onResetScreenshotDirectory,
                onClearCaptureHistory: onClearCaptureHistory,
                launchAtLoginService: launchAtLoginService
            )
        ))
        if #available(macOS 26.0, *) {
            detail.automaticallyAdjustsSafeAreaInsets = true
        }
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        addSplitViewItem(sidebar)
        addSplitViewItem(detail)
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        nil
    }

    func selectSection(_ section: SettingsSection) {
        presentation.section = section
    }

    func update(strings: AppStrings) {
        presentation.strings = strings
    }
}

private struct SettingsDetailView: View {
    let presentation: SettingsPresentation
    let onShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
    let onRecordingShortcutChange: @MainActor (ScreenshotShortcut?) -> Bool
    let onShortcutRecordingChange: @MainActor (Bool) -> Void
    let onLanguageChange: @MainActor (AppLanguage) -> Void
    let onChooseScreenshotDirectory: @MainActor () -> URL?
    let onResetScreenshotDirectory: @MainActor () -> Void
    let onClearCaptureHistory: @MainActor () throws -> Void
    let launchAtLoginService: any LaunchAtLoginServicing

    private var strings: AppStrings { presentation.strings }
    @State private var automaticallyCopiesCaptures = SettingsStore.automaticallyCopiesCaptures()
    @State private var quickAccessDismissal = SettingsStore.quickAccessDismissal()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(presentation.section.title(strings: strings))
                    .font(.system(size: 24, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)

                sectionContent
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .id(presentation.section)
        .background {
            Color(nsColor: .textBackgroundColor).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch presentation.section {
        case .general:
            GeneralSettingsView(
                strings: strings,
                onShortcutChange: onShortcutChange,
                onRecordingShortcutChange: onRecordingShortcutChange,
                onShortcutRecordingChange: onShortcutRecordingChange,
                onChooseScreenshotDirectory: onChooseScreenshotDirectory,
                onResetScreenshotDirectory: onResetScreenshotDirectory,
                onLanguageChange: onLanguageChange,
                launchAtLoginService: launchAtLoginService
            )
        case .capture:
            VStack(alignment: .leading, spacing: 18) {
                SettingsControlGroup {
                    SettingsControlRow(
                        strings.settingsAutomaticallyCopyCaptures,
                        subtitle: strings.settingsAutomaticallyCopyCapturesDescription
                    ) {
                        Toggle(strings.settingsAutomaticallyCopyCaptures, isOn: $automaticallyCopiesCaptures)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: automaticallyCopiesCaptures) { _, isEnabled in
                                SettingsStore.setAutomaticallyCopiesCaptures(isEnabled)
                            }
                    }

                    SettingsControlDivider()

                    SettingsControlRow(strings.settingsQuickAccessDismissal) {
                        SettingsMenuPicker(
                            strings.settingsQuickAccessDismissal,
                            value: strings.settingsQuickAccessDismissalOption(quickAccessDismissal),
                            selection: $quickAccessDismissal
                        ) {
                            ForEach(QuickAccessDismissal.allCases) { dismissal in
                                Text(strings.settingsQuickAccessDismissalOption(dismissal)).tag(dismissal)
                            }
                        }
                        .onChange(of: quickAccessDismissal) { _, dismissal in
                            SettingsStore.setQuickAccessDismissal(dismissal)
                        }
                    }
                }
                ScreenshotSettingsView(strings: strings)
                RecordingSettingsView(strings: strings)
                TextRecognitionSettingsView(strings: strings)
            }
        case .history:
            HistorySettingsView(strings: strings, onClearCaptureHistory: onClearCaptureHistory)
        case .permissions:
            SettingsSectionGroup(title: strings.settingsPermissions) {
                PermissionsSettingsView(strings: strings)
            }
            SettingsSectionGroup(title: strings.settingsPrivacy) {
                SettingsControlGroup {
                    SettingsControlRow(strings.shareUsageAndDiagnostics) {
                        TelemetryConsentToggle(strings: strings)
                            .labelsHidden()
                            .accessibilityLabel(strings.shareUsageAndDiagnostics)
                    }
                    SettingsControlDivider()
                    SettingsLinkRow(title: strings.settingsPrivacyPolicy, symbol: "arrow.up.forward",
                                    destination: URL(string: "https://dewshot.oushihao97.workers.dev/privacy/")!)
                }
            }
        }
    }
}

private struct SettingsSidebar: View {
    @Bindable var presentation: SettingsPresentation

    var body: some View {
        List(selection: $presentation.section) {
            ForEach(SettingsSection.allCases) { section in
                Label {
                    Text(section.title(strings: presentation.strings))
                } icon: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 18)
                }
                .padding(.vertical, 7)
                .tag(section)
                .accessibilityIdentifier("settings.section.\(section.rawValue)")
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.top, 10, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SettingsAboutFooterView()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 17)
                .padding(.vertical, 12)
        }
    }
}

private struct GeneralSettingsView: View {
    let strings: AppStrings
    let onShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
    let onRecordingShortcutChange: @MainActor (ScreenshotShortcut?) -> Bool
    let onShortcutRecordingChange: @MainActor (Bool) -> Void
    let onChooseScreenshotDirectory: @MainActor () -> URL?
    let onResetScreenshotDirectory: @MainActor () -> Void
    let onLanguageChange: @MainActor (AppLanguage) -> Void
    let launchAtLoginService: any LaunchAtLoginServicing

    @State private var selectedLanguage = SettingsStore.appLanguage()
    @State private var selectedTheme = SettingsStore.appTheme()
    @State private var selectedShortcut = SettingsStore.screenshotShortcut()
    @State private var selectedRecordingShortcut = SettingsStore.recordingShortcut()
    @State private var shortcutErrorText: String?
    @State private var recordingShortcutErrorText: String?
    @AppStorage(SettingsStore.screenshotDirectoryKey) private var screenshotDirectoryPath: String?
    @State private var launchAtLoginState: LaunchAtLoginSettingState

    init(
        strings: AppStrings,
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onRecordingShortcutChange: @escaping @MainActor (ScreenshotShortcut?) -> Bool,
        onShortcutRecordingChange: @escaping @MainActor (Bool) -> Void,
        onChooseScreenshotDirectory: @escaping @MainActor () -> URL?,
        onResetScreenshotDirectory: @escaping @MainActor () -> Void,
        onLanguageChange: @escaping @MainActor (AppLanguage) -> Void,
        launchAtLoginService: any LaunchAtLoginServicing
    ) {
        self.strings = strings
        self.onShortcutChange = onShortcutChange
        self.onRecordingShortcutChange = onRecordingShortcutChange
        self.onShortcutRecordingChange = onShortcutRecordingChange
        self.onChooseScreenshotDirectory = onChooseScreenshotDirectory
        self.onResetScreenshotDirectory = onResetScreenshotDirectory
        self.onLanguageChange = onLanguageChange
        self.launchAtLoginService = launchAtLoginService
        _launchAtLoginState = State(
            initialValue: LaunchAtLoginSettingState(service: launchAtLoginService)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionGroup(title: strings.settingsAppearance) {
                SettingsThemePicker(strings: strings, selection: $selectedTheme)
                    .onChange(of: selectedTheme) { _, newTheme in
                        SettingsStore.setAppTheme(newTheme)
                        newTheme.apply(to: NSApp)
                    }
            }

            SettingsSectionGroup(title: strings.settingsPreferences) {
                SettingsControlGroup {
                    SettingsControlRow(strings.settingsLanguage) {
                        SettingsMenuPicker(
                            strings.settingsLanguage,
                            value: selectedLanguage.displayName(strings: strings),
                            selection: $selectedLanguage
                        ) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName(strings: strings))
                                    .tag(language)
                            }
                        }
                        .onChange(of: selectedLanguage) { _, newLanguage in
                            SettingsStore.setAppLanguage(newLanguage)
                            onLanguageChange(newLanguage)
                        }
                    }

                    SettingsControlDivider()

                    SettingsControlRow(strings.settingsLaunchAtLogin) {
                        VStack(alignment: .trailing, spacing: 5) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { launchAtLoginState.isEnabled },
                                    set: { isEnabled in
                                        updateLaunchAtLogin(isEnabled)
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .accessibilityLabel(strings.settingsLaunchAtLogin)

                            if launchAtLoginState.status == .requiresApproval {
                                Text(strings.settingsLaunchAtLoginRequiresApproval)
                                    .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
                                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                    .multilineTextAlignment(.trailing)
                            }

                            if let errorDescription = launchAtLoginState.errorDescription {
                                Text(strings.settingsLaunchAtLoginUpdateFailed(errorDescription: errorDescription))
                                    .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
                                    .foregroundStyle(Color(nsColor: .systemRed))
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }

                    SettingsControlDivider()

                    SettingsControlRow(
                        strings.settingsSaveLocation,
                        subtitle: saveLocation?.path ?? strings.settingsSaveFolderOnFirstSave
                    ) {
                        HStack(spacing: 8) {
                            if let saveLocation, CaptureSaveDirectory.isSandboxed || !saveLocation.isDefaultLocation {
                                Button(strings.settingsRestoreDefaultFolder, action: onResetScreenshotDirectory)
                            }
                            Button(strings.settingsChooseFolder) { _ = onChooseScreenshotDirectory() }
                        }
                    }
                }
            }

            SettingsSectionGroup(title: strings.settingsShortcuts) {
                SettingsControlGroup {
                    SettingsControlRow(strings.settingsScreenshotShortcut) {
                        VStack(alignment: .trailing, spacing: 5) {
                            ShortcutRecorderControl(
                                strings: strings,
                                accessibilityLabel: strings.settingsScreenshotShortcut,
                                shortcut: selectedShortcut,
                                allowsEmptyShortcut: false,
                                reservedShortcuts: [],
                                duplicateShortcut: selectedRecordingShortcut,
                                onShortcutChange: { shortcut in
                                    guard let shortcut else {
                                        return false
                                    }

                                    return changeShortcut(shortcut)
                                },
                                onValidationFailure: updateShortcutValidationFailure,
                                onRecordingChange: onShortcutRecordingChange
                            )

                            if let shortcutErrorText {
                                Text(shortcutErrorText)
                                    .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
                                    .foregroundStyle(Color(nsColor: .systemRed))
                            }
                        }
                    }

                    SettingsControlDivider()

                    SettingsControlRow(strings.settingsRecordingShortcut) {
                        VStack(alignment: .trailing, spacing: 5) {
                            ShortcutRecorderControl(
                                strings: strings,
                                accessibilityLabel: strings.settingsRecordingShortcut,
                                shortcut: selectedRecordingShortcut,
                                allowsEmptyShortcut: true,
                                reservedShortcuts: [],
                                duplicateShortcut: selectedShortcut,
                                onShortcutChange: changeRecordingShortcut,
                                onValidationFailure: updateRecordingShortcutValidationFailure,
                                onRecordingChange: onShortcutRecordingChange
                            )

                            if let recordingShortcutErrorText {
                                Text(recordingShortcutErrorText)
                                    .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
                                    .foregroundStyle(Color(nsColor: .systemRed))
                            }
                        }
                    }
                }
            }
            SettingsControlGroup {
                SettingsLinkRow(title: strings.settingsContactSupport, symbol: "envelope",
                                destination: URL(string: "mailto:deweyou97@gmail.com")!)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLoginState.refresh(using: launchAtLoginService)
        }
    }

    private func changeShortcut(_ shortcut: ScreenshotShortcut) -> Bool {
        selectedShortcut = shortcut
        guard onShortcutChange(shortcut) else {
            selectedShortcut = SettingsStore.screenshotShortcut()
            return false
        }
        shortcutErrorText = nil
        return true
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        launchAtLoginState.setEnabled(isEnabled, using: launchAtLoginService)
    }

    private func changeRecordingShortcut(_ shortcut: ScreenshotShortcut?) -> Bool {
        selectedRecordingShortcut = shortcut
        guard onRecordingShortcutChange(shortcut) else {
            selectedRecordingShortcut = SettingsStore.recordingShortcut()
            return false
        }
        recordingShortcutErrorText = nil
        return true
    }

    private func updateShortcutValidationFailure(_ failure: ScreenshotShortcutValidationFailure?) {
        shortcutErrorText = failure.map { strings.settingsShortcutRecorderError($0) }
    }

    private func updateRecordingShortcutValidationFailure(_ failure: ScreenshotShortcutValidationFailure?) {
        recordingShortcutErrorText = failure.map { strings.settingsShortcutRecorderError($0) }
    }

    private var saveLocation: SettingsSaveLocationSummary? {
        if let screenshotDirectoryPath, !screenshotDirectoryPath.isEmpty {
            return SettingsSaveLocationSummary(url: URL(fileURLWithPath: screenshotDirectoryPath, isDirectory: true))
        }
        guard !CaptureSaveDirectory.isSandboxed else { return nil }
        let directory = (try? SettingsStore.screenshotDirectory()) ?? FileManager.default.homeDirectoryForCurrentUser
        return SettingsSaveLocationSummary(url: directory)
    }
}

enum SettingsGeneralMetrics {
    static let containsLaunchAtLogin = true
    static let containsScreenshotShortcut = true
    static let containsRecordingShortcut = true
    static let containsSaveLocation = true
}

enum SettingsScreenshotMetrics {
    static let containsShortcut = false
    static let containsSaveLocation = false
    static let containsImageWorkspaceSaveCurrentBehavior = false
}

enum SettingsGroupMetrics {
    static let cornerRadius: CGFloat = 12
    static let rowMinHeight: CGFloat = 42
    static let horizontalPadding: CGFloat = 14
    static let controlSpacing: CGFloat = 12
}

enum SettingsTypographyMetrics {
    static let usesSystemFont = true
    static let usesMediumRowLabels = true
    static let sectionFontSize: CGFloat = 13
    static let rowFontSize: CGFloat = 13
    static let secondaryFontSize: CGFloat = 12
    static let footerFontSize: CGFloat = 11
}

enum SettingsSectionGroupMetrics {
    static let titleSpacing: CGFloat = 8
}

enum SettingsShortcutRecorderMetrics {
    static let usesInlineRecorder = true
    static let width: CGFloat = 118
    static let minHeight: CGFloat = 28
    static let cornerRadius: CGFloat = 7
}

enum SettingsSaveLocationMetrics {
    static let usesSummaryRow = true
    static let opensChooserFromSummary = false
    static let showsFinderAction = false
    static let showsFolderName = false
    static let showsResetOnlyForCustomLocation = true
    static let usesNestedControlBackground = false
    static let usesSeparateRevealBox = false
}

enum SettingsOCRLanguageMetrics {
    static let usesDisclosure = false
    static let usesSheet = true
    static let opensFromWholeRow = true
    static let sheetWidth: CGFloat = 420
    static let sheetHeight: CGFloat = 460
    static let gridMinimumItemWidth: CGFloat = 180
    static let gridSpacing: CGFloat = 8
}

enum SettingsMouseHintColorMetrics {
    static let usesSwatchPicker = true
    static let usesPresetOnlyPicker = true
    static let usesSelectedCheckmark = true
    static let showsCustomColorPicker = false
    static let showsResetAction = false
    static let swatchSize: CGFloat = 24
    static let controlSpacing: CGFloat = 8
}

struct SettingsSaveLocationSummary: Equatable {
    let path: String
    let isDefaultLocation: Bool

    init(
        url: URL,
        desktopURL: URL = SettingsSaveLocationSummary.defaultDesktopURL,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let standardizedURL = url.standardizedFileURL
        let standardizedDesktopURL = desktopURL.standardizedFileURL

        isDefaultLocation = standardizedURL.path == standardizedDesktopURL.path
        path = Self.abbreviatedPath(for: standardizedURL, homeURL: homeURL)
    }

    private static let defaultDesktopURL = FileManager.default
        .urls(for: .desktopDirectory, in: .userDomainMask)
        .first ?? FileManager.default.homeDirectoryForCurrentUser

    private static func abbreviatedPath(for url: URL, homeURL: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = homeURL.standardizedFileURL.path

        guard path != homePath else {
            return "~"
        }

        let homePrefix = homePath + "/"
        guard path.hasPrefix(homePrefix) else {
            return path
        }

        return "~/" + String(path.dropFirst(homePrefix.count))
    }
}

private struct SettingsControlGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(.primary.opacity(0.038), in: RoundedRectangle(cornerRadius: SettingsGroupMetrics.cornerRadius))
    }
}

private struct SettingsControlRow<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        HStack(spacing: SettingsGroupMetrics.controlSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: SettingsTypographyMetrics.rowFontSize, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(subtitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SettingsGroupMetrics.horizontalPadding)
        .padding(.vertical, 7)
        .frame(minHeight: SettingsGroupMetrics.rowMinHeight)
    }
}

private struct SettingsLinkRow: View {
    let title: String
    let symbol: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            SettingsControlRow(title) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct SettingsMenuPicker<Selection: Hashable, Options: View>: View {
    let title: String
    let value: String
    @Binding var selection: Selection
    @ViewBuilder let options: Options

    init(
        _ title: String,
        value: String,
        selection: Binding<Selection>,
        @ViewBuilder options: () -> Options
    ) {
        self.title = title
        self.value = value
        _selection = selection
        self.options = options()
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                options
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text("\(value)  \(settingsChevron("chevron.down"))")
                .font(.system(size: SettingsTypographyMetrics.rowFontSize))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.regular)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct SettingsButtonRow: View {
    let title: String
    let value: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsGroupMetrics.controlSpacing) {
                Text(title)
                    .font(.system(size: SettingsTypographyMetrics.rowFontSize, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(value)
                    .font(.system(size: SettingsTypographyMetrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)

                settingsChevron("chevron.right")
            }
            .padding(.horizontal, SettingsGroupMetrics.horizontalPadding)
            .frame(minHeight: SettingsGroupMetrics.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private func settingsChevron(_ symbol: String) -> Text {
    Text("\(Image(systemName: symbol))")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.tertiary)
}

private struct SettingsControlDivider: View {
    var body: some View {
        Divider()
            .opacity(0.65)
            .padding(.horizontal, SettingsGroupMetrics.horizontalPadding)
    }
}

private struct ScreenshotSettingsView: View {
    let strings: AppStrings

    @State private var selectedWindowScreenshotDecorationStyle = SettingsStore.windowScreenshotDecorationStyle()
    @State private var selectedImageWorkspaceSaveCurrentBehavior = SettingsStore.imageWorkspaceSaveCurrentBehavior()

    var body: some View {
        SettingsSectionGroup(title: strings.settingsScreenshot) {
            SettingsControlGroup {
                SettingsControlRow(strings.settingsWindowScreenshotDecorationStyle) {
                    SettingsMenuPicker(
                        strings.settingsWindowScreenshotDecorationStyle,
                        value: selectedWindowScreenshotDecorationStyle.displayName(strings: strings),
                        selection: $selectedWindowScreenshotDecorationStyle
                    ) {
                        ForEach(WindowScreenshotDecorationStyle.allCases) { style in
                            Text(style.displayName(strings: strings))
                                .tag(style)
                        }
                    }
                    .onChange(of: selectedWindowScreenshotDecorationStyle) { _, style in
                        SettingsStore.setWindowScreenshotDecorationStyle(style)
                    }
                }

                if SettingsScreenshotMetrics.containsImageWorkspaceSaveCurrentBehavior {
                    SettingsControlDivider()

                    SettingsControlRow(strings.settingsImageWorkspaceSaveCurrentBehavior) {
                        SettingsMenuPicker(
                            strings.settingsImageWorkspaceSaveCurrentBehavior,
                            value: strings.imageWorkspaceSaveCurrentBehaviorName(selectedImageWorkspaceSaveCurrentBehavior),
                            selection: $selectedImageWorkspaceSaveCurrentBehavior
                        ) {
                            ForEach(ImageWorkspaceSaveCurrentBehavior.allCases, id: \.self) { behavior in
                                Text(strings.imageWorkspaceSaveCurrentBehaviorName(behavior))
                                    .tag(behavior)
                            }
                        }
                        .onChange(of: selectedImageWorkspaceSaveCurrentBehavior) { _, behavior in
                            SettingsStore.setImageWorkspaceSaveCurrentBehavior(behavior)
                        }
                    }
                }
            }
        }
    }
}

struct ShortcutRecorderControl: NSViewRepresentable {
    let strings: AppStrings
    let accessibilityLabel: String
    let shortcut: ScreenshotShortcut?
    var validationMessage: String?
    let allowsEmptyShortcut: Bool
    let reservedShortcuts: Set<ScreenshotShortcut>
    let duplicateShortcut: ScreenshotShortcut?
    let onShortcutChange: @MainActor (ScreenshotShortcut?) -> Bool
    let onValidationFailure: @MainActor (ScreenshotShortcutValidationFailure?) -> Void
    let onRecordingChange: @MainActor (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onShortcutChange: onShortcutChange,
            onValidationFailure: onValidationFailure,
            onRecordingChange: onRecordingChange
        )
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.startRecording(_:))
        configure(button, context: context)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        context.coordinator.onShortcutChange = onShortcutChange
        context.coordinator.onValidationFailure = onValidationFailure
        context.coordinator.onRecordingChange = onRecordingChange
        configure(button, context: context)
    }

    private func configure(_ button: ShortcutRecorderButton, context: Context) {
        button.toolTip = validationMessage
        button.setAccessibilityHelp(validationMessage)
        button.update(
            strings: strings,
            accessibilityLabel: accessibilityLabel,
            shortcut: shortcut,
            allowsEmptyShortcut: allowsEmptyShortcut,
            reservedShortcuts: reservedShortcuts,
            duplicateShortcut: duplicateShortcut,
            onShortcutChange: context.coordinator.onShortcutChange,
            onValidationFailure: context.coordinator.onValidationFailure,
            onRecordingChange: context.coordinator.onRecordingChange
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var onShortcutChange: @MainActor (ScreenshotShortcut?) -> Bool
        var onValidationFailure: @MainActor (ScreenshotShortcutValidationFailure?) -> Void
        var onRecordingChange: @MainActor (Bool) -> Void

        init(
            onShortcutChange: @escaping @MainActor (ScreenshotShortcut?) -> Bool,
            onValidationFailure: @escaping @MainActor (ScreenshotShortcutValidationFailure?) -> Void,
            onRecordingChange: @escaping @MainActor (Bool) -> Void
        ) {
            self.onShortcutChange = onShortcutChange
            self.onValidationFailure = onValidationFailure
            self.onRecordingChange = onRecordingChange
        }

        @objc func startRecording(_ sender: ShortcutRecorderButton) {
            sender.startRecording()
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    private var strings = AppStrings(language: .system)
    private var shortcutAccessibilityLabel = ""
    private var shortcut: ScreenshotShortcut?
    private var allowsEmptyShortcut = false
    private var reservedShortcuts: Set<ScreenshotShortcut> = [.defaultRecording]
    private var duplicateShortcut: ScreenshotShortcut?
    private var isRecording = false
    private var recordingPreviewTitle: String?
    private var onShortcutChange: (@MainActor (ScreenshotShortcut?) -> Bool)?
    private var onValidationFailure: (@MainActor (ScreenshotShortcutValidationFailure?) -> Void)?
    private var onRecordingChange: (@MainActor (Bool) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryChange)
        isBordered = false
        alignment = .center
        lineBreakMode = .byTruncatingTail
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: SettingsShortcutRecorderMetrics.width).isActive = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsShortcutRecorderMetrics.minHeight).isActive = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(
        strings: AppStrings,
        accessibilityLabel: String = "",
        shortcut: ScreenshotShortcut?,
        allowsEmptyShortcut: Bool = false,
        reservedShortcuts: Set<ScreenshotShortcut> = [.defaultRecording],
        duplicateShortcut: ScreenshotShortcut? = nil,
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut?) -> Bool,
        onValidationFailure: @escaping @MainActor (ScreenshotShortcutValidationFailure?) -> Void,
        onRecordingChange: @escaping @MainActor (Bool) -> Void
    ) {
        self.strings = strings
        shortcutAccessibilityLabel = accessibilityLabel.isEmpty ? strings.settingsScreenshotShortcut : accessibilityLabel
        self.shortcut = shortcut
        self.allowsEmptyShortcut = allowsEmptyShortcut
        self.reservedShortcuts = reservedShortcuts
        self.duplicateShortcut = duplicateShortcut
        self.onShortcutChange = onShortcutChange
        self.onValidationFailure = onValidationFailure
        self.onRecordingChange = onRecordingChange

        if isRecording {
            title = recordingTitle
        } else {
            title = displayTitle
        }
        updateAccessibilityLabel()
        updateAppearance()
    }

    func startRecording() {
        guard !isRecording else {
            return
        }

        isRecording = true
        recordingPreviewTitle = nil
        title = recordingTitle
        onValidationFailure?(nil)
        onRecordingChange?(true)
        window?.makeFirstResponder(self)
        updateAccessibilityLabel()
        updateAppearance()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == shortcutRecorderEscapeKeyCode {
            stopRecording()
            return
        }

        if allowsEmptyShortcut,
           shortcutRecorderClearKeyCodes.contains(event.keyCode) {
            let didApply = onShortcutChange?(nil) ?? false
            if didApply {
                shortcut = nil
            }
            stopRecording()
            return
        }

        let key = ScreenshotShortcutKey(event: event)
        let modifiers = ScreenshotShortcutModifier.modifiers(event: event)
        updateRecordingPreview(key: key, modifiers: modifiers)

        let result = ScreenshotShortcut.validate(
            key: key,
            modifiers: modifiers,
            reservedShortcuts: reservedShortcuts,
            duplicateShortcut: duplicateShortcut
        )

        switch result {
        case let .valid(shortcut):
            let didApply = onShortcutChange?(shortcut) ?? false
            if didApply {
                self.shortcut = shortcut
            }
            stopRecording()
        case let .invalid(failure):
            onValidationFailure?(failure)
            updateAppearance()
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        updateRecordingPreview(key: nil, modifiers: ScreenshotShortcutModifier.modifiers(event: event))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil && isRecording {
            stopRecording()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            stopRecording(clearsFirstResponder: false)
        }

        return super.resignFirstResponder()
    }

    private func stopRecording(clearsFirstResponder: Bool = true) {
        guard isRecording else {
            return
        }

        isRecording = false
        recordingPreviewTitle = nil
        title = displayTitle
        onValidationFailure?(nil)
        onRecordingChange?(false)
        if clearsFirstResponder {
            window?.makeFirstResponder(nil)
        }
        updateAccessibilityLabel()
        updateAppearance()
    }

    private func updateRecordingPreview(
        key: ScreenshotShortcutKey?,
        modifiers: Set<ScreenshotShortcutModifier>
    ) {
        let preview = ShortcutRecorderPreview.title(key: key, modifiers: modifiers)
        recordingPreviewTitle = preview.isEmpty ? nil : preview
        title = recordingTitle
        updateAccessibilityLabel()
        updateAppearance()
    }

    private var recordingTitle: String {
        recordingPreviewTitle ?? strings.settingsShortcutRecorderPrompt
    }

    private var displayTitle: String {
        shortcut?.displayName ?? strings.settingsShortcutRecorderUnset
    }

    private func updateAccessibilityLabel() {
        setAccessibilityLabel("\(shortcutAccessibilityLabel), \(title)")
    }

    private func updateAppearance() {
        focusRingType = isRecording ? .none : .default
        let hasShortcut = isRecording || shortcut != nil
        font = .systemFont(ofSize: 12, weight: hasShortcut ? .medium : .regular)
        contentTintColor = hasShortcut ? .labelColor : .secondaryLabelColor
        wantsLayer = true
        layer?.cornerRadius = SettingsShortcutRecorderMetrics.cornerRadius
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isRecording
                ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
                : NSColor.labelColor.withAlphaComponent(0.055).cgColor
        }
    }
}

private extension ScreenshotShortcutKey {
    init(event: NSEvent) {
        guard let character = event.charactersIgnoringModifiers?.uppercased().first,
              let scalar = String(character).unicodeScalars.first else {
            self = .unsupported
            return
        }

        switch scalar.value {
        case ShortcutRecorderScalar.capitalA...ShortcutRecorderScalar.capitalZ:
            self = .letter(String(character))
        case ShortcutRecorderScalar.zero...ShortcutRecorderScalar.nine:
            self = .number(String(character))
        default:
            self = .unsupported
        }
    }
}

private enum ShortcutRecorderPreview {
    static func title(
        key: ScreenshotShortcutKey?,
        modifiers: Set<ScreenshotShortcutModifier>
    ) -> String {
        orderedModifiers
            .filter { modifiers.contains($0) }
            .map(\.symbol)
            .joined() + (key?.displayName ?? "")
    }

    private static let orderedModifiers: [ScreenshotShortcutModifier] = [
        .command,
        .option,
        .control,
        .shift,
    ]
}

private extension ScreenshotShortcutModifier {
    static func modifiers(event: NSEvent) -> Set<ScreenshotShortcutModifier> {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = Set<ScreenshotShortcutModifier>()
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        return modifiers
    }
}

private enum ShortcutRecorderScalar {
    static let zero = UnicodeScalar("0").value
    static let nine = UnicodeScalar("9").value
    static let capitalA = UnicodeScalar("A").value
    static let capitalZ = UnicodeScalar("Z").value
}

private let shortcutRecorderEscapeKeyCode: UInt16 = 53
private let shortcutRecorderClearKeyCodes: Set<UInt16> = [UInt16(kVK_Delete), UInt16(kVK_ForwardDelete)]

private struct RecordingSettingsView: View {
    let strings: AppStrings

    @State private var selectedRecordingMouseHintColor = SettingsStore.recordingOptions().mouseHintColor

    var body: some View {
        SettingsSectionGroup(title: strings.settingsRecording) {
            SettingsControlGroup {
                SettingsControlRow(strings.settingsRecordingMouseHintColor) {
                    RecordingMouseHintColorControl(
                        strings: strings,
                        selectedColor: $selectedRecordingMouseHintColor,
                        onChange: updateRecordingMouseHintColor
                    )
                }
            }
        }
        .onAppear(perform: normalizeRecordingMouseHintColor)
    }

    private func updateRecordingMouseHintColor(_ color: RecordingMouseHintColor) {
        selectedRecordingMouseHintColor = color
        let options = SettingsStore.recordingOptions()
        SettingsStore.setRecordingOptions(
            RecordingOptions(
                format: options.format,
                showsCursor: options.showsCursor,
                showsMouseClickHighlights: options.showsMouseClickHighlights,
                showsKeyboardHints: options.showsKeyboardHints,
                audioSource: options.audioSource,
                mouseHintColor: color
            )
        )
    }

    private func normalizeRecordingMouseHintColor() {
        let normalizedColor = RecordingMouseHintColorPreset.normalizedColor(selectedRecordingMouseHintColor)
        guard !selectedRecordingMouseHintColor.isApproximatelyEqual(to: normalizedColor) else {
            return
        }

        updateRecordingMouseHintColor(normalizedColor)
    }
}

private struct TextRecognitionSettingsView: View {
    let strings: AppStrings

    @State private var selectedOCRLanguageIdentifiers = Set(SettingsStore.ocrRecognitionLanguages())
    @State private var isShowingOCRLanguageSheet = false

    var body: some View {
        SettingsSectionGroup(title: strings.settingsTextRecognition) {
            SettingsControlGroup {
                SettingsButtonRow(
                    title: strings.settingsOCRLanguages,
                    value: summaryText,
                    accessibilityLabel: "\(strings.settingsOCRLanguages), \(summaryText), \(strings.settingsChooseOCRLanguages)",
                    action: {
                        isShowingOCRLanguageSheet = true
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingOCRLanguageSheet) {
            OCRLanguageSelectionSheet(
                strings: strings,
                selectedOCRLanguageIdentifiers: $selectedOCRLanguageIdentifiers,
                onDone: {
                    isShowingOCRLanguageSheet = false
                }
            )
        }
    }

    private var summaryText: String {
        strings.settingsOCRLanguagesSelected(
            count: selectedOCRLanguageIdentifiers.count,
            total: OCRLanguageOption.allCases.count
        )
    }
}

private struct OCRLanguageSelectionSheet: View {
    let strings: AppStrings
    @Binding var selectedOCRLanguageIdentifiers: Set<String>
    let onDone: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: SettingsOCRLanguageMetrics.gridMinimumItemWidth), alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(strings.settingsOCRLanguages)
                .font(.system(size: 18, weight: .semibold))

            Text(summaryText)
                .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(
                    columns: columns,
                    alignment: .leading,
                    spacing: SettingsOCRLanguageMetrics.gridSpacing
                ) {
                    ForEach(OCRLanguageOption.allCases) { option in
                        Toggle(
                            strings.ocrLanguageDisplayName(option),
                            isOn: Binding(
                                get: {
                                    selectedOCRLanguageIdentifiers.contains(option.rawValue)
                                },
                                set: { isSelected in
                                    updateOCRLanguage(option, isSelected: isSelected)
                                }
                            )
                        )
                        .accessibilityLabel(strings.ocrLanguageDisplayName(option))
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()

            HStack {
                Spacer()

                Button(strings.done, action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(
            width: SettingsOCRLanguageMetrics.sheetWidth,
            height: SettingsOCRLanguageMetrics.sheetHeight,
            alignment: .topLeading
        )
    }

    private var summaryText: String {
        strings.settingsOCRLanguagesSelected(
            count: selectedOCRLanguageIdentifiers.count,
            total: OCRLanguageOption.allCases.count
        )
    }

    private func updateOCRLanguage(_ option: OCRLanguageOption, isSelected: Bool) {
        var identifiers = selectedOCRLanguageIdentifiers
        if isSelected {
            identifiers.insert(option.rawValue)
        } else {
            identifiers.remove(option.rawValue)
        }

        let validatedIdentifiers = SettingsStore.setOCRRecognitionLanguages(Array(identifiers))
        selectedOCRLanguageIdentifiers = Set(validatedIdentifiers)
    }
}

private struct HistorySettingsView: View {
    let strings: AppStrings
    let onClearCaptureHistory: @MainActor () throws -> Void

    @State private var isCaptureHistoryEnabled = SettingsStore.isCaptureHistoryEnabled()
    @State private var selectedCaptureHistoryRetention = SettingsStore.captureHistoryRetention()
    @State private var selectedCaptureHistorySizeLimit = SettingsStore.captureHistorySizeLimit()
    @State private var isShowingClearConfirmation = false
    @State private var clearStatusMessage: String?
    @State private var clearStatusIsError = false

    var body: some View {
        SettingsControlGroup {
            SettingsControlRow(strings.settingsCaptureHistoryEnabled) {
                Toggle("", isOn: $isCaptureHistoryEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel(strings.settingsCaptureHistoryEnabled)
                    .onChange(of: isCaptureHistoryEnabled) { _, isEnabled in
                        SettingsStore.setCaptureHistoryEnabled(isEnabled)
                    }
            }

            SettingsControlDivider()

            SettingsControlRow(strings.settingsCaptureHistoryRetention) {
                SettingsMenuPicker(
                    strings.settingsCaptureHistoryRetention,
                    value: selectedCaptureHistoryRetention.displayName(strings: strings),
                    selection: $selectedCaptureHistoryRetention
                ) {
                    ForEach(CaptureHistoryRetention.allCases) { retention in
                        Text(retention.displayName(strings: strings))
                            .tag(retention)
                    }
                }
                .disabled(!isCaptureHistoryEnabled)
                .onChange(of: selectedCaptureHistoryRetention) { _, retention in
                    SettingsStore.setCaptureHistoryRetention(retention)
                }
            }

            SettingsControlDivider()

            SettingsControlRow(strings.settingsCaptureHistorySizeLimit) {
                SettingsMenuPicker(
                    strings.settingsCaptureHistorySizeLimit,
                    value: selectedCaptureHistorySizeLimit.displayName(strings: strings),
                    selection: $selectedCaptureHistorySizeLimit
                ) {
                    ForEach(CaptureHistorySizeLimit.settingsCases) { sizeLimit in
                        Text(sizeLimit.displayName(strings: strings))
                            .tag(sizeLimit)
                    }
                }
                .disabled(!isCaptureHistoryEnabled)
                .onChange(of: selectedCaptureHistorySizeLimit) { _, sizeLimit in
                    SettingsStore.setCaptureHistorySizeLimit(sizeLimit)
                }
            }

            SettingsControlDivider()

            HStack(spacing: 12) {
                if let clearStatusMessage {
                    Text(clearStatusMessage)
                        .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
                        .foregroundStyle(clearStatusIsError ? .red : .secondary)
                }

                Spacer()

                Button(strings.settingsCaptureHistoryClear, role: .destructive) {
                    isShowingClearConfirmation = true
                }
            }
            .padding(.horizontal, SettingsGroupMetrics.horizontalPadding)
            .frame(minHeight: SettingsGroupMetrics.rowMinHeight)
        }
        .alert(strings.settingsCaptureHistoryClearConfirmationTitle, isPresented: $isShowingClearConfirmation) {
            Button(strings.settingsCaptureHistoryClear, role: .destructive, action: clearCaptureHistory)
            Button(strings.cancel, role: .cancel) {}
        } message: {
            Text(strings.settingsCaptureHistoryClearConfirmationMessage)
        }
    }

    private func clearCaptureHistory() {
        do {
            try onClearCaptureHistory()
            clearStatusIsError = false
            clearStatusMessage = strings.settingsCaptureHistoryCleared
        } catch {
            clearStatusIsError = true
            clearStatusMessage = strings.settingsCaptureHistoryClearFailed(errorDescription: error.localizedDescription)
        }
    }
}

private struct PermissionsSettingsView: View {
    let strings: AppStrings

    @State private var hasScreenRecordingAccess = ScreenRecordingPermission.hasAccess
    @State private var hasAccessibilityAccess = AccessibilityPermission.hasAccess
    @State private var hasInputMonitoringAccess = InputMonitoringPermission.hasAccess

    var body: some View {
        SettingsControlGroup {
            permissionRow(
                strings.settingsScreenRecordingPermission,
                purpose: strings.settingsScreenRecordingPurpose,
                hasAccess: hasScreenRecordingAccess,
                openSettings: { ScreenRecordingPermission.openSettings(strings: strings) }
            )

            SettingsControlDivider()

            permissionRow(
                strings.settingsAccessibilityPermission,
                purpose: strings.settingsAccessibilityPurpose,
                hasAccess: hasAccessibilityAccess,
                openSettings: AccessibilityPermission.openSettings
            )

            SettingsControlDivider()

            permissionRow(
                strings.settingsInputMonitoringPermission,
                purpose: strings.settingsInputMonitoringPurpose,
                hasAccess: hasInputMonitoringAccess,
                openSettings: InputMonitoringPermission.openSettings
            )
        }
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func permissionRow(
        _ title: String,
        purpose: String,
        hasAccess: Bool,
        openSettings: @escaping () -> Void
    ) -> some View {
        SettingsControlRow(title, subtitle: purpose) {
            if hasAccess {
                Label {
                    Text(strings.settingsPermissionGranted)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
            } else {
                Button(strings.settingsOpenSystemSettings, action: openSettings)
                    .accessibilityLabel("\(title), \(strings.settingsOpenSystemSettings)")
            }
        }
    }

    private func refreshPermissions() {
        hasScreenRecordingAccess = ScreenRecordingPermission.hasAccess
        hasAccessibilityAccess = AccessibilityPermission.hasAccess
        hasInputMonitoringAccess = InputMonitoringPermission.hasAccess
    }
}

enum RecordingMouseHintColorPreset: String, CaseIterable, Identifiable {
    case coral
    case amber
    case sky
    case mint
    case violet

    var id: String {
        rawValue
    }

    static let defaultPreset = RecordingMouseHintColorPreset.coral
    static let standardPresets: [RecordingMouseHintColorPreset] = [.coral, .amber, .sky, .mint, .violet]

    static func normalizedColor(_ color: RecordingMouseHintColor) -> RecordingMouseHintColor {
        standardPresets.first { preset in
            color.isApproximatelyEqual(to: preset.color)
        }?.color ?? defaultPreset.color
    }

    var color: RecordingMouseHintColor {
        switch self {
        case .coral:
            RecordingMouseHintColor(red: 1, green: 0.32, blue: 0.36)
        case .amber:
            RecordingMouseHintColor(red: 1, green: 0.68, blue: 0.18)
        case .sky:
            RecordingMouseHintColor(red: 0.16, green: 0.56, blue: 1)
        case .mint:
            RecordingMouseHintColor(red: 0.2, green: 0.78, blue: 0.52)
        case .violet:
            RecordingMouseHintColor(red: 0.58, green: 0.42, blue: 1)
        }
    }

    func accessibilityLabel(strings: AppStrings) -> String {
        switch (strings.language, self) {
        case (.zhHans, .coral): "珊瑚色"
        case (.en, .coral): "Coral"
        case (.zhHans, .amber): "琥珀色"
        case (.en, .amber): "Amber"
        case (.zhHans, .sky): "天蓝色"
        case (.en, .sky): "Sky"
        case (.zhHans, .mint): "薄荷色"
        case (.en, .mint): "Mint"
        case (.zhHans, .violet): "紫色"
        case (.en, .violet): "Violet"
        }
    }
}

private struct RecordingMouseHintColorControl: View {
    let strings: AppStrings
    @Binding var selectedColor: RecordingMouseHintColor
    let onChange: (RecordingMouseHintColor) -> Void

    var body: some View {
        HStack(spacing: SettingsMouseHintColorMetrics.controlSpacing) {
            ForEach(RecordingMouseHintColorPreset.standardPresets) { preset in
                Button {
                    onChange(preset.color)
                } label: {
                    RecordingMouseHintColorSwatch(
                        color: preset.color,
                        isSelected: selectedColor.isApproximatelyEqual(to: preset.color)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.accessibilityLabel(strings: strings))
            }
        }
    }
}

private struct RecordingMouseHintColorSwatch: View {
    let color: RecordingMouseHintColor
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(Color(nsColor: color.nsColor))
            .overlay {
                Circle()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(1)
                }
            }
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(nsColor: color.selectionGlyphColor))
                }
            }
            .frame(width: SettingsMouseHintColorMetrics.swatchSize, height: SettingsMouseHintColorMetrics.swatchSize)
            .contentShape(Circle())
    }
}

private struct SettingsAboutFooterView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(appName)
                .font(.system(size: 12, weight: .semibold))
            Text("\(versionText) (\(buildText))")
                .font(.system(size: SettingsTypographyMetrics.footerFontSize, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SettingsAboutFooterText.value(appName: appName, version: versionText, build: buildText))
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "dewShot"
    }

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? FrameVersion.shortVersion
    }

    private var buildText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? FrameVersion.build
    }
}

enum SettingsAboutFooterText {
    static func value(appName: String, version: String, build: String) -> String {
        "\(appName) · Version \(version) · Build \(build)"
    }
}

private struct SettingsSectionGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsSectionGroupMetrics.titleSpacing) {
            Text(title)
                .font(.system(size: SettingsTypographyMetrics.sectionFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private extension RecordingMouseHintColor {
    func isApproximatelyEqual(to color: RecordingMouseHintColor) -> Bool {
        abs(red - color.red) < 0.001
            && abs(green - color.green) < 0.001
            && abs(blue - color.blue) < 0.001
            && abs(alpha - color.alpha) < 0.001
    }

    var selectionGlyphColor: NSColor {
        let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
        return luminance > 0.62 ? .black : .white
    }
}
