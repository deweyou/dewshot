import CoreGraphics
import Foundation

public enum ImageAnnotationTool: CaseIterable, Sendable, Equatable {
    case select
    case shape
    case brush
    case text
    case mosaic
    case highlight
}

public enum ImageAnnotationShapeKind: Codable, CaseIterable, Sendable, Equatable {
    case rectangle
    case ellipse
    case line
    case arrow
}

public enum ImageAnnotationMosaicMode: Codable, CaseIterable, Sendable, Equatable {
    case rectangle
    case brush
    case blur
    case redact
}

public enum ImageAnnotationFontWeight: Codable, Sendable, Equatable {
    case regular
    case bold
}

public struct ImageAnnotationColor: Codable, Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = ImageAnnotationColor(red: 1, green: 0.231, blue: 0.188)
    public static let yellow = ImageAnnotationColor(red: 1, green: 0.8, blue: 0)
    public static let blue = ImageAnnotationColor(red: 0.039, green: 0.518, blue: 1)
    public static let green = ImageAnnotationColor(red: 0.204, green: 0.78, blue: 0.349)
    public static let white = ImageAnnotationColor(red: 1, green: 1, blue: 1)
    public static let black = ImageAnnotationColor(red: 0, green: 0, blue: 0)

    public func withAlpha(_ alpha: Double) -> ImageAnnotationColor {
        ImageAnnotationColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

public enum ImageAnnotationTextAlignment: String, Codable, Sendable, Equatable {
    case left, center, right
}

public enum ImageAnnotationLinePattern: String, CaseIterable, Codable, Sendable {
    case solid, dashed, dotted
}

public enum ImageAnnotationArrowStyle: String, CaseIterable, Codable, Sendable {
    case wedge, open, doubleHeaded
}

public struct ImageAnnotationStyle: Codable, Sendable, Equatable {
    public var strokeColor: ImageAnnotationColor
    public var fillColor: ImageAnnotationColor?
    public var lineWidth: CGFloat
    public var fontSize: CGFloat
    public var fontWeight: ImageAnnotationFontWeight
    public var mosaicBlockSize: CGFloat
    public var mosaicStrength: CGFloat
    public var mosaicBrushWidth: CGFloat?
    public var textAlignment: ImageAnnotationTextAlignment
    public var textBoxWidth: CGFloat?
    public var fontName: String?
    public var linePattern: ImageAnnotationLinePattern?
    public var arrowStyle: ImageAnnotationArrowStyle?
    public var textOutline: ImageAnnotationColor?

    public init(
        strokeColor: ImageAnnotationColor,
        fillColor: ImageAnnotationColor? = nil,
        lineWidth: CGFloat,
        fontSize: CGFloat,
        fontWeight: ImageAnnotationFontWeight,
        mosaicBlockSize: CGFloat,
        mosaicStrength: CGFloat,
        mosaicBrushWidth: CGFloat? = nil,
        textAlignment: ImageAnnotationTextAlignment = .left,
        textBoxWidth: CGFloat? = nil,
        fontName: String? = nil
    ) {
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.mosaicBlockSize = mosaicBlockSize
        self.mosaicStrength = mosaicStrength
        self.mosaicBrushWidth = mosaicBrushWidth
        self.textAlignment = textAlignment
        self.textBoxWidth = textBoxWidth
        self.fontName = fontName
    }

    public static let `default` = ImageAnnotationStyle(
        strokeColor: .red,
        fillColor: nil,
        lineWidth: 4,
        fontSize: 16,
        fontWeight: .regular,
        mosaicBlockSize: 20,
        mosaicStrength: 0.82
    )
}

public enum ImageAnnotationElementKind: Codable, Sendable, Equatable {
    case shape(ImageAnnotationShapeKind)
    case brush
    case text(String)
    case mosaic(ImageAnnotationMosaicMode)
    case highlight
    case counter(Int)
    case spotlight
    case image(Data)
}

public struct ImageAnnotationElement: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var kind: ImageAnnotationElementKind
    public var bounds: CGRect
    public var points: [CGPoint]
    public var style: ImageAnnotationStyle
    public var contentOrientation: [CGFloat]?

    public init(
        id: UUID = UUID(),
        kind: ImageAnnotationElementKind,
        bounds: CGRect,
        points: [CGPoint] = [],
        style: ImageAnnotationStyle,
        contentOrientation: [CGFloat]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.bounds = bounds.standardized
        self.points = points
        self.style = style
        self.contentOrientation = contentOrientation
    }
}

