import AppKit
import FrameCore

@MainActor
final class ImageAnnotationCanvasView: NSView, NSTextViewDelegate, ImageWorkspaceZoomableImageSurfaceForTesting {
    private var image: NSImage
    private var baseScreenshot: CapturedScreenshot?
    private var document: ImageAnnotationDocument
    private let onDocumentChange: (ImageAnnotationDocument) -> Void
    private let imageZoom: ImageWorkspaceImageZoom
    private var interaction: AnnotationInteraction?
    private var activeTextEditor: ImageAnnotationTextEditorView?
    private var activeTextElementID: UUID?
    private var activeTextOrigin: CGPoint?
    private var activeTextSwapsAxes = false
    private var newTextDragOrigin: CGPoint?
    private var activeTextDidBeginMutation = false
    private var textEditBaseline: ImageAnnotationDocument?
    private var displayedImagePNG: Data?
    private var isCropping = false
    private var cropStart: CGPoint?
    private var cropMoveOffset: CGPoint?
    private var cropRatio: CGFloat?
    private var stamp: ImageWorkspaceStamp?
    private var spacePanPoint: CGPoint?
    private var isSpaceDown = false
    private(set) var cropBounds: CGRect?
    var onCropChanged: (() -> Void)?
    var onCropCommit: (() -> Void)?
    var onImageChanged: (() -> Void)?
    var onCopyOutput: (() -> Void)?
    var onCanvasResize: (() -> Void)?
    var onDropImage: ((CapturedScreenshot) -> Void)?

    private var mosaicDrawingSource: ImageMosaicDrawingSource?
    var menuProvider: (() -> NSMenu)?
    var onToolContextRequest: ((ImageAnnotationCanvasToolContext) -> Void)?
    var onEditingOptionsChange: (() -> Void)?

    init(
        image: NSImage,
        document: ImageAnnotationDocument,
        imageZoom: ImageWorkspaceImageZoom = ImageWorkspaceImageZoom(),
        onDocumentChange: @escaping (ImageAnnotationDocument) -> Void = { _ in }
    ) {
        self.image = image
        self.document = document
        self.imageZoom = imageZoom
        self.onDocumentChange = onDocumentChange
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var documentForTesting: ImageAnnotationDocument {
        document
    }

    var isEditingTextForTesting: Bool {
        activeTextEditor != nil
    }

    var activeTextEditorFontSizeForTesting: CGFloat? {
        activeTextEditor?.font?.pointSize
    }

    var currentScreenshotForTesting: CapturedScreenshot {
        baseScreenshot ?? CapturedScreenshot(
            pngData: image.pngData() ?? Data(),
            image: image,
            rect: CGRect(origin: .zero, size: image.size)
        )
    }

    var lastDrawRectForTesting: CGRect {
        imageDrawRect
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isCropping ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard !isCropping, let onDropImage else { return false }
        let pasteboard = sender.draggingPasteboard
        if let url = NSURL(from: pasteboard) as URL?, url.isFileURL,
           let data = try? Data(contentsOf: url),
           let screenshot = try? ImageWorkspaceRaster.screenshot(data: data) {
            onDropImage(screenshot)
            return true
        }
        if let screenshot = try? ImageWorkspaceRaster.pasteboardImage(pasteboard) {
            onDropImage(screenshot)
            return true
        }
        return false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?() ?? super.menu(for: event)
    }

    @objc func copy(_ sender: Any?) {
        onCopyOutput?()
    }

    func hasEditableObject(at viewPoint: CGPoint) -> Bool {
        let drawRect = imageDrawRect
        guard drawRect.contains(viewPoint), drawRect.width > 0, drawRect.height > 0 else { return false }
        let point = CGPoint(x: (viewPoint.x - drawRect.minX) * image.size.width / drawRect.width,
                            y: (viewPoint.y - drawRect.minY) * image.size.height / drawRect.height)
        if let selectedElement {
            if isLine(selectedElement), selectedElement.points.contains(where: { handleRect(center: $0).contains(point) }) {
                return true
            }
            if !isLine(selectedElement), selectedElement.bounds.contains(point) { return true }
        }
        return document.topmostElementID(at: point, tolerance: 6 / max(0.1, imageDisplayScale)) != nil
    }

    func setDocument(_ document: ImageAnnotationDocument) {
        self.document = document
        needsDisplay = true
        notifyDocumentChanged()
    }

    func setBaseScreenshot(_ screenshot: CapturedScreenshot) {
        baseScreenshot = screenshot
        image = screenshot.image
        mosaicDrawingSource = nil
        needsDisplay = true
    }

    func selectTool(_ tool: ImageAnnotationTool) {
        stamp = nil
        if isCropping { cancelCrop() }
        finishTextEditing()
        document.selectTool(tool)
        if tool != .select, let selectedElement,
           !tool.acceptsEditing(kind: selectedElement.kind) {
            document.selectElement(id: nil)
        }
        needsDisplay = true
        notifyDocumentChanged()
    }

    func finishTextEditing() {
        if let activeTextEditor { commitActiveText(activeTextEditor.string) }
    }

    var currentImage: NSImage { image }

    var selectedStyle: ImageAnnotationStyle {
        selectedElement?.style ?? document.editingOptions.style
    }

    var currentSnapshotImage: CapturedScreenshot {
        if let baseScreenshot, let data = document.editedImagePNG {
            return CapturedScreenshot(id: baseScreenshot.id, pngData: data, image: image,
                                      rect: CGRect(origin: baseScreenshot.rect.origin, size: image.size))
        }
        return currentScreenshotForTesting
    }

    func applyRasterEdit(_ operation: ImageWorkspaceRasterOperation) throws {
        finishTextEditing()
        let result = try ImageWorkspaceRaster.apply(operation, to: currentSnapshotImage)
        document.applyImageEdit(result.screenshot.pngData, size: result.screenshot.image.size, transform: result.annotationTransform, styleScale: result.styleScale)
        image = result.screenshot.image
        displayedImagePNG = result.screenshot.pngData
        mosaicDrawingSource = nil
        notifyDocumentChanged()
        onImageChanged?()
        needsDisplay = true
    }

    func addImage(_ screenshot: CapturedScreenshot) {
        finishTextEditing()
        let scale = min(1, image.size.width * 0.65 / screenshot.image.size.width,
                        image.size.height * 0.65 / screenshot.image.size.height)
        let width = screenshot.image.size.width * scale
        let height = screenshot.image.size.height * scale
        addElement(kind: .image(screenshot.pngData), bounds: CGRect(
            x: (image.size.width - width) / 2, y: (image.size.height - height) / 2, width: width, height: height
        ))
        needsDisplay = true
    }

    func useStamp(_ stamp: ImageWorkspaceStamp) {
        finishTextEditing()
        self.stamp = stamp
        document.selectElement(id: nil)
        needsDisplay = true
        notifyDocumentChanged()
    }

    func copyObject() { document.duplicateSelected(); needsDisplay = true; notifyDocumentChanged() }

    func reorderObject(forward: Bool) {
        document.reorderSelected(forward: forward)
        needsDisplay = true
        notifyDocumentChanged()
    }

    func startCrop() {
        finishTextEditing()
        isCropping = true
        cropBounds = CGRect(origin: .zero, size: image.size)
        cropRatio = nil
        window?.makeFirstResponder(self)
        onCropChanged?()
        needsDisplay = true
    }

    func selectCropRatio(_ ratio: CGFloat?) {
        cropRatio = ratio
        if let ratio, let current = cropBounds {
            let width = min(current.width, current.height * ratio)
            let height = width / ratio
            cropBounds = CGRect(x: current.midX - width / 2, y: current.midY - height / 2, width: width, height: height)
        }
        onCropChanged?()
        needsDisplay = true
    }

    func cancelCrop() {
        isCropping = false
        cropBounds = nil
        cropStart = nil
        cropMoveOffset = nil
        onCropChanged?()
        needsDisplay = true
    }

    private func updateCrop(to point: CGPoint) {
        if let offset = cropMoveOffset, let crop = cropBounds {
            cropBounds = CGRect(
                x: clamp(point.x - offset.x, min: 0, max: image.size.width - crop.width),
                y: clamp(point.y - offset.y, min: 0, max: image.size.height - crop.height),
                width: crop.width, height: crop.height
            )
        } else if let start = cropStart {
            var width = point.x - start.x
            var height = point.y - start.y
            if let ratio = cropRatio {
                let boundedWidth = min(abs(width), abs(height) * ratio)
                width = width < 0 ? -boundedWidth : boundedWidth
                height = (height < 0 ? -1 : 1) * boundedWidth / ratio
            }
            cropBounds = CGRect(x: start.x, y: start.y, width: width, height: height).standardized
        }
        onCropChanged?()
        needsDisplay = true
    }

    func applyCrop() throws {
        guard let cropBounds else { return }
        let pixels = ImageWorkspaceRaster.pixelSize(image)
        let pixelRect = ImageWorkspaceRaster.cropPixelRect(cropBounds, logicalSize: image.size, pixelSize: pixels)
        guard pixelRect.width >= 1, pixelRect.height >= 1 else { return }
        if pixelRect == CGRect(origin: .zero, size: pixels) {
            cancelCrop()
            return
        }
        try applyRasterEdit(.crop(cropBounds))
        cancelCrop()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onCanvasResize?()
    }

    func zoom(by magnification: CGFloat) {
        _ = imageZoom.applyMagnification(magnification, imageSize: image.size, bounds: bounds, allowsBelowFit: true)
    }

    func setZoom(actualPixels: Bool) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let backing = window?.backingScaleFactor ?? 1
        let displayScale = actualPixels
            ? ImageWorkspaceRaster.pixelSize(image).width / (backing * size.width)
            : min(bounds.width / size.width, bounds.height / size.height)
        imageZoom.setDisplayScale(displayScale, imageSize: size, bounds: bounds)
    }

