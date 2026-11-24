import FirebaseAnalytics
import FirebaseCore
import Foundation
import Sentry
import SwiftUI
import StoreKit

@MainActor
enum AppTelemetry {
    static let consentKey = "shareUsageAndDiagnostics"
    private static var active = false
    private static var configuredFirebase = false

    private static var resolving: Task<Void, Never>?
    private static var pendingSetup: [(Bool, Bool)] = []
    private static let cache = URL.cachesDirectory.appending(path: "DewShotDiagnostics")

    enum Stage: String {
        case overlayReady = "overlay_ready"
        case screenshotPreview = "screenshot_preview_ready"
        case scrollFinalize = "scroll_finalize"
        case recordingStart = "recording_start"
        case recordingFinalize = "recording_finalize"
    }

    enum Source: String { case preview, history, pinned, automatic }
    enum Action: String { case copy, save, pin, open }
    enum Media: String { case screenshot, recording }

    static func resetDevelopmentConsentOnLaunch(bundleID: String?, defaults: UserDefaults) {
        if bundleID == "dev.deweyou.dewshot.dev" {
            defaults.removeObject(forKey: consentKey)
        }
    }

    static func refresh() {
        guard UserDefaults.standard.bool(forKey: consentKey) else {
            resolving?.cancel()
            resolving = nil
            pendingSetup.removeAll()
            if active {
                Analytics.setAnalyticsCollectionEnabled(false)
                Analytics.resetAnalyticsData()
                // Closing Sentry flushes its queue. Discard pending envelopes first.
                try? FileManager.default.removeItem(at: cache)
                SentrySDK.close()
                active = false
            }
            try? FileManager.default.removeItem(at: cache)
            return
        }
        guard !active, resolving == nil else { return }
        let id = Bundle.main.bundleIdentifier
        if id == "dev.deweyou.dewshot.dev" {
            start(channel: "development")
        } else if id == "dev.deweyou.dewshot" {
            resolving = Task {
                let transaction = try? await AppTransaction.shared
                guard !Task.isCancelled else { return }
                defer { resolving = nil; pendingSetup.removeAll() }
                guard case let .verified(app) = transaction, app.bundleID == id else { return }
                if app.environment == .production { start(channel: "production") }
                if app.environment == .sandbox { start(channel: "testflight") }
                for (granted, transition) in pendingSetup where active {
                    setup(granted: granted, transition: transition)
                }
            }
        }
    }

    private static func start(channel: String) {
        guard UserDefaults.standard.bool(forKey: consentKey), let id = Bundle.main.bundleIdentifier,
              ["dev.deweyou.dewshot.dev", "dev.deweyou.dewshot"].contains(id),
              let path = Bundle.main.path(forResource: "GoogleService-\(channel)", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path), options.bundleID == id,
              let url = Bundle.main.url(forResource: "sentry-\(channel)", withExtension: "txt"),
              let dsn = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !dsn.isEmpty else { return }
        if !configuredFirebase {
            FirebaseApp.configure(options: options)
            configuredFirebase = true
        }
        Analytics.setAnalyticsCollectionEnabled(true)
        SentrySDK.start { configuration in
            configuration.dsn = dsn
            configuration.environment = channel
            configuration.cacheDirectoryPath = cache.appending(path: channel).path
            configuration.beforeSend = { event in
                guard UserDefaults.standard.bool(forKey: "shareUsageAndDiagnostics") else { return nil }
                event.message = nil
                event.user = nil
                event.extra = nil
                event.context = nil
                event.request = nil
                event.breadcrumbs = nil
                for exception in event.exceptions ?? [] {
                    exception.value = nil
                    exception.mechanism?.data = nil
                    exception.mechanism?.desc = nil
                }
                let traces = (event.threads ?? []).compactMap(\.stacktrace)
                    + (event.exceptions ?? []).compactMap(\.stacktrace) + [event.stacktrace].compactMap { $0 }
                for trace in traces {
                    for frame in trace.frames {
                        frame.fileName = nil
                        frame.vars = nil
                        frame.preContext = nil
                        frame.postContext = nil
                        frame.contextLine = nil
                        frame.package = frame.package.map { URL(fileURLWithPath: $0).lastPathComponent }
                    }
                }
                for image in event.debugMeta ?? [] {
                    image.codeFile = image.codeFile.map { URL(fileURLWithPath: $0).lastPathComponent }
                }
                return event
            }
            configuration.shutdownTimeInterval = 0
            configuration.sendDefaultPii = false
            configuration.maxBreadcrumbs = 0
            configuration.enableAutoBreadcrumbTracking = false
            configuration.enableAutoSessionTracking = false
            configuration.enableCaptureFailedRequests = false
            configuration.enableNetworkTracking = false
            configuration.enableSwizzling = false
            configuration.enableAppHangTracking = false
        }
        active = true
    }

