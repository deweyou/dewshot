import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FrameApp

final class CaptureHistoryWindowControllerTests: XCTestCase {
    private var rootDirectory: URL!
    private var store: CaptureHistoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameHistoryWindowTests-\(UUID().uuidString)", isDirectory: true)
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

    @MainActor
    func testDoubleClickAndReturnOpenTheSelectedHistoryItemWithoutRestoring() throws {
        _ = NSApplication.shared
        let screenshot = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let recording = try addRecord(kind: .recording, date: Date(timeIntervalSince1970: 101))
        var opened: [CaptureHistoryRecord] = []
        let controller = CaptureHistoryWindowController(
            store: store,
            open: { opened.append($0) },
            restore: { _ in XCTFail("Open should not restore to Quick Access") }
        )

        controller.show(strings: AppStrings(language: .en))
        defer { controller.close() }
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "Capture History" && $0.isVisible })
        let root = try XCTUnwrap(window.contentView)
        let scrollView = try XCTUnwrap(findView(in: root, ofType: NSScrollView.self))
        let grid = try XCTUnwrap(scrollView.documentView)
        root.layoutSubtreeIfNeeded()

        func pressKey(_ keyCode: UInt16, characters: String) throws {
            grid.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            )))
        }

        XCTAssertTrue(window.makeFirstResponder(grid))
        try pressKey(124, characters: "")
        try pressKey(36, characters: "\r")
        XCTAssertEqual(opened, [recording])

        let screenshotTile = try XCTUnwrap(grid.subviews.first { $0.identifier?.rawValue == screenshot.id.uuidString })
        let clickLocation = screenshotTile.convert(CGPoint(x: 20, y: 40), to: nil)
        for clickCount in [1, 2] {
            let click = try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown, location: clickLocation, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: clickCount, pressure: 1
            ))
            let gridPoint = grid.convert(clickLocation, from: nil)
            let clickedView = try XCTUnwrap(grid.hitTest(grid.superview?.convert(gridPoint, from: grid) ?? gridPoint))
            clickedView.mouseDown(with: click)
            XCTAssertTrue(screenshotTile.isAccessibilitySelected())
            XCTAssertEqual(opened, clickCount == 1 ? [recording] : [recording, screenshot])
        }
    }

    @MainActor
    func testShowCreatesWindowWithPreviewGrid() throws {
        _ = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        XCTAssertTrue(controller.isWindowVisible)
        XCTAssertEqual(controller.visibleRecords().count, 1)
        XCTAssertEqual(controller.selectedFilter, .all)
        XCTAssertEqual(controller.visibleColumnIdentifiers(), [])
        XCTAssertEqual(controller.visibleTileCount(), 1)
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "Capture History" && $0.isVisible })
        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.toolbarStyle, .unified)
        XCTAssertNotNil(window.standardWindowButton(.closeButton))
        XCTAssertNotNil(window.standardWindowButton(.miniaturizeButton))
        XCTAssertNotNil(window.standardWindowButton(.zoomButton))
        XCTAssertNotNil(window.toolbar)
        let contentView = try XCTUnwrap(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        let scrollView = try XCTUnwrap(findView(in: contentView, ofType: NSScrollView.self))
        XCTAssertEqual(scrollView.convert(scrollView.bounds, to: nil).maxY, window.contentLayoutRect.maxY, accuracy: 0.5)
    }

    @MainActor
    func testFilterCanShowScreenshotsOrRecordings() throws {
        let screenshot = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let recording = try addRecord(kind: .recording, date: Date(timeIntervalSince1970: 101))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        controller.setFilter(.screenshots)
        XCTAssertEqual(controller.visibleRecords(), [screenshot])

        controller.setFilter(.recordings)
        XCTAssertEqual(controller.visibleRecords(), [recording])

        controller.setFilter(.all)
        XCTAssertEqual(controller.visibleRecords(), [recording, screenshot])
        controller.close()
    }

    @MainActor
    func testEmptyStateOffersCaptureSettingsOrResettingTheFilter() throws {
        var historyEnabled = true
        var beginFilters: [CaptureHistoryFilter] = []
        var settingsOpened = false
        let controller = CaptureHistoryWindowController(
            store: store,
            isHistoryEnabled: { historyEnabled },
            startCapture: { beginFilters.append($0) },
            openHistorySettings: { settingsOpened = true }
        )
        let strings = AppStrings(language: .en)
        controller.show(strings: strings)
        defer { controller.close() }

        let window = try XCTUnwrap(NSApp.windows.first { $0.title == strings.captureHistoryTitle && $0.isVisible })
        XCTAssertEqual(window.titleVisibility, .visible)
        let contentView = try XCTUnwrap(window.contentView)
        let action = try XCTUnwrap(findButtons(in: contentView).first {
            $0.identifier?.rawValue == "CaptureHistoryEmptyAction"
        })
        XCTAssertEqual(action.title, strings.menuCapture)
        action.performClick(nil)
        XCTAssertEqual(beginFilters, [.all])

        historyEnabled = false
        controller.show(strings: strings)
        XCTAssertEqual(action.title, strings.settingsTitle)
        action.performClick(nil)
        XCTAssertTrue(settingsOpened)

        historyEnabled = true
        _ = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        controller.setFilter(.recordings)
        XCTAssertEqual(action.title, strings.captureHistoryFilterAll)
        action.performClick(nil)
        XCTAssertEqual(controller.selectedFilter, .all)
        XCTAssertEqual(controller.visibleTileCount(), 1)
    }

    @MainActor
    func testFilterControlUsesToolbarPillButtons() throws {
        let screenshot = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let recording = try addRecord(kind: .recording, date: Date(timeIntervalSince1970: 101))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "Capture History" && $0.isVisible })
        let toolbar = try XCTUnwrap(window.toolbar)
        XCTAssertEqual(toolbar.items.map(\.itemIdentifier.rawValue), ["NSToolbarFlexibleSpaceItem", "CaptureHistoryFilter"])
        let filterControl = try XCTUnwrap(toolbar.items.last?.view)
        filterControl.layoutSubtreeIfNeeded()
        XCTAssertEqual(filterControl.accessibilityLabel(), "Capture History Filter")
        XCTAssertTrue(filterControl.window === window)
        XCTAssertGreaterThan(filterControl.frame.height, 0)
        XCTAssertEqual(filterControl.layer?.cornerRadius ?? 0, filterControl.frame.height / 2, accuracy: 1)

        let buttons = findButtons(in: filterControl)
        XCTAssertEqual(buttons.map(\.title), ["All", "Screenshots", "Recordings"])
        XCTAssertTrue(buttons.allSatisfy { $0.acceptsFirstMouse(for: nil) })

        buttons[1].performClick(nil)
        XCTAssertEqual(controller.selectedFilter, .screenshots)
        XCTAssertEqual(controller.visibleRecords(), [screenshot])

        buttons[2].performClick(nil)
        XCTAssertEqual(controller.selectedFilter, .recordings)
        XCTAssertEqual(controller.visibleRecords(), [recording])
    }

    @MainActor
    func testChineseFilterControlSizesToShortLabels() throws {
        _ = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .zhHans))
        defer {
            controller.close()
        }

        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "捕获历史" && $0.isVisible })
        let filterControl = try XCTUnwrap(window.toolbar?.items.last?.view)
        filterControl.layoutSubtreeIfNeeded()
        XCTAssertEqual(filterControl.accessibilityLabel(), "捕获历史筛选")
        let buttons = findButtons(in: filterControl)
        XCTAssertEqual(buttons.map(\.title), ["全部", "截图", "录屏"])
        XCTAssertLessThanOrEqual(filterControl.frame.width, 152)
        XCTAssertGreaterThanOrEqual(buttons.map(\.frame.width).min() ?? 0, 40)
    }

    @MainActor
    func testRecordActionsCallConfiguredHandlers() throws {
        let record = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        var restored: CaptureHistoryRecord?
        var copied: CaptureHistoryRecord?
        var saved: CaptureHistoryRecord?
        var deleted: CaptureHistoryRecord?
        let controller = CaptureHistoryWindowController(
            store: store,
            restore: { restored = $0 },
            copy: { copied = $0 },
            save: { saved = $0 },
            delete: { deleted = $0 },
            confirmDelete: { _, _ in true }
        )

        controller.show(strings: AppStrings(language: .en))
        controller.restoreRecord(record)
        controller.copyRecord(record)
        controller.saveRecord(record)
        controller.deleteRecord(record)

        XCTAssertEqual(restored, record)
        XCTAssertEqual(copied, record)
        XCTAssertEqual(saved, record)
        XCTAssertEqual(deleted, record)
        controller.close()
    }

    @MainActor
    func testDeleteDoesNotRunWhenConfirmationIsCancelled() throws {
        let record = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        var didDelete = false
        let controller = CaptureHistoryWindowController(
            store: store,
            delete: { _ in didDelete = true },
            confirmDelete: { _, _ in false }
        )

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        XCTAssertFalse(controller.deleteRecord(record))
        XCTAssertFalse(didDelete)
        XCTAssertEqual(controller.visibleRecords(), [record])
    }

    @MainActor
    func testTileActionsAreVisibleOnlyWhenHovered() throws {
        let record = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        XCTAssertFalse(controller.areActionsVisible(for: record))
        controller.setActionsVisible(true, for: record)
        XCTAssertTrue(controller.areActionsVisible(for: record))
        controller.setActionsVisible(false, for: record)
        XCTAssertFalse(controller.areActionsVisible(for: record))
    }

    @MainActor
    func testTileShadowDeepensOnHover() throws {
        let record = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        let idleShadowOpacity = try XCTUnwrap(controller.tileShadowOpacity(for: record))
        let idleBackgroundAlpha = try XCTUnwrap(controller.tileBackgroundAlpha(for: record))
        XCTAssertGreaterThan(idleShadowOpacity, 0)

        controller.setActionsVisible(true, for: record)

        let hoverShadowOpacity = try XCTUnwrap(controller.tileShadowOpacity(for: record))
        let hoverBackgroundAlpha = try XCTUnwrap(controller.tileBackgroundAlpha(for: record))
        XCTAssertGreaterThan(hoverShadowOpacity, idleShadowOpacity)
        XCTAssertGreaterThan(hoverBackgroundAlpha, idleBackgroundAlpha)
    }

    @MainActor
    func testTileShadowOnlyWrapsPreview() throws {
        let record = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        let previewFrame = try XCTUnwrap(controller.previewFrame(for: record))
        let shadowBounds = try XCTUnwrap(controller.tileShadowBounds(for: record))

        XCTAssertEqual(shadowBounds.width, previewFrame.width, accuracy: 0.5)
        XCTAssertEqual(shadowBounds.height, previewFrame.height, accuracy: 0.5)
    }

    @MainActor
    func testOnlyOneTileShowsActionsAtATime() throws {
        let first = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let second = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 101))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        controller.setActionsVisible(true, for: first)
        XCTAssertTrue(controller.areActionsVisible(for: first))
        XCTAssertFalse(controller.areActionsVisible(for: second))

        controller.setActionsVisible(true, for: second)
        XCTAssertFalse(controller.areActionsVisible(for: first))
        XCTAssertTrue(controller.areActionsVisible(for: second))
    }

    @MainActor
    func testStaleHoverExitDoesNotHideCurrentTileActions() throws {
        let first = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let second = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 101))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        controller.setActionsVisible(true, for: first)
        controller.setActionsVisible(true, for: second)
        controller.setActionsVisible(false, for: first)

        XCTAssertFalse(controller.areActionsVisible(for: first))
        XCTAssertTrue(controller.areActionsVisible(for: second))
    }

    @MainActor
    func testTileHoverFollowsPointerWhenTrackingEventsAreMissedOrStale() throws {
        let record = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)
        controller.show(strings: AppStrings(language: .en))
        defer { controller.close() }
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "Capture History" && $0.isVisible })
        let contentView = try XCTUnwrap(window.contentView)
        let grid = try XCTUnwrap(findView(in: contentView, ofType: NSScrollView.self)?.documentView)
        contentView.layoutSubtreeIfNeeded()
        let tile = try XCTUnwrap(grid.subviews.first { $0.identifier?.rawValue == record.id.uuidString })
        let inside = tile.convert(NSPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: nil)
        let outside = tile.convert(NSPoint(x: tile.bounds.maxX + 5, y: tile.bounds.midY), to: nil)

        func trackingEvent(_ type: NSEvent.EventType, at location: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.enterExitEvent(
                with: type, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                trackingNumber: 0, userData: nil
            ))
        }

        controller.setActionsVisible(false, for: record)
        tile.mouseMoved(with: try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved, location: inside, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 0, pressure: 0
        )))
        XCTAssertTrue(controller.areActionsVisible(for: record))

        tile.mouseExited(with: try trackingEvent(.mouseExited, at: inside))
        XCTAssertTrue(controller.areActionsVisible(for: record))

        tile.mouseExited(with: try trackingEvent(.mouseExited, at: outside))
        XCTAssertFalse(controller.areActionsVisible(for: record))
        tile.mouseEntered(with: try trackingEvent(.mouseEntered, at: outside))
        XCTAssertFalse(controller.areActionsVisible(for: record))
    }

    @MainActor
    func testTileActionButtonsExposePointerCursorAndTooltips() throws {
        _ = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        let buttons = controller.visibleActionButtons()
        XCTAssertEqual(buttons.count, 4)
        XCTAssertTrue(buttons.allSatisfy { $0.acceptsFirstMouse(for: nil) })
        XCTAssertEqual(buttons.compactMap(\.toolTip).sorted(), ["Copy", "Delete", "Restore", "Save"])
    }

    @MainActor
    func testDeleteActionSitsInPreviewTopRightCorner() throws {
        let record = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        controller.setActionsVisible(true, for: record)

        let saveFrame = try XCTUnwrap(controller.actionButtonFrame(title: "Save", for: record))
        let copyFrame = try XCTUnwrap(controller.actionButtonFrame(title: "Copy", for: record))
        let restoreFrame = try XCTUnwrap(controller.actionButtonFrame(title: "Restore", for: record))
        let deleteFrame = try XCTUnwrap(controller.actionButtonFrame(title: "Delete", for: record))

        XCTAssertGreaterThan(deleteFrame.minY, max(saveFrame.maxY, copyFrame.maxY, restoreFrame.maxY))
        XCTAssertGreaterThan(deleteFrame.minX, max(saveFrame.maxX, copyFrame.maxX, restoreFrame.maxX))
    }

    @MainActor
    func testTilePreviewUsesDesktopAspectRatio() throws {
        let record = try addRecord(
            kind: .screenshot,
            date: Date(timeIntervalSince1970: 100),
            imageSize: CGSize(width: 1600, height: 900),
            rect: CGRect(x: 0, y: 0, width: 1600, height: 900)
        )
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        let previewFrame = try XCTUnwrap(controller.previewFrame(for: record))
        XCTAssertEqual(
            previewFrame.height / previewFrame.width,
            CapturePreviewMetrics.desktopAspectRatio(),
            accuracy: 0.01,
            "previewFrame=\(previewFrame.debugDescription)"
        )
    }

    @MainActor
    func testRecordingTileUsesFirstFrameThumbnailWhenAvailable() throws {
        let gifData = try makeOneFrameGIFData()
        let record = try addRecord(
            kind: .recording,
            date: Date(timeIntervalSince1970: 100),
            data: gifData,
            filenameExtension: "gif",
            imageSize: CGSize(width: 2, height: 2),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        XCTAssertEqual(controller.previewImageSize(for: record), CGSize(width: 2, height: 2))
    }

    private func addRecord(
        kind: CaptureHistoryKind,
        date: Date,
        data: Data? = nil,
        filenameExtension: String? = nil,
        imageSize: CGSize = CGSize(width: 10, height: 8),
        rect: CGRect = CGRect(x: 0, y: 0, width: 10, height: 8)
    ) throws -> CaptureHistoryRecord {
        try XCTUnwrap(try store.addCapture(
            kind: kind,
            data: data ?? Data([UInt8(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 255))]),
            filenameExtension: filenameExtension,
            imageSize: imageSize,
            rect: rect,
            date: date,
            configuration: .init(isEnabled: true, retention: .forever, sizeLimit: .twoGB)
        ))
    }

    @MainActor
    private func findButtons(in view: NSView) -> [NSButton] {
        var buttons: [NSButton] = []
        if let button = view as? NSButton {
            buttons.append(button)
        }

        for subview in view.subviews {
            buttons.append(contentsOf: findButtons(in: subview))
        }

        return buttons
    }

    @MainActor
    private func findView<T: NSView>(in view: NSView, ofType type: T.Type) -> T? {
        if let matchingView = view as? T {
            return matchingView
        }

        for subview in view.subviews {
            if let matchingView = findView(in: subview, ofType: type) {
                return matchingView
            }
        }

        return nil
    }

    private func makeOneFrameGIFData() throws -> Data {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let url = rootDirectory.appendingPathComponent("one-frame-\(UUID().uuidString).gif")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let pixels: [UInt8] = [
            255, 0, 0, 255,
            0, 255, 0, 255,
            0, 0, 255, 255,
            255, 255, 255, 255,
        ]
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 8,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.gif.identifier as CFString,
                1,
                nil
              ) else {
            return Data()
        }

        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return try Data(contentsOf: url)
    }
}
