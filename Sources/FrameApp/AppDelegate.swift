import AVFoundation
import AppKit
import FrameCore
import ImageIO

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlayDismissalCaptureDelay: DispatchTimeInterval = .milliseconds(80)

    private var statusItemController: StatusItemController?
    private var hotKeyController: HotKeyController?
    private let selectionOverlayController: SelectionOverlayControlling
    private let captureService = CaptureService()
    private let scrollingScreenshotSessionController: ScrollingScreenshotSessionControlling
    private let quickAccessPanelController: QuickAccessPanelController
    private let videoPreviewWindowController: VideoPreviewWindowController
    private let imageWorkspacePanelController = ImageWorkspacePanelController()
    private let captureHistoryStore: CaptureHistoryStore
    private let ocrService = OCRService()
    private let ocrTextPanelController = OCRTextPanelController()
    private let clipboardWriter: ClipboardWriter
    private let automaticallyCopiesCaptures: () -> Bool
    private let recordingService: RecordingServicing
    private let recordingFileWriter: RecordingFileWriter
    private let videoEditingExporter: VideoEditingExporting
    private let keyboardHintOverlayController: KeyboardHintOverlayControlling
    private let hasScreenRecordingAccess: () -> Bool
    private let showMissingScreenRecordingPermission: () -> Void
    private let playInvalidActionFeedback: () -> Void
    private let activeRecordingHUDPanelController = ActiveRecordingHUDPanelController()
    private let recordingBoundaryOverlayController = RecordingBoundaryOverlayController()
    private let settingsWindowController = SettingsWindowController()
    private var captureHistoryWindowController: CaptureHistoryWindowController?
    private var strings = AppStrings.current()
    private var activeQuickAccessScreenshotIDs: Set<UUID> = []
    private var activeQuickAccessScreenshots: [UUID: CapturedScreenshot] = [:]
    private var recognizingScreenshotIDs: Set<UUID> = []
    private var recognizedTextLayouts: [UUID: RecognizedTextLayout] = [:]
    private var activeRecordingSession: RecordingSessionControlling?
    private var activeRecordingSelection: SelectionCapture?
    private var activeRecordingOptions = RecordingOptions.defaults
    private var activeRecordingClock: RecordingElapsedClock?
    private var activeRecordingElapsedTimer: Timer?
    private var activeRecordingQuickAccessAnchor: CGRect?
    private var pendingRecordingStartTask: Task<Void, Never>?
    private var isStoppingActiveRecording = false

    init(
        selectionOverlayController: SelectionOverlayControlling = SelectionOverlayController(),
        scrollingScreenshotSessionController: ScrollingScreenshotSessionControlling = ScrollingScreenshotSessionController(),
        recordingService: RecordingServicing = ScreenCaptureRecordingService(),
        keyboardHintOverlayController: KeyboardHintOverlayControlling = KeyboardHintOverlayController(),
        quickAccessPanelController: QuickAccessPanelController = QuickAccessPanelController(),
        videoPreviewWindowController: VideoPreviewWindowController = VideoPreviewWindowController(),
        captureHistoryStore: CaptureHistoryStore = CaptureHistoryStore(),
        clipboardWriter: ClipboardWriter = ClipboardWriter(),
        automaticallyCopiesCaptures: @escaping () -> Bool = { SettingsStore.automaticallyCopiesCaptures() },
        recordingFileWriter: RecordingFileWriter = RecordingFileWriter(),
        videoEditingExporter: VideoEditingExporting = VideoEditingExporter(),
        hasScreenRecordingAccess: @escaping () -> Bool = { ScreenRecordingPermission.hasAccess },
        showMissingScreenRecordingPermission: @escaping () -> Void = {
            ScreenRecordingPermission.showMissingPermissionAlert(strings: .current())
        },
        playInvalidActionFeedback: @escaping () -> Void = { NSSound.beep() }
    ) {
        self.selectionOverlayController = selectionOverlayController
        self.scrollingScreenshotSessionController = scrollingScreenshotSessionController
        self.recordingService = recordingService
        self.keyboardHintOverlayController = keyboardHintOverlayController
        self.quickAccessPanelController = quickAccessPanelController
        self.videoPreviewWindowController = videoPreviewWindowController
        self.captureHistoryStore = captureHistoryStore
        self.clipboardWriter = clipboardWriter
        self.automaticallyCopiesCaptures = automaticallyCopiesCaptures
        self.recordingFileWriter = recordingFileWriter
        self.videoEditingExporter = videoEditingExporter
        self.hasScreenRecordingAccess = hasScreenRecordingAccess
        self.showMissingScreenRecordingPermission = showMissingScreenRecordingPermission
        self.playInvalidActionFeedback = playInvalidActionFeedback
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        strings = AppStrings.current()
        SettingsStore.appTheme().apply(to: NSApp)
        let usesDefaultRecordingShortcut = !SettingsStore.hasSavedRecordingShortcut()
        if usesDefaultRecordingShortcut,
           SettingsStore.recordingShortcut() == nil || HotKeyController.systemShortcutIsInUse(.defaultRecording) {
            SettingsStore.setRecordingShortcut(nil)
        }

        statusItemController = StatusItemController(
            strings: strings,
            onCapture: { [weak self] in
                self?.onCapture()
            },
            onRecord: { [weak self] in
                self?.startRecordingCaptureFlow()
            },
            onHistory: { [weak self] in
                self?.onHistory()
            },
            onSettings: { [weak self] in
                self?.onSettings()
            },
            onStopRecording: { [weak self] in
                self?.stopActiveRecording()
            },
            onOpenImage: { [weak self] in self?.openImageFile() },
            onOpenClipboardImage: { [weak self] in self?.openClipboardImage() }
        )

        try? captureHistoryStore.cleanup()

        let hotKeyController = HotKeyController(
            shortcut: SettingsStore.screenshotShortcut(),
            recordingShortcut: SettingsStore.recordingShortcut()
        )
        hotKeyController.onScreenshot = { [weak self] in
            self?.startCaptureFlow()
        }
        hotKeyController.onRecording = { [weak self] in
            self?.startRecordingCaptureFlow()
        }

        do {
            do {
                try hotKeyController.register()
            } catch HotKeyRegistrationError.shortcutInUse(let shortcut)
                where usesDefaultRecordingShortcut && hotKeyController.recordingShortcut == shortcut {
                try hotKeyController.register(recordingShortcut: .some(nil))
                SettingsStore.setRecordingShortcut(nil)
                statusItemController?.updateShortcuts(
                    screenshotShortcut: hotKeyController.shortcut,
                    recordingShortcut: nil
                )
            }
            self.hotKeyController = hotKeyController
        } catch {
            showHotKeyRegistrationFailedAlert(error)
            NSLog("Frame 快捷键注册失败: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyController?.unregister()
    }

    @objc func onCapture() {
        startCaptureFlow()
    }

    @objc func onSettings() {
        settingsWindowController.show(
            strings: strings,
            onShortcutChange: { [weak self] shortcut in
                self?.changeScreenshotShortcut(to: shortcut) ?? false
            },
            onRecordingShortcutChange: { [weak self] shortcut in
                self?.changeRecordingShortcut(to: shortcut) ?? false
            },
            onShortcutRecordingChange: { [weak self] isRecording in
                self?.setScreenshotShortcutRecorderActive(isRecording)
            },
            onLanguageChange: { [weak self] language in
                self?.changeLanguage(to: language)
            },
            onChooseScreenshotDirectory: { [weak self] in
                self?.chooseScreenshotDirectory()
            },
            onResetScreenshotDirectory: {
                SettingsStore.resetScreenshotDirectory()
            },
            onClearCaptureHistory: { [weak self] in
                try self?.captureHistoryStore.clear()
            }
        )
    }

    @objc func onHistory() {
        showCaptureHistory()
    }

    private var isCaptureFlowBusy: Bool {
        selectionOverlayController.isSelecting
            || scrollingScreenshotSessionController.isActive
            || pendingRecordingStartTask != nil
            || activeRecordingSession != nil
            || isStoppingActiveRecording
    }

    @discardableResult
    func startCaptureFlow() -> Bool {
        startCaptureFlow(initialMode: .screenshot)
    }

    @discardableResult
    private func startRecordingCaptureFlow() -> Bool {
        startCaptureFlow(initialMode: .recordingSetup)
    }

    @discardableResult
    private func startCaptureFlow(initialMode: SelectionOverlayInitialMode) -> Bool {
        guard !isCaptureFlowBusy else {
            recordScreenshotShortcutHintIfRecording()
            playInvalidActionFeedback()
            return false
        }

        guard hasScreenRecordingAccess() else {
            showMissingScreenRecordingPermission()
            return false
        }

        quickAccessPanelController.temporarilyHidePreviews()

        let quickAccessAnchor = ActiveScreenResolver.preferredQuickAccessAnchor()

        selectionOverlayController.startSelection(
            strings: strings,
            initialMode: initialMode,
            onStartRecording: { [weak self] overlayWindow, selection, options in
                self?.startRecording(
                    selection: selection,
                    options: options,
                    overlayWindow: overlayWindow,
                    anchor: quickAccessAnchor
                )
            }
        ) { [weak self] completion in
            guard let self else {
                return
            }

            guard let completion else {
                self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + overlayDismissalCaptureDelay) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    switch completion {
                    case let .startRecording(selection, options):
                        self.startRecording(
                            selection: selection,
                            options: options,
                            overlayWindow: nil,
                            anchor: quickAccessAnchor
                        )
                    case .fullScreen:
                        do {
                            let screenshots = try self.captureService.captureFullScreens()
                            let anchorPoint = quickAccessAnchor?.center ?? NSEvent.mouseLocation
                            let activeScreenshot = screenshots.first { $0.rect.contains(anchorPoint) } ?? screenshots.first
                            let copied = activeScreenshot.map(self.automaticallyCopyScreenshot) ?? false
                            self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                            for screenshot in screenshots {
                                let stored = self.storeInCaptureHistory(screenshot)
                                self.showQuickAccess(
                                    for: screenshot,
                                    anchor: quickAccessAnchor,
                                    canAutoDismiss: stored || (copied && screenshot.id == activeScreenshot?.id)
                                )
                            }
                            NSLog("Frame 已捕获全屏截图：screens=\(screenshots.count)")
                        } catch {
                            self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                            self.showCaptureFailedAlert(error)
                        }
                    case let .scrollingScreenshot(selection):
                        self.startScrollingScreenshot(selection: selection, anchor: quickAccessAnchor)
                    case let .capture(selection):
                        do {
                            let screenshot = try await self.captureService.capture(selection: selection)
                            let copied = self.automaticallyCopyScreenshot(screenshot)
                            let stored = self.storeInCaptureHistory(screenshot)
                            self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                            self.showQuickAccess(for: screenshot, anchor: quickAccessAnchor, canAutoDismiss: copied || stored)
                            NSLog("Frame 截图选区类型：\(selection.kind)")
                        } catch {
                            self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                            self.showCaptureFailedAlert(error)
                        }
                    case let .recognizeText(selection):
                        await self.recognizeTextFromSelection(selection)
                    }
                }
            }
        }

        return true
    }

    private func recordScreenshotShortcutHintIfRecording() {
        guard let activeRecordingSession else {
            return
        }

        let shortcut = hotKeyController?.shortcut ?? SettingsStore.screenshotShortcut()
        activeRecordingSession.recordKeyboardHint(recordingHintLabel(for: shortcut))
    }

    private func startScrollingScreenshot(selection: SelectionCapture, anchor: CGRect?) {
        var latestPreview: CapturedScreenshot?
        var pendingPreview: CapturedScreenshot?
        scrollingScreenshotSessionController.start(
            selection: selection,
            strings: strings,
            onPreviewUpdate: { [weak self] preview in
                latestPreview = preview
                guard let self,
                      pendingPreview?.id == preview.id else {
                    return
                }

                self.activeQuickAccessScreenshots[preview.id] = preview
                self.quickAccessPanelController.updatePreview(for: preview)
                pendingPreview = preview
            },
            onFinishStarted: { [weak self] preview in
                guard let self,
                      let preview = preview ?? latestPreview else {
                    return
                }

                pendingPreview = preview
                self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                self.showQuickAccess(for: preview, anchor: anchor, isPending: true)
            },
            onComplete: { [weak self] screenshot in
                guard let self else {
                    return
                }

                let copied = self.automaticallyCopyScreenshot(screenshot)
                let stored = self.storeInCaptureHistory(screenshot)
                if pendingPreview?.id == screenshot.id {
                    self.activeQuickAccessScreenshots[screenshot.id] = screenshot
                    self.quickAccessPanelController.updatePreview(for: screenshot)
                    self.quickAccessPanelController.setScreenshotPending(
                        false, for: screenshot, canAutoDismiss: copied || stored
                    )
                } else {
                    self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                    self.showQuickAccess(for: screenshot, anchor: anchor, canAutoDismiss: copied || stored)
                }
                pendingPreview = nil
                NSLog("Frame 已完成滚动长截图：rect=\(screenshot.rect.debugDescription)")
            },
            onCancel: { [weak self] in
                guard let self else {
                    return
                }
                if let pendingPreview {
                    self.quickAccessPanelController.closePreview(for: pendingPreview, notify: false)
                    self.endQuickAccessLifecycle(for: pendingPreview)
                }
                self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                NSLog("Frame 滚动长截图已取消")
            },
            onRetryableFailure: { [weak self] error in
                guard let self else {
                    return
                }
                if let pendingPreview {
                    self.quickAccessPanelController.closePreview(for: pendingPreview, notify: false)
                    self.endQuickAccessLifecycle(for: pendingPreview)
                }
                pendingPreview = nil
                self.quickAccessPanelController.temporarilyHidePreviews()
                NSLog("Frame 滚动长截图拼接失败，已恢复采样：\(error.localizedDescription)")
            },
            onFailure: { [weak self] error in
                guard let self else {
                    return
                }

                if let pendingPreview {
                    self.quickAccessPanelController.closePreview(for: pendingPreview, notify: false)
                    self.endQuickAccessLifecycle(for: pendingPreview)
                }
                self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                self.showScrollingScreenshotFailedAlert(error)
            }
        )
    }

    private func recordingHintLabel(for shortcut: ScreenshotShortcut) -> String {
        shortcut.displayName
    }

    private func recognizeTextFromSelection(_ selection: SelectionCapture) async {
        let screenshot: CapturedScreenshot
        do {
            screenshot = try await captureService.capture(selection: selection)
        } catch {
            quickAccessPanelController.restoreTemporarilyHiddenPreviews()
            showCaptureFailedAlert(error)
            return
        }

        quickAccessPanelController.restoreTemporarilyHiddenPreviews()

        do {
            let layout = try await ocrService.recognizeText(in: screenshot)
            guard !layout.isEmpty else {
                showOCRNoTextFoundAlert()
                return
            }

            showOCRPanel(layout, for: screenshot)
            NSLog("Frame 已从截图 HUD 识别文字：选区类型=\(selection.kind)")
        } catch {
            showQuickAccessFailedAlert(title: strings.ocrFailedTitle, error: error)
        }
    }

    private func showQuickAccess(
        for screenshot: CapturedScreenshot,
        anchor: CGRect?,
        isPending: Bool = false,
        canAutoDismiss: Bool = false
    ) {
        if activeQuickAccessScreenshotIDs.contains(screenshot.id),
           quickAccessPanelController.updatePreview(for: screenshot) {
            activeQuickAccessScreenshots[screenshot.id] = screenshot
            return
        }

        activeQuickAccessScreenshotIDs.insert(screenshot.id)
        activeQuickAccessScreenshots[screenshot.id] = screenshot
        quickAccessPanelController.show(
            for: screenshot,
            preferredAnchor: anchor,
            strings: strings,
            isPending: isPending,
            canAutoDismiss: canAutoDismiss,
            isInUse: { [weak self] in
                guard let self else { return false }
                return self.recognizingScreenshotIDs.contains(screenshot.id)
                    || self.ocrTextPanelController.hasPanel(for: screenshot)
            },
            copy: { [weak self] in
                guard let self else {
                    return false
                }

                let currentScreenshot = self.currentQuickAccessScreenshot(for: screenshot)
                let didCopy = self.copyToClipboard(currentScreenshot)
                if didCopy {
                    self.quickAccessPanelController.showDeliveryFeedback(self.strings.quickAccessCopied, captureID: screenshot.id)
                    self.endQuickAccessLifecycle(for: screenshot)
                }

                return didCopy
            },
            save: { [weak self] in
                guard let self else {
                    return false
                }

                let currentScreenshot = self.currentQuickAccessScreenshot(for: screenshot)
                guard let savedURL = self.saveScreenshotFile(currentScreenshot) else {
                    return false
                }
                self.showQuickAccessSavedFeedback(for: screenshot.id, fileURL: savedURL)
                self.endQuickAccessLifecycle(for: screenshot)
                return true
            },
            recognizeText: { [weak self] in
                guard let self else {
                    return false
                }

                return self.recognizeText(in: self.currentQuickAccessScreenshot(for: screenshot))
            },
            openWorkspace: { [weak self] in
                guard let self else {
                    return false
                }

                return self.openWorkspace(self.currentQuickAccessScreenshot(for: screenshot), kind: .temporaryPreview)
            },
            pin: { [weak self] in
                guard let self else {
                    return false
                }

                let didOpen = self.openWorkspace(self.currentQuickAccessScreenshot(for: screenshot), kind: .pinned)
                if didOpen {
                    self.endQuickAccessLifecycle(for: screenshot)
                }

                return didOpen
            },
            close: { [weak self] in
                self?.endQuickAccessLifecycle(for: screenshot)
                NSLog("Frame 快速操作已关闭")
            }
        )

        NSLog(
            "Frame 已捕获截图：rect=\(screenshot.rect.debugDescription), pngSize=\(screenshot.pngData.count) bytes"
        )
    }

    private func startRecording(
        selection: SelectionCapture,
        options: RecordingOptions,
        overlayWindow: SelectionOverlayWindow?,
        anchor: CGRect?
    ) {
        guard activeRecordingSession == nil,
              pendingRecordingStartTask == nil else {
            NSSound.beep()
            return
        }

        quickAccessPanelController.setPreviewRestorationSuppressed(true)
        quickAccessPanelController.closePreviewsForRecordingStart()
        keyboardHintOverlayController.hide()

        beginRecordingPreparation(
            selection: selection,
            options: options,
            overlayWindow: overlayWindow,
            anchor: anchor
        )
    }

    private func beginRecordingPreparation(
        selection: SelectionCapture,
        options: RecordingOptions,
        overlayWindow: SelectionOverlayWindow?,
        anchor: CGRect?
    ) {
        activeRecordingQuickAccessAnchor = anchor
        recordingBoundaryOverlayController.show(rect: selection.rect, preparationState: .loading)
        if overlayWindow != nil {
            selectionOverlayController.dismissSelectionForRecording()
        }

        pendingRecordingStartTask = Task { @MainActor [weak self, weak overlayWindow] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else {
                return
            }
            self.pendingRecordingStartTask = nil
            self.recordingBoundaryOverlayController.updatePreparationState(nil)
            beginRecordingNow(
                selection: selection,
                options: options,
                overlayWindow: overlayWindow,
                anchor: anchor
            )
        }
    }

    private func beginRecordingNow(
        selection: SelectionCapture,
        options: RecordingOptions,
        overlayWindow: SelectionOverlayWindow?,
        anchor: CGRect?
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let session = try await self.recordingService.startRecording(
                    RecordingRequest(selection: selection, options: options)
                )
                let startedAt = Date()
                self.activeRecordingSession = session
                self.activeRecordingSelection = selection
                self.activeRecordingOptions = options
                self.activeRecordingClock = RecordingElapsedClock(startedAt: startedAt)
                self.activeRecordingQuickAccessAnchor = anchor
                self.isStoppingActiveRecording = false

                self.recordingBoundaryOverlayController.show(rect: selection.rect)
                self.activeRecordingHUDPanelController.show(
                    near: selection.rect,
                    elapsed: 0,
                    isPaused: false,
                    stop: { [weak self] in
                        self?.stopActiveRecording()
                    },
                    restart: { [weak self] in
                        self?.restartActiveRecording()
                    },
                    delete: { [weak self] in
                        self?.deleteActiveRecording()
                    }
                )
                self.statusItemController?.setRecordingState(.recording)
                self.startRecordingElapsedTimer()

                NSLog("Frame 已开始录屏：rect=\(selection.rect.debugDescription), format=\(options.format.rawValue)")
            } catch {
                self.quickAccessPanelController.setPreviewRestorationSuppressed(false)
                self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                self.recordingBoundaryOverlayController.close()
                self.showCaptureFailedAlert(error)
            }
        }
    }

    private func pauseActiveRecording() {
        guard let session = activeRecordingSession else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await session.pause()
                var clock = self.activeRecordingClock
                clock?.pause(at: Date())
                self.activeRecordingClock = clock
                let elapsed = self.currentRecordingElapsed()
                self.activeRecordingHUDPanelController.update(elapsed: elapsed, isPaused: true)
                self.statusItemController?.setRecordingState(.paused)
                NSLog("Frame 录屏已暂停")
            } catch {
                self.showCaptureFailedAlert(error)
            }
        }
    }

    private func resumeActiveRecording() {
        guard let session = activeRecordingSession else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await session.resume()
                var clock = self.activeRecordingClock
                clock?.resume(at: Date())
                self.activeRecordingClock = clock
                let elapsed = self.currentRecordingElapsed()
                self.activeRecordingHUDPanelController.update(elapsed: elapsed, isPaused: false)
                self.statusItemController?.setRecordingState(.recording)
                NSLog("Frame 录屏已继续")
            } catch {
                self.showCaptureFailedAlert(error)
            }
        }
    }

    private func stopActiveRecording() {
        guard let session = activeRecordingSession,
              !isStoppingActiveRecording else {
            return
        }

        isStoppingActiveRecording = true
        let duration = currentRecordingElapsed()
        activeRecordingElapsedTimer?.invalidate()
        activeRecordingElapsedTimer = nil
        activeRecordingHUDPanelController.setStopping(true)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let capturedRecording = try await session.stop()
                let recording = CapturedRecording(
                    id: capturedRecording.id,
                    fileURL: capturedRecording.fileURL,
                    format: capturedRecording.format,
                    rect: capturedRecording.rect,
                    pixelSize: capturedRecording.pixelSize,
                    byteSize: capturedRecording.byteSize,
                    duration: duration
                )
                let (stableRecording, stored) = self.storeInCaptureHistory(recording)
                let anchor = self.activeRecordingQuickAccessAnchor
                self.finishActiveRecording()
                let copied = self.automaticallyCopiesCaptures()
                    && self.copyRecordingFileToClipboard(stableRecording.fileURL, showsFailureAlert: false)
                self.showVideoQuickAccess(for: stableRecording, anchor: anchor, canAutoDismiss: copied || stored)
                NSLog(
                    "Frame 已停止录屏：url=\(stableRecording.fileURL.path), duration=\(stableRecording.duration)"
                )
            } catch {
                self.finishActiveRecording()
                self.showCaptureFailedAlert(error)
            }
        }
    }

    private func restartActiveRecording() {
        guard let session = activeRecordingSession,
              let selection = activeRecordingSelection else {
            return
        }
        let options = activeRecordingOptions
        let anchor = activeRecordingQuickAccessAnchor
        activeRecordingHUDPanelController.setStopping(true)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await session.cancel()
            self.finishActiveRecording()
            self.startRecording(
                selection: selection,
                options: options,
                overlayWindow: nil,
                anchor: anchor
            )
            NSLog("Frame 录屏已重新开始")
        }
    }

    private func deleteActiveRecording() {
        guard let session = activeRecordingSession else {
            return
        }
        activeRecordingHUDPanelController.setStopping(true)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await session.cancel()
            self.finishActiveRecording()
            NSLog("Frame 录屏已删除")
        }
    }

    private func startRecordingElapsedTimer() {
        activeRecordingElapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshRecordingElapsedHUD()
            }
        }
        activeRecordingElapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshRecordingElapsedHUD() {
        let isPaused = activeRecordingSession?.state == .paused
        activeRecordingHUDPanelController.update(elapsed: currentRecordingElapsed(), isPaused: isPaused)
    }

    private func currentRecordingElapsed() -> TimeInterval {
        activeRecordingClock?.elapsed(at: Date()) ?? 0
    }

    private func finishActiveRecording() {
        pendingRecordingStartTask?.cancel()
        pendingRecordingStartTask = nil
        activeRecordingElapsedTimer?.invalidate()
        activeRecordingElapsedTimer = nil
        activeRecordingHUDPanelController.close()
        recordingBoundaryOverlayController.close()
        keyboardHintOverlayController.hide()
        statusItemController?.setRecordingState(.idle)
        activeRecordingSession = nil
        activeRecordingSelection = nil
        activeRecordingClock = nil
        activeRecordingQuickAccessAnchor = nil
        isStoppingActiveRecording = false
        quickAccessPanelController.setPreviewRestorationSuppressed(false)
    }

    func startRecordingForTesting(
        selection: SelectionCapture,
        options: RecordingOptions,
        anchor: CGRect? = nil
    ) {
        startRecording(
            selection: selection,
            options: options,
            overlayWindow: nil,
            anchor: anchor
        )
    }

    @discardableResult
    func startCaptureFlowForTesting() -> Bool {
        startCaptureFlow()
    }

    @discardableResult
    func startRecordingCaptureFlowForTesting() -> Bool {
        startRecordingCaptureFlow()
    }

    func finishActiveRecordingForTesting() {
        finishActiveRecording()
    }

    func stopActiveRecordingForTesting() {
        stopActiveRecording()
    }

    func restartActiveRecordingForTesting() {
        restartActiveRecording()
    }

    func deleteActiveRecordingForTesting() {
        deleteActiveRecording()
    }

    func activeRecordingElapsedTimerIsValidForTesting() -> Bool {
        activeRecordingElapsedTimer?.isValid == true
    }

    func hasActiveRecordingForTesting() -> Bool {
        activeRecordingSession != nil && activeRecordingSelection != nil
    }

    func showVideoQuickAccessForTesting(_ recording: CapturedRecording) {
        showVideoQuickAccess(for: recording, anchor: nil)
    }

    func restoreHistoryRecordForTesting(_ record: CaptureHistoryRecord) async {
        guard record.kind == .screenshot else {
            await restoreHistoryRecording(record)
            return
        }

        restoreHistoryRecord(record)
    }

    func quickAccessRecordingCountForTesting() -> Int {
        quickAccessPanelController.recordingCountForTesting()
    }

    func quickAccessScreenshotCountForTesting() -> Int {
        activeQuickAccessScreenshotIDs.count
    }

    func quickAccessScreenshotIsPendingForTesting(id: UUID) -> Bool {
        quickAccessPanelController.screenshotIsPendingForTesting(id: id)
    }

    func quickAccessRecordingForTesting(id: UUID) -> CapturedRecording? {
        quickAccessPanelController.recordingForTesting(id: id)
    }

    func saveEditedRecordingForTesting(
        _ recording: CapturedRecording,
        editingState: VideoEditingState,
        choice: VideoPreviewSaveChoice
    ) async -> Bool {
        await exportEditedRecording(recording, editingState: editingState, choice: choice)
    }

    private func showVideoQuickAccess(
        for recording: CapturedRecording,
        anchor: CGRect?,
        canAutoDismiss: Bool = false
    ) {
        quickAccessPanelController.show(
            for: recording,
            preferredAnchor: anchor,
            strings: strings,
            canAutoDismiss: canAutoDismiss,
            download: { [weak self] in
                guard let self, let savedURL = self.saveRecordingFile(recording.fileURL, format: recording.format) else {
                    return false
                }
                self.showQuickAccessSavedFeedback(for: recording.id, fileURL: savedURL)
                return true
            },
            copy: { [weak self] in
                guard let self, self.copyRecordingToClipboard(recording) else {
                    return false
                }
                self.quickAccessPanelController.showDeliveryFeedback(self.strings.quickAccessCopied, captureID: recording.id)
                return true
            },
            preview: { [weak self] in
                self?.openVideoPreview(recording) ?? false
            },
            edit: { [weak self] in
                self?.openVideoPreview(recording, focusEditor: true) ?? false
            },
            close: {
                NSLog("Frame 录屏快速操作已关闭")
            }
        )
    }

    private func openVideoPreview(_ recording: CapturedRecording, focusEditor: Bool = false) -> Bool {
        videoPreviewWindowController.show(
            recording: recording,
            strings: strings,
            copy: { [weak self] recording, editingState in
                self?.copyRecordingToClipboard(recording, editingState: editingState) ?? false
            },
            download: { [weak self] recording, editingState in
                self?.downloadRecording(recording, editingState: editingState) ?? false
            },
            saveCurrent: { [weak self] recording, editingState, choice in
                self?.saveEditedRecording(recording, editingState: editingState, choice: choice) ?? false
            },
            focusEditor: focusEditor
        )
        return true
    }

    private func saveEditedRecording(
        _ recording: CapturedRecording,
        editingState: VideoEditingState,
        choice: VideoPreviewSaveChoice
    ) -> Bool {
        Task { @MainActor in
            _ = await self.exportEditedRecording(recording, editingState: editingState, choice: choice)
        }
        return true
    }

    private func exportEditedRecording(
        _ recording: CapturedRecording,
        editingState: VideoEditingState,
        choice: VideoPreviewSaveChoice
    ) async -> Bool {
        do {
            let exportedURL = try await videoEditingExporter.export(
                sourceURL: recording.fileURL,
                format: recording.format,
                editingState: editingState
            )
            let editedRecording = CapturedRecording(
                id: choice == .replaceCurrent ? recording.id : UUID(),
                fileURL: exportedURL,
                format: .mp4,
                rect: recording.rect,
                pixelSize: recording.pixelSize,
                byteSize: byteSize(of: exportedURL),
                duration: editingState.outputDuration
            )

            switch choice {
            case .replaceCurrent:
                _ = quickAccessPanelController.updatePreview(for: editedRecording)
            case .saveAsNew:
                let (stableRecording, stored) = storeInCaptureHistory(editedRecording)
                showVideoQuickAccess(for: stableRecording, anchor: nil, canAutoDismiss: stored)
            }

            return true
        } catch {
            showQuickAccessFailedAlert(title: strings.saveFailedTitle, error: error)
            return false
        }
    }

    private func showCaptureHistory() {
        let controller = captureHistoryWindowController ?? CaptureHistoryWindowController(
            store: captureHistoryStore,
            open: { [weak self] record in
                self?.openHistoryRecord(record)
            },
            restore: { [weak self] record in
                self?.restoreHistoryRecord(record)
            },
            copy: { [weak self] record in
                self?.copyHistoryRecord(record)
            },
            save: { [weak self] record in
                self?.saveHistoryRecord(record)
            },
            delete: { [weak self] record in
                self?.deleteHistoryRecord(record)
            },
            startCapture: { [weak self] filter in
                if filter == .recordings {
                    self?.startRecordingCaptureFlow()
                } else {
                    self?.onCapture()
                }
            },
            openHistorySettings: { [weak self] in
                self?.onSettings()
                self?.settingsWindowController.selectSection(.history)
            }
        )
        captureHistoryWindowController = controller
        controller.show(strings: strings)
    }

    private func storeInCaptureHistory(_ screenshot: CapturedScreenshot) -> Bool {
        do {
            return try captureHistoryStore.addScreenshot(screenshot) != nil
        } catch {
            NSLog("Frame 写入截图历史失败: \(error.localizedDescription)")
            return false
        }
    }

    private func storeInCaptureHistory(_ recording: CapturedRecording) -> (CapturedRecording, Bool) {
        do {
            let recordingData = try Data(contentsOf: recording.fileURL)
            guard let record = try captureHistoryStore.addRecording(
                data: recordingData,
                filenameExtension: recording.format.fileExtension,
                pixelSize: recording.pixelSize,
                rect: recording.rect
            ) else {
                return (recording, false)
            }

            let storedRecording = CapturedRecording(
                id: record.id,
                fileURL: captureHistoryStore.fileURL(for: record),
                format: recording.format,
                rect: record.rect,
                pixelSize: CGSize(width: CGFloat(record.pixelWidth), height: CGFloat(record.pixelHeight)),
                byteSize: record.byteSize,
                duration: recording.duration
            )
            return (storedRecording, true)
        } catch {
            NSLog("Frame 写入录屏历史失败: \(error.localizedDescription)")
            return (recording, false)
        }
    }

    private func screenshot(from record: CaptureHistoryRecord) throws -> CapturedScreenshot {
        let data = try captureHistoryStore.data(for: record)
        guard let image = NSImage(data: data) else {
            throw CaptureHistoryError.imageDecodeFailed
        }

        return CapturedScreenshot(id: record.id, pngData: data, image: image, rect: record.rect)
    }

    private func recording(from record: CaptureHistoryRecord) async throws -> CapturedRecording {
        guard let format = recordingFormat(for: record) else {
            throw CaptureHistoryError.recordingFormatUnsupported
        }

        return CapturedRecording(
            id: record.id,
            fileURL: captureHistoryStore.fileURL(for: record),
            format: format,
            rect: record.rect,
            pixelSize: CGSize(width: CGFloat(record.pixelWidth), height: CGFloat(record.pixelHeight)),
            byteSize: record.byteSize,
            duration: await recordingDuration(for: record, format: format)
        )
    }

    private func recordingDuration(for record: CaptureHistoryRecord, format: RecordingFormat) async -> TimeInterval {
        let fileURL = captureHistoryStore.fileURL(for: record)
        switch format {
        case .mp4:
            let asset = AVURLAsset(url: fileURL)
            guard let duration = try? await asset.load(.duration) else {
                return 0
            }

            return normalizedRecordingDuration(duration.seconds)
        case .gif:
            return gifRecordingDuration(for: fileURL)
        }
    }

    private func gifRecordingDuration(for fileURL: URL) -> TimeInterval {
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return 0
        }

        let frameCount = CGImageSourceGetCount(imageSource)
        return (0..<frameCount).reduce(0) { duration, frameIndex in
            duration + gifFrameDuration(in: imageSource, at: frameIndex)
        }
    }

    private func gifFrameDuration(in imageSource: CGImageSource, at frameIndex: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, frameIndex, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0
        }

        let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber
        let delay = gifProperties[kCGImagePropertyGIFDelayTime] as? NSNumber
        return normalizedRecordingDuration((unclampedDelay ?? delay)?.doubleValue ?? 0)
    }

    private func normalizedRecordingDuration(_ duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite, duration > 0 else {
            return 0
        }

        return duration
    }

    private func openHistoryRecord(_ record: CaptureHistoryRecord) {
        switch record.kind {
        case .screenshot:
            do {
                _ = openWorkspace(try screenshot(from: record), kind: .temporaryPreview)
            } catch {
                showQuickAccessFailedAlert(title: strings.captureFailedTitle, error: error)
            }
        case .recording:
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    _ = self.openVideoPreview(try await self.recording(from: record))
                } catch {
                    self.showQuickAccessFailedAlert(title: self.strings.captureFailedTitle, error: error)
                }
            }
        }
    }

    private func restoreHistoryRecord(_ record: CaptureHistoryRecord) {
        guard record.kind == .screenshot else {
            Task { @MainActor in
                await restoreHistoryRecording(record)
            }
            return
        }

        do {
            showQuickAccess(
                for: try screenshot(from: record),
                anchor: ActiveScreenResolver.preferredQuickAccessFollowAnchor(),
                canAutoDismiss: true
            )
        } catch {
            showQuickAccessFailedAlert(title: strings.captureFailedTitle, error: error)
        }
    }

    private func restoreHistoryRecording(_ record: CaptureHistoryRecord) async {
        do {
            showVideoQuickAccess(
                for: try await recording(from: record),
                anchor: ActiveScreenResolver.preferredQuickAccessFollowAnchor(),
                canAutoDismiss: true
            )
        } catch {
            showQuickAccessFailedAlert(title: strings.captureFailedTitle, error: error)
        }
    }

    private func copyHistoryRecord(_ record: CaptureHistoryRecord) {
        guard record.kind == .screenshot else {
            do {
                try clipboardWriter.write(fileURL: captureHistoryStore.fileURL(for: record))
            } catch {
                showQuickAccessFailedAlert(title: strings.copyFailedTitle, error: error)
            }
            return
        }

        do {
            _ = copyToClipboard(try screenshot(from: record))
        } catch {
            showQuickAccessFailedAlert(title: strings.copyFailedTitle, error: error)
        }
    }

    private func saveHistoryRecord(_ record: CaptureHistoryRecord) {
        guard record.kind == .screenshot else {
            guard let format = recordingFormat(for: record) else {
                return
            }

            do {
                _ = try recordingFileWriter.copyRecording(
                    from: captureHistoryStore.fileURL(for: record),
                    format: format,
                    date: record.createdAt
                )
            } catch {
                showQuickAccessFailedAlert(title: strings.saveFailedTitle, error: error)
            }
            return
        }

        do {
            _ = saveToDesktop(try screenshot(from: record))
        } catch {
            showQuickAccessFailedAlert(title: strings.saveFailedTitle, error: error)
        }
    }

    private func deleteHistoryRecord(_ record: CaptureHistoryRecord) {
        do {
            try captureHistoryStore.delete(recordID: record.id)
        } catch {
            showQuickAccessFailedAlert(title: strings.captureHistoryDelete, error: error)
        }
    }

    private func openImageFile() {
        NSApp.activate(ignoringOtherApps: true)
        ImageWorkspaceFileDialogs.open(strings: strings, window: nil) { [weak self] url in
            self?.openEditorFile(at: url)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL {
            openEditorFile(at: url)
        }
    }

    private func openEditorFile(at url: URL) {
        do {
            if url.pathExtension.lowercased() == "frameimage" {
                let project = try ImageWorkspaceRaster.project(at: url)
                _ = openWorkspace(try project.screenshot(), kind: .temporaryPreview, initialElements: project.elements)
            } else {
                let screenshot = try ImageWorkspaceRaster.screenshot(data: Data(contentsOf: url))
                _ = openWorkspace(screenshot, kind: .temporaryPreview)
            }
        } catch {
            ImageWorkspaceFileDialogs.showError(error, strings: strings, window: nil)
        }
    }

    private func openClipboardImage() {
        NSApp.activate(ignoringOtherApps: true)
        do {
            _ = openWorkspace(try ImageWorkspaceRaster.pasteboardImage(.general), kind: .temporaryPreview)
        } catch {
            ImageWorkspaceFileDialogs.showError(error, strings: strings, window: nil,
                message: strings.editorLabel("剪贴板里没有可打开的图片。", "The clipboard doesn’t contain a readable image."))
        }
    }

    private func openWorkspace(
        _ screenshot: CapturedScreenshot,
        kind: ImageWorkspaceKind,
        initialElements: [ImageAnnotationElement] = []
    ) -> Bool {
        imageWorkspacePanelController.show(
            screenshot: screenshot,
            kind: kind,
            strings: strings,
            copy: { [weak self] editedScreenshot in
                guard let self,
                      self.copyToClipboard(editedScreenshot) else {
                    return false
                }

                self.quickAccessPanelController.closePreview(for: screenshot, notify: false)
                self.endQuickAccessLifecycle(for: screenshot)
                return true
            },
            save: { [weak self] editedScreenshot in
                guard let self else { return false }
                let saved = kind == .pinned
                    ? self.saveToDesktop(editedScreenshot)
                    : ImageWorkspaceFileDialogs.export(editedScreenshot, strings: self.strings)
                guard saved else { return false }

                self.quickAccessPanelController.closePreview(for: screenshot, notify: false)
                self.endQuickAccessLifecycle(for: screenshot)
                return true
            },
            recognizeText: { [weak self] screenshot in
                guard let self else {
                    throw OCRServiceError.cgImageUnavailable
                }

                return try await self.ocrService.recognizeText(in: screenshot)
            },
            copyRecognizedText: { [weak self] text in
                self?.copyRecognizedText(text) ?? false
            },
            replaceCurrent: { [weak self] editedScreenshot in
                guard let self else {
                    throw CocoaError(.userCancelled)
                }

                try self.persistEditedScreenshot(editedScreenshot)
                self.recognizedTextLayouts.removeValue(forKey: editedScreenshot.id)
                if self.activeQuickAccessScreenshotIDs.contains(editedScreenshot.id) {
                    self.activeQuickAccessScreenshots[editedScreenshot.id] = editedScreenshot
                    self.quickAccessPanelController.updatePreview(for: editedScreenshot)
                }
            },
            saveAsNew: { [weak self] editedScreenshot in
                guard let self else {
                    return false
                }

                do {
                    let stored = try self.persistEditedScreenshot(editedScreenshot)
                    self.showQuickAccess(for: editedScreenshot, anchor: editedScreenshot.rect, canAutoDismiss: stored)
                    return true
                } catch {
                    return false
                }
            },
            initialElements: initialElements
        )
    }

    @discardableResult
    private func persistEditedScreenshot(_ screenshot: CapturedScreenshot) throws -> Bool {
        do {
            let stored = try captureHistoryStore.saveEditedScreenshot(screenshot)
            captureHistoryWindowController?.refreshRecords()
            return stored
        } catch {
            showQuickAccessFailedAlert(title: strings.saveFailedTitle, error: error)
            throw error
        }
    }

    private func recognizeText(in screenshot: CapturedScreenshot) -> Bool {
        guard activeQuickAccessScreenshotIDs.contains(screenshot.id) else {
            return false
        }

        if let layout = recognizedTextLayouts[screenshot.id] {
            quickAccessPanelController.setOCRStatus(.idle(accessibilityLabel: strings.quickAccessOCR), for: screenshot)
            showOCRPanel(layout, for: screenshot)
            return true
        }

        guard !recognizingScreenshotIDs.contains(screenshot.id) else {
            return true
        }

        recognizingScreenshotIDs.insert(screenshot.id)
        quickAccessPanelController.setOCRStatus(.recognizing(strings.ocrRecognizing), for: screenshot)
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let layout = try await self.ocrService.recognizeText(in: screenshot)
                self.recognizingScreenshotIDs.remove(screenshot.id)

                guard self.activeQuickAccessScreenshotIDs.contains(screenshot.id) else {
                    return
                }

                guard !layout.isEmpty else {
                    self.quickAccessPanelController.setOCRStatus(
                        .message(self.strings.ocrNoTextFound, resetAfter: 2.2),
                        for: screenshot
                    )
                    return
                }

                self.recognizedTextLayouts[screenshot.id] = layout
                self.quickAccessPanelController.setOCRStatus(
                    .idle(accessibilityLabel: self.strings.quickAccessOCR),
                    for: screenshot
                )
                self.showOCRPanel(layout, for: screenshot)
            } catch {
                self.recognizingScreenshotIDs.remove(screenshot.id)
                guard self.activeQuickAccessScreenshotIDs.contains(screenshot.id) else {
                    return
                }

                self.quickAccessPanelController.setOCRStatus(
                    .message(self.strings.ocrFailedTitle, resetAfter: 2.2),
                    for: screenshot
                )
                self.showQuickAccessFailedAlert(title: self.strings.ocrFailedTitle, error: error)
            }
        }

        return true
    }

    private func showOCRPanel(_ layout: RecognizedTextLayout, for screenshot: CapturedScreenshot) {
        ocrTextPanelController.show(
            layout: layout,
            for: screenshot,
            strings: strings,
            copyText: { [weak self] text in
                guard let self,
                      self.copyRecognizedText(text) else {
                    return false
                }

                self.quickAccessPanelController.setOCRStatus(
                    .message(self.strings.ocrCopied, resetAfter: 1.4),
                    for: screenshot
                )
                return true
            }
        )
    }

    private func copyRecognizedText(_ text: String) -> Bool {
        do {
            try clipboardWriter.write(text: text)
            NSLog("Frame 已复制识别文字到剪贴板")
            return true
        } catch {
            showQuickAccessFailedAlert(title: strings.copyFailedTitle, error: error)
            return false
        }
    }

    private func showOCRNoTextFoundAlert() {
        let alert = NSAlert()
        alert.messageText = strings.ocrNoTextFound
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }

    private func endQuickAccessLifecycle(for screenshot: CapturedScreenshot) {
        activeQuickAccessScreenshotIDs.remove(screenshot.id)
        activeQuickAccessScreenshots.removeValue(forKey: screenshot.id)
        recognizingScreenshotIDs.remove(screenshot.id)
        recognizedTextLayouts.removeValue(forKey: screenshot.id)
        _ = ocrTextPanelController.closePanel(for: screenshot)
    }

    private func currentQuickAccessScreenshot(for screenshot: CapturedScreenshot) -> CapturedScreenshot {
        activeQuickAccessScreenshots[screenshot.id] ?? screenshot
    }

    private func automaticallyCopyScreenshot(_ screenshot: CapturedScreenshot) -> Bool {
        guard automaticallyCopiesCaptures() else {
            return false
        }

        return copyToClipboard(screenshot, showsFailureAlert: false)
    }

    private func copyToClipboard(_ screenshot: CapturedScreenshot, showsFailureAlert: Bool = true) -> Bool {
        do {
            try clipboardWriter.write(image: screenshot.image, pngData: screenshot.pngData)
            NSLog("Frame 已复制截图到剪贴板")
            return true
        } catch {
            reportClipboardFailure(error, showsAlert: showsFailureAlert)
            return false
        }
    }

    private func copyRecordingToClipboard(
        _ recording: CapturedRecording,
        editingState: VideoEditingState? = nil
    ) -> Bool {
        guard let editingState else {
            return copyRecordingFileToClipboard(recording.fileURL)
        }

        Task { @MainActor in
            _ = await self.copyEditedRecordingToClipboard(recording, editingState: editingState)
        }
        return true
    }

    private func copyRecordingFileToClipboard(_ fileURL: URL, showsFailureAlert: Bool = true) -> Bool {
        do {
            try clipboardWriter.write(fileURL: fileURL)
            NSLog("Frame 已复制录屏文件到剪贴板")
            return true
        } catch {
            reportClipboardFailure(error, showsAlert: showsFailureAlert)
            return false
        }
    }

    private func reportClipboardFailure(_ error: Error, showsAlert: Bool) {
        if showsAlert {
            showQuickAccessFailedAlert(title: strings.copyFailedTitle, error: error)
        } else {
            NSLog("Frame 自动复制失败: \(error.localizedDescription)")
        }
    }

    private func copyEditedRecordingToClipboard(
        _ recording: CapturedRecording,
        editingState: VideoEditingState
    ) async -> Bool {
        do {
            let exportedURL = try await videoEditingExporter.export(
                sourceURL: recording.fileURL,
                format: recording.format,
                editingState: editingState
            )
            return copyRecordingFileToClipboard(exportedURL)
        } catch {
            showQuickAccessFailedAlert(title: strings.copyFailedTitle, error: error)
            return false
        }
    }

    private func showQuickAccessSavedFeedback(for captureID: UUID, fileURL: URL) {
        let folder = FileManager.default.displayName(atPath: fileURL.deletingLastPathComponent().path)
        quickAccessPanelController.showDeliveryFeedback(strings.quickAccessSaved(to: folder), captureID: captureID)
    }

    private func saveToDesktop(_ screenshot: CapturedScreenshot) -> Bool {
        saveScreenshotFile(screenshot) != nil
    }

    private func saveScreenshotFile(_ screenshot: CapturedScreenshot) -> URL? {
        do {
            let saveURL = try ScreenshotFileWriter(strings: strings).write(pngData: screenshot.pngData)
            NSLog("Frame 已保存截图：\(saveURL.path)")
            return saveURL
        } catch {
            showQuickAccessFailedAlert(title: strings.saveFailedTitle, error: error)
            return nil
        }
    }

    private func downloadRecording(
        _ recording: CapturedRecording,
        editingState: VideoEditingState? = nil
    ) -> Bool {
        guard let editingState else {
            return downloadRecordingFile(recording.fileURL, format: recording.format)
        }

        Task { @MainActor in
            _ = await self.downloadEditedRecording(recording, editingState: editingState)
        }
        return true
    }

    private func downloadRecordingFile(_ fileURL: URL, format: RecordingFormat) -> Bool {
        saveRecordingFile(fileURL, format: format) != nil
    }

    private func saveRecordingFile(_ fileURL: URL, format: RecordingFormat) -> URL? {
        do {
            let saveURL = try recordingFileWriter.copyRecording(
                from: fileURL,
                format: format
            )
            NSLog("Frame 已保存录屏：\(saveURL.path)")
            return saveURL
        } catch {
            showQuickAccessFailedAlert(title: strings.saveFailedTitle, error: error)
            return nil
        }
    }

    private func downloadEditedRecording(
        _ recording: CapturedRecording,
        editingState: VideoEditingState
    ) async -> Bool {
        do {
            let exportedURL = try await videoEditingExporter.export(
                sourceURL: recording.fileURL,
                format: recording.format,
                editingState: editingState
            )
            return downloadRecordingFile(exportedURL, format: .mp4)
        } catch {
            showQuickAccessFailedAlert(title: strings.saveFailedTitle, error: error)
            return false
        }
    }

    private func byteSize(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes?[.size] as? NSNumber {
            return size.intValue
        }

        return attributes?[.size] as? Int ?? 0
    }

    private func recordingFormat(for record: CaptureHistoryRecord) -> RecordingFormat? {
        RecordingFormat(rawValue: (record.filename as NSString).pathExtension)
    }

    private func chooseScreenshotDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = strings.settingsSaveLocation
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let directory = panel.url else {
            return nil
        }

        return directory
    }

    private func changeLanguage(to language: AppLanguage) {
        SettingsStore.setAppLanguage(language)
        strings = AppStrings.current()
        statusItemController?.reloadMenu(strings: strings)
        settingsWindowController.update(strings: strings)
    }

    private func changeScreenshotShortcut(to shortcut: ScreenshotShortcut) -> Bool {
        if shortcut == SettingsStore.screenshotShortcut() {
            return true
        }
        guard confirmShortcutChange(shortcut) else { return false }

        guard let hotKeyController else {
            SettingsStore.setScreenshotShortcut(shortcut)
            statusItemController?.updateShortcuts(
                screenshotShortcut: shortcut,
                recordingShortcut: SettingsStore.recordingShortcut()
            )
            return true
        }

        let previousShortcut = hotKeyController.shortcut

        do {
            try hotKeyController.register(shortcut: shortcut)
            SettingsStore.setScreenshotShortcut(shortcut)
            statusItemController?.updateShortcuts(
                screenshotShortcut: shortcut,
                recordingShortcut: hotKeyController.recordingShortcut
            )
            NSLog("Frame 截图快捷键已更新为 \(shortcut.displayName)")
            return true
        } catch {
            do {
                try hotKeyController.register(shortcut: previousShortcut)
            } catch {
                NSLog("Frame 恢复原快捷键失败: \(error.localizedDescription)")
            }

            showHotKeyRegistrationFailedAlert(error)
            return false
        }
    }

    private func changeRecordingShortcut(to shortcut: ScreenshotShortcut?) -> Bool {
        if shortcut == SettingsStore.recordingShortcut() {
            return true
        }
        if let shortcut, !confirmShortcutChange(shortcut) {
            return false
        }

        guard let hotKeyController else {
            SettingsStore.setRecordingShortcut(shortcut)
            statusItemController?.updateShortcuts(
                screenshotShortcut: SettingsStore.screenshotShortcut(),
                recordingShortcut: shortcut
            )
            return true
        }

        let screenshotShortcut = hotKeyController.shortcut
        let previousShortcut = hotKeyController.recordingShortcut

        do {
            try hotKeyController.register(shortcut: screenshotShortcut, recordingShortcut: .some(shortcut))
            SettingsStore.setRecordingShortcut(shortcut)
            statusItemController?.updateShortcuts(
                screenshotShortcut: screenshotShortcut,
                recordingShortcut: shortcut
            )
            NSLog("Frame 录屏快捷键已更新为 \(shortcut?.displayName ?? "未设置")")
            return true
        } catch {
            do {
                try hotKeyController.register(shortcut: screenshotShortcut, recordingShortcut: .some(previousShortcut))
            } catch {
                NSLog("Frame 恢复原录屏快捷键失败: \(error.localizedDescription)")
            }

            showHotKeyRegistrationFailedAlert(error)
            return false
        }
    }

    private func confirmShortcutChange(_ shortcut: ScreenshotShortcut) -> Bool {
        if HotKeyController.systemShortcutIsInUse(shortcut) {
            showHotKeyConflictAlert(message: strings.systemHotKeyConflictMessage(shortcut: shortcut.displayName))
            return false
        }

        guard HotKeyController.overlapsCommonAppShortcut(shortcut) else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = strings.commonHotKeyWarningTitle
        alert.informativeText = strings.commonHotKeyWarningMessage(shortcut: shortcut.displayName)
        alert.addButton(withTitle: strings.hotKeyChooseAnother).keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: strings.hotKeyUseAnyway)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func setScreenshotShortcutRecorderActive(_ isRecording: Bool) {
        guard let hotKeyController else {
            return
        }

        if isRecording {
            hotKeyController.unregister()
            return
        }

        do {
            try hotKeyController.register()
        } catch {
            showHotKeyRegistrationFailedAlert(error)
        }
    }

    private func showHotKeyRegistrationFailedAlert(_ error: Error) {
        if case let HotKeyRegistrationError.shortcutInUse(shortcut) = error {
            showHotKeyConflictAlert(message: strings.appHotKeyConflictMessage(shortcut: shortcut.displayName))
            return
        }

        let alert = NSAlert()
        alert.messageText = strings.hotKeyRegistrationFailedTitle
        alert.informativeText = strings.hotKeyRegistrationFailedMessage(errorDescription: error.localizedDescription)
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }

    private func showHotKeyConflictAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = strings.hotKeyConflictTitle
        alert.informativeText = message
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }

    private func showCaptureFailedAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = strings.captureFailedTitle
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }

    private func showScrollingScreenshotFailedAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = strings.scrollingScreenshotFailedTitle
        if let stitchingError = error as? ScrollingScreenshotStitchingError,
           stitchingError == .insufficientFrames || stitchingError == .noScrollProgress {
            alert.informativeText = strings.scrollingScreenshotInsufficientProgress
        } else if let stitchingError = error as? ScrollingScreenshotStitchingError,
                  stitchingError == .noReliableOverlap {
            alert.informativeText = strings.scrollingScreenshotNoReliableOverlap
        } else {
            alert.informativeText = error.localizedDescription
        }
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }

    private func showQuickAccessFailedAlert(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }
}

private enum CaptureHistoryError: Error, LocalizedError {
    case imageDecodeFailed
    case recordingFormatUnsupported

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            "Could not decode the cached capture image."
        case .recordingFormatUnsupported:
            "Could not restore the cached recording because its format is unsupported."
        }
    }
}
