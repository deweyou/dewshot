import AppKit
import FrameCore
import SwiftUI
import XCTest
@testable import FrameApp

final class FirstRunSetupTests: XCTestCase {
    func testOnlyFinishedProgressUnlocksTheApp() {
        XCTAssertTrue(FirstRunSetupProgress.new.requiresSetup)
        XCTAssertTrue(FirstRunSetupProgress.inProgress.requiresSetup)
        XCTAssertFalse(FirstRunSetupProgress.finished.requiresSetup)
    }

    @MainActor
    func testPermissionActionRequestsOnceThenReturnsToSettingsUntilGranted() {
        var hasAccess = false
        var requests = 0
        var settingsOpens = 0
        let state = FirstRunSetupState(
            hasAccess: { hasAccess },
            requestAccess: { requests += 1 },
            openSettings: { settingsOpens += 1 }
        )

        XCTAssertEqual(state.phase, .needsPermission)
        state.requestPermission()
        state.requestPermission()
        XCTAssertEqual(state.phase, .waitingForPermission)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(settingsOpens, 2)

        hasAccess = true
        state.refresh()
        XCTAssertEqual(state.phase, .ready)
        state.requestPermission()
        XCTAssertEqual(settingsOpens, 2)
    }

    @MainActor
    func testPermissionGrantedByTheSystemPromptSkipsOpeningSettings() {
        var hasAccess = false
        let state = FirstRunSetupState(
            hasAccess: { hasAccess },
            requestAccess: { hasAccess = true },
            openSettings: { XCTFail("Opening Settings after access is granted") }
        )

        state.requestPermission()
        XCTAssertEqual(state.phase, .ready)
    }

    @MainActor
    func testOptionalPermissionsCanChangeWithoutBlockingCapture() {
        var optionalPermissions: Set<PermissionSettingsPage> = []
        let state = FirstRunSetupState(
            hasAccess: { true },
            requestAccess: {},
            openSettings: {},
            readOptionalPermissions: { optionalPermissions }
        )

        XCTAssertEqual(state.phase, .ready)
        XCTAssertTrue(state.grantedOptionalPermissions.isEmpty)

        optionalPermissions = [.accessibility]
        state.refresh()
        XCTAssertEqual(state.grantedOptionalPermissions, [.accessibility])
        XCTAssertEqual(state.phase, .ready)
    }

    @MainActor
    func testWelcomeViewFitsBothLanguagesAcrossPermissionPhases() {
        _ = NSApplication.shared
        for strings in [AppStrings(language: .en), AppStrings(language: .zhHans)] {
            var hasAccess = false
            let state = FirstRunSetupState(
                hasAccess: { hasAccess },
                requestAccess: {},
                openSettings: {}
            )
            let view = FirstRunSetupView(
                strings: strings,
                screenshotShortcut: .default,
                recordingShortcut: .defaultRecording,
                state: state,
                onStartCapture: {}
            )

            var fittedHeights: [CGFloat] = []
            for phase in [FirstRunSetupState.Phase.needsPermission, .waitingForPermission, .ready] {
                if phase == .waitingForPermission { state.requestPermission() }
                if phase == .ready {
                    hasAccess = true
                    state.refresh()
                }
                let host = NSHostingView(rootView: view)
                XCTAssertEqual(host.fittingSize.width, 476)
                XCTAssertGreaterThan(host.fittingSize.height, 450)
                XCTAssertLessThan(host.fittingSize.height, 620)
                fittedHeights.append(host.fittingSize.height)
            }
            XCTAssertEqual(Set(fittedHeights).count, 1, "\(strings.language) heights: \(fittedHeights)")
        }
    }

