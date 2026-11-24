import AppKit
import XCTest
@testable import FrameApp

final class PermissionGuidePanelTests: XCTestCase {
    @MainActor
    func testGuidePinsSettingsEvenWhenAFilePickerIsLargerAndFrontmost() {
        let settings = (id: CGWindowID(15), frame: CGRect(x: 0, y: 0, width: 700, height: 600))
        let picker = (id: CGWindowID(16), frame: CGRect(x: 0, y: 0, width: 900, height: 800))
        let moved = (id: settings.id, frame: settings.frame.offsetBy(dx: 210, dy: 70))
        XCTAssertEqual(PermissionGuidePanel.settingsAnchor(in: [picker, settings], pinnedID: nil)?.id, settings.id)
        XCTAssertEqual(PermissionGuidePanel.settingsAnchor(in: [picker, moved], pinnedID: settings.id)?.frame, moved.frame)
        XCTAssertNil(PermissionGuidePanel.settingsAnchor(in: [picker], pinnedID: settings.id))
    }

    @MainActor
    func testGuideUsesOpenSpaceBesideSettingsOnExternalDisplay() {
        let screen = CGRect(x: -1440, y: 40, width: 1440, height: 840)
        let settings = CGRect(x: -1350, y: 130, width: 850, height: 710)
        let size = CGSize(width: 310, height: 160)

        let origin = PermissionGuidePanel.origin(for: size, beside: settings, in: screen)

        XCTAssertEqual(origin, CGPoint(x: -488, y: 680))
        XCTAssertFalse(settings.intersects(CGRect(origin: origin, size: size)))
    }

    @MainActor
    func testGuideMovesBelowSettingsWhenNeitherSideFits() {
        let screen = CGRect(x: 0, y: 40, width: 1200, height: 860)
        let settings = CGRect(x: 190, y: 275, width: 850, height: 600)
        let size = CGSize(width: 310, height: 160)

        let origin = PermissionGuidePanel.origin(for: size, beside: settings, in: screen)

        XCTAssertEqual(origin, CGPoint(x: 460, y: 103))
    }

    @MainActor
    func testGuideStaysVisibleWhenSettingsFillsDisplay() {
        let screen = CGRect(x: 0, y: 40, width: 1200, height: 860)
        let size = CGSize(width: 310, height: 160)

        let origin = PermissionGuidePanel.origin(for: size, beside: screen, in: screen)

        XCTAssertTrue(screen.contains(CGRect(origin: origin, size: size)))
        XCTAssertLessThan(origin.x, screen.midX)
    }
}
