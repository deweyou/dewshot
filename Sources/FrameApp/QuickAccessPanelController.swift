import AppKit
import AVKit

@MainActor
final class QuickAccessPanelController: NSObject {
    static let previewWindowTitle = "dewShot Quick Access Preview"
    static let hoverPreviewWindowTitle = "dewShot Quick Access Hover Preview"
    static let deliveryFeedbackWindowTitle = "dewShot Quick Access Feedback"
    static let defaultHoverPreviewDelayForTesting: TimeInterval = 2

    private typealias ConfirmableAction = () -> Bool
    private typealias CloseAction = () -> Void

    private let thumbnailProvider: RecordingThumbnailProvider
    private let hoverPreviewDelay: TimeInterval
    private let dismissalDelay: () -> TimeInterval?
    private let hoverPreviewController = QuickAccessHoverPreviewController()
    private weak var hoverPreviewOwner: QuickAccessPreviewItem?
    private var previewItems: [QuickAccessPreviewItem] = []
    private var dismissalTimer: Timer?
    private var deliveryFeedbackPanel: NSPanel?
    private var deliveryFeedbackTimer: Timer?
    private var screenConfigurationObserver: NSObjectProtocol?
    private var currentPreviewScreenID: CGDirectDisplayID?
    private var isPreviewRestorationSuppressed = false

    init(
        thumbnailProvider: RecordingThumbnailProvider = RecordingThumbnailProvider(),
        hoverPreviewDelay: TimeInterval = QuickAccessPanelController.defaultHoverPreviewDelayForTesting,
        dismissalDelay: @escaping () -> TimeInterval? = { SettingsStore.quickAccessDismissal().delay }
    ) {
        self.thumbnailProvider = thumbnailProvider
        self.hoverPreviewDelay = hoverPreviewDelay
        self.dismissalDelay = dismissalDelay
    }

    func show(
        for captured: CapturedScreenshot,
        preferredAnchor: CGRect?,
        strings: AppStrings = AppStrings.current(),
        isPending: Bool = false,
        canAutoDismiss: Bool = false,
        isInUse: @escaping () -> Bool = { false },
        copy: @escaping () -> Bool,
        save: @escaping () -> Bool,
        recognizeText: @escaping () -> Bool,
        openExternally: @escaping () -> Bool,
        pin: @escaping () -> Bool,
        close: @escaping () -> Void
    ) {
        let panel = makePanel(for: captured.image)
        let content = makeContentView(for: captured, strings: strings, isPending: isPending)
        panel.contentView = content.view
        let item = QuickAccessPreviewItem(
            screenshotID: captured.id,
            recordingID: nil,
            panel: panel,
            ocrButton: content.ocrButton,
            ocrProgressIndicator: content.ocrProgressIndicator,
            ocrFeedback: content.ocrFeedback,
            screenshotImageView: content.imageView,
            screenshotContentView: content.view,
            pendingProgressIndicator: content.pendingProgressIndicator,
            recordingContentView: nil,
            copy: copy,
            save: save,
            recognizeText: recognizeText,
            openExternally: openExternally,
            pin: pin,
            downloadRecording: nil,
            copyRecording: nil,
            previewRecording: nil,
            hoverPreviewMedia: .image(captured.image),
            isInUse: isInUse,
            close: close
        )
        previewItems.append(item)
        if canAutoDismiss && !isPending {
            startCountdown(for: item)
        }
        layoutPreviewStack(preferredAnchor: preferredAnchor)
        observeScreenConfiguration()

        panel.orderFrontRegardless()
    }

    func show(
        for recording: CapturedRecording,
        preferredAnchor: CGRect?,
        strings: AppStrings = AppStrings.current(),
        canAutoDismiss: Bool = false,
        download: @escaping () -> Bool,
        copy: @escaping () -> Bool,
        preview: @escaping () -> Bool,
        openExternally: @escaping () -> Bool,
        close: @escaping () -> Void
    ) {
        restoreTemporarilyHiddenPreviews()
        if let item = previewItems.first(where: { $0.recordingID == recording.id }) {
            item.panel.orderFrontRegardless()
            return
        }

        let sourceSize = recording.pixelSize == .zero ? recording.rect.size : recording.pixelSize
        let previewSize = Self.recordingPreviewSize(forSourceSize: sourceSize)
        let panel = makePanel(size: previewSize)
        let content = makeRecordingContentView(
            for: recording,
            previewSize: previewSize,
            strings: strings,
            preview: preview
        )
        content.frame = CGRect(origin: .zero, size: previewSize)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        let item = QuickAccessPreviewItem(
            screenshotID: nil,
            recordingID: recording.id,
            panel: panel,
            ocrButton: nil,
            ocrProgressIndicator: nil,
            ocrFeedback: nil,
            screenshotImageView: nil,
            screenshotContentView: nil,
            pendingProgressIndicator: nil,
            recordingContentView: content,
            copy: nil,
            save: nil,
            recognizeText: nil,
            openExternally: openExternally,
            pin: nil,
            downloadRecording: download,
            copyRecording: copy,
            previewRecording: preview,
            hoverPreviewMedia: .recording(recording),
            close: close
        )
        previewItems.append(item)
        if canAutoDismiss {
            startCountdown(for: item)
        }
        layoutPreviewStack(preferredAnchor: preferredAnchor)
        observeScreenConfiguration()

        panel.orderFrontRegardless()
        content.layoutSubtreeIfNeeded()
    }