    @MainActor
    func testWelcomeRecorderRejectsDuplicateAndAppliesReplacement() throws {
        _ = NSApplication.shared
        var applied: [(HotKeyController.HotKeyKind, ScreenshotShortcut?)] = []
        let status = ShortcutRegistrationStatus()
        status.messages[.screenshot] = "Shortcut already in use"
        let view = FirstRunSetupView(
            strings: AppStrings(language: .en), screenshotShortcut: .default, recordingShortcut: .defaultRecording,
            state: FirstRunSetupState(hasAccess: { false }, requestAccess: {}, openSettings: {}),
            shortcutControls: FirstRunShortcutControls(status: status, apply: { kind, shortcut in
                applied.append((kind, shortcut))
                return nil
            }), onStartCapture: {}
        )
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func recorders(in view: NSView) -> [ShortcutRecorderButton] {
            if let button = view as? ShortcutRecorderButton { return [button] }
            return view.subviews.flatMap { recorders(in: $0) }
        }
        let buttons = recorders(in: host)
        XCTAssertEqual(buttons.count, 2)
        let recorder = try XCTUnwrap(buttons.first { $0.title == ScreenshotShortcut.default.displayName })
        let recording = try XCTUnwrap(buttons.first { $0.title == ScreenshotShortcut.defaultRecording.displayName })
        let top = recorder.convert(recorder.bounds, to: nil)
        let bottom = recording.convert(recording.bounds, to: nil)
        XCTAssertGreaterThanOrEqual(top.minY, bottom.maxY)
        XCTAssertEqual(top.minX, bottom.minX, accuracy: 1)
        XCTAssertEqual(recorder.toolTip, status.messages[.screenshot])
        XCTAssertEqual(recorder.accessibilityHelp(), recorder.toolTip)
        func press(_ letter: String, code: UInt16) throws {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [.command, .shift], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: letter, charactersIgnoringModifiers: letter,
                isARepeat: false, keyCode: code))
            recorder.keyDown(with: event)
        }
        recorder.startRecording()
        try press("r", code: 15)
        XCTAssertTrue(applied.isEmpty)
        try press("k", code: 40)
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.0, .screenshot)
        XCTAssertEqual(applied.first?.1?.key, .letter("K"))
    }

    @MainActor
    func testStartRequiresScreenAccessAndTwoAvailableShortcuts() {
        var granted = false
        let state = FirstRunSetupState(hasAccess: { granted }, requestAccess: {}, openSettings: {})
        let status = ShortcutRegistrationStatus()
        func welcome(_ screenshot: ScreenshotShortcut?, _ recording: ScreenshotShortcut?) -> FirstRunSetupView {
            FirstRunSetupView(strings: AppStrings(language: .en), screenshotShortcut: screenshot,
                              recordingShortcut: recording, state: state,
                              shortcutControls: FirstRunShortcutControls(status: status), onStartCapture: {})
        }
        XCTAssertFalse(welcome(.default, .defaultRecording).canStartCapture)
        granted = true
        state.refresh()
        XCTAssertFalse(welcome(nil, .defaultRecording).canStartCapture)
        XCTAssertFalse(welcome(.default, nil).canStartCapture)
        XCTAssertFalse(welcome(.default, .default).canStartCapture)
        for kind in [HotKeyController.HotKeyKind.screenshot, .recording] {
            status.messages[kind] = "Conflict"
            XCTAssertFalse(welcome(.default, .defaultRecording).canStartCapture)
            status.messages[kind] = nil
        }
        XCTAssertTrue(welcome(.default, .defaultRecording).canStartCapture)
    }

    @MainActor
    func testWelcomeViewWrapsLongShortcutsWithoutClipping() {
        _ = NSApplication.shared
        let modifiers = Set(ScreenshotShortcutModifier.allCases)
        let host = NSHostingView(rootView: FirstRunSetupView(
            strings: AppStrings(language: .en),
            screenshotShortcut: ScreenshotShortcut(key: .letter("A"), modifiers: modifiers),
            recordingShortcut: ScreenshotShortcut(key: .letter("R"), modifiers: modifiers),
            state: FirstRunSetupState(hasAccess: { false }, requestAccess: {}, openSettings: {}),
            onStartCapture: {}
        ))

        XCTAssertEqual(host.fittingSize.width, 476)
        XCTAssertLessThan(host.fittingSize.height, 620)
    }
}
