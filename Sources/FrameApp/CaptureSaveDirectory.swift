import Foundation
import Security

struct CaptureSaveDirectory {
    static let isSandboxed: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool == true
    }()

    private static let bookmarkKey = "screenshotDirectoryBookmark"
    private let defaults: UserDefaults
    private let isSandboxed: Bool

    init(defaults: UserDefaults = .standard, isSandboxed: Bool = Self.isSandboxed) {
        self.defaults = defaults
        self.isSandboxed = isSandboxed
    }

    func select(_ directory: URL) throws {
        if isSandboxed {
            let bookmark = try directory.bookmarkData(options: .withSecurityScope)
            defaults.set(bookmark, forKey: Self.bookmarkKey)
        }
        SettingsStore.setScreenshotDirectory(directory, defaults: defaults)
    }

    func reset() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        SettingsStore.resetScreenshotDirectory(defaults: defaults)
    }

    func withAccess<Result>(_ action: (URL) throws -> Result) throws -> Result {
        guard isSandboxed else {
            return try action(SettingsStore.screenshotDirectory(defaults: defaults))
        }

        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else {
            throw AccessError.selectionRequired
        }
        var isStale = false
        guard let directory = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            bookmarkDataIsStale: &isStale
        ), directory.startAccessingSecurityScopedResource() else {
            throw AccessError.selectionRequired
        }
        defer { directory.stopAccessingSecurityScopedResource() }

        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw AccessError.selectionRequired
        }
        if isStale {
            do {
                try select(directory)
            } catch {
                throw AccessError.selectionRequired
            }
        } else if defaults.string(forKey: SettingsStore.screenshotDirectoryKey) != directory.path {
            SettingsStore.setScreenshotDirectory(directory, defaults: defaults)
        }
        return try action(directory)
    }

    enum AccessError: LocalizedError {
        case selectionRequired

        var errorDescription: String? { AppStrings.current().settingsSaveFolderOnFirstSave }
    }
}
