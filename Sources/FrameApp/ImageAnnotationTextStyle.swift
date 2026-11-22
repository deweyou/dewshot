import AppKit
import FrameCore

enum ImageAnnotationTextStyle {
    static let minimumBoundsSize = CGSize(width: 80, height: 24)

    static func font(for style: ImageAnnotationStyle, scale: CGFloat = 1) -> NSFont {
        let size = pointSize(for: style, scale: scale)
        if let name = style.fontName, let font = NSFont(name: name, size: size) {
            return style.fontWeight == .bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        }
        return NSFont.systemFont(
            ofSize: size,
            weight: style.fontWeight == .bold ? .bold : .regular
        )
    }

    static func attributes(for style: ImageAnnotationStyle, scale: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment(for: style)
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .paragraphStyle: paragraph,
            .font: font(for: style, scale: scale),
            .foregroundColor: foregroundColor(for: style),
        ]
    }

    static func alignment(for style: ImageAnnotationStyle) -> NSTextAlignment {
        switch style.textAlignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }

    static func draw(_ text: String, in bounds: CGRect, style: ImageAnnotationStyle) {
        guard !text.isEmpty else { return }
        if let background = style.fillColor {
            background.nsColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: -4, dy: -2), xRadius: 4, yRadius: 4).fill()
        }
        var textAttributes = attributes(for: style)
        if let outline = style.textOutline {
            textAttributes[.strokeColor] = outline.nsColor
            textAttributes[.strokeWidth] = -4
        }
        (text as NSString).draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: textAttributes, context: nil)
    }

    static func pointSize(for style: ImageAnnotationStyle, scale: CGFloat = 1) -> CGFloat {
        max(1, max(8, style.fontSize) * scale)
    }

    static func foregroundColor(for style: ImageAnnotationStyle) -> NSColor {
        style.strokeColor.nsColor
    }

    static func bounds(for text: String, origin: CGPoint, style: ImageAnnotationStyle) -> CGRect {
        let measuredText = text.isEmpty ? " " : text
        let boxWidth = style.textBoxWidth.map { max(40, $0) }
        let textBounds = (measuredText as NSString).boundingRect(
            with: CGSize(width: boxWidth ?? CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(for: style),
            context: nil
        )
        let font = font(for: style)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: boxWidth ?? max(minimumBoundsSize.width, ceil(textBounds.width)),
            height: max(minimumBoundsSize.height, ceil(textBounds.height), lineHeight)
        )
    }
}