    func showDeliveryFeedback(_ message: String, captureID: UUID) {
        guard let source = previewItems.first(where: {
            $0.screenshotID == captureID || $0.recordingID == captureID
        })?.panel else {
            return
        }

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = FrameHUDChrome.primaryIcon
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        let visibleFrame = source.screen?.visibleFrame ?? source.frame
        let size = CGSize(width: min(260, max(72, ceil(label.fittingSize.width) + 24)), height: 32)
        let origin = CGPoint(
            x: min(max(source.frame.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: max(visibleFrame.minY, source.frame.minY)
        )

        let panel = NSPanel(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = Self.deliveryFeedbackWindowTitle
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let glass = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        FrameHUDChrome.configure(glass, surface: .overlay, cornerRadius: size.height / 2)
        label.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: glass.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -12),
        ])
        panel.contentView = glass
        panel.setFrameOrigin(origin)

        closeDeliveryFeedback()
        deliveryFeedbackPanel = panel
        panel.orderFrontRegardless()
        deliveryFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closeDeliveryFeedback()
            }
        }
    }

    @discardableResult
    func closePreview(for screenshot: CapturedScreenshot, notify: Bool) -> Bool {
        guard let item = previewItems.first(where: { $0.screenshotID == screenshot.id }) else {
            return false
        }

        closePreview(item, notify: notify)
        return true
    }

    @discardableResult
    func updatePreview(for screenshot: CapturedScreenshot) -> Bool {
        guard let item = previewItems.first(where: { $0.screenshotID == screenshot.id }) else {
            return false
        }

        item.screenshotImageView?.setImage(screenshot.image)
        item.hoverPreviewMedia = .image(screenshot.image)
        item.hoverPreviewWorkItem?.cancel()
        item.hoverPreviewWorkItem = nil
        if hoverPreviewOwner === item {
            closeHoverPreview()
        }
        return true
    }

    @discardableResult
    func setScreenshotPending(
        _ isPending: Bool,
        for screenshot: CapturedScreenshot,
        canAutoDismiss: Bool = false
    ) -> Bool {
        guard let item = previewItems.first(where: { $0.screenshotID == screenshot.id }) else {
            return false
        }

        item.screenshotContentView?.setActionsEnabled(!isPending)
        if isPending {
            item.dismissalRemaining = nil
            stopDismissalTimerIfNeeded()
            item.pendingProgressIndicator?.isHidden = false
            item.pendingProgressIndicator?.startAnimation(nil)
        } else {
            item.pendingProgressIndicator?.stopAnimation(nil)
            item.pendingProgressIndicator?.isHidden = true
            if canAutoDismiss {
                startCountdown(for: item)
            }
        }
        return true
    }

    private func startCountdown(for item: QuickAccessPreviewItem) {
        guard let delay = dismissalDelay() else { return }
        item.dismissalRemaining = delay
        item.dismissalUpdatedAt = ProcessInfo.processInfo.systemUptime

        guard dismissalTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                self.updatePreviewExpiry(
                    at: ProcessInfo.processInfo.systemUptime,
                    mouseLocation: NSEvent.mouseLocation,
                    isPointerDown: NSEvent.pressedMouseButtons & 1 != 0
                )
            }
        }
        timer.tolerance = 0.02
        dismissalTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func updatePreviewExpiry(at now: TimeInterval, mouseLocation: CGPoint, isPointerDown: Bool) {
        var expired: [QuickAccessPreviewItem] = []
        for item in previewItems {
            guard let remaining = item.dismissalRemaining else { continue }
            let elapsed = max(0, now - item.dismissalUpdatedAt)
            item.dismissalUpdatedAt = now

            let isOverCard = item.panel.frame.contains(mouseLocation)
            item.isHoldingPointer = isPointerDown && (isOverCard || item.isHoldingPointer)
            if item.isTemporarilyHidden || isOverCard || item.isHoldingPointer
                || hoverPreviewOwner === item || item.isInUse() {
                continue
            }

            item.dismissalRemaining = remaining - elapsed
            if elapsed >= remaining {
                expired.append(item)
            }
        }

        for item in expired {
            closePreview(item, notify: true)
        }
    }

    private func stopDismissalTimerIfNeeded() {
        guard !previewItems.contains(where: { $0.dismissalRemaining != nil }) else { return }
        dismissalTimer?.invalidate()
        dismissalTimer = nil
    }

    @discardableResult
    func updatePreview(for recording: CapturedRecording) -> Bool {
        guard let item = previewItems.first(where: { $0.recordingID == recording.id }) else {
            return false
        }

        item.hoverPreviewMedia = .recording(recording)
        item.recordingContentView?.updateDuration(recording.duration)
        item.hoverPreviewWorkItem?.cancel()
        item.hoverPreviewWorkItem = nil
        if hoverPreviewOwner === item {
            closeHoverPreview()
        }
        return true
    }

    func setOCRStatus(_ status: QuickAccessOCRStatus, for screenshot: CapturedScreenshot) {
        guard let item = previewItems.first(where: { $0.screenshotID == screenshot.id }) else {
            return
        }
        guard let ocrButton = item.ocrButton,
              let ocrProgressIndicator = item.ocrProgressIndicator,
              let ocrFeedback = item.ocrFeedback else {
            return
        }

        item.statusResetWorkItem?.cancel()
        item.statusResetWorkItem = nil

        switch status {
        case let .idle(accessibilityLabel):
            ocrButton.isEnabled = true
            ocrButton.alphaValue = 1
            ocrButton.setAccessibilityHelp(accessibilityLabel)
            ocrButton.toolTip = accessibilityLabel
            ocrProgressIndicator.stopAnimation(nil)
            ocrProgressIndicator.isHidden = true
            ocrFeedback.message = nil
        case let .recognizing(message):
            ocrButton.isEnabled = false
            ocrButton.alphaValue = 0.18
            ocrButton.setAccessibilityHelp(message)
            ocrButton.toolTip = nil
            ocrProgressIndicator.isHidden = false
            ocrProgressIndicator.startAnimation(nil)
            ocrFeedback.message = nil
        case let .message(message, resetAfter):
            ocrButton.isEnabled = true
            ocrButton.alphaValue = 1
            ocrButton.setAccessibilityHelp(ocrButton.accessibilityLabel())
            ocrButton.toolTip = ocrButton.accessibilityLabel()
            ocrProgressIndicator.stopAnimation(nil)
            ocrProgressIndicator.isHidden = true
            ocrFeedback.message = message

            let workItem = DispatchWorkItem { [weak ocrFeedback] in
                ocrFeedback?.message = nil
            }
            item.statusResetWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + resetAfter, execute: workItem)
        }
    }

    private func closeDeliveryFeedback() {
        deliveryFeedbackTimer?.invalidate()
        deliveryFeedbackTimer = nil
        deliveryFeedbackPanel?.close()
        deliveryFeedbackPanel = nil
    }

    func temporarilyHidePreviews() {
        closeDeliveryFeedback()
        for item in previewItems {
            item.isTemporarilyHidden = true
            item.hoverPreviewWorkItem?.cancel()
            item.hoverPreviewWorkItem = nil
            hideTemporarily(item.panel)
        }
        closeHoverPreview()
    }

    func closePreviewsForRecordingStart() {
        temporarilyHidePreviews()
        closeOrphanPreviewPanels()
    }

    func setPreviewRestorationSuppressed(_ isSuppressed: Bool) {
        isPreviewRestorationSuppressed = isSuppressed
        if isSuppressed {
            temporarilyHidePreviews()
        }
    }

    func restoreTemporarilyHiddenPreviews() {
        guard !isPreviewRestorationSuppressed else {
            temporarilyHidePreviews()
            return
        }

        let hiddenItems = previewItems.filter(\.isTemporarilyHidden)
        guard !hiddenItems.isEmpty else {
            return
        }

        layoutPreviewStack()
        let now = ProcessInfo.processInfo.systemUptime
        for item in hiddenItems {
            item.isTemporarilyHidden = false
            item.dismissalUpdatedAt = now
            restoreTemporarilyHiddenPanel(item.panel)
            item.panel.orderFrontRegardless()
        }
    }

    private func hideTemporarily(_ panel: NSPanel) {
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    private func restoreTemporarilyHiddenPanel(_ panel: NSPanel) {
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
    }

    private func configurePreviewEdge(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
    }

    private func makePanel(for image: NSImage) -> NSPanel {
        // Non-activating panels do not reliably participate in cursor-rect updates
        // while another app is focused, so Quick Access stays a normal floating panel.
        makePanel(size: previewSize)
    }

    private func makePanel(size: CGSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.title = Self.previewWindowTitle

        return panel
    }

    private func makeContentView(
        for screenshot: CapturedScreenshot,
        strings: AppStrings,
        isPending: Bool
    ) -> QuickAccessContent {
        let contentView = ScreenshotPreviewView()
        contentView.setActionsEnabled(!isPending)
        contentView.wantsLayer = true
        contentView.onPointerDown = { [weak self, weak contentView] in
            self?.previewItem(for: contentView?.window)?.isHoldingPointer = true
        }
        contentView.onHoverChanged = { [weak self, weak contentView] isHovered in
            contentView?.setActionsVisible(isHovered)
            if isHovered {
                self?.scheduleHoverPreview(for: contentView?.window)
            } else {
                self?.cancelHoverPreview(for: contentView?.window)
            }
        }

        let imageView = AspectFillImageView(image: screenshot.image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        configurePreviewEdge(imageView)
        imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let overlayView = NSVisualEffectView()
        overlayView.identifier = NSUserInterfaceItemIdentifier("QuickAccessActionOverlay")
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        FrameHUDChrome.configure(overlayView, surface: .overlay, cornerRadius: 14)
        overlayView.alphaValue = 0

        let ocrFeedback = QuickAccessOCRFeedback()

        let pendingProgressIndicator = NSProgressIndicator()
        pendingProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
        pendingProgressIndicator.style = .spinning
        pendingProgressIndicator.controlSize = .small
        pendingProgressIndicator.isDisplayedWhenStopped = false
        pendingProgressIndicator.isHidden = !isPending
        pendingProgressIndicator.setAccessibilityLabel("Generating screenshot")
        if isPending {
            pendingProgressIndicator.startAnimation(nil)
        }

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 5
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = makeIconButton(
            title: strings.quickAccessClose,
            symbolName: "xmark",
            action: #selector(closeButtonClicked),
            style: .floatingCorner
        )
        closeButton.alphaValue = 0
        let saveButton = makeIconButton(
            title: strings.quickAccessSave,
            symbolName: "square.and.arrow.down",
            action: #selector(saveButtonClicked),
            style: .toolbar
        )
        let copyButton = makeIconButton(
            title: strings.quickAccessCopy,
            symbolName: "doc.on.doc",
            action: #selector(copyButtonClicked),
            style: .toolbar
        )
        let ocrButton = makeIconButton(
            title: strings.quickAccessOCR,
            symbolName: "character.textbox",
            action: #selector(ocrButtonClicked),
            style: .toolbar
        )
        let ocrProgressIndicator = NSProgressIndicator()
        ocrProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
        ocrProgressIndicator.style = .spinning
        ocrProgressIndicator.controlSize = .small
        ocrProgressIndicator.isDisplayedWhenStopped = false
        ocrProgressIndicator.isHidden = true
        ocrProgressIndicator.setAccessibilityLabel(strings.ocrRecognizing)
        let pinButton = makeIconButton(
            title: strings.quickAccessPin,
            symbolName: "pin",
            action: #selector(pinButtonClicked),
            style: .toolbar
        )
        let openExternallyButton = makeIconButton(
            title: strings.quickAccessOpen,
            symbolName: "arrow.up.forward.app",
            action: #selector(openExternallyButtonClicked),
            style: .toolbar
        )

        stackView.addArrangedSubview(copyButton)
        stackView.addArrangedSubview(saveButton)
        for button in [ocrButton, pinButton, openExternallyButton] {
            button.contentTintColor = FrameHUDChrome.secondaryIcon
        }
        stackView.addArrangedSubview(ocrButton)
        stackView.addArrangedSubview(pinButton)
        stackView.addArrangedSubview(openExternallyButton)

        contentView.actionsViews = [closeButton, overlayView]
        contentView.addSubview(imageView)
        contentView.addSubview(overlayView)
        contentView.addSubview(closeButton)
        contentView.addSubview(ocrFeedback)
        contentView.addSubview(pendingProgressIndicator)
        overlayView.addSubview(stackView)
        overlayView.addSubview(ocrProgressIndicator)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            overlayView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -7),
            overlayView.widthAnchor.constraint(equalToConstant: 154),
            overlayView.heightAnchor.constraint(equalToConstant: 28),

            ocrFeedback.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            ocrFeedback.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            ocrFeedback.widthAnchor.constraint(lessThanOrEqualTo: imageView.widthAnchor, constant: -24),

            pendingProgressIndicator.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            pendingProgressIndicator.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),

            stackView.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 7),
            stackView.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -7),
            stackView.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor, constant: -4),

            ocrProgressIndicator.centerXAnchor.constraint(equalTo: ocrButton.centerXAnchor),
            ocrProgressIndicator.centerYAnchor.constraint(equalTo: ocrButton.centerYAnchor),
            ocrProgressIndicator.widthAnchor.constraint(equalToConstant: 14),
            ocrProgressIndicator.heightAnchor.constraint(equalToConstant: 14),

            closeButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -cornerButtonInset),
            closeButton.topAnchor.constraint(equalTo: imageView.topAnchor, constant: cornerButtonInset),
            closeButton.widthAnchor.constraint(equalToConstant: floatingButtonDiameter),
            closeButton.heightAnchor.constraint(equalToConstant: floatingButtonDiameter),
        ])

        return QuickAccessContent(
            view: contentView,
            imageView: imageView,
            ocrButton: ocrButton,
            ocrProgressIndicator: ocrProgressIndicator,
            ocrFeedback: ocrFeedback,
            pendingProgressIndicator: pendingProgressIndicator
        )
    }

    private func makeRecordingContentView(
        for recording: CapturedRecording,
        previewSize: CGSize,
        strings: AppStrings,
        preview: @escaping () -> Bool
    ) -> RecordingQuickAccessContentView {
        let contentView = RecordingQuickAccessContentView()
        contentView.preferredContentSize = previewSize
        contentView.wantsLayer = true
        contentView.onPreviewRequested = preview
        contentView.onHoverChanged = { [weak self, weak contentView] isHovered in
            contentView?.setActionsVisible(isHovered)
            if isHovered {
                self?.scheduleHoverPreview(for: contentView?.window)
            } else {
                self?.cancelHoverPreview(for: contentView?.window)
            }
        }

        let thumbnail = thumbnailProvider.thumbnail(for: recording.fileURL)
        let previewSurface: NSView
        if let thumbnail {
            let imageView = RecordingThumbnailImageView(image: thumbnail)
            imageView.setAccessibilityLabel(strings.videoQuickAccessPreview)
            previewSurface = imageView
            contentView.hasThumbnailForTesting = true
        } else {
            let visualEffectView = NSVisualEffectView()
            visualEffectView.identifier = NSUserInterfaceItemIdentifier("QuickAccessPlaceholderSurface")
            FrameHUDChrome.configure(visualEffectView, surface: .overlay, cornerRadius: 12)
            previewSurface = visualEffectView
        }
        configurePreviewEdge(previewSurface)

        let playImageView = NSImageView(
            image: NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: strings.videoQuickAccessPreview) ?? NSImage()
        )
        playImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .medium)
        playImageView.contentTintColor = FrameHUDChrome.primaryIcon.withAlphaComponent(0.82)

        let duration = DurationBadgeLabel(text: formattedDuration(recording.duration))

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 5
        stackView.addArrangedSubview(
            makeIconButton(
                title: strings.videoQuickAccessDownload,
                symbolName: "square.and.arrow.down",
                action: #selector(downloadRecordingButtonClicked),
                style: .toolbar
            )
        )
        stackView.addArrangedSubview(
            makeIconButton(
                title: strings.videoQuickAccessCopy,
                symbolName: "doc.on.doc",
                action: #selector(copyRecordingButtonClicked),
                style: .toolbar
            )
        )
        let openButton = makeIconButton(
            title: strings.quickAccessOpen,
            symbolName: "arrow.up.forward.app",
            action: #selector(openExternallyButtonClicked),
            style: .toolbar
        )
        stackView.addArrangedSubview(openButton)

        let overlayView = NSVisualEffectView()
        overlayView.identifier = NSUserInterfaceItemIdentifier("QuickAccessActionOverlay")
        FrameHUDChrome.configure(overlayView, surface: .overlay, cornerRadius: 14)
        overlayView.alphaValue = 0

        let closeButton = makeIconButton(
            title: strings.quickAccessClose,
            symbolName: "xmark",
            action: #selector(closeButtonClicked),
            style: .floatingCorner
        )
        closeButton.alphaValue = 0

        contentView.actionsViews = [closeButton, overlayView]
        contentView.addSubview(previewSurface)
        contentView.addSubview(overlayView)
        contentView.addSubview(closeButton)
        previewSurface.addSubview(playImageView)
        previewSurface.addSubview(duration)
        overlayView.addSubview(stackView)
        contentView.installLayoutViews(
            previewSurface: previewSurface,
            playImageView: playImageView,
            durationLabel: duration,
            overlayView: overlayView,
            actionsView: stackView,
            closeButton: closeButton,
            floatingButtonDiameter: floatingButtonDiameter
        )

        return contentView
    }

    private enum IconButtonStyle {
        case floatingCorner
        case toolbar
    }

    private func makeIconButton(
        title: String,
        symbolName: String,
        action: Selector,
        style: IconButtonStyle
    ) -> NSButton {
        let button = PointingHandButton(
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage(),
            target: self,
            action: action
        )
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.toolTip = title
        let symbolPointSize = quickAccessSymbolPointSize(symbolName: symbolName, style: style)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
        button.contentTintColor = FrameHUDChrome.primaryIcon
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(title)
        button.identifier = NSUserInterfaceItemIdentifier(symbolName)
        if style == .floatingCorner {
            button.usesManualIconRendering = true
            button.drawsCenteredXMark = true
            button.ignoresHighlight = true
            button.controlSize = .mini
            button.contentTintColor = FrameHUDChrome.secondaryIcon
            button.wantsLayer = true
            FrameHUDChrome.configureAccessoryChip(
                button.layer,
                cornerRadius: floatingButtonRadius,
                masksToBounds: false
            )
            button.layer?.shadowColor = NSColor.black.cgColor
            button.layer?.shadowOpacity = 0.14
            button.layer?.shadowRadius = 3
            button.layer?.shadowOffset = CGSize(width: 0, height: -1)
        }
        return button
    }

    private func quickAccessSymbolPointSize(symbolName: String, style: IconButtonStyle) -> CGFloat {
        switch style {
        case .floatingCorner:
            9.5
        case .toolbar:
            switch symbolName {
            case "square.and.arrow.down", "character.textbox":
                12.5
            default:
                11.5
            }
        }
    }

    private let floatingButtonDiameter: CGFloat = 20
    private let cornerButtonInset: CGFloat = 6
    private var floatingButtonRadius: CGFloat {
        floatingButtonDiameter / 2
    }
    private let previewPadding: CGFloat = 18
    private let previewSpacing: CGFloat = 12

    private var previewSize: CGSize {
        CapturePreviewMetrics.quickAccessCardSize
    }

    nonisolated static func recordingPreviewSize(
        forSourceSize sourceSize: CGSize,
        maximumSize maxSize: CGSize = CGSize(width: CapturePreviewMetrics.previewWidth, height: 160)
    ) -> CGSize {
        CapturePreviewMetrics.quickAccessCardSize
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func scheduleHoverPreviewForTesting(window: NSWindow) {
        scheduleHoverPreview(for: window)
    }

    func closeHoverPreviewForTesting() {
        closeHoverPreview()
    }

    func hoverPreviewFrameForTesting() -> CGRect? {
        hoverPreviewController.frameForTesting()
    }

    func hoverPreviewPlayerIsMutedForTesting() -> Bool? {
        hoverPreviewController.playerIsMutedForTesting()
    }

    func hoverPreviewBubbleMetricsForTesting() -> QuickAccessHoverPreviewMetricsForTesting? {
        hoverPreviewController.bubbleMetricsForTesting()
    }

    func screenshotPreviewPNGDataForTesting(for screenshot: CapturedScreenshot) -> Data? {
        previewItems.first { $0.screenshotID == screenshot.id }?
            .screenshotImageView?
            .pngDataForTesting()
    }

    func recordingCountForTesting() -> Int {
        previewItems.filter { $0.recordingID != nil }.count
    }

    func screenshotIsPendingForTesting(id: UUID) -> Bool {
        guard let indicator = previewItems.first(where: { $0.screenshotID == id })?.pendingProgressIndicator else {
            return false
        }
        return !indicator.isHidden
    }

    func recordingForTesting(id: UUID) -> CapturedRecording? {
        previewItems.compactMap { item -> CapturedRecording? in
            guard item.recordingID == id,
                  case let .recording(recording) = item.hoverPreviewMedia else {
                return nil
            }

            return recording
        }.first
    }

    private func scheduleHoverPreview(for window: NSWindow?) {
        guard let item = previewItem(for: window) else {
            return
        }

        item.hoverPreviewWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak item] in
            guard let self,
                  let item,
                  !item.isTemporarilyHidden,
                  self.previewItems.contains(where: { $0 === item }) else {
                return
            }

            self.hoverPreviewController.show(media: item.hoverPreviewMedia, near: item.panel.frame)
            self.hoverPreviewOwner = item
        }
        item.hoverPreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverPreviewDelay, execute: workItem)
    }

    private func cancelHoverPreview(for window: NSWindow?) {
        guard let item = previewItem(for: window) else {
            closeHoverPreview()
            return
        }

        item.hoverPreviewWorkItem?.cancel()
        item.hoverPreviewWorkItem = nil
        if hoverPreviewOwner === item {
            closeHoverPreview()
        }
    }

    private func closeHoverPreview() {
        hoverPreviewOwner = nil
        hoverPreviewController.close()
    }

    private func observeScreenConfiguration() {
        guard screenConfigurationObserver == nil else { return }

        screenConfigurationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.layoutPreviewStack()
            }
        }
    }

    private func stopObservingScreenConfigurationIfNeeded() {
        guard previewItems.isEmpty else { return }
        if let screenConfigurationObserver {
            NotificationCenter.default.removeObserver(screenConfigurationObserver)
            self.screenConfigurationObserver = nil
        }
        currentPreviewScreenID = nil
    }

    private func layoutPreviewStack(preferredAnchor: CGRect? = nil) {
        guard !previewItems.isEmpty else { return }

        let pinnedScreen = currentPreviewScreenID.flatMap { id in
            NSScreen.screens.first { displayID(for: $0) == id }
        }
        let targetScreen = pinnedScreen ?? preferredScreen(for: preferredAnchor)
        let targetScreenID = displayID(for: targetScreen)
        currentPreviewScreenID = targetScreenID
        let visibleFrame = targetScreen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero
        var currentY = visibleFrame.minY + previewPadding
        for item in previewItems {
            let panelSize = item.panel.frame.size
            let unclampedOrigin = CGPoint(
                x: visibleFrame.minX + previewPadding,
                y: currentY
            )
            let origin = CGPoint(
                x: min(
                    max(unclampedOrigin.x, visibleFrame.minX + previewPadding),
                    visibleFrame.maxX - panelSize.width - previewPadding
                ),
                y: min(
                    max(unclampedOrigin.y, visibleFrame.minY + previewPadding),
                    visibleFrame.maxY - panelSize.height - previewPadding
                )
            )

            item.panel.setFrameOrigin(origin)
            currentY = origin.y + panelSize.height + previewSpacing
        }
    }

    private func preferredScreen(for preferredAnchor: CGRect?) -> NSScreen? {
        let fallbackScreen = NSScreen.main ?? NSScreen.screens.first
        guard let preferredAnchor else { return fallbackScreen }
        let bestMatch = NSScreen.screens.max {
            intersectionArea($0.frame, preferredAnchor) < intersectionArea($1.frame, preferredAnchor)
        }
        guard let bestMatch, intersectionArea(bestMatch.frame, preferredAnchor) > 0 else {
            return fallbackScreen
        }
        return bestMatch
    }

    private func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen,
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(displayNumber.uint32Value)
    }

    private func intersectionArea(_ firstRect: CGRect, _ secondRect: CGRect) -> CGFloat {
        let intersection = firstRect.intersection(secondRect)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    @objc private func copyButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        if item.copy?() == true {
            closePreview(item, notify: false)
        }
    }

    @objc private func ocrButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        _ = item.recognizeText?()
    }

    @objc private func saveButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        if item.save?() == true {
            closePreview(item, notify: false)
        }
    }

    @objc private func openExternallyButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        _ = item.openExternally?()
    }

    @objc private func pinButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        if item.pin?() == true {
            closePreview(item, notify: false)
        }
    }

    @objc private func downloadRecordingButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        if item.downloadRecording?() == true {
            closePreview(item, notify: false)
        }
    }

    @objc private func copyRecordingButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        if item.copyRecording?() == true {
            closePreview(item, notify: false)
        }
    }

    @objc private func closeButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        closePreview(item, notify: true)
    }

    private func previewItem(for window: NSWindow?) -> QuickAccessPreviewItem? {
        guard let window else {
            return nil
        }

        return previewItems.first { $0.panel === window }
    }

    private func closePreview(_ item: QuickAccessPreviewItem, notify: Bool) {
        item.statusResetWorkItem?.cancel()
        item.hoverPreviewWorkItem?.cancel()
        if hoverPreviewOwner === item {
            closeHoverPreview()
        }
        item.panel.close()
        previewItems.removeAll { $0 === item }
        stopDismissalTimerIfNeeded()
        layoutPreviewStack()
        stopObservingScreenConfigurationIfNeeded()
        if notify {
            item.close()
        }
    }

    private func closeAllPreviews(notify: Bool) {
        let closingItems = previewItems
        for item in closingItems {
            item.statusResetWorkItem?.cancel()
            item.hoverPreviewWorkItem?.cancel()
            item.panel.close()
            if notify {
                item.close()
            }
        }
        previewItems.removeAll()
        stopDismissalTimerIfNeeded()
        closeHoverPreview()
        stopObservingScreenConfigurationIfNeeded()
    }

    private func closeOrphanPreviewPanels() {
        for window in NSApp.windows where window.title == Self.previewWindowTitle {
            guard !previewItems.contains(where: { $0.panel === window }) else {
                continue
            }

            window.orderOut(nil)
            window.close()
        }
    }
}