    var zoomPercentage: Int {
        let width = ImageWorkspaceRaster.pixelSize(image).width
        guard width > 0 else { return 100 }
        return Int((imageDrawRect.width * (window?.backingScaleFactor ?? 1) * 100 / width).rounded())
    }

    func setShapeKind(_ shapeKind: ImageAnnotationShapeKind) {
        document.setShapeKind(shapeKind)
        notifyDocumentChanged()
    }

    func setMosaicMode(_ mosaicMode: ImageAnnotationMosaicMode) {
        document.setMosaicMode(mosaicMode)
        notifyDocumentChanged()
    }

    func setInspectorMosaicMode(_ mode: ImageAnnotationMosaicMode) {
        document.setMosaicMode(mode)
        document.changeSelectedMosaicMode(mode)
        needsDisplay = true
        notifyDocumentChanged()
        onEditingOptionsChange?()
    }

    func setStyle(_ style: ImageAnnotationStyle) {
        document.setStyle(style)
        updateSelectedElementStyleIfNeeded(style)
        notifyDocumentChanged()
        onEditingOptionsChange?()
    }

    func undo() {
        document.undo()
        needsDisplay = true
        notifyDocumentChanged()
    }

    func redo() {
        document.redo()
        needsDisplay = true
        notifyDocumentChanged()
    }

    func markCurrentRenditionSaved() {
        document.markCurrentRenditionSaved()
        needsDisplay = true
        notifyDocumentChanged()
    }

