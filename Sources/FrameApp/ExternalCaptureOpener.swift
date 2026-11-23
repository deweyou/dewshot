import AppKit

@MainActor
struct ExternalCaptureOpener {
    var openFile: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    func open(_ screenshot: CapturedScreenshot) throws {
        try openCopy(named: "dewShot Screenshot.png") { fileURL in
            try screenshot.pngData.write(to: fileURL, options: .atomic)
        }
    }

    func open(_ recording: CapturedRecording) throws {
        try openCopy(named: recording.fileURL.lastPathComponent) { fileURL in
            try FileManager.default.copyItem(at: recording.fileURL, to: fileURL)
        }
    }

    private func openCopy(named name: String, write: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dewShot-Open-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent(name, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try write(fileURL)
            guard openFile(fileURL) else {
                throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: fileURL])
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