struct QuickAccessHoverPreviewMetricsForTesting {
    let panelFrame: CGRect
    let mediaFrame: CGRect
}

enum QuickAccessOCRStatus: Equatable {
    case idle(accessibilityLabel: String)
    case recognizing(String)
    case message(String, resetAfter: TimeInterval)
}

private final class QuickAccessOCRFeedback: NSView {
    private let label = NSTextField(labelWithString: "")

    var message: String? {
        didSet {
            label.stringValue = message ?? ""
            isHidden = message == nil
        }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.76).cgColor
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityLabel("OCR Status")
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct QuickAccessContent {
    let view: ScreenshotPreviewView
    let imageView: AspectFillImageView
    let ocrButton: NSButton
    let ocrProgressIndicator: NSProgressIndicator
    let ocrFeedback: QuickAccessOCRFeedback
    let pendingProgressIndicator: NSProgressIndicator
}

private enum QuickAccessHoverPreviewMedia {
    case image(NSImage)
    case recording(CapturedRecording)
}

private final class QuickAccessPreviewItem {
    let screenshotID: UUID?
    let recordingID: UUID?
    let panel: NSPanel
    let ocrButton: NSButton?
    let ocrProgressIndicator: NSProgressIndicator?
    let ocrFeedback: QuickAccessOCRFeedback?
    weak var screenshotImageView: AspectFillImageView?
    weak var screenshotContentView: ScreenshotPreviewView?
    weak var pendingProgressIndicator: NSProgressIndicator?
    weak var recordingContentView: RecordingQuickAccessContentView?
    let copy: (() -> Bool)?
    let save: (() -> Bool)?
    let recognizeText: (() -> Bool)?
    let openExternally: (() -> Bool)?
    let pin: (() -> Bool)?
    let downloadRecording: (() -> Bool)?
    let copyRecording: (() -> Bool)?
    let previewRecording: (() -> Bool)?
    var hoverPreviewMedia: QuickAccessHoverPreviewMedia
    let close: () -> Void
    let isInUse: () -> Bool
    var dismissalRemaining: TimeInterval?
    var dismissalUpdatedAt: TimeInterval = 0
    var isHoldingPointer = false
    var isTemporarilyHidden = false
    var statusResetWorkItem: DispatchWorkItem?
    var hoverPreviewWorkItem: DispatchWorkItem?

