import XCTest
@testable import FrameApp

final class ScreenshotFileWriterTests: XCTestCase {
    func testWriteUsesConfiguredDirectory() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let writer = ScreenshotFileWriter(
            fileManager: .default,
            saveDirectory: { temporaryDirectory },
            strings: AppStrings(language: .en)
        )

        let url = try writer.write(pngData: Data([1, 2, 3]), filename: "Screenshot.png")

        XCTAssertEqual(url.deletingLastPathComponent(), temporaryDirectory)
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))
    }

    func testReusesExistingIdenticalPNGWithAnotherName() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = Data([1, 2, 3])
        let existing = directory.appendingPathComponent("Renamed screenshot.PNG")
        try png.write(to: existing)
        let other = directory.appendingPathComponent("Other screenshot.png")
        try Data([3, 2, 1]).write(to: other)

        let saved = try ScreenshotFileWriter().write(pngData: png, filename: "Screenshot.png", directory: directory)

        XCTAssertEqual(saved.path, existing.path)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }

    func testSameTimestampWithDifferentScreenshotsKeepsBothFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = ScreenshotFileWriter()
        let filename = "dewShot 2026-11-23 10.20.30.png"
        let firstPNG = Data([1, 2, 3])
        let secondPNG = Data([3, 2, 1])

        let first = try writer.write(pngData: firstPNG, filename: filename, directory: directory)
        let second = try writer.write(pngData: secondPNG, filename: filename, directory: directory)
        let repeated = try ScreenshotFileWriter().write(
            pngData: secondPNG, filename: filename, directory: directory
        )

        XCTAssertEqual(first.lastPathComponent, filename)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), firstPNG)
        XCTAssertEqual(try Data(contentsOf: second), secondPNG)
        XCTAssertEqual(repeated.path, second.path)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