    func imageZoomDidChange() {
        updateActiveTextEditorFrame()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func commitActiveTextForTesting(_ text: String) {
        activeTextEditor?.string = text
        updateActiveTextElement(text)
        commitActiveText(text)
    }

    func editActiveTextForTesting(_ text: String) {
        activeTextEditor?.string = text
        updateActiveTextElement(text)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let drawRect = imageDrawRect
        drawTransparencyGrid(in: drawRect)
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        let mosaicSource = mosaicSourceIfNeeded()

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        let scaleX = drawRect.width / max(1, image.size.width)
        let scaleY = drawRect.height / max(1, image.size.height)
        transform.translateX(by: drawRect.minX, yBy: drawRect.minY)
        transform.scaleX(by: scaleX, yBy: scaleY)
        transform.concat()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: CGRect(origin: .zero, size: image.size)).addClip()
        ImageAnnotationViewRenderer.draw(
            document: document,
            mosaicSource: mosaicSource,
            imageSize: image.size,
            excluding: activeTextEditor == nil ? nil : activeTextElementID
        )
        drawDraftIfNeeded(mosaicSource: mosaicSource)
        NSGraphicsContext.restoreGraphicsState()
        if isCropping { drawCropOverlay() } else { drawSelectionHandleIfNeeded() }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let activeTextEditor {
            let viewPoint = convert(event.locationInWindow, from: nil)
            if activeTextEditor.frame.contains(viewPoint) {
                return
            }
            commitActiveText(activeTextEditor.string)
        }

        if isSpaceDown {
            spacePanPoint = event.locationInWindow
            return
        }
        guard let imagePoint = imagePoint(for: event) else { return }
        if isCropping {
            beginCropDrag(at: imagePoint)
            return
        }
        if let stamp {
            switch stamp {
            case .counter:
                let numbers = document.elements.compactMap { element -> Int? in
                    if case let .counter(number) = element.kind { return number }
                    return nil
                }
                addElement(kind: .counter((numbers.max() ?? 0) + 1),
                           bounds: CGRect(x: imagePoint.x - 16, y: imagePoint.y - 16, width: 32, height: 32))
                needsDisplay = true
            case .spotlight:
                interaction = .creatingSpotlight(start: imagePoint, current: imagePoint)
            }
            return
        }
        if event.clickCount >= 2,
           beginToolContextInteraction(at: imagePoint) {
            needsDisplay = true
            return
        }

        if document.selectedTool == .text {
            handleTextToolMouseDown(at: imagePoint, clickCount: event.clickCount)
            needsDisplay = true
            return
        }

        if !event.modifierFlags.contains(.option),
           shouldBeginSelectedElementInteraction(at: imagePoint) || shouldBeginExistingElementInteraction(at: imagePoint) {
            beginSelectionInteraction(at: imagePoint, clickCount: event.clickCount)
            needsDisplay = true
            return
        }

        if shouldBeginPendingCreation {
            interaction = .pendingCreation(start: imagePoint)
            needsDisplay = true
            return
        }

        switch document.selectedTool {
        case .select:
            beginSelectionInteraction(at: imagePoint, clickCount: event.clickCount)
        case .shape:
            interaction = .creatingShape(start: imagePoint, current: imagePoint)
        case .brush:
            interaction = .drawingPoints(kind: .brush, points: [imagePoint])
        case .highlight:
            interaction = .drawingPoints(kind: .highlight, points: [imagePoint])
        case .mosaic:
            switch document.editingOptions.mosaicMode {
            case .rectangle, .blur, .redact:
                interaction = .creatingMosaic(start: imagePoint, current: imagePoint)
            case .brush:
                interaction = .drawingPoints(kind: .mosaic(.brush), points: [imagePoint])
            }
        case .text:
            break
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if let last = spacePanPoint {
            let current = event.locationInWindow
            _ = imageZoom.applyScroll(delta: CGSize(width: current.x - last.x, height: last.y - current.y),
                                      imageSize: image.size, bounds: bounds)
            spacePanPoint = current
            return
        }
        guard let imagePoint = imagePoint(for: event, clamped: true) else { return }
        if isCropping { updateCrop(to: imagePoint); return }
        if let origin = newTextDragOrigin, let editor = activeTextEditor, abs(imagePoint.x - origin.x) > 6 {
            let start = CGPoint(x: min(origin.x, imagePoint.x), y: origin.y)
            activeTextOrigin = start
            var style = selectedStyle
            style.textBoxWidth = max(40, abs(imagePoint.x - origin.x))
            document.updateSelectedStyle(style, recordingUndo: false)
            updateActiveTextElement(editor.string)
            return
        }
        guard let interaction else {
            return
        }

        switch interaction {
        case let .creatingShape(start, _):
            self.interaction = .creatingShape(
                start: start,
                current: constrainedShapePoint(start: start, current: imagePoint, modifierFlags: event.modifierFlags)
            )
        case let .creatingSpotlight(start, _):
            self.interaction = .creatingSpotlight(start: start, current: imagePoint)
        case let .editingEndpoint(index, hasStartedMutation):
            document.moveSelectedEndpoint(index, to: imagePoint, recordingUndo: !hasStartedMutation)
            self.interaction = .editingEndpoint(index, hasStartedMutation: true)
            notifyDocumentChanged()
        case let .creatingMosaic(start, _):
            self.interaction = .creatingMosaic(start: start, current: imagePoint)
        case let .drawingPoints(kind, points):
            self.interaction = .drawingPoints(kind: kind, points: points + [imagePoint])
        case let .moving(lastPoint, hasStartedMutation):
            if !hasStartedMutation {
                document.beginEditingSelectedElement()
            }
            document.moveSelected(
                by: CGSize(width: imagePoint.x - lastPoint.x, height: imagePoint.y - lastPoint.y),
                recordingUndo: false
            )
            self.interaction = .moving(lastPoint: imagePoint, hasStartedMutation: true)
            notifyDocumentChanged()
        case let .resizing(anchor, hasStartedMutation):
            if !hasStartedMutation {
                document.beginEditingSelectedElement()
            }
            let bounds = CGRect(
                x: anchor.x,
                y: anchor.y,
                width: imagePoint.x - anchor.x,
                height: imagePoint.y - anchor.y
            ).standardized
            if let selectedElement, case let .text(text) = selectedElement.kind {
                var style = selectedElement.style
                let swapsAxes = selectedElement.contentSwapsAxes
                style.textBoxWidth = max(40, swapsAxes ? bounds.height : bounds.width)
                let textBounds = ImageAnnotationTextStyle.bounds(for: text, origin: selectedElement.bounds.origin, style: style)
                document.updateSelectedStyle(style, bounds: textBounds.swappingSizeAxes(if: swapsAxes), recordingUndo: false)
            } else if let selectedElement, case .image = selectedElement.kind,
                      selectedElement.bounds.height > 0 {
                let aspect = selectedElement.bounds.width / selectedElement.bounds.height
                let width = max(2, min(bounds.width, bounds.height * aspect))
                let height = width / aspect
                let x = imagePoint.x >= anchor.x ? anchor.x : anchor.x - width
                let y = imagePoint.y >= anchor.y ? anchor.y : anchor.y - height
                document.resizeSelected(to: CGRect(x: x, y: y, width: width, height: height), recordingUndo: false)
            } else {
                document.resizeSelected(to: minimumAnnotationBounds(bounds), recordingUndo: false)
            }
            self.interaction = .resizing(anchor: anchor, hasStartedMutation: true)
            notifyDocumentChanged()
        case let .pendingCreation(start):
            self.interaction = creationInteraction(start: start, current: imagePoint)
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        newTextDragOrigin = nil
        if spacePanPoint != nil { spacePanPoint = nil; return }
        if isCropping { cropStart = nil; cropMoveOffset = nil; return }
        guard let interaction else { return }

        switch interaction {
        case let .creatingSpotlight(start, current):
            addElement(kind: .spotlight, bounds: CGRect(x: start.x, y: start.y, width: current.x - start.x,
                                                         height: current.y - start.y).standardized)
        case let .creatingShape(start, current):
            let shapeKind = document.editingOptions.shapeKind
            let finalPoint = constrainedShapePoint(start: start, current: current, modifierFlags: event.modifierFlags)
            addElement(
                kind: .shape(shapeKind),
                bounds: minimumAnnotationBounds(CGRect(
                    x: start.x,
                    y: start.y,
                    width: finalPoint.x - start.x,
                    height: finalPoint.y - start.y
                ).standardized),
                points: shapePoints(for: shapeKind, start: start, current: finalPoint)
            )
        case let .creatingMosaic(start, current):
            addElement(
                kind: .mosaic(document.editingOptions.mosaicMode),
                bounds: minimumAnnotationBounds(CGRect(
                    x: start.x,
                    y: start.y,
                    width: current.x - start.x,
                    height: current.y - start.y
                ).standardized)
            )
        case let .drawingPoints(kind, points):
            guard !points.isEmpty else {
                break
            }

            let bounds = pointsBounds(points, radius: max(2, document.editingOptions.style.lineWidth))
            document.add(ImageAnnotationElement(
                kind: kind,
                bounds: bounds,
                points: points,
                style: document.editingOptions.style
            ))
            notifyDocumentChanged()
        case .moving, .resizing, .editingEndpoint:
            break
        case let .pendingCreation(start):
            document.selectTopmostElement(at: start)
            notifyDocumentChanged()
            break
        }

        self.interaction = nil
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        if imageZoom.applyMagnification(event.magnification, imageSize: image.size, bounds: bounds) {
            imageZoomDidChange()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if imageZoom.applyScroll(
            delta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
            imageSize: image.size,
            bounds: bounds
        ) {
            imageZoomDidChange()
            return
        }

        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isCropping && event.keyCode == 53 { cancelCrop(); return }
        if isCropping && (event.keyCode == 36 || event.keyCode == 76) { onCropCommit?(); return }
        if event.keyCode == 49 { isSpaceDown = true; return }
        if selectedElement != nil, [123, 124, 125, 126].contains(event.keyCode),
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            let amount: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta: CGSize
            switch event.keyCode {
            case 123: delta = CGSize(width: -amount, height: 0)
            case 124: delta = CGSize(width: amount, height: 0)
            case 125: delta = CGSize(width: 0, height: -amount)
            default: delta = CGSize(width: 0, height: amount)
            }
            document.moveSelected(by: delta)
            needsDisplay = true
            notifyDocumentChanged()
            return
        }
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) {
                redo()
            } else {
                undo()
            }
            return
        }

        if handleKeyboardShortcut(event) {
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 || (event.keyCode == 53 && selectedElement != nil) {
            document.deleteSelected()
            needsDisplay = true
            notifyDocumentChanged()
            return
        }

        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { isSpaceDown = false; spacePanPoint = nil; return }
        super.keyUp(with: event)
    }

    override func resignFirstResponder() -> Bool {
        isSpaceDown = false
        spacePanPoint = nil
        return super.resignFirstResponder()
    }

    private func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        let disallowedModifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard disallowedModifiers.isEmpty,
              let character = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch character {
        case "v":
            requestToolContext(.tool(.select))
        case "r":
            requestToolContext(.shape(.rectangle))
        case "o":
            requestToolContext(.shape(.ellipse))
        case "l":
            requestToolContext(.shape(.line))
        case "a":
            requestToolContext(.shape(.arrow))
        case "b":
            requestToolContext(.tool(.brush))
        case "t":
            requestToolContext(.tool(.text))
        case "h":
            requestToolContext(.tool(.highlight))
        case "m":
            requestToolContext(.tool(.mosaic))
        case "+", "=": zoom(by: 0.25)
        case "-": zoom(by: -0.2)
        case "0": setZoom(actualPixels: false)
        case "1": setZoom(actualPixels: true)
        case "[":
            adjustSelectedStyleSize(direction: -1)
        case "]":
            adjustSelectedStyleSize(direction: 1)
        default:
            return false
        }

        return true
    }

