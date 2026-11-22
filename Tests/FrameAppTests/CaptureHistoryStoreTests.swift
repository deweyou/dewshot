import AppKit
import XCTest
@testable import FrameApp

final class CaptureHistoryStoreTests: XCTestCase {
    private var rootDirectory: URL!
    private var store: CaptureHistoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameHistoryTests-\(UUID().uuidString)", isDirectory: true)
        store = CaptureHistoryStore(rootDirectory: rootDirectory)
    }

    override func tearDownWithError() throws {
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        store = nil
        rootDirectory = nil
        try super.tearDownWithError()
    }

    func testDefaultRootDirectorySeparatesDevelopmentHistoryFromProduction() {
        let production = CaptureHistoryStore.defaultRootDirectory(bundleIdentifier: "dev.deweyou.frame")
        let development = CaptureHistoryStore.defaultRootDirectory(bundleIdentifier: "dev.deweyou.frame.dev")

        XCTAssertTrue(production.path.hasSuffix("/Application Support/Frame/History"))
        XCTAssertTrue(development.path.hasSuffix("/Application Support/Frame Dev/History"))
    }

    func testAddScreenshotStoresMetadataAndPNGData() throws {
        let record = try XCTUnwrap(try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            imageSize: CGSize(width: 40, height: 20),
            rect: CGRect(x: 10, y: 20, width: 40, height: 20),
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
        ))

        XCTAssertEqual(record.kind, .screenshot)
        XCTAssertEqual(record.byteSize, 3)
        XCTAssertEqual(record.pixelWidth, 40)
        XCTAssertEqual(record.pixelHeight, 20)
        XCTAssertEqual(try store.data(for: record), Data([1, 2, 3]))
        XCTAssertEqual(try store.records(), [record])
    }

    func testSavingAnEditReplacesTheSameHistoryEntryAndSavingACopyAddsOne() throws {
        let size = CGSize(width: 40, height: 20)
        let rect = CGRect(origin: .zero, size: size)
        let configuration = CaptureHistoryConfiguration(isEnabled: true, retention: .forever, sizeLimit: .twoGB)
        let original = CapturedScreenshot(pngData: Data([1]), image: NSImage(size: size), rect: rect)
        let record = try XCTUnwrap(try store.addScreenshot(original, configuration: configuration))
        let edited = CapturedScreenshot(id: original.id, pngData: Data([2, 3]), image: original.image, rect: rect)
        let copy = CapturedScreenshot(pngData: Data([4]), image: original.image, rect: rect)

        try store.saveEditedScreenshot(edited, configuration: configuration)
        try store.saveEditedScreenshot(copy, configuration: configuration)

        let reopened = CaptureHistoryStore(rootDirectory: rootDirectory)
        let records = try reopened.records()
        XCTAssertEqual(records.count, 2)
        let replacement = try XCTUnwrap(records.first { $0.id == record.id })
        XCTAssertEqual(replacement.createdAt, record.createdAt)
        XCTAssertEqual(replacement.byteSize, 2)
        XCTAssertEqual(try reopened.data(for: replacement), edited.pngData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: record).path))
        XCTAssertEqual(try reopened.data(for: XCTUnwrap(records.first { $0.id == copy.id })), copy.pngData)
    }

    func testReplacingEditedImageEnforcesAggregateHistoryLimit() throws {
        let size = CGSize(width: 40, height: 20)
        let rect = CGRect(origin: .zero, size: size)
        let configuration = CaptureHistoryConfiguration(isEnabled: true, retention: .forever, sizeLimit: .custom(bytes: 10))
        let original = CapturedScreenshot(pngData: Data([1]), image: NSImage(size: size), rect: rect)
        let date = Date(timeIntervalSince1970: 100)
        let originalRecord = try XCTUnwrap(store.addScreenshot(original, date: date, configuration: configuration))
        let otherImage = CapturedScreenshot(pngData: Data(repeating: 2, count: 8), image: original.image, rect: rect)
        let evicted = try XCTUnwrap(store.addScreenshot(otherImage, date: date.addingTimeInterval(1), configuration: configuration))

        let edited = CapturedScreenshot(id: original.id, pngData: Data(repeating: 3, count: 6), image: original.image, rect: rect)
        XCTAssertTrue(try store.saveEditedScreenshot(edited, configuration: configuration))

        let records = try store.records()
        XCTAssertEqual(records.map(\.id), [original.id])
        XCTAssertEqual(records.first?.createdAt, originalRecord.createdAt)
        XCTAssertEqual(try store.data(for: XCTUnwrap(records.first)), edited.pngData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: evicted).path))
    }

    func testDisabledHistoryDoesNotStoreScreenshot() throws {
        let record = try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            imageSize: CGSize(width: 40, height: 20),
            rect: .zero,
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: false, retention: .sevenDays, sizeLimit: .twoGB)
        )

        XCTAssertNil(record)
        XCTAssertEqual(try store.records(), [])
    }

    func testDeleteRecordRemovesMetadataAndCachedFile() throws {
        let record = try XCTUnwrap(try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            imageSize: CGSize(width: 40, height: 20),
            rect: .zero,
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
        ))

        try store.delete(recordID: record.id)

        XCTAssertEqual(try store.records(), [])
        XCTAssertThrowsError(try store.data(for: record))
    }

    func testClearRemovesAllRecordsAndFiles() throws {
        _ = try store.addScreenshot(
            pngData: Data([1]),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
        )
        _ = try store.addScreenshot(
            pngData: Data([2]),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 101),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
        )

        try store.clear()

        XCTAssertEqual(try store.records(), [])
    }

    func testCleanupRemovesRecordsOlderThanRetention() throws {
        let old = try XCTUnwrap(try store.addScreenshot(
            pngData: Data([1]),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 0),
            configuration: .init(isEnabled: true, retention: .forever, sizeLimit: .twoGB)
        ))
        let recent = try XCTUnwrap(try store.addScreenshot(
            pngData: Data([2]),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 8 * 24 * 60 * 60),
            configuration: .init(isEnabled: true, retention: .forever, sizeLimit: .twoGB)
        ))

        try store.cleanup(
            now: Date(timeIntervalSince1970: 8 * 24 * 60 * 60),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
        )

        XCTAssertEqual(try store.records(), [recent])
        XCTAssertThrowsError(try store.data(for: old))
    }

    func testCleanupRemovesOldestRecordsWhenSizeLimitIsExceeded() throws {
        let first = try XCTUnwrap(try store.addScreenshot(
            pngData: Data(repeating: 1, count: 6),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: true, retention: .forever, sizeLimit: .custom(bytes: 20))
        ))
        let second = try XCTUnwrap(try store.addScreenshot(
            pngData: Data(repeating: 2, count: 6),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 101),
            configuration: .init(isEnabled: true, retention: .forever, sizeLimit: .custom(bytes: 20))
        ))
        let newest = try XCTUnwrap(try store.addScreenshot(
            pngData: Data(repeating: 3, count: 6),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 102),
            configuration: .init(isEnabled: true, retention: .forever, sizeLimit: .custom(bytes: 12))
        ))

        XCTAssertEqual(try store.records(), [newest, second])
        XCTAssertThrowsError(try store.data(for: first))
    }

    func testOversizedSingleFileIsNotStored() throws {
        let record = try store.addScreenshot(
            pngData: Data(repeating: 1, count: 13),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .custom(bytes: 12))
        )

        XCTAssertNil(record)
        XCTAssertEqual(try store.records(), [])
    }

    func testAddRecordingStoresMovieMetadataAndData() throws {
        let record = try XCTUnwrap(try store.addRecording(
            data: Data([9, 8, 7]),
            filenameExtension: "mp4",
            pixelSize: CGSize(width: 1280, height: 720),
            rect: CGRect(x: 10, y: 20, width: 1280, height: 720),
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
        ))

        XCTAssertEqual(record.kind, .recording)
        XCTAssertTrue(record.filename.hasSuffix(".mp4"))
        XCTAssertEqual(record.pixelWidth, 1280)
        XCTAssertEqual(record.pixelHeight, 720)
        XCTAssertEqual(try store.data(for: record), Data([9, 8, 7]))
    }
}
