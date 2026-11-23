import AppKit
import CoreImage
import FrameCore
import ImageIO
import UniformTypeIdentifiers
import Vision

enum ImageWorkspaceRasterOperation {
    case crop(CGRect)
    case resize(width: Int, height: Int)
    case rotate(clockwise: Bool)
    case flip(horizontal: Bool)
    case adjust(exposure: Double, contrast: Double, saturation: Double)
    case extend(padding: Int, color: NSColor)
    case removeBackground
}

struct ImageWorkspaceProject: Codable {
    let imagePNG: Data
    let imageSize: CGSize
    let elements: [ImageAnnotationElement]

    @MainActor func screenshot() throws -> CapturedScreenshot {
        try ImageWorkspaceRaster.screenshot(data: imagePNG, size: imageSize)
    }
}

@MainActor
enum ImageWorkspaceRaster {
    private static let context = CIContext()
    static let maximumPixelCount = 100_000_000

    static func screenshot(data: Data, id: UUID = UUID(), size: CGSize? = nil, origin: CGPoint = .zero) throws -> CapturedScreenshot {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              validSize(width, height),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
              ] as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let logicalSize = size ?? CGSize(width: cgImage.width, height: cgImage.height)
        guard logicalSize.width.isFinite, logicalSize.height.isFinite, logicalSize.width > 0, logicalSize.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        bitmap.size = logicalSize
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return CapturedScreenshot(id: id, pngData: png, image: NSImage(cgImage: cgImage, size: logicalSize),
                                  rect: CGRect(origin: origin, size: logicalSize))
    }

    static func pasteboardImage(_ pasteboard: NSPasteboard) throws -> CapturedScreenshot {
        if let png = pasteboard.data(forType: .png) {
            return try screenshot(data: png)
        }
        if let tiff = pasteboard.data(forType: .tiff) ?? NSImage(pasteboard: pasteboard)?.tiffRepresentation {
            return try screenshot(data: tiff)
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    static func project(at url: URL) throws -> ImageWorkspaceProject {
        let project = try JSONDecoder().decode(ImageWorkspaceProject.self, from: Data(contentsOf: url))
        guard project.elements.count <= 10_000, project.elements.allSatisfy({ !$0.bounds.isNull && !$0.bounds.isInfinite }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return project
    }

    static func pixelSize(_ image: NSImage) -> CGSize {
        guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image.size }
        return CGSize(width: pixels.width, height: pixels.height)
    }

    static func cropPixelRect(_ bounds: CGRect, logicalSize: CGSize, pixelSize: CGSize) -> CGRect {
        let scaleX = pixelSize.width / logicalSize.width
        let scaleY = pixelSize.height / logicalSize.height
        let rounded = CGRect(x: (bounds.minX * scaleX).rounded(), y: (bounds.minY * scaleY).rounded(),
                             width: (bounds.width * scaleX).rounded(), height: (bounds.height * scaleY).rounded())
        return rounded.intersection(CGRect(origin: .zero, size: pixelSize))
    }

    static func validSize(_ width: Int, _ height: Int) -> Bool {
        width > 0 && height > 0 && width <= maximumPixelCount / height
    }

    static func apply(_ operation: ImageWorkspaceRasterOperation, to screenshot: CapturedScreenshot)
        throws -> (screenshot: CapturedScreenshot, annotationTransform: CGAffineTransform, styleScale: CGFloat) {
        guard let pixels = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              validSize(pixels.width, pixels.height) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let image = CIImage(cgImage: pixels)
        let size = screenshot.image.size
        let densityX = image.extent.width / size.width
        let densityY = image.extent.height / size.height
        var result = image
        var transform = CGAffineTransform.identity
        var outputSize = size
        var styleScale: CGFloat = 1
        switch operation {
        case let .crop(bounds):
            let pixelRect = Self.cropPixelRect(bounds, logicalSize: size, pixelSize: image.extent.size)
            guard pixelRect.width >= 1, pixelRect.height >= 1 else { throw CocoaError(.fileWriteUnknown) }
            result = image.cropped(to: pixelRect)
            transform = CGAffineTransform(translationX: -pixelRect.minX / densityX, y: -pixelRect.minY / densityY)
            outputSize = CGSize(width: pixelRect.width / densityX, height: pixelRect.height / densityY)
        case let .resize(width, height):
            guard validSize(width, height) else { throw CocoaError(.fileWriteUnknown) }
            let scaleX = CGFloat(width) / image.extent.width
            let scaleY = CGFloat(height) / image.extent.height
            result = image.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scaleY, kCIInputAspectRatioKey: scaleX / scaleY,
            ]).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
            transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            outputSize = size.applying(transform)
            styleScale = min(scaleX, scaleY)
        case let .rotate(clockwise):
            result = image.oriented(clockwise ? .right : .left)
            outputSize = CGSize(width: size.height, height: size.width)
            transform = clockwise
                ? CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: size.width)
                : CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.height, ty: 0)
        case let .flip(horizontal):
            result = image.oriented(horizontal ? .upMirrored : .downMirrored)
            transform = horizontal
                ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: size.width, ty: 0)
                : CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        case let .adjust(exposure, contrast, saturation):
            result = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: contrast, kCIInputSaturationKey: saturation,
                ])
        case .removeBackground:
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: pixels)
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                throw ImageWorkspaceRasterError.foregroundUnavailable
            }
            let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
            let transparent = CIImage(color: .clear).cropped(to: image.extent)
            result = image.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: transparent,
                kCIInputMaskImageKey: CIImage(cvPixelBuffer: mask),
            ]).cropped(to: image.extent)
        case let .extend(padding, color):
            let width = pixels.width + padding * 2
            let height = pixels.height + padding * 2
            guard padding >= 0, validSize(width, height), let rgb = color.usingColorSpace(.deviceRGB) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let extent = CGRect(x: 0, y: 0, width: width, height: height)
            let background = CIImage(color: CIColor(
                red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent
            )).cropped(to: extent)
            result = image.transformed(by: CGAffineTransform(translationX: CGFloat(padding), y: CGFloat(padding)))
                .composited(over: background)
            transform = CGAffineTransform(translationX: CGFloat(padding) / densityX, y: CGFloat(padding) / densityY)
            outputSize = CGSize(width: extent.width / densityX, height: extent.height / densityY)
        }

        guard let rendered = context.createCGImage(result, from: result.extent.integral) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let bitmap = NSBitmapImageRep(cgImage: rendered)
        bitmap.size = outputSize
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        return (
            CapturedScreenshot(id: screenshot.id, pngData: png, image: NSImage(cgImage: rendered, size: outputSize),
                               rect: CGRect(origin: screenshot.rect.origin, size: outputSize)),
            transform,
            styleScale
        )
    }

    static func export(_ screenshot: CapturedScreenshot, to url: URL, type: UTType, quality: Double) throws {
        if type == .png {
            try screenshot.pngData.write(to: url, options: .atomic)
            return
        }

        guard let image = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let pixels: CGImage
        if type == .jpeg {
            let source = CIImage(cgImage: image)
            let white = CIImage(color: .white).cropped(to: source.extent)
            guard let flattened = context.createCGImage(source.composited(over: white), from: source.extent) else {
                throw CocoaError(.fileWriteUnknown)
            }
            pixels = flattened
        } else {
            pixels = image
        }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, pixels, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try (encoded as Data).write(to: url, options: .atomic)
    }
}


private enum ImageWorkspaceRasterError: LocalizedError {
    case foregroundUnavailable

    var errorDescription: String? {
        AppStrings.current().editorLabel("没有识别到可保留的主体。", "dewShot couldn’t identify a foreground subject.")
    }
}
