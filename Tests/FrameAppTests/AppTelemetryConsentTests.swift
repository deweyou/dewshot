import XCTest
@testable import FrameApp

final class AppTelemetryConsentTests: XCTestCase {
    @MainActor
    func testWelcomeSharingDefaultsToOnOnlyForStoreBuildsAndRespectsSavedChoice() throws {
        let suite = "WelcomeSharingTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for bundleID in ["dev.deweyou.dewshot.dev", "unknown"] {
            XCTAssertFalse(AppTelemetry.defaultWelcomeSharing(bundleID: bundleID))
            AppTelemetry.applyWelcomeDefaultIfNeeded(bundleID: bundleID, defaults: defaults)
            XCTAssertNil(defaults.object(forKey: AppTelemetry.consentKey))
        }

        let store = "dev.deweyou.dewshot"
        XCTAssertTrue(AppTelemetry.defaultWelcomeSharing(bundleID: store))
        XCTAssertNil(defaults.object(forKey: AppTelemetry.consentKey))
        AppTelemetry.applyWelcomeDefaultIfNeeded(bundleID: store, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: AppTelemetry.consentKey))
        defaults.set(false, forKey: AppTelemetry.consentKey)
        AppTelemetry.applyWelcomeDefaultIfNeeded(bundleID: store, defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: AppTelemetry.consentKey))
    }

    @MainActor
    func testOnlyLocalDevelopmentClearsPreviousConsentAtLaunch() throws {
        let suite = "AppTelemetryConsentTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for previouslyEnabled in [false, true] {
            for bundleID in ["dev.deweyou.dewshot", "dev.deweyou.dewshot.dev"] {
                defaults.set(previouslyEnabled, forKey: AppTelemetry.consentKey)
                AppTelemetry.resetDevelopmentConsentOnLaunch(bundleID: bundleID, defaults: defaults)
                XCTAssertEqual(defaults.bool(forKey: AppTelemetry.consentKey),
                               bundleID == "dev.deweyou.dewshot" && previouslyEnabled)
            }
        }
    }
}
