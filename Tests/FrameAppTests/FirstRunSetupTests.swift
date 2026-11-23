import AppKit
import FrameCore
import SwiftUI
import XCTest
@testable import FrameApp

final class FirstRunSetupTests: XCTestCase {
    func testLaunchShowsSetupForNewUsersWithoutAccessAndResumesAfterRelaunch() {
        XCTAssertTrue(FirstRunSetupProgress.new.shouldShowOnLaunch(hasAccess: false))
        XCTAssertFalse(FirstRunSetupProgress.new.shouldShowOnLaunch(hasAccess: true))
        XCTAssertTrue(FirstRunSetupProgress.inProgress.shouldShowOnLaunch(hasAccess: true))
        XCTAssertTrue(FirstRunSetupProgress.inProgress.shouldShowOnLaunch(hasAccess: false))
        XCTAssertFalse(FirstRunSetupProgress.finished.shouldShowOnLaunch(hasAccess: false))
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
                icon: NSImage(size: CGSize(width: 64, height: 64)),
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
            XCTAssertEqual(Set(fittedHeights).count, 1)
        }
    }

    @MainActor
    func testWelcomeViewWrapsLongShortcutsWithoutClipping() {
        _ = NSApplication.shared
        let modifiers = Set(ScreenshotShortcutModifier.allCases)
        let host = NSHostingView(rootView: FirstRunSetupView(
            strings: AppStrings(language: .en),
            screenshotShortcut: ScreenshotShortcut(key: .letter("A"), modifiers: modifiers),
            recordingShortcut: ScreenshotShortcut(key: .letter("R"), modifiers: modifiers),
            icon: NSImage(size: CGSize(width: 64, height: 64)),
            state: FirstRunSetupState(hasAccess: { false }, requestAccess: {}, openSettings: {}),
            onStartCapture: {}
        ))

        XCTAssertEqual(host.fittingSize.width, 476)
        XCTAssertLessThan(host.fittingSize.height, 620)
    }
}
