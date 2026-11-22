import AppKit
import Carbon
import SwiftUI
import XCTest
import FrameCore
@testable import FrameApp

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testSettingsNavigationKeepsCategoriesInProductOrder() {
        let sections: [SettingsSection] = [.general, .capture, .history, .permissions]
        XCTAssertEqual(SettingsSection.allCases, sections)
        XCTAssertEqual(sections.map { $0.title(strings: AppStrings(language: .zhHans)) }, [
            "通用", "捕获", "历史", "权限",
        ])
        XCTAssertEqual(sections.map { $0.title(strings: AppStrings(language: .en)) }, [
            "General", "Capture", "History", "Permissions",
        ])
    }

    func testSettingsTypographyUsesSystemFontsAndReadableRows() {
        XCTAssertTrue(SettingsTypographyMetrics.usesSystemFont)
        XCTAssertTrue(SettingsTypographyMetrics.usesMediumRowLabels)
        XCTAssertEqual(SettingsTypographyMetrics.sectionFontSize, 13, accuracy: 0.5)
        XCTAssertEqual(SettingsTypographyMetrics.rowFontSize, 13, accuracy: 0.5)
        XCTAssertEqual(SettingsTypographyMetrics.secondaryFontSize, 12, accuracy: 0.5)
        XCTAssertEqual(SettingsTypographyMetrics.footerFontSize, 11, accuracy: 0.5)
    }

    func testAboutFooterUsesEnglishPlaceholderText() {
        XCTAssertEqual(
            SettingsAboutFooterText.value(appName: "Frame", version: "0.1.0", build: "1"),
            "Frame · Version 0.1.0 · Build 1"
        )
    }

    func testScreenshotShortcutSettingsUseInlineRecorder() {
        XCTAssertTrue(SettingsGeneralMetrics.containsLaunchAtLogin)
        XCTAssertTrue(SettingsGeneralMetrics.containsScreenshotShortcut)
        XCTAssertTrue(SettingsGeneralMetrics.containsRecordingShortcut)
        XCTAssertFalse(SettingsScreenshotMetrics.containsShortcut)
        XCTAssertTrue(SettingsShortcutRecorderMetrics.usesInlineRecorder)
        XCTAssertEqual(SettingsShortcutRecorderMetrics.width, 118, accuracy: 0.5)
        XCTAssertEqual(SettingsShortcutRecorderMetrics.minHeight, 28, accuracy: 0.5)
        XCTAssertEqual(SettingsShortcutRecorderMetrics.cornerRadius, 7, accuracy: 0.5)
    }

    func testScreenshotStylePickerIncludesOriginalOutputOption() {
        XCTAssertEqual(WindowScreenshotDecorationStyle.allCases, [
            .softBackdrop,
            .canvasGlow,
            .transparentShadow,
            .original,
        ])
    }

    func testScreenshotSettingsIncludeImageWorkspaceSaveCurrentBehavior() {
        XCTAssertTrue(SettingsScreenshotMetrics.containsImageWorkspaceSaveCurrentBehavior)
        XCTAssertEqual(ImageWorkspaceSaveCurrentBehavior.allCases, [
            .askEveryTime,
            .replaceCurrent,
            .saveAsNew,
        ])
    }

    func testSaveLocationSettingsUseCompactSummaryRow() {
        XCTAssertTrue(SettingsGeneralMetrics.containsSaveLocation)
        XCTAssertFalse(SettingsScreenshotMetrics.containsSaveLocation)
        XCTAssertTrue(SettingsSaveLocationMetrics.usesSummaryRow)
        XCTAssertFalse(SettingsSaveLocationMetrics.opensChooserFromSummary)
        XCTAssertFalse(SettingsSaveLocationMetrics.showsFinderAction)
        XCTAssertFalse(SettingsSaveLocationMetrics.showsFolderName)
        XCTAssertTrue(SettingsSaveLocationMetrics.showsResetOnlyForCustomLocation)
        XCTAssertFalse(SettingsSaveLocationMetrics.usesNestedControlBackground)
        XCTAssertFalse(SettingsSaveLocationMetrics.usesSeparateRevealBox)
    }

    func testSaveLocationSummaryUsesAbbreviatedPathForDefaultDirectory() {
        let homeURL = URL(fileURLWithPath: "/Users/deweyou", isDirectory: true)
        let desktopURL = homeURL.appendingPathComponent("Desktop", isDirectory: true)

        let summary = SettingsSaveLocationSummary(
            url: desktopURL,
            desktopURL: desktopURL,
            homeURL: homeURL
        )

        XCTAssertEqual(summary.path, "~/Desktop")
        XCTAssertTrue(summary.isDefaultLocation)
    }

    func testSaveLocationSummaryAbbreviatesCustomDirectoryUnderHome() {
        let homeURL = URL(fileURLWithPath: "/Users/deweyou", isDirectory: true)
        let desktopURL = homeURL.appendingPathComponent("Desktop", isDirectory: true)
        let customURL = homeURL
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Frame Captures", isDirectory: true)

        let summary = SettingsSaveLocationSummary(
            url: customURL,
            desktopURL: desktopURL,
            homeURL: homeURL
        )

        XCTAssertEqual(summary.path, "~/Pictures/Frame Captures")
        XCTAssertFalse(summary.isDefaultLocation)
    }

    func testShortcutRecorderSuspendsGlobalHotKeyWhileRecording() {
        let button = ShortcutRecorderButton(frame: .zero)
        var recordingStates: [Bool] = []
        var appliedShortcuts: [ScreenshotShortcut?] = []
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { shortcut in
                appliedShortcuts.append(shortcut)
                return true
            },
            onValidationFailure: { _ in },
            onRecordingChange: { isRecording in
                recordingStates.append(isRecording)
            }
        )

        button.startRecording()
        button.keyDown(with: keyEvent(characters: "a", modifiers: [.command, .shift], keyCode: kVK_ANSI_A))

        XCTAssertEqual(recordingStates, [true, false])
        XCTAssertEqual(appliedShortcuts, [.default])
    }

    func testShortcutRecorderStopsRecordingWhenFirstResponderMovesElsewhere() {
        let button = ShortcutRecorderButton(frame: .zero)
        var recordingStates: [Bool] = []
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { _ in true },
            onValidationFailure: { _ in },
            onRecordingChange: { isRecording in
                recordingStates.append(isRecording)
            }
        )

        button.startRecording()
        XCTAssertEqual(button.title, "Press shortcut")

        XCTAssertTrue(button.resignFirstResponder())

        XCTAssertEqual(button.title, "⌘⇧A")
        XCTAssertEqual(recordingStates, [true, false])
    }

    func testRecordingShortcutRecorderCanClearShortcut() {
        let button = ShortcutRecorderButton(frame: .zero)
        var appliedShortcuts: [ScreenshotShortcut?] = []
        button.update(
            strings: AppStrings(language: .en),
            shortcut: ScreenshotShortcut(key: .number("8"), modifiers: [.command, .control]),
            allowsEmptyShortcut: true,
            onShortcutChange: { shortcut in
                appliedShortcuts.append(shortcut)
                return true
            },
            onValidationFailure: { _ in },
            onRecordingChange: { _ in }
        )

        button.startRecording()
        button.keyDown(with: keyEvent(characters: "\u{7F}", modifiers: [], keyCode: kVK_Delete))

        XCTAssertEqual(button.title, "Not set")
        XCTAssertEqual(appliedShortcuts.count, 1)
        XCTAssertNil(appliedShortcuts.first!)
    }

    func testShortcutRecorderShowsEmptyShortcutTitle() {
        let strings = AppStrings(language: .zhHans)
        let button = ShortcutRecorderButton(frame: .zero)
        button.update(
            strings: strings,
            shortcut: nil,
            allowsEmptyShortcut: true,
            onShortcutChange: { _ in true },
            onValidationFailure: { _ in },
            onRecordingChange: { _ in }
        )

        XCTAssertEqual(strings.settingsShortcutRecorderUnset, "未设置")
        XCTAssertEqual(button.title, "未设置")
    }

    func testShortcutRecorderResumesGlobalHotKeyWhenCancelled() {
        let button = ShortcutRecorderButton(frame: .zero)
        var recordingStates: [Bool] = []
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { _ in true },
            onValidationFailure: { _ in },
            onRecordingChange: { isRecording in
                recordingStates.append(isRecording)
            }
        )

        button.startRecording()
        button.keyDown(with: keyEvent(characters: "\u{1B}", modifiers: [], keyCode: 53))

        XCTAssertEqual(recordingStates, [true, false])
    }

    func testShortcutRecorderShowsPressedModifiersWhileRecording() {
        let button = ShortcutRecorderButton(frame: .zero)
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { _ in true },
            onValidationFailure: { _ in },
            onRecordingChange: { _ in }
        )

        button.startRecording()
        button.flagsChanged(with: flagsChangedEvent(modifiers: [.command], keyCode: kVK_Command))
        XCTAssertEqual(button.title, "⌘")

        button.flagsChanged(with: flagsChangedEvent(modifiers: [.command, .shift], keyCode: kVK_Shift))
        XCTAssertEqual(button.title, "⌘⇧")

        button.flagsChanged(with: flagsChangedEvent(modifiers: [], keyCode: kVK_Shift))
        XCTAssertEqual(button.title, "Press shortcut")
    }

    func testShortcutRecorderShowsInvalidPressedCombinationWhileRecording() {
        let button = ShortcutRecorderButton(frame: .zero)
        var failures: [ScreenshotShortcutValidationFailure?] = []
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { _ in true },
            onValidationFailure: { failure in
                failures.append(failure)
            },
            onRecordingChange: { _ in }
        )

        button.startRecording()
        button.keyDown(with: keyEvent(characters: "a", modifiers: [], keyCode: kVK_ANSI_A))

        XCTAssertEqual(button.title, "A")
        XCTAssertEqual(failures, [nil, .insufficientModifiers])
    }

    func testShortcutRecorderCanReportDuplicateShortcut() {
        let strings = AppStrings(language: .en)

        XCTAssertEqual(
            strings.settingsShortcutRecorderError(.duplicateShortcut),
            "Already used by another Frame shortcut"
        )
    }

    func testShortcutRecorderKeepsPressedCombinationAfterViewUpdate() {
        let button = ShortcutRecorderButton(frame: .zero)
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { _ in true },
            onValidationFailure: { _ in },
            onRecordingChange: { _ in }
        )

        button.startRecording()
        button.keyDown(with: keyEvent(characters: "a", modifiers: [.shift], keyCode: kVK_ANSI_A))
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { _ in true },
            onValidationFailure: { _ in },
            onRecordingChange: { _ in }
        )

        XCTAssertEqual(button.title, "⇧A")
    }

    func testSettingsWindowUsesConfiguredMinimumSize() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = SettingsWindowController()

        controller.show(
            strings: AppStrings(language: .en),
            onShortcutChange: { _ in true },
            onLanguageChange: { _ in },
            onChooseScreenshotDirectory: { nil },
            onResetScreenshotDirectory: {},
            onClearCaptureHistory: {}
        )

        let window = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) })
        defer {
            window.close()
        }

        XCTAssertEqual(window.minSize.width, 688, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(window.minSize.height, SettingsWindowLayout.minimumSize.height)
        XCTAssertEqual(window.frame.size.width, 752, accuracy: 0.5)
        XCTAssertEqual(window.frame.size.height, 556, accuracy: 0.5)
        XCTAssertEqual(window.title, "Settings")
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))

        let split = try XCTUnwrap(window.contentViewController as? NSSplitViewController)
        XCTAssertTrue(split.splitView.isVertical)
        XCTAssertEqual(split.splitViewItems.map(\.behavior), [.sidebar, .default])
        XCTAssertTrue(split.splitViewItems[0].allowsFullHeightLayout)
        XCTAssertFalse(split.splitViewItems[0].canCollapse)
        if #available(macOS 26.0, *) {
            XCTAssertTrue(split.splitViewItems[1].automaticallyAdjustsSafeAreaInsets)
        }
        controller.update(strings: AppStrings(language: .zhHans))
        XCTAssertEqual(window.title, "设置")
    }

    func testOCRLanguageSettingsExposeDefaultOptions() {
        XCTAssertEqual(OCRLanguageOption.allCases.map(\.rawValue).count, 25)
        XCTAssertEqual(OCRLanguageOption.defaultIdentifiers.count, 5)
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("zh-Hans"))
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("zh-Hant"))
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("en-US"))
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("ja-JP"))
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("ko-KR"))
    }

    func testOCRLanguageSettingsOpenDedicatedChooserFromWholeRow() {
        XCTAssertFalse(SettingsOCRLanguageMetrics.usesDisclosure)
        XCTAssertTrue(SettingsOCRLanguageMetrics.usesSheet)
        XCTAssertTrue(SettingsOCRLanguageMetrics.opensFromWholeRow)
        XCTAssertEqual(SettingsOCRLanguageMetrics.sheetWidth, 420, accuracy: 0.5)
        XCTAssertEqual(SettingsOCRLanguageMetrics.sheetHeight, 460, accuracy: 0.5)
        XCTAssertEqual(SettingsOCRLanguageMetrics.gridMinimumItemWidth, 180, accuracy: 0.5)
        XCTAssertEqual(SettingsOCRLanguageMetrics.gridSpacing, 8, accuracy: 0.5)
    }

    func testRecordingMouseHintColorPresetsExposeDefaultAndCustomChoices() {
        XCTAssertEqual(RecordingMouseHintColorPreset.defaultPreset, .coral)
        XCTAssertEqual(RecordingMouseHintColorPreset.standardPresets.map(\.id), [
            "coral",
            "amber",
            "sky",
            "mint",
            "violet",
        ])
    }

    func testRecordingMouseHintColorPresetsExposeLocalizedAccessibilityLabels() {
        let strings = AppStrings(language: .zhHans)

        XCTAssertEqual(
            RecordingMouseHintColorPreset.standardPresets.map { $0.accessibilityLabel(strings: strings) },
            ["珊瑚色", "琥珀色", "天蓝色", "薄荷色", "紫色"]
        )
    }

    func testRecordingMouseHintColorUsesQuietSwatchPickerMetrics() {
        XCTAssertTrue(SettingsMouseHintColorMetrics.usesSwatchPicker)
        XCTAssertTrue(SettingsMouseHintColorMetrics.usesPresetOnlyPicker)
        XCTAssertTrue(SettingsMouseHintColorMetrics.usesSelectedCheckmark)
        XCTAssertFalse(SettingsMouseHintColorMetrics.showsCustomColorPicker)
        XCTAssertFalse(SettingsMouseHintColorMetrics.showsResetAction)
        XCTAssertEqual(SettingsMouseHintColorMetrics.swatchSize, 24, accuracy: 0.5)
    }

    func testSettingsWindowPlacementCentersInsideActiveVisibleFrame() {
        let visibleFrame = CGRect(x: 1440, y: 80, width: 1200, height: 800)
        let frame = SettingsWindowLayout.centeredFrame(
            windowSize: CGSize(width: 900, height: 540),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.5)
        XCTAssertEqual(frame.width, 900, accuracy: 0.5)
        XCTAssertEqual(frame.height, 540, accuracy: 0.5)
    }

    private func keyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags,
        keyCode: Int
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }

    private func flagsChangedEvent(
        modifiers: NSEvent.ModifierFlags,
        keyCode: Int
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }
}