    init(
        screenshotID: UUID?,
        recordingID: UUID?,
        panel: NSPanel,
        ocrButton: NSButton?,
        ocrProgressIndicator: NSProgressIndicator?,
        ocrFeedback: QuickAccessOCRFeedback?,
        screenshotImageView: AspectFillImageView?,
        screenshotContentView: ScreenshotPreviewView?,
        pendingProgressIndicator: NSProgressIndicator?,
        recordingContentView: RecordingQuickAccessContentView?,
        copy: (() -> Bool)?,
        save: (() -> Bool)?,
        recognizeText: (() -> Bool)?,
        openExternally: (() -> Bool)?,
        pin: (() -> Bool)?,
        downloadRecording: (() -> Bool)?,
        copyRecording: (() -> Bool)?,
        previewRecording: (() -> Bool)?,
        hoverPreviewMedia: QuickAccessHoverPreviewMedia,
        isInUse: @escaping () -> Bool = { false },
        close: @escaping () -> Void
    ) {
        self.screenshotID = screenshotID
        self.recordingID = recordingID
        self.panel = panel
        self.ocrButton = ocrButton
        self.ocrProgressIndicator = ocrProgressIndicator
        self.ocrFeedback = ocrFeedback
        self.screenshotImageView = screenshotImageView
        self.screenshotContentView = screenshotContentView
        self.pendingProgressIndicator = pendingProgressIndicator
        self.recordingContentView = recordingContentView
        self.copy = copy
        self.save = save
        self.recognizeText = recognizeText
        self.openExternally = openExternally
        self.pin = pin
        self.downloadRecording = downloadRecording
        self.copyRecording = copyRecording
        self.previewRecording = previewRecording
        self.hoverPreviewMedia = hoverPreviewMedia
        self.isInUse = isInUse
        self.close = close
    }
}

@MainActor
private final class QuickAccessHoverPreviewController {
    private var panel: NSPanel?
    private var player: AVPlayer?
    private var mediaFrame: CGRect?
    private let maximumMediaSize = CGSize(width: 640, height: 420)
    private let contentInset: CGFloat = 12
    private let spacing: CGFloat = 12

