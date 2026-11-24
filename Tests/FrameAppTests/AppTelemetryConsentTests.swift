import XCTest
@testable import FrameApp

final class AppTelemetryConsentTests: XCTestCase {
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