public struct ImageAnnotationEditingOptions: Sendable, Equatable {
    public var shapeKind: ImageAnnotationShapeKind
    public var mosaicMode: ImageAnnotationMosaicMode
    public var style: ImageAnnotationStyle

    public init(
        shapeKind: ImageAnnotationShapeKind = .rectangle,
        mosaicMode: ImageAnnotationMosaicMode = .rectangle,
        style: ImageAnnotationStyle = .default,
        contentOrientation: [CGFloat]? = nil
    ) {
        self.shapeKind = shapeKind
        self.mosaicMode = mosaicMode
        self.style = style
    }
}

public struct ImageAnnotationDocument: Sendable, Equatable {
    public private(set) var elements: [ImageAnnotationElement]
    public private(set) var selectedElementID: UUID?
    public private(set) var selectedTool: ImageAnnotationTool
    public private(set) var editingOptions: ImageAnnotationEditingOptions
    public private(set) var editedImagePNG: Data?
    public private(set) var editedImageSize: CGSize?
    private var savedElements: [ImageAnnotationElement]
    private var savedImagePNG: Data?
    private var initialEdits: Bool

    public var hasUncommittedEdits: Bool {
        initialEdits || elements != savedElements || editedImagePNG != savedImagePNG
    }

    private var undoStack: [ImageAnnotationSnapshot]
    private var redoStack: [ImageAnnotationSnapshot]

