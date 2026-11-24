import AppKit
import CoreImage
import FrameCore

@MainActor
struct ImageAnnotationRenderer {
    func render(
        screenshot: CapturedScreenshot,
        document: ImageAnnotationDocument,
        preservingID: Bool
    ) throws -> CapturedScreenshot {
        guard !document.elements.isEmpty else {
            return preservingID ? screenshot : CapturedScreenshot(
                pngData: screenshot.pngData,
                image: screenshot.image,
                rect: screenshot.rect
            )
        }

        let imageSize = screenshot.image.size.width > 0 && screenshot.image.size.height > 0
            ? screenshot.image.size
            : screenshot.rect.size
        let pixelSize = ImageWorkspaceRaster.pixelSize(screenshot.image)
        guard ImageWorkspaceRaster.validSize(Int(pixelSize.width), Int(pixelSize.height)),
              let graphics = CGContext(data: nil, width: Int(pixelSize.width), height: Int(pixelSize.height),
                                       bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ImageAnnotationRendererError.pngEncodingFailed
        }
        let mosaicSource = document.containsMosaicElements
            ? ImageMosaicDrawingSource(sourceImage: screenshot.image, imageSize: imageSize)
            : nil

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(cgContext: graphics, flipped: false)
        NSGraphicsContext.current = context
        graphics.scaleBy(x: pixelSize.width / imageSize.width, y: pixelSize.height / imageSize.height)
        context.imageInterpolation = .high
        screenshot.image.draw(in: CGRect(origin: .zero, size: imageSize), from: .zero, operation: .sourceOver, fraction: 1)
        ImageAnnotationViewRenderer.draw(document: document, mosaicSource: mosaicSource, imageSize: imageSize)
        NSGraphicsContext.restoreGraphicsState()

        guard let image = graphics.makeImage() else {
            throw ImageAnnotationRendererError.pngEncodingFailed
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = imageSize
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageAnnotationRendererError.pngEncodingFailed
        }

        return CapturedScreenshot(
            id: preservingID ? screenshot.id : UUID(),
            exportFilename: preservingID ? screenshot.exportFilename : ScreenshotNaming().filename(),
            pngData: pngData,
            image: NSImage(cgImage: image, size: imageSize), rect: screenshot.rect
        )
    }
}

extension ImageAnnotationDocument {
    var containsMosaicElements: Bool {
        elements.contains { element in
            if case .mosaic = element.kind {
                return true
            }

            return false
        }
    }
}

final class ImageMosaicDrawingSource {
    private let sourceImage: NSImage
    private let imageSize: CGSize
    private var sourcePixels: ImageMosaicPixelBuffer?
    private var blurredImagesByRadius: [Int: NSImage] = [:]
    private var pixelatedImagesByBlockSize: [Int: NSImage] = [:]

    init(sourceImage: NSImage, imageSize: CGSize) {
        self.sourceImage = sourceImage
        self.imageSize = imageSize
    }

    func pixelatedImage(blockSize: CGFloat) -> NSImage? {
        let blockDimension = max(4, Int(blockSize.rounded(.toNearestOrAwayFromZero)))
        if let cachedImage = pixelatedImagesByBlockSize[blockDimension] {
            return cachedImage
        }

        guard let pixels = sourcePixelBuffer() else {
            return nil
        }

        guard let pixelatedImage = makePixelatedImage(from: pixels, blockDimension: blockDimension) else {
            return nil
        }
        pixelatedImagesByBlockSize[blockDimension] = pixelatedImage
        return pixelatedImage
    }