    static func setup(granted: Bool, transition: Bool = false) {
        guard active else {
            if resolving != nil && UserDefaults.standard.bool(forKey: consentKey) {
                pendingSetup.append((granted, transition))
            }
            return
        }
        Analytics.logEvent("setup_step", parameters: [
            "step": transition ? "access_granted" : "viewed",
            "screen_access": granted ? "granted" : "missing"
        ])
    }

    static func capture(_ stage: Stage, since start: ContinuousClock.Instant?, fields: [String: String], failed: Bool = false) {
        var parameters = fields
        parameters["stage"] = stage.rawValue
        result("capture_step", fields: parameters, start: start, failed: failed, operation: stage.rawValue)
    }

    static func action(_ action: Action, source: Source, media: Media, success: Bool, since start: ContinuousClock.Instant? = nil, disposition: String? = nil, error: Error? = nil) {
        var fields = ["action": action.rawValue, "source": source.rawValue, "media": media.rawValue]
        fields["disposition"] = disposition
        result("capture_action", fields: fields,
               start: start, failed: !success, operation: action.rawValue, error: error)
    }

    private static func result(_ event: String, fields: [String: String], start: ContinuousClock.Instant?, failed: Bool, operation: String, error: Error? = nil) {
        guard active else { return }
        var parameters: [String: Any] = fields
        parameters["outcome"] = failed ? "failure" : "success"
        if let start {
            let elapsed = start.duration(to: .now).components
            let ms = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
            parameters["duration_ms"] = ms
            parameters["duration_bucket"] = [100, 300, 1000, 3000, 10000].first(where: { ms < $0 }).map { "lt_\($0)" } ?? "ge_10000"
        }
        if failed {
            var underlying = error
            if case let .writeFailed(cause, _) = error as? ScreenshotFileWriterError { underlying = cause }
            let diskFull = (underlying as? CocoaError)?.code == .fileWriteOutOfSpace
            let reason = diskFull ? "disk_full" : "\(operation)_failed"
            parameters["reason"] = reason
            parameters["impact"] = fields["source"] == Source.automatic.rawValue ? "degraded" : "blocked"
            if !diskFull && (event == "capture_step" || operation == Action.save.rawValue) {
                SentrySDK.capture(error: NSError(domain: "DewShot.\(operation)", code: 1)) { scope in
                    scope.setTag(value: operation, key: "operation")
                    scope.setTag(value: reason, key: "reason")
                    scope.setTag(value: "blocked", key: "impact")
                }
            }
        }
        Analytics.logEvent(event, parameters: parameters)
    }
}

struct TelemetryConsentToggle: View {
    let strings: AppStrings
    var expandsLabel = false
    var enabled: (() -> Void)?
    @AppStorage(AppTelemetry.consentKey) private var consent = false

    var body: some View {
        Toggle(isOn: Binding(get: { consent }, set: { value in
            consent = value
            AppTelemetry.refresh()
            if value { enabled?() }
        })) {
            Text(strings.language == .zhHans ? "共享使用统计与故障诊断" : "Share usage statistics and diagnostics")
                .frame(maxWidth: expandsLabel ? .infinity : nil, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .help(strings.language == .zhHans ? "帮助我们了解常用功能、操作耗时和应用故障。" : "Help us understand feature use, delays and app failures.")
    }
}