    private func requestToolContext(_ context: ImageAnnotationCanvasToolContext) {
        if let onToolContextRequest {
            onToolContextRequest(context)
            return
        }

        applyToolContext(context)
        notifyDocumentChanged()
    }

    private func applyToolContext(_ context: ImageAnnotationCanvasToolContext) {
        switch context {
        case let .tool(tool):
            document.selectTool(tool)
        case let .shape(shapeKind):
            document.setShapeKind(shapeKind)
            document.selectTool(.shape)
        case let .mosaic(mosaicMode):
            document.setMosaicMode(mosaicMode)
            document.selectTool(.mosaic)
        }

        needsDisplay = true
    }

    private func adjustSelectedStyleSize(direction: Int) {
        var style = document.editingOptions.style
        switch document.selectedTool {
        case .text:
            style.fontSize = steppedValue(
                from: style.fontSize,
                values: Self.textFontSizes,
                direction: direction
            )
        case .shape, .brush, .highlight:
            style.lineWidth = steppedValue(
                from: style.lineWidth,
                values: Self.annotationLineWidths,
                direction: direction
            )
        case .select, .mosaic:
            return
        }

        setStyle(style)
        onEditingOptionsChange?()
    }

    private func steppedValue(from currentValue: CGFloat, values: [CGFloat], direction: Int) -> CGFloat {
        guard let currentIndex = values.firstIndex(of: currentValue) else {
            return currentValue
        }

        let nextIndex = max(0, min(values.count - 1, currentIndex + direction))
        return values[nextIndex]
    }

    private var imageDrawRect: CGRect {
        imageZoom.drawRect(imageSize: image.size, in: bounds)
    }

    private var imageDisplayScale: CGFloat {
        imageDrawRect.width / max(1, image.size.width)
    }

    private func imagePoint(for event: NSEvent, clamped: Bool = false) -> CGPoint? {
        let point = convert(event.locationInWindow, from: nil)
        let drawRect = imageDrawRect
        guard (clamped || drawRect.contains(point)), drawRect.width > 0, drawRect.height > 0 else {
            return nil
        }

        let scaleX = image.size.width / drawRect.width
        let scaleY = image.size.height / drawRect.height
        return CGPoint(
            x: clamp((point.x - drawRect.minX) * scaleX, min: 0, max: image.size.width),
            y: clamp((point.y - drawRect.minY) * scaleY, min: 0, max: image.size.height)
        )
    }

    private func beginSelectionInteraction(at point: CGPoint, clickCount: Int, preferMoving: Bool = false) {
        if preferMoving {
            interaction = .moving(lastPoint: point, hasStartedMutation: false)
            return
        }
        if let selectedElement, isLine(selectedElement),
           let endpoint = selectedElement.points.firstIndex(where: { handleRect(center: $0).contains(point) }) {
            interaction = .editingEndpoint(endpoint, hasStartedMutation: false)
            return
        }
        if let selectedElement, !isLine(selectedElement),
           let anchor = oppositeCorner(for: selectedElement.bounds, at: point) {
            interaction = .resizing(anchor: anchor, hasStartedMutation: false)
            return
        }
        let hitID = document.topmostElementID(at: point, tolerance: 6 / max(0.1, imageDisplayScale))
        let selectedInterior = selectedElement.flatMap { element in
            !isLine(element) && element.bounds.contains(point) ? element.id : nil
        }
        document.selectElement(id: hitID ?? selectedInterior)
        notifyDocumentChanged()

        if clickCount >= 2,
           let selectedElement = selectedElement,
           case let .text(text) = selectedElement.kind {
            beginTextEditing(elementID: selectedElement.id, origin: selectedElement.bounds.origin, initialText: text)
            return
        }

        guard let selectedElement else {
            interaction = nil
            return
        }

        if let anchor = oppositeCorner(for: selectedElement.bounds, at: point), !isLine(selectedElement) {
            interaction = .resizing(anchor: anchor, hasStartedMutation: false)
        } else {
            interaction = .moving(lastPoint: point, hasStartedMutation: false)
        }
    }

