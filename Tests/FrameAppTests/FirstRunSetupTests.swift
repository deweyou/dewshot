import AppKit
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
                shortcut: .default,
                icon: NSImage(size: CGSize(width: 64, height: 64)),
                state: state,
                onLater: {},
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
                XCTAssertGreaterThan(host.fittingSize.height, 340)
                XCTAssertLessThan(host.fittingSize.height, 480)
                fittedHeights.append(host.fittingSize.height)
            }
            XCTAssertEqual(Set(fittedHeights).count, 1)
        }
    }
}
