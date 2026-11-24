import Foundation
import FrameCore

final class ScreenshotFileWriter {
    private static let saveLock = NSLock()
    private let fileManager: FileManager
    private let saveDirectory: () throws -> URL
    private let strings: AppStrings

    init(
        fileManager: FileManager = .default,
        saveDirectory: @escaping () throws -> URL = { try SettingsStore.screenshotDirectory() },
        strings: AppStrings = AppStrings.current()
    ) {
        self.fileManager = fileManager
        self.saveDirectory = saveDirectory
        self.strings = strings
    }

    func write(pngData: Data, filename: String, directory: URL? = nil) throws -> URL {
        try writeWithDisposition(pngData: pngData, filename: filename, directory: directory).url
    }

    func writeWithDisposition(pngData: Data, filename: String, directory: URL? = nil) throws -> (url: URL, reused: Bool) {
        let directory = try directory ?? saveDirectory()
        guard filename.hasSuffix(".png"), !filename.contains("/") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let preferredURL = ScreenshotNaming.saveURL(
            desktopDirectory: directory,
            filename: filename
        )

        do {
            return try Self.saveLock.withLock {
                if let existing = try matchingPNG(pngData, in: directory) {
                    return (directory.appendingPathComponent(existing.lastPathComponent, isDirectory: false), true)
                }
                return (try writeNewPNG(pngData, preferredURL: preferredURL, directory: directory), false)
            }
        } catch {
            throw ScreenshotFileWriterError.writeFailed(underlying: error,
                message: strings.saveFailedMessage(
                    path: preferredURL.path,
                    errorDescription: error.localizedDescription
                )
            )
        }
    }

    private func matchingPNG(_ pngData: Data, in directory: URL) throws -> URL? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
        return files.first { file in
            guard file.pathExtension.lowercased() == "png",
                  let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.fileSize == pngData.count else {
                return false
            }
            return (try? Data(contentsOf: file)) == pngData
        }
    }

    private func writeNewPNG(_ pngData: Data, preferredURL: URL, directory: URL) throws -> URL {
        let stagedURL = directory.appendingPathComponent(".dewshot-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: stagedURL) }
        try pngData.write(to: stagedURL, options: .atomic)

        let stem = preferredURL.deletingPathExtension().lastPathComponent
        var destination = preferredURL
        var suffix = 2
        while true {
            do {
                try fileManager.moveItem(at: stagedURL, to: destination)
                return destination
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                destination = directory.appendingPathComponent("\(stem) (\(suffix)).png")
                suffix += 1
            }
        }
    }
}

enum ScreenshotFileWriterError: Error, LocalizedError {
    case writeFailed(underlying: Error, message: String)

    var errorDescription: String? {
        switch self {
        case let .writeFailed(_, message):
            message
        }
    }
}