    private func beginToolContextInteraction(at point: CGPoint) -> Bool {
        let elementID = document.topmostElementID(at: point, tolerance: 6)
            ?? document.elements.reversed().first(where: { element in
                if case .shape(.rectangle) = element.kind { return element.bounds.contains(point) }
                if case .shape(.ellipse) = element.kind { return element.bounds.contains(point) }
                return false
            })?.id
        guard let elementID, let element = document.elements.first(where: { $0.id == elementID }) else {
            return false
        }

        document.selectElement(id: elementID)
        notifyDocumentChanged()
        requestToolContext(ImageAnnotationCanvasToolContext(elementKind: element.kind))

        if case let .text(text) = element.kind {
            beginTextEditing(elementID: elementID, origin: element.bounds.origin, initialText: text)
        }

        return true
    }

    private var selectedElement: ImageAnnotationElement? {
        guard let selectedElementID = document.selectedElementID else {
            return nil
        }

        return document.elements.first { $0.id == selectedElementID }
    }

    private func shouldBeginSelectedElementInteraction(at point: CGPoint) -> Bool {
        switch document.selectedTool {
        case .select, .text:
            return false
        case .shape, .brush, .highlight, .mosaic:
            break
        }

        guard let selectedElement else {
            return false
        }

        return oppositeCorner(for: selectedElement.bounds, at: point) != nil
            || (isLine(selectedElement) && selectedElement.points.contains { handleRect(center: $0).contains(point) })
            || (!isLine(selectedElement) && selectedElement.bounds.contains(point))
            || document.topmostElementID(at: point, tolerance: 6) == selectedElement.id
    }

    private func shouldBeginExistingElementInteraction(at point: CGPoint) -> Bool {
        shouldBeginPendingCreation && document.topmostElementID(at: point, tolerance: 6) != nil
    }

    private var shouldBeginPendingCreation: Bool {
        switch document.selectedTool {
        case .shape, .brush, .highlight, .mosaic:
            return true
        case .select, .text:
            return false
        }
    }

    private func handleTextToolMouseDown(at point: CGPoint, clickCount: Int) {
        if let selectedElement, case .text = selectedElement.kind, selectedElement.bounds.contains(point) {
            beginSelectionInteraction(at: point, clickCount: clickCount, preferMoving: true)
            return
        }
        if document.topmostElementID(at: point, tolerance: 6) != nil {
            beginSelectionInteraction(at: point, clickCount: clickCount)
            return
        }

        beginTextEditing(elementID: nil, origin: point, initialText: "")
        newTextDragOrigin = point
    }

    private func creationInteraction(start: CGPoint, current: CGPoint) -> AnnotationInteraction {
        switch document.selectedTool {
        case .shape:
            return .creatingShape(start: start, current: current)
        case .mosaic:
            switch document.editingOptions.mosaicMode {
            case .rectangle, .blur, .redact:
                return .creatingMosaic(start: start, current: current)
            case .brush:
                return .drawingPoints(kind: .mosaic(.brush), points: [start, current])
            }
        case .brush:
            return .drawingPoints(kind: .brush, points: [start, current])
        case .highlight:
            return .drawingPoints(kind: .highlight, points: [start, current])
        case .select, .text:
            return .pendingCreation(start: start)
        }
    }

    private func beginTextEditing(elementID: UUID?, origin: CGPoint, initialText: String) {
        removeActiveTextEditor()
        textEditBaseline = document

        let style: ImageAnnotationStyle
        let textBounds: CGRect
        let swapsAxes: Bool
        let editingElementID: UUID
        if let elementID,
           let element = document.elements.first(where: { $0.id == elementID }) {
            document.selectElement(id: elementID)
            editingElementID = elementID
            style = element.style
            textBounds = element.bounds
            swapsAxes = element.contentSwapsAxes
            activeTextDidBeginMutation = false
        } else {
            style = document.editingOptions.style
            swapsAxes = false
            textBounds = ImageAnnotationTextStyle.bounds(for: initialText, origin: origin, style: style)
            let element = ImageAnnotationElement(
                kind: .text(initialText),
                bounds: textBounds,
                style: style
            )
            document.add(element)
            editingElementID = element.id
            activeTextDidBeginMutation = true
            notifyDocumentChanged()
        }

        activeTextElementID = editingElementID
        activeTextOrigin = textBounds.origin
        activeTextSwapsAxes = swapsAxes

        let editor = ImageAnnotationTextEditorView()
        editor.string = initialText
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.font = ImageAnnotationTextStyle.font(for: style, scale: imageDisplayScale)
        editor.textColor = ImageAnnotationTextStyle.foregroundColor(for: style)
        editor.drawsBackground = false
        editor.backgroundColor = .clear
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = true
        editor.alignment = ImageAnnotationTextStyle.alignment(for: style)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.delegate = self
        editor.onCommit = { [weak self, weak editor] in
            guard let editor else {
                return
            }
            self?.commitActiveText(editor.string)
        }
        editor.onCancel = { [weak self] in
            guard let self, let baseline = self.textEditBaseline else { return }
            self.removeActiveTextEditor()
            self.document = baseline
            self.window?.makeFirstResponder(self)
            self.needsDisplay = true
            self.notifyDocumentChanged()
        }
        activeTextEditor = editor
        addSubview(editor)

        let frame = viewRect(forImageRect: textBounds.swappingSizeAxes(if: swapsAxes))
        editor.frame = frame
        editor.textContainer?.containerSize = frame.size
        window?.makeFirstResponder(editor)
        needsDisplay = true
    }

    private func textEditingStyle(for elementID: UUID?) -> ImageAnnotationStyle {
        guard let elementID,
              let element = document.elements.first(where: { $0.id == elementID }) else {
            return document.editingOptions.style
        }

        return element.style
    }