    func show(media: QuickAccessHoverPreviewMedia, near anchorFrame: CGRect) {
        close()

        let mediaSize = aspectFitSize(
            sourceSize: sourceSize(for: media),
            maximumSize: maximumMediaSize
        )
        let panelSize = CGSize(
            width: contentInset * 2 + mediaSize.width,
            height: contentInset * 2 + mediaSize.height
        )
        let mediaFrame = CGRect(
            x: contentInset,
            y: contentInset,
            width: mediaSize.width,
            height: mediaSize.height
        )
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = QuickAccessPanelController.hoverPreviewWindowTitle
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.ignoresMouseEvents = false

        let rootView = NSView(frame: CGRect(origin: .zero, size: panelSize))
        rootView.wantsLayer = true
        rootView.autoresizingMask = [.width, .height]

        let container = NSVisualEffectView(frame: CGRect(
            x: 0,
            y: 0,
            width: panelSize.width,
            height: panelSize.height
        ))
        container.identifier = NSUserInterfaceItemIdentifier("QuickAccessHoverPreviewChrome")
        FrameHUDChrome.configure(container, surface: .overlay, cornerRadius: 12)

        let mediaView = makeMediaView(for: media)
        mediaView.frame = mediaFrame
        mediaView.autoresizingMask = []
        rootView.addSubview(container)
        rootView.addSubview(mediaView)
        panel.contentView = rootView
        panel.setFrameOrigin(origin(near: anchorFrame, panelSize: panelSize))
        panel.orderFrontRegardless()

        self.panel = panel
        self.mediaFrame = mediaFrame
    }