    func blurredImage(radius: CGFloat) -> NSImage? {
        let key = max(2, Int(radius.rounded()))
        if let image = blurredImagesByRadius[key] { return image }
        guard let pixels = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: pixels)
        let blur = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: CGFloat(key) * input.extent.width / max(1, imageSize.width),
        ])
        guard let output = Self.blurContext.createCGImage(blur, from: input.extent) else { return nil }
        let image = NSImage(cgImage: output, size: imageSize)
        blurredImagesByRadius[key] = image
        return image
    }

    private static let blurContext = CIContext()

    private func sourcePixelBuffer() -> ImageMosaicPixelBuffer? {
        if let sourcePixels {
            return sourcePixels
        }

        guard imageSize.width > 0, imageSize.height > 0 else {
            return nil
        }

        let width = max(1, Int(ceil(imageSize.width)))
        let height = max(1, Int(ceil(imageSize.height)))
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = ImageMosaicPixelBuffer.bitmapInfo
        var proposedRect = CGRect(origin: .zero, size: imageSize)

        guard let cgImage = sourceImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let didDraw = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo.rawValue
                  ) else {
                return false
            }

            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard didDraw else {
            return nil
        }

        let pixelBuffer = ImageMosaicPixelBuffer(
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            pixels: pixels
        )
        sourcePixels = pixelBuffer
        return pixelBuffer
    }

    private func makePixelatedImage(from source: ImageMosaicPixelBuffer, blockDimension: Int) -> NSImage? {
        var outputPixels = [UInt8](repeating: 0, count: source.height * source.bytesPerRow)

        var blockY = 0
        while blockY < source.height {
            var blockX = 0
            let blockHeight = min(blockDimension, source.height - blockY)

            while blockX < source.width {
                let blockWidth = min(blockDimension, source.width - blockX)
                let average = averagePixel(
                    in: CGRect(x: blockX, y: blockY, width: blockWidth, height: blockHeight),
                    source: source
                )
                fill(
                    CGRect(x: blockX, y: blockY, width: blockWidth, height: blockHeight),
                    in: &outputPixels,
                    bytesPerRow: source.bytesPerRow,
                    average: average
                )
                blockX += blockDimension
            }

            blockY += blockDimension
        }

        let data = Data(outputPixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: source.width,
                height: source.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: source.bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: ImageMosaicPixelBuffer.bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: imageSize)
    }

    private func averagePixel(in rect: CGRect, source: ImageMosaicPixelBuffer) -> ImageMosaicAveragePixel {
        let minX = Int(rect.minX)
        let minY = Int(rect.minY)
        let maxX = Int(rect.maxX)
        let maxY = Int(rect.maxY)
        var red: UInt64 = 0
        var green: UInt64 = 0
        var blue: UInt64 = 0
        var alpha: UInt64 = 0
        var count: UInt64 = 0

        for y in minY..<maxY {
            var offset = y * source.bytesPerRow + minX * 4
            for _ in minX..<maxX {
                red += UInt64(source.pixels[offset])
                green += UInt64(source.pixels[offset + 1])
                blue += UInt64(source.pixels[offset + 2])
                alpha += UInt64(source.pixels[offset + 3])
                count += 1
                offset += 4
            }
        }

        guard count > 0 else {
            return ImageMosaicAveragePixel(red: 0, green: 0, blue: 0, alpha: 255)
        }

        return ImageMosaicAveragePixel(
            red: UInt8(red / count),
            green: UInt8(green / count),
            blue: UInt8(blue / count),
            alpha: UInt8(alpha / count)
        )
    }

    private func fill(
        _ rect: CGRect,
        in pixels: inout [UInt8],
        bytesPerRow: Int,
        average: ImageMosaicAveragePixel
    ) {
        let minX = Int(rect.minX)
        let minY = Int(rect.minY)
        let maxX = Int(rect.maxX)
        let maxY = Int(rect.maxY)

        for y in minY..<maxY {
            var offset = y * bytesPerRow + minX * 4
            for _ in minX..<maxX {
                pixels[offset] = average.red
                pixels[offset + 1] = average.green
                pixels[offset + 2] = average.blue
                pixels[offset + 3] = average.alpha
                offset += 4
            }
        }
    }
}

private struct ImageMosaicPixelBuffer {
    static let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixels: [UInt8]
}

private struct ImageMosaicAveragePixel {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

enum ImageMosaicDrawing {
    static func draw(
        _ element: ImageAnnotationElement,
        mode: ImageAnnotationMosaicMode,
        source: ImageMosaicDrawingSource?,
        imageSize: CGSize
    ) {
        if mode == .redact {
            NSColor.black.setFill()
            element.bounds.integral.fill()
            return
        }

        let blockSize = max(4, element.style.mosaicBlockSize)
        let strength = element.style.mosaicStrength
        let blurRadius = strength <= 1 ? blockSize * strength : strength
        let transformed = mode == .blur ? source?.blurredImage(radius: blurRadius) : source?.pixelatedImage(blockSize: blockSize)
        guard let pixelatedImage = transformed else {
            return
        }

        switch mode {
        case .rectangle, .blur:
            draw(
                pixelatedImage,
                imageSize: imageSize,
                clippedTo: element.bounds.standardized
            )
        case .brush:
            draw(
                pixelatedImage,
                imageSize: imageSize,
                clippedToStrokeThrough: element.points,
                width: max(2, element.style.mosaicBrushWidth ?? max(blockSize * 2, element.style.lineWidth))
            )
        case .redact:
            break
        }
    }

    private static func draw(
        _ pixelatedImage: NSImage,
        imageSize: CGSize,
        clippedTo rect: CGRect
    ) {
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let clippedRect = rect.standardized.intersection(imageBounds)
        guard !clippedRect.isNull, !clippedRect.isEmpty else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: clippedRect).addClip()
        draw(pixelatedImage, imageSize: imageSize)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func draw(
        _ pixelatedImage: NSImage,
        imageSize: CGSize,
        clippedToStrokeThrough points: [CGPoint],
        width: CGFloat
    ) {
        guard let firstPoint = points.first else {
            return
        }

        let imageBounds = CGRect(origin: .zero, size: imageSize)
        NSGraphicsContext.saveGraphicsState()
        if points.count == 1 {
            let radius = width / 2
            let clipRect = CGRect(
                x: firstPoint.x - radius,
                y: firstPoint.y - radius,
                width: radius * 2,
                height: radius * 2
            ).intersection(imageBounds)
            guard !clipRect.isNull, !clipRect.isEmpty else {
                NSGraphicsContext.restoreGraphicsState()
                return
            }
            NSBezierPath(ovalIn: clipRect).addClip()
        } else if let context = NSGraphicsContext.current?.cgContext {
            let path = CGMutablePath()
            path.move(to: firstPoint)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.addPath(path)
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
            context.clip()
            NSBezierPath(rect: imageBounds).addClip()
        } else {
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        draw(pixelatedImage, imageSize: imageSize)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func draw(_ pixelatedImage: NSImage, imageSize: CGSize) {
        pixelatedImage.draw(
            in: CGRect(origin: .zero, size: imageSize),
            from: CGRect(origin: .zero, size: imageSize),
            operation: .copy,
            fraction: 1
        )
    }
}

enum ImageAnnotationRendererError: LocalizedError {
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .pngEncodingFailed:
            "Failed to encode the edited screenshot as PNG."
        }
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