    private func updateSelectedElementStyleIfNeeded(_ style: ImageAnnotationStyle) {
        if let activeTextElementID {
            document.selectElement(id: activeTextElementID)
        }

        guard let selectedElement else {
            activeTextEditor?.font = ImageAnnotationTextStyle.font(for: style, scale: imageDisplayScale)
            activeTextEditor?.textColor = ImageAnnotationTextStyle.foregroundColor(for: style)
            needsDisplay = true
            return
        }

        let updatedBounds: CGRect?
        if case let .text(text) = selectedElement.kind {
            updatedBounds = ImageAnnotationTextStyle.bounds(
                for: text,
                origin: selectedElement.bounds.origin,
                style: style
            ).swappingSizeAxes(if: selectedElement.contentSwapsAxes)
        } else {
            updatedBounds = nil
        }

        document.updateSelectedStyle(style, bounds: updatedBounds)

        if let activeTextEditor,
           selectedElement.id == activeTextElementID,
           let updatedBounds {
            activeTextEditor.font = ImageAnnotationTextStyle.font(for: style, scale: imageDisplayScale)
            activeTextEditor.textColor = ImageAnnotationTextStyle.foregroundColor(for: style)
            activeTextEditor.alignment = ImageAnnotationTextStyle.alignment(for: style)
            let frame = viewRect(forImageRect: updatedBounds.swappingSizeAxes(if: activeTextSwapsAxes))
            activeTextEditor.frame = frame
            activeTextEditor.textContainer?.containerSize = frame.size
            activeTextOrigin = updatedBounds.origin
            activeTextDidBeginMutation = true
        }

        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === activeTextEditor else {
            return
        }

        updateActiveTextElement(activeTextEditor?.string ?? "")
    }

    private func commitActiveText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedText.isEmpty {
            if let baseline = textEditBaseline, let id = activeTextElementID,
               !baseline.elements.contains(where: { $0.id == id }) {
                removeActiveTextEditor()
                document = baseline
                window?.makeFirstResponder(self)
                needsDisplay = true
                notifyDocumentChanged()
            } else {
                deleteActiveTextElement()
            }
            return
        }

        if let textElementID = activeTextElementID {
            document.selectElement(id: textElementID)
            if selectedElement?.kind != .text(text) { updateActiveTextElement(text) }
            notifyDocumentChanged()
        }

        removeActiveTextEditor()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func updateActiveTextElement(_ text: String) {
        guard let textElementID = activeTextElementID,
              let origin = activeTextOrigin else {
            return
        }

        document.selectElement(id: textElementID)
        if !activeTextDidBeginMutation {
            document.beginEditingSelectedElement()
            activeTextDidBeginMutation = true
        }

        let style = textEditingStyle(for: textElementID)
        let bounds = ImageAnnotationTextStyle.bounds(for: text, origin: origin, style: style)
        document.updateSelectedText(text, bounds: bounds.swappingSizeAxes(if: activeTextSwapsAxes), recordingUndo: false)
        if let activeTextEditor {
            let frame = viewRect(forImageRect: bounds)
            activeTextEditor.frame = frame
            activeTextEditor.textContainer?.containerSize = frame.size
        }
        needsDisplay = true
        notifyDocumentChanged()
    }

    private func updateActiveTextEditorFrame() {
        guard let activeTextEditor,
              let activeTextElementID,
              let element = document.elements.first(where: { $0.id == activeTextElementID }) else {
            return
        }

        let style = textEditingStyle(for: activeTextElementID)
        let frame = viewRect(forImageRect: element.bounds.swappingSizeAxes(if: activeTextSwapsAxes))
        activeTextEditor.font = ImageAnnotationTextStyle.font(for: style, scale: imageDisplayScale)
        activeTextEditor.frame = frame
        activeTextEditor.textContainer?.containerSize = frame.size
    }

    private func deleteActiveTextElement() {
        if let textElementID = activeTextElementID {
            document.selectElement(id: textElementID)
            document.deleteSelected()
            notifyDocumentChanged()
        }

        removeActiveTextEditor()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func removeActiveTextEditor() {
        activeTextEditor?.delegate = nil
        activeTextEditor?.onCommit = nil
        activeTextEditor?.onCancel = nil
        activeTextEditor?.removeFromSuperview()
        activeTextEditor = nil
        activeTextElementID = nil
        activeTextOrigin = nil
        activeTextSwapsAxes = false
        newTextDragOrigin = nil
        textEditBaseline = nil
        activeTextDidBeginMutation = false
    }

    private func addElement(kind: ImageAnnotationElementKind, bounds: CGRect, points: [CGPoint] = []) {
        guard bounds.width >= 2, bounds.height >= 2 else {
            return
        }

        document.add(ImageAnnotationElement(
            kind: kind,
            bounds: bounds,
            points: points,
            style: document.editingOptions.style
        ))
        notifyDocumentChanged()
    }

    private func drawDraftIfNeeded(mosaicSource: ImageMosaicDrawingSource?) {
        guard let interaction else {
            return
        }

        switch interaction {
        case let .creatingShape(start, current):
            let shapeKind = document.editingOptions.shapeKind
            let element = ImageAnnotationElement(
                kind: .shape(shapeKind),
                bounds: minimumAnnotationBounds(CGRect(
                    x: start.x,
                    y: start.y,
                    width: current.x - start.x,
                    height: current.y - start.y
                ).standardized),
                points: shapePoints(for: shapeKind, start: start, current: current),
                style: document.editingOptions.style
            )
            ImageAnnotationViewRenderer.draw(element, mosaicSource: mosaicSource, imageSize: image.size)
        case let .creatingMosaic(start, current):
            let bounds = minimumAnnotationBounds(CGRect(x: start.x, y: start.y, width: current.x - start.x,
                                                         height: current.y - start.y).standardized)
            let element = ImageAnnotationElement(kind: .mosaic(document.editingOptions.mosaicMode),
                                                 bounds: bounds, style: document.editingOptions.style)
            ImageAnnotationViewRenderer.draw(element, mosaicSource: mosaicSource, imageSize: image.size)
            drawMosaicSelectionDraft(in: bounds)
        case let .creatingSpotlight(start, current):
            let bounds = CGRect(x: start.x, y: start.y, width: current.x - start.x, height: current.y - start.y).standardized
            ImageAnnotationViewRenderer.draw(ImageAnnotationElement(kind: .spotlight, bounds: bounds,
                style: document.editingOptions.style), imageSize: image.size)
        case let .drawingPoints(kind, points):
            let element = ImageAnnotationElement(
                kind: kind,
                bounds: pointsBounds(points, radius: document.editingOptions.style.lineWidth),
                points: points,
                style: document.editingOptions.style
            )
            ImageAnnotationViewRenderer.draw(element, mosaicSource: mosaicSource, imageSize: image.size)
        case .moving, .resizing, .editingEndpoint, .pendingCreation:
            break
        }
    }

    private func drawSelectionHandleIfNeeded() {
        guard let selectedElement else {
            return
        }

        let bounds = selectedElement.bounds
        if isLine(selectedElement) {
            drawHandles(selectedElement.points)
        } else {
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: bounds)
            outline.lineWidth = 1 / max(0.1, imageDisplayScale)
            outline.stroke()
            drawHandles(corners(of: bounds))
        }
    }

