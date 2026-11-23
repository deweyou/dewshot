import AppKit
import XCTest
@testable import FrameApp

@MainActor
final class ExternalCaptureOpenerTests: XCTestCase {
    func testOpeningRecordingHandsOffACopyWithoutModifyingTheOriginal() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: source) }
        let original = Data([1, 2, 3])
        try original.write(to: source)
        let recording = CapturedRecording(
            id: UUID(), fileURL: source, format: .mp4, rect: .zero,
            pixelSize: .zero, byteSize: original.count, duration: 1
        )
        var openedURL: URL?
        let opener = ExternalCaptureOpener { url in
            openedURL = url
            return true
        }

        try opener.open(recording)

        let copy = try XCTUnwrap(openedURL)
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        XCTAssertNotEqual(copy, source)
        XCTAssertEqual(copy.lastPathComponent, source.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: copy), original)
        try Data([4, 5, 6]).write(to: copy)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testFailedScreenshotHandoffRemovesTheTemporaryCopy() throws {
        let screenshot = CapturedScreenshot(pngData: Data([1, 2, 3]), image: NSImage(), rect: .zero)
        var openedURL: URL?
        let opener = ExternalCaptureOpener { url in
            openedURL = url
            XCTAssertEqual(url.pathExtension, "png")
            XCTAssertEqual(try? Data(contentsOf: url), screenshot.pngData)
            return false
        }

        XCTAssertThrowsError(try opener.open(screenshot))

        let url = try XCTUnwrap(openedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }
}
