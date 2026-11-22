import AppKit

struct ClipboardWriter {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(image: NSImage, pngData: Data? = nil) throws {
        let item = NSPasteboardItem()
        if let pngData, pngData.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { item.setData(pngData, forType: .png) }
        if let tiff = image.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        guard !item.types.isEmpty else { throw ClipboardWriterError.writeFailed }

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw ClipboardWriterError.writeFailed
        }
    }

    func write(text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw ClipboardWriterError.writeFailed
        }
    }

    func write(fileURL: URL) throws {
        pasteboard.clearContents()
        guard pasteboard.writeObjects([fileURL as NSURL]) else {
            throw ClipboardWriterError.writeFailed
        }
    }
}

enum ClipboardWriterError: LocalizedError {
    case writeFailed

    var errorDescription: String? {
        "Failed to write to the clipboard."
    }
}