    private func drawHandles(_ handles: [CGPoint]) {
        let size = 7 / max(0.1, imageDisplayScale)
        for point in handles {
            let handle = NSBezierPath(roundedRect: CGRect(x: point.x - size / 2, y: point.y - size / 2,
                                                          width: size, height: size), xRadius: 1, yRadius: 1)
            NSColor.white.setFill()
            handle.fill()
            NSColor.controlAccentColor.setStroke()
            handle.lineWidth = 1 / max(0.1, imageDisplayScale)
            handle.stroke()
        }
    }

    private func drawCropOverlay() {
        guard let cropBounds else { return }
        let shade = NSBezierPath(rect: CGRect(origin: .zero, size: image.size))
        shade.appendRect(cropBounds)
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.56).setFill()
        shade.fill()
        NSColor.white.withAlphaComponent(0.55).setStroke()
        let guides = NSBezierPath()
        for fraction in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
            let x = cropBounds.minX + cropBounds.width * fraction
            let y = cropBounds.minY + cropBounds.height * fraction
            guides.move(to: CGPoint(x: x, y: cropBounds.minY))
            guides.line(to: CGPoint(x: x, y: cropBounds.maxY))
            guides.move(to: CGPoint(x: cropBounds.minX, y: y))
            guides.line(to: CGPoint(x: cropBounds.maxX, y: y))
        }
        guides.lineWidth = 0.5 / max(0.1, imageDisplayScale)
        guides.stroke()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: cropBounds)
        border.lineWidth = 1 / max(0.1, imageDisplayScale)
        border.stroke()
        drawHandles(corners(of: cropBounds))
    }

    private func drawTransparencyGrid(in rect: CGRect) {
        let visible = bounds.intersection(rect)
        guard !visible.isNull, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: rect)
        context.setFillColor(NSColor(white: 0.24, alpha: 1).cgColor)
        context.fill(visible)
        context.setFillColor(NSColor(white: 0.31, alpha: 1).cgColor)
        let tile: CGFloat = 10
        for row in Int(floor(visible.minY / tile))..<Int(ceil(visible.maxY / tile)) {
            for column in Int(floor(visible.minX / tile))..<Int(ceil(visible.maxX / tile)) where (row + column) % 2 == 0 {
                context.fill(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile))
            }
        }
        context.restoreGState()
    }

    private func beginCropDrag(at point: CGPoint) {
        if let cropBounds, let anchor = oppositeCorner(for: cropBounds, at: point) {
            cropStart = anchor
        } else if let cropBounds, cropBounds != CGRect(origin: .zero, size: image.size), cropBounds.contains(point) {
            cropMoveOffset = CGPoint(x: point.x - cropBounds.minX, y: point.y - cropBounds.minY)
        } else {
            cropStart = point
        }
    }

    private func drawMosaicSelectionDraft(in bounds: CGRect) {
        let path = NSBezierPath(rect: bounds.standardized)
        path.lineWidth = 1.5
        path.setLineDash([5, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()

        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(rect: bounds.standardized).fill()
    }

    private func isLine(_ element: ImageAnnotationElement) -> Bool {
        element.kind == .shape(.line) || element.kind == .shape(.arrow)
    }

    private func corners(of bounds: CGRect) -> [CGPoint] {
        [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
         CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY)]
    }

    private func handleRect(center: CGPoint) -> CGRect {
        let radius = 6 / max(0.1, imageDisplayScale)
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    private func oppositeCorner(for bounds: CGRect, at point: CGPoint) -> CGPoint? {
        let anchors = corners(of: bounds)
        guard let index = anchors.firstIndex(where: { handleRect(center: $0).contains(point) }) else { return nil }
        return anchors[(index + 2) % anchors.count]
    }

    private func viewRect(forImageRect imageRect: CGRect) -> CGRect {
        let drawRect = imageDrawRect
        let scaleX = drawRect.width / max(1, image.size.width)
        let scaleY = drawRect.height / max(1, image.size.height)
        return CGRect(
            x: drawRect.minX + imageRect.minX * scaleX,
            y: drawRect.minY + imageRect.minY * scaleY,
            width: imageRect.width * scaleX,
            height: imageRect.height * scaleY
        )
    }

    private func pointsBounds(_ points: [CGPoint], radius: CGFloat) -> CGRect {
        guard let first = points.first else {
            return .zero
        }

        let rect = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { partialResult, point in
            partialResult.union(CGRect(origin: point, size: .zero))
        }
        return rect.insetBy(dx: -radius, dy: -radius).standardized
    }

    private func shapePoints(for shapeKind: ImageAnnotationShapeKind, start: CGPoint, current: CGPoint) -> [CGPoint] {
        switch shapeKind {
        case .line, .arrow:
            return [start, current]
        case .rectangle, .ellipse:
            return []
        }
    }

    private func constrainedShapePoint(
        start: CGPoint,
        current: CGPoint,
        modifierFlags: NSEvent.ModifierFlags
    ) -> CGPoint {
        guard modifierFlags.contains(.shift) else {
            return current
        }

        switch document.editingOptions.shapeKind {
        case .rectangle, .ellipse:
            let deltaX = current.x - start.x
            let deltaY = current.y - start.y
            let side = max(abs(deltaX), abs(deltaY))
            return CGPoint(
                x: start.x + (deltaX < 0 ? -side : side),
                y: start.y + (deltaY < 0 ? -side : side)
            )
        case .line, .arrow:
            return snappedLinePoint(start: start, current: current)
        }
    }

    private func snappedLinePoint(start: CGPoint, current: CGPoint) -> CGPoint {
        let deltaX = current.x - start.x
        let deltaY = current.y - start.y
        let absoluteX = abs(deltaX)
        let absoluteY = abs(deltaY)
        guard absoluteX > 0 || absoluteY > 0 else {
            return current
        }

        let axisThreshold = CGFloat(tan(Double.pi / 8))
        if absoluteY <= absoluteX * axisThreshold {
            return CGPoint(x: current.x, y: start.y)
        }
        if absoluteX <= absoluteY * axisThreshold {
            return CGPoint(x: start.x, y: current.y)
        }

        let side = max(absoluteX, absoluteY)
        return CGPoint(
            x: start.x + (deltaX < 0 ? -side : side),
            y: start.y + (deltaY < 0 ? -side : side)
        )
    }

    private func minimumAnnotationBounds(_ bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(2, bounds.width),
            height: max(2, bounds.height)
        )
    }

    private func notifyDocumentChanged() {
        if displayedImagePNG != document.editedImagePNG {
            if let data = document.editedImagePNG,
               let edited = try? ImageWorkspaceRaster.screenshot(data: data, size: document.editedImageSize) {
                image = edited.image
            } else if let baseScreenshot {
                image = baseScreenshot.image
            }
            displayedImagePNG = document.editedImagePNG
            mosaicDrawingSource = nil
            onImageChanged?()
        }
        onDocumentChange(document)
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func mosaicSourceIfNeeded() -> ImageMosaicDrawingSource? {
        guard document.containsMosaicElements || interaction?.requiresMosaicRendering == true else {
            return nil
        }

        if let mosaicDrawingSource {
            return mosaicDrawingSource
        }

        let source = ImageMosaicDrawingSource(sourceImage: image, imageSize: image.size)
        mosaicDrawingSource = source
        return source
    }

    private static let annotationLineWidths: [CGFloat] = [1, 2, 4, 8, 12, 16, 24]
    private static let textFontSizes: [CGFloat] = [12, 14, 16, 18, 22, 28, 36, 48, 64, 80, 96]
}

enum ImageAnnotationCanvasToolContext: Equatable {
    case tool(ImageAnnotationTool)
    case shape(ImageAnnotationShapeKind)
    case mosaic(ImageAnnotationMosaicMode)

    init(elementKind: ImageAnnotationElementKind) {
        switch elementKind {
        case let .shape(shapeKind):
            self = .shape(shapeKind)
        case .brush:
            self = .tool(.brush)
        case .text:
            self = .tool(.text)
        case let .mosaic(mosaicMode):
            self = .mosaic(mosaicMode)
        case .highlight:
            self = .tool(.highlight)
        case .counter, .spotlight, .image:
            self = .tool(.select)
        }
    }
}

enum ImageWorkspaceStamp {
    case counter, spotlight
}

private enum AnnotationInteraction {
    case creatingSpotlight(start: CGPoint, current: CGPoint)
    case editingEndpoint(Int, hasStartedMutation: Bool)
    case creatingShape(start: CGPoint, current: CGPoint)
    case creatingMosaic(start: CGPoint, current: CGPoint)
    case drawingPoints(kind: ImageAnnotationElementKind, points: [CGPoint])
    case moving(lastPoint: CGPoint, hasStartedMutation: Bool)
    case resizing(anchor: CGPoint, hasStartedMutation: Bool)
    case pendingCreation(start: CGPoint)

    var requiresMosaicRendering: Bool {
        switch self {
        case .creatingMosaic:
            return true
        case let .drawingPoints(kind, _):
            if case .mosaic = kind {
                return true
            }

            return false
        case .creatingShape, .creatingSpotlight, .editingEndpoint, .moving, .resizing, .pendingCreation:
            return false
        }
    }
}

private final class ImageAnnotationTextEditorView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        if event.keyCode == 36, event.modifierFlags.contains(.command) {
            onCommit?()
            return
        }

        super.keyDown(with: event)
    }
}