    public init(
        elements: [ImageAnnotationElement] = [],
        selectedElementID: UUID? = nil,
        selectedTool: ImageAnnotationTool = .select,
        editingOptions: ImageAnnotationEditingOptions = ImageAnnotationEditingOptions(),
        hasUncommittedEdits: Bool = false,
        editedImagePNG: Data? = nil,
        editedImageSize: CGSize? = nil
    ) {
        self.elements = elements
        self.selectedElementID = selectedElementID
        self.selectedTool = selectedTool
        self.editingOptions = editingOptions
        self.initialEdits = hasUncommittedEdits
        self.editedImagePNG = editedImagePNG
        self.editedImageSize = editedImageSize
        savedElements = elements
        savedImagePNG = editedImagePNG
        undoStack = []
        redoStack = []
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    public mutating func selectTool(_ tool: ImageAnnotationTool) {
        selectedTool = tool
    }

    public mutating func setShapeKind(_ shapeKind: ImageAnnotationShapeKind) {
        editingOptions.shapeKind = shapeKind
    }

    public mutating func setMosaicMode(_ mosaicMode: ImageAnnotationMosaicMode) {
        editingOptions.mosaicMode = mosaicMode
    }

    public mutating func setStyle(_ style: ImageAnnotationStyle) {
        editingOptions.style = style
    }

    public mutating func add(_ element: ImageAnnotationElement) {
        pushUndoSnapshot()
        elements.append(element)
        selectedElementID = element.id
    }

    public mutating func selectElement(id: UUID?) {
        selectedElementID = id
    }

    public mutating func selectTopmostElement(at point: CGPoint, tolerance: CGFloat = 4) {
        selectedElementID = topmostElementID(at: point, tolerance: tolerance)
    }

    public func topmostElementID(at point: CGPoint, tolerance: CGFloat = 4) -> UUID? {
        elements.reversed().first { element in
            element.contains(point, tolerance: tolerance)
        }?.id
    }

    public mutating func beginEditingSelectedElement() {
        guard selectedIndex != nil else {
            return
        }

        pushUndoSnapshot()
    }

    public mutating func moveSelected(by delta: CGSize, recordingUndo: Bool = true) {
        guard let selectedIndex else {
            return
        }

        if recordingUndo {
            pushUndoSnapshot()
        }
        elements[selectedIndex].bounds = elements[selectedIndex].bounds.offsetBy(dx: delta.width, dy: delta.height)
        elements[selectedIndex].points = elements[selectedIndex].points.map {
            CGPoint(x: $0.x + delta.width, y: $0.y + delta.height)
        }
    }

    public mutating func resizeSelected(to bounds: CGRect, recordingUndo: Bool = true) {
        guard let selectedIndex else {
            return
        }

        if recordingUndo {
            pushUndoSnapshot()
        }
        let oldBounds = elements[selectedIndex].bounds
        let newBounds = bounds.standardized
        let scaleX = newBounds.width / max(oldBounds.width, 1)
        let scaleY = newBounds.height / max(oldBounds.height, 1)
        elements[selectedIndex].points = elements[selectedIndex].points.map {
            CGPoint(x: newBounds.minX + ($0.x - oldBounds.minX) * scaleX,
                    y: newBounds.minY + ($0.y - oldBounds.minY) * scaleY)
        }
        elements[selectedIndex].bounds = newBounds
    }

    public mutating func moveSelectedEndpoint(_ endpoint: Int, to point: CGPoint, recordingUndo: Bool = true) {
        guard let selectedIndex, elements[selectedIndex].points.indices.contains(endpoint) else { return }
        if recordingUndo { pushUndoSnapshot() }
        elements[selectedIndex].points[endpoint] = point
        let points = elements[selectedIndex].points
        let x = points.map(\.x)
        let y = points.map(\.y)
        let minX = x.min() ?? point.x
        let minY = y.min() ?? point.y
        elements[selectedIndex].bounds = CGRect(
            x: minX, y: minY,
            width: max(2, (x.max() ?? point.x) - minX),
            height: max(2, (y.max() ?? point.y) - minY)
        )
    }

    public mutating func applyImageEdit(_ pngData: Data, size: CGSize, transform: CGAffineTransform, styleScale: CGFloat = 1) {
        pushUndoSnapshot()
        editedImagePNG = pngData
        editedImageSize = size
        for index in elements.indices {
            elements[index].bounds = elements[index].bounds.applying(transform).standardized
            elements[index].points = elements[index].points.map { $0.applying(transform) }
            if transform.b != 0 || transform.c != 0 || transform.a < 0 || transform.d < 0 {
                var a: CGFloat = 1, b: CGFloat = 0, c: CGFloat = 0, d: CGFloat = 1
                if let orientation = elements[index].contentOrientation, orientation.count == 4 {
                    (a, b, c, d) = (orientation[0], orientation[1], orientation[2], orientation[3])
                }
                let matrix = CGAffineTransform(a: a, b: b, c: c, d: d, tx: 0, ty: 0)
                    .concatenating(CGAffineTransform(a: transform.a, b: transform.b, c: transform.c, d: transform.d, tx: 0, ty: 0))
                elements[index].contentOrientation = [matrix.a, matrix.b, matrix.c, matrix.d]
            }
            elements[index].style.lineWidth *= styleScale
            elements[index].style.fontSize *= styleScale
            elements[index].style.mosaicBlockSize *= styleScale
            if let width = elements[index].style.mosaicBrushWidth { elements[index].style.mosaicBrushWidth = width * styleScale }
            if let width = elements[index].style.textBoxWidth {
                elements[index].style.textBoxWidth = width * styleScale
            }
        }
    }

    public mutating func duplicateSelected() {
        guard let selectedIndex else { return }
        let element = elements[selectedIndex]
        add(ImageAnnotationElement(
            kind: element.kind,
            bounds: element.bounds.offsetBy(dx: 12, dy: -12),
            points: element.points.map { CGPoint(x: $0.x + 12, y: $0.y - 12) },
            style: element.style,
            contentOrientation: element.contentOrientation
        ))
    }

    public mutating func reorderSelected(forward: Bool) {
        guard let selectedIndex else { return }
        let destination = forward ? elements.count - 1 : 0
        guard destination != selectedIndex else { return }
        pushUndoSnapshot()
        let element = elements.remove(at: selectedIndex)
        elements.insert(element, at: destination)
    }

    public mutating func replaceSelectedText(_ text: String) {
        guard let selectedIndex,
              case .text = elements[selectedIndex].kind else {
            return
        }

        pushUndoSnapshot()
        elements[selectedIndex].kind = .text(text)
    }

    public mutating func updateSelectedText(_ text: String, bounds: CGRect, recordingUndo: Bool = true) {
        guard let selectedIndex,
              case .text = elements[selectedIndex].kind else {
            return
        }

        if recordingUndo {
            pushUndoSnapshot()
        }
        elements[selectedIndex].kind = .text(text)
        elements[selectedIndex].bounds = bounds.standardized
    }

    public mutating func updateSelectedStyle(
        _ style: ImageAnnotationStyle,
        bounds: CGRect? = nil,
        recordingUndo: Bool = true
    ) {
        guard let selectedIndex else {
            return
        }

        if recordingUndo {
            pushUndoSnapshot()
        }
        editingOptions.style = style
        elements[selectedIndex].style = style
        if let bounds {
            elements[selectedIndex].bounds = bounds.standardized
        }
    }

    public mutating func deleteSelected() {
        guard let selectedElementID,
              elements.contains(where: { $0.id == selectedElementID }) else {
            return
        }

        pushUndoSnapshot()
        elements.removeAll { $0.id == selectedElementID }
        self.selectedElementID = nil
    }

    public mutating func undo() {
        guard let snapshot = undoStack.popLast() else {
            return
        }

        redoStack.append(currentSnapshot)
        restore(snapshot)
    }

    public mutating func redo() {
        guard let snapshot = redoStack.popLast() else {
            return
        }

        undoStack.append(currentSnapshot)
        restore(snapshot)
    }

    public mutating func markCurrentRenditionSaved() {
        savedElements = elements
        savedImagePNG = editedImagePNG
        initialEdits = false
    }

    private var selectedIndex: Int? {
        guard let selectedElementID else {
            return nil
        }

        return elements.firstIndex { $0.id == selectedElementID }
    }

    private var currentSnapshot: ImageAnnotationSnapshot {
        ImageAnnotationSnapshot(
            elements: elements,
            selectedElementID: selectedElementID,
            editedImagePNG: editedImagePNG,
            editedImageSize: editedImageSize
        )
    }

    private mutating func pushUndoSnapshot() {
        undoStack.append(currentSnapshot)
        redoStack.removeAll()
    }

    private mutating func restore(_ snapshot: ImageAnnotationSnapshot) {
        elements = snapshot.elements
        selectedElementID = snapshot.selectedElementID
        editedImagePNG = snapshot.editedImagePNG
        editedImageSize = snapshot.editedImageSize
    }
}

private struct ImageAnnotationSnapshot: Sendable, Equatable {
    let elements: [ImageAnnotationElement]
    let selectedElementID: UUID?
    let editedImagePNG: Data?
    let editedImageSize: CGSize?
}

private extension ImageAnnotationElement {
    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch kind {
        case let .shape(shapeKind):
            if shapeKind == .line || shapeKind == .arrow {
                let start = points.first ?? bounds.origin
                let end = points.last ?? CGPoint(x: bounds.maxX, y: bounds.maxY)
                let dx = end.x - start.x
                let dy = end.y - start.y
                let lengthSquared = max(1, dx * dx + dy * dy)
                let progress = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
                let closest = CGPoint(x: start.x + dx * progress, y: start.y + dy * progress)
                return closest.distance(to: point) <= max(tolerance, style.lineWidth * (shapeKind == .arrow ? 2 : 0.5))

            }

            let margin = max(tolerance, style.lineWidth / 2)
            if shapeKind == .ellipse {
                let radiusX = max(1, bounds.width / 2)
                let radiusY = max(1, bounds.height / 2)
                let dx = point.x - bounds.midX
                let dy = point.y - bounds.midY
                let outer = hypot(dx / (radiusX + margin), dy / (radiusY + margin))
                let inner = hypot(dx / max(1, radiusX - margin), dy / max(1, radiusY - margin))
                return outer <= 1 && (style.fillColor != nil || inner >= 1)
            }
            return bounds.insetBy(dx: -margin, dy: -margin).contains(point)
                && (style.fillColor != nil || !bounds.insetBy(dx: margin, dy: margin).contains(point))
        case .brush, .highlight:
            let hitRadius = max(tolerance, style.lineWidth / 2)
            return points.contains { $0.distance(to: point) <= hitRadius }
                || bounds.insetBy(dx: -hitRadius, dy: -hitRadius).contains(point)
        case .text, .mosaic, .counter, .spotlight, .image:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        hypot(x - point.x, y - point.y)
    }
}