    func close() {
        player?.pause()
        player = nil
        mediaFrame = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    func frameForTesting() -> CGRect? {
        panel?.frame
    }

    func playerIsMutedForTesting() -> Bool? {
        player?.isMuted
    }

    func bubbleMetricsForTesting() -> QuickAccessHoverPreviewMetricsForTesting? {
        guard let panel,
              let mediaFrame else {
            return nil
        }

        return QuickAccessHoverPreviewMetricsForTesting(
            panelFrame: panel.frame,
            mediaFrame: mediaFrame
        )
    }

    private func makeMediaView(for media: QuickAccessHoverPreviewMedia) -> NSView {
        switch media {
        case let .image(image):
            let imageView = AspectFitImageView(image: image)
            imageView.wantsLayer = true
            imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            return imageView
        case let .recording(recording):
            switch recording.format {
            case .gif:
                let imageView = NSImageView()
                imageView.image = NSImage(contentsOf: recording.fileURL)
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.animates = true
                imageView.wantsLayer = true
                imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                return imageView
            case .mp4:
                let player = AVPlayer(url: recording.fileURL)
                player.isMuted = true
                player.actionAtItemEnd = .none
                let playerView = AVPlayerView()
                playerView.controlsStyle = .none
                playerView.videoGravity = .resizeAspect
                playerView.player = player
                self.player = player
                player.play()
                return playerView
            }
        }
    }

    private func sourceSize(for media: QuickAccessHoverPreviewMedia) -> CGSize {
        switch media {
        case let .image(image):
            return image.size == .zero ? maximumMediaSize : image.size
        case let .recording(recording):
            if recording.pixelSize.width > 0, recording.pixelSize.height > 0 {
                return recording.pixelSize
            }

            return recording.rect.size == .zero ? maximumMediaSize : recording.rect.size
        }
    }

    private func aspectFitSize(sourceSize: CGSize, maximumSize: CGSize) -> CGSize {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              maximumSize.width > 0,
              maximumSize.height > 0 else {
            return maximumSize
        }

        let scale = min(maximumSize.width / sourceSize.width, maximumSize.height / sourceSize.height)
        return CGSize(width: floor(sourceSize.width * scale), height: floor(sourceSize.height * scale))
    }

    private func origin(near anchorFrame: CGRect, panelSize: CGSize) -> CGPoint {
        let fallbackVisibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? anchorFrame
        let targetScreen = NSScreen.screens.first { $0.visibleFrame.intersects(anchorFrame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = targetScreen?.visibleFrame ?? fallbackVisibleFrame
        let preferredX = anchorFrame.maxX + spacing
        let fallbackX = anchorFrame.minX - panelSize.width - spacing
        let x = preferredX + panelSize.width <= visibleFrame.maxX - spacing ? preferredX : fallbackX
        let centeredY = anchorFrame.midY - panelSize.height / 2
        let y = min(max(centeredY, visibleFrame.minY + spacing), visibleFrame.maxY - panelSize.height - spacing)
        return CGPoint(x: x, y: y)
    }
}

private class ScreenshotPreviewView: NSView {
    var actionsViews: [NSView] = []
    var onHoverChanged: ((Bool) -> Void)?
    var onPointerDown: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var pendingHideActionsWorkItem: DispatchWorkItem?
    private var areActionsVisible = false
    private var areActionsEnabled = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        guard areActionsEnabled else {
            return
        }
        showActions()
        onHoverChanged?(true)
        updateCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        guard areActionsEnabled else {
            return
        }
        scheduleActionsHide()
    }

    override func mouseDown(with event: NSEvent) {
        onPointerDown?()
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: event)
        super.mouseMoved(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(for: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else {
            return nil
        }

        guard areActionsEnabled else {
            return self
        }

        for actionsView in actionsViews.reversed() {
            let actionPoint = actionsView.convert(point, from: self)
            guard actionsView.bounds.contains(actionPoint) else {
                continue
            }

            if let hitView = hitActionView(actionsView, at: actionPoint) {
                return hitView
            }

            return actionsView
        }

        return self
    }

    func setActionsVisible(_ isVisible: Bool) {
        guard areActionsVisible != isVisible else {
            return
        }

        areActionsVisible = isVisible
        window?.invalidateCursorRects(for: self)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isVisible ? 0.16 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for actionsView in actionsViews {
                actionsView.layer?.removeAnimation(forKey: "opacity")
                actionsView.animator().alphaValue = isVisible ? 1 : 0
            }
        }
    }

    func setActionsEnabled(_ isEnabled: Bool) {
        areActionsEnabled = isEnabled
        pendingHideActionsWorkItem?.cancel()
        pendingHideActionsWorkItem = nil
        if !isEnabled {
            onHoverChanged?(false)
            setActionsVisible(false)
            NSCursor.arrow.set()
        }
    }

    private func showActions() {
        pendingHideActionsWorkItem?.cancel()
        pendingHideActionsWorkItem = nil
        setActionsVisible(true)
    }

    private func scheduleActionsHide() {
        pendingHideActionsWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isMouseInsideBounds else {
                return
            }

            self.setActionsVisible(false)
            self.onHoverChanged?(false)
            NSCursor.arrow.set()
        }
        pendingHideActionsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private var isMouseInsideBounds: Bool {
        guard let window else {
            return false
        }

        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func isPointInActions(_ point: NSPoint) -> Bool {
        guard areActionsVisible else {
            return false
        }

        return actionsViews.contains { actionsView in
            actionsView.frame.contains(point)
        }
    }

    private func hitActionView(_ view: NSView, at point: NSPoint) -> NSView? {
        guard !view.isHidden,
              view.bounds.contains(point) else {
            return nil
        }

        if view is NSButton {
            return view
        }

        for subview in view.subviews.reversed() {
            let subviewPoint = subview.convert(point, from: view)
            if let hitView = hitActionView(subview, at: subviewPoint) {
                return hitView
            }
        }

        return view
    }

    private func updateCursor(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isPointInActions(point) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

final class DurationBadgeLabel: NSTextField {
    static let badgeSize = CGSize(width: 44, height: 18)
    static let fontSize: CGFloat = 11

    var textDrawingRectForTesting: CGRect {
        textDrawingRect()
    }

    init(text: String) {
        super.init(frame: CGRect(origin: .zero, size: Self.badgeSize))
        stringValue = text
        font = .monospacedDigitSystemFont(ofSize: Self.fontSize, weight: .semibold)
        textColor = FrameHUDChrome.primaryIcon
        alignment = .center
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        backgroundColor = .clear
        focusRingType = .none
        wantsLayer = true
        FrameHUDChrome.configureAccessoryChip(layer, cornerRadius: Self.badgeSize.height / 2)
        setAccessibilityLabel(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        attributedBadgeText.draw(with: textDrawingRect(), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private var attributedBadgeText: NSAttributedString {
        NSAttributedString(
            string: stringValue,
            attributes: [
                .font: font ?? NSFont.monospacedDigitSystemFont(ofSize: Self.fontSize, weight: .semibold),
                .foregroundColor: textColor ?? NSColor.labelColor,
            ]
        )
    }

    private func textDrawingRect() -> CGRect {
        let textSize = attributedBadgeText.size()
        let width = min(ceil(textSize.width), bounds.width)
        let height = min(ceil(textSize.height), bounds.height)
        return CGRect(
            x: floor((bounds.width - width) / 2),
            y: floor((bounds.height - height) / 2),
            width: width,
            height: height
        )
    }
}

private final class RecordingQuickAccessContentView: ScreenshotPreviewView {
    var hasThumbnailForTesting = false
    var onPreviewRequested: (() -> Bool)?
    var previewSurfaceFrameForTesting: CGRect? {
        previewSurface?.frame
    }

    private weak var previewSurface: NSView?
    private weak var playImageView: NSImageView?
    private weak var durationLabel: NSTextField?
    private weak var overlayView: NSView?
    private weak var actionsView: NSView?
    private weak var closeButton: NSButton?
    private var floatingButtonDiameter: CGFloat = 20
    var preferredContentSize: CGSize = .zero {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    func updateDuration(_ duration: TimeInterval) {
        let seconds = max(0, Int(duration.rounded(.down)))
        let text = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        durationLabel?.stringValue = text
        durationLabel?.setAccessibilityLabel(text)
        durationLabel?.needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        preferredContentSize == .zero ? super.intrinsicContentSize : preferredContentSize
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point),
              isPointInPlayOverlay(point),
              !isPointInActionControls(point) else {
            super.mouseUp(with: event)
            return
        }

        _ = onPreviewRequested?()
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point),
           isPointInPlayOverlay(point),
           !isPointInActionControls(point) {
            NSCursor.pointingHand.set()
            return
        }

        super.cursorUpdate(with: event)
    }

    override func setFrameSize(_ newSize: NSSize) {
        guard preferredContentSize != .zero else {
            super.setFrameSize(newSize)
            return
        }

        let clampedSize = CGSize(
            width: max(newSize.width, preferredContentSize.width),
            height: max(newSize.height, preferredContentSize.height)
        )
        super.setFrameSize(clampedSize)
    }

    func installLayoutViews(
        previewSurface: NSView,
        playImageView: NSImageView,
        durationLabel: NSTextField,
        overlayView: NSView,
        actionsView: NSView,
        closeButton: NSButton,
        floatingButtonDiameter: CGFloat
    ) {
        self.previewSurface = previewSurface
        self.playImageView = playImageView
        self.durationLabel = durationLabel
        self.overlayView = overlayView
        self.actionsView = actionsView
        self.closeButton = closeButton
        self.floatingButtonDiameter = floatingButtonDiameter
        needsLayout = true
    }

    private func isPointInActionControls(_ point: NSPoint) -> Bool {
        [overlayView, closeButton].contains { view in
            view?.frame.contains(point) == true
        }
    }

    private func isPointInPlayOverlay(_ point: NSPoint) -> Bool {
        guard let playImageView else {
            return false
        }

        return playImageView.frame.insetBy(dx: -8, dy: -8).contains(point)
    }

    override func layout() {
        super.layout()

        previewSurface?.frame = bounds
        playImageView?.frame = CGRect(
            x: floor((bounds.width - 34) / 2),
            y: floor((bounds.height - 34) / 2),
            width: 34,
            height: 34
        )
        let durationSize = DurationBadgeLabel.badgeSize
        durationLabel?.frame = CGRect(
            x: bounds.maxX - durationSize.width - 9,
            y: bounds.minY + 9,
            width: durationSize.width,
            height: durationSize.height
        )
        let overlayWidth = min(96, max(76, bounds.width - 14))
        overlayView?.frame = CGRect(
            x: floor((bounds.width - overlayWidth) / 2),
            y: bounds.minY + 7,
            width: overlayWidth,
            height: 28
        )
        if let overlayView {
            actionsView?.frame = overlayView.bounds.insetBy(dx: 7, dy: 4)
        }
        closeButton?.frame = CGRect(
            x: bounds.maxX - floatingButtonDiameter - 6,
            y: bounds.maxY - floatingButtonDiameter - 6,
            width: floatingButtonDiameter,
            height: floatingButtonDiameter
        )
    }
}

private final class PointingHandButton: NSButton {
    private let manualIconLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    private var manualIconImage: NSImage?
    var drawsCenteredXMark = false {
        didSet {
            updateManualIcon()
        }
    }
    var ignoresHighlight = false {
        didSet {
            configureHighlightBehavior()
        }
    }
    var usesManualIconRendering = false {
        didSet {
            configureManualIconRendering()
        }
    }

    override var state: NSControl.StateValue {
        get {
            super.state
        }
        set {
            super.state = ignoresHighlight ? .off : newValue
        }
    }

    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override var image: NSImage? {
        get {
            usesManualIconRendering ? manualIconImage : super.image
        }
        set {
            if usesManualIconRendering {
                manualIconImage = newValue
                updateManualIcon()
            } else {
                super.image = newValue
            }
        }
    }

    override var contentTintColor: NSColor? {
        didSet {
            updateManualIcon()
        }
    }

    override func highlight(_ flag: Bool) {
        guard !ignoresHighlight else {
            clearHighlightState()
            return
        }

        super.highlight(flag)
    }

    override func draw(_ dirtyRect: NSRect) {
        if ignoresHighlight {
            clearHighlightState()
        }

        super.draw(dirtyRect)
    }

    override func layout() {
        super.layout()

        guard usesManualIconRendering else {
            return
        }

        let iconSize = min(bounds.width, bounds.height, 9.5)
        manualIconLayer.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        manualIconLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        updateManualIcon()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
    }

    private func configureHighlightBehavior() {
        guard ignoresHighlight else {
            return
        }

        if let cell = cell as? NSButtonCell {
            cell.highlightsBy = []
            cell.showsStateBy = []
        }
        clearHighlightState()
    }

    private func configureManualIconRendering() {
        guard usesManualIconRendering else {
            manualIconLayer.removeFromSuperlayer()
            if super.image == nil {
                super.image = manualIconImage
            }
            return
        }

        manualIconImage = super.image
        super.image = nil
        wantsLayer = true
        layer?.addSublayer(manualIconLayer)
        manualIconLayer.contentsGravity = .resizeAspect
        manualIconLayer.lineCap = .round
        manualIconLayer.lineJoin = .round
        updateManualIcon()
        needsLayout = true
    }

    private func updateManualIcon() {
        guard usesManualIconRendering else {
            return
        }

        if drawsCenteredXMark {
            manualIconLayer.contents = nil
            let inset = manualIconLayer.bounds.width * 0.18
            let path = CGMutablePath()
            path.move(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: manualIconLayer.bounds.maxX - inset, y: manualIconLayer.bounds.maxY - inset))
            path.move(to: CGPoint(x: manualIconLayer.bounds.maxX - inset, y: inset))
            path.addLine(to: CGPoint(x: inset, y: manualIconLayer.bounds.maxY - inset))
            manualIconLayer.path = path
            manualIconLayer.fillColor = nil
            manualIconLayer.strokeColor = (contentTintColor ?? .labelColor).cgColor
            manualIconLayer.lineWidth = 1.7
        } else {
            manualIconLayer.path = nil
            manualIconLayer.strokeColor = nil
            manualIconLayer.contents = manualIconImage?.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: [.ctm: NSAffineTransform()]
            )
        }
        manualIconLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        manualIconLayer.compositingFilter = nil
    }

    private func clearHighlightState() {
        cell?.isHighlighted = false
        super.state = .off
    }
}

private final class AspectFillImageView: NSView {
    private var image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setImage(_ image: NSImage) {
        self.image = image
        needsDisplay = true
    }

    func pngDataForTesting() -> Data? {
        image.pngData()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return
        }

        let drawRect = CapturePreviewMetrics.aspectFillDrawRect(
            imageSize: image.size,
            in: bounds
        )

        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

private final class AspectFitImageView: NSView {
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return
        }

        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

@MainActor
protocol RecordingThumbnailDrawableForTesting: AnyObject {
    var lastDrawRectForTesting: CGRect { get }
}

private final class RecordingThumbnailImageView: NSView, RecordingThumbnailDrawableForTesting {
    private let image: NSImage

    var lastDrawRectForTesting: CGRect {
        drawRectForCurrentBounds()
    }

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let sourceSize = image.size == .zero ? bounds.size : image.size
        let drawRect = drawRectForCurrentBounds()
        image.draw(
            in: drawRect,
            from: CGRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )
    }

    private func drawRectForCurrentBounds() -> CGRect {
        let sourceSize = image.size == .zero ? bounds.size : image.size
        return CapturePreviewMetrics.aspectFillDrawRect(
            imageSize: sourceSize,
            in: bounds
        )
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