enum ImageAnnotationViewRenderer {
    static func draw(
        document: ImageAnnotationDocument,
        mosaicSource: ImageMosaicDrawingSource? = nil,
        imageSize: CGSize = .zero,
        excluding excludedElementID: UUID? = nil
    ) {
        for element in document.elements {
            if element.id == excludedElementID || element.kind == .mosaic(.redact) {
                continue
            }
            draw(element, mosaicSource: mosaicSource, imageSize: imageSize)
        }
        for element in document.elements where element.kind == .mosaic(.redact) {
            draw(element, mosaicSource: mosaicSource, imageSize: imageSize)
        }
    }

    static func draw(
        _ element: ImageAnnotationElement,
        mosaicSource: ImageMosaicDrawingSource? = nil,
        imageSize: CGSize = .zero
    ) {
        switch element.kind {
        case let .shape(kind):
            drawShape(element, kind: kind)
        case .brush:
            drawStroke(element.points, style: element.style, alpha: 1)
        case let .text(text):
            drawWithOrientation(of: element) { bounds in
                ImageAnnotationTextStyle.draw(text, in: bounds, style: element.style)
            }
        case let .counter(number):
            let shape = NSBezierPath(ovalIn: element.bounds)
            element.style.strokeColor.nsColor.setFill()
            shape.fill()
            var labelStyle = element.style
            labelStyle.strokeColor = .white
            labelStyle.fillColor = nil
            labelStyle.fontWeight = .bold
            labelStyle.fontSize = max(8, element.bounds.height * 0.5)
            labelStyle.textAlignment = .center
            let rect = element.bounds.insetBy(dx: 0, dy: element.bounds.height * 0.17)
            ImageAnnotationTextStyle.draw(String(number), in: rect, style: labelStyle)
        case .spotlight:
            let shade = NSBezierPath(rect: CGRect(origin: .zero, size: imageSize))
            shade.appendRect(element.bounds)
            shade.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.56).setFill()
            shade.fill()
        case let .image(data):
            drawWithOrientation(of: element) { bounds in
                NSImage(data: data)?.draw(in: bounds)
            }
        case let .mosaic(mode):
            ImageMosaicDrawing.draw(
                element,
                mode: mode,
                source: mosaicSource,
                imageSize: imageSize
            )
        case .highlight:
            drawStroke(element.points, style: element.style, alpha: 0.42)
        }
    }

    private static func drawShape(_ element: ImageAnnotationElement, kind: ImageAnnotationShapeKind) {
        ImageAnnotationShapeDrawing.draw(element, kind: kind)
    }

    private static func drawStroke(_ points: [CGPoint], style: ImageAnnotationStyle, alpha: Double) {
        guard let first = points.first else {
            return
        }

        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = max(1, style.lineWidth)
        path.move(to: first)
        for point in points.dropFirst() {
            path.line(to: point)
        }
        style.strokeColor.withAlpha(style.strokeColor.alpha * alpha).nsColor.setStroke()
        path.stroke()
    }

    private static func drawWithOrientation(of element: ImageAnnotationElement, draw: (CGRect) -> Void) {
        guard let orientation = element.contentOrientation, orientation.count == 4 else {
            draw(element.bounds)
            return
        }
        let bounds = element.bounds
        let swapsAxes = orientation[1] != 0
        let width = swapsAxes ? bounds.height : bounds.width
        let height = swapsAxes ? bounds.width : bounds.height
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.concatenate(CGAffineTransform(
            a: orientation[0], b: orientation[1], c: orientation[2], d: orientation[3],
            tx: bounds.midX, ty: bounds.midY
        ))
        draw(CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension ImageAnnotationColor {
    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
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


private extension ImageAnnotationTool {
    func acceptsEditing(kind: ImageAnnotationElementKind) -> Bool {
        switch (self, kind) {
        case (.select, _), (.shape, .shape), (.text, .text), (.brush, .brush), (.highlight, .highlight), (.mosaic, .mosaic):
            true
        default:
            false
        }
    }
}


private extension ImageAnnotationElement {
    var contentSwapsAxes: Bool {
        guard let orientation = contentOrientation, orientation.count == 4 else { return false }
        return orientation[1] != 0
    }
}

private extension CGRect {
    func swappingSizeAxes(if shouldSwap: Bool) -> CGRect {
        shouldSwap ? CGRect(x: minX, y: minY, width: height, height: width) : self
    }
}
