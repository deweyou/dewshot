import AppKit
import CoreImage
import FrameCore
import UniformTypeIdentifiers

@MainActor
enum ImageWorkspaceFileDialogs {
    static let projectType = UTType(exportedAs: "dev.deweyou.frame.image-project", conformingTo: .data)
    private static let exportFormats: [(title: String, type: UTType)] = [
        ("PNG", .png), ("JPEG", .jpeg), ("HEIC", .heic), ("TIFF", .tiff),
    ]

    static func open(strings: AppStrings, window: NSWindow?, acceptsProjects: Bool = true, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = strings.editorLabel("打开图片", "Open Image")
        panel.allowedContentTypes = acceptsProjects ? [.image, projectType] : [.image]
        if let window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url { completion(url) }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    static func export(_ screenshot: CapturedScreenshot, strings: AppStrings) -> Bool {
        let panel = NSSavePanel()
        panel.title = strings.editorLabel("导出图片", "Export Image")
        panel.nameFieldStringValue = strings.editorLabel("Frame 图片", "Frame Image")
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.png]
        let format = popup(exportFormats.map(\.title))
        let quality = popup(["60%", "80%", "90%", "100%"])
        quality.selectItem(at: 2)
        quality.isEnabled = false
        let controls = form([
            (strings.editorLabel("格式", "Format"), format),
            (strings.editorLabel("质量", "Quality"), quality),
        ])
        let handler = ImageWorkspaceDialogAction {
            let type = exportFormats[format.indexOfSelectedItem].type
            panel.allowedContentTypes = [type]
            quality.isEnabled = type == .heic || type == .jpeg
        }
        format.target = handler
        format.action = #selector(ImageWorkspaceDialogAction.invoke)
        panel.accessoryView = controls
        let result = withExtendedLifetime(handler) { panel.runModal() }
        guard result == .OK, let url = panel.url else { return false }
        do {
            let type = exportFormats[format.indexOfSelectedItem].type
            try ImageWorkspaceRaster.export(screenshot, to: url, type: type, quality: [0.6, 0.8, 0.9, 1][quality.indexOfSelectedItem])
            return true
        } catch {
            showError(error, strings: strings, window: nil)
            return false
        }
    }

    static func saveProject(_ project: ImageWorkspaceProject, strings: AppStrings, window: NSWindow, completion: @escaping () -> Void) {
        let panel = NSSavePanel()
        panel.title = strings.editorLabel("保存可编辑工程", "Save Editable Project")
        panel.nameFieldStringValue = "Frame"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [projectType]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let output = url.pathExtension.isEmpty ? url.appendingPathExtension("frameimage") : url
            do {
                try JSONEncoder().encode(project).write(to: output, options: .atomic)
                completion()
            } catch {
                showError(error, strings: strings, window: window)
            }
        }
    }

    static func resize(size: CGSize, strings: AppStrings, window: NSWindow, completion: @escaping (Int, Int) -> Void) {
        let units = popup([strings.editorLabel("像素", "Pixels"), strings.editorLabel("百分比", "Percent")])
        let width = field(Double(size.width))
        let height = field(Double(size.height))
        let lock = NSButton(checkboxWithTitle: strings.editorLabel("锁定宽高比", "Lock aspect ratio"), target: nil, action: nil)
        lock.state = .on
        let model = ImageWorkspaceResizeForm(size: size, units: units, width: width, height: height, lock: lock)
        width.delegate = model
        height.delegate = model
        units.target = model
        units.action = #selector(ImageWorkspaceResizeForm.changeUnits)
        lock.target = model
        lock.action = #selector(ImageWorkspaceResizeForm.changeLock)
        let controls = form([
            (strings.editorLabel("单位", "Units"), units),
            (strings.editorLabel("宽度", "Width"), width),
            (strings.editorLabel("高度", "Height"), height),
            ("", lock),
        ])
        present(strings.editorLabel("缩放图片尺寸", "Resize Image"), controls: controls, strings: strings, window: window) {
            guard let output = model.pixelSize, ImageWorkspaceRaster.validSize(output.width, output.height) else {
                showError(CocoaError(.fileWriteUnknown), strings: strings, window: window,
                          message: strings.editorLabel("请输入有效尺寸，最多 1 亿像素。", "Enter valid dimensions up to 100 million pixels."))
                return
            }
            completion(output.width, output.height)
        }
    }

    static func adjustColor(image: NSImage?, strings: AppStrings, window: NSWindow, completion: @escaping (ImageWorkspaceRasterOperation) -> Void) {
        let exposure = NSSlider(value: 0, minValue: -3, maxValue: 3, target: nil, action: nil)
        let contrast = NSSlider(value: 1, minValue: 0.25, maxValue: 2, target: nil, action: nil)
        let saturation = NSSlider(value: 1, minValue: 0, maxValue: 2, target: nil, action: nil)
        let sliders = [exposure, contrast, saturation]
        for slider in sliders {
            slider.widthAnchor.constraint(equalToConstant: 175).isActive = true
        }
        let reset = NSButton(title: strings.editorLabel("重置", "Reset"), target: nil, action: nil)
        let preview = NSImageView()
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.widthAnchor.constraint(equalToConstant: 210).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 115).isActive = true
        let context = CIContext()
        let thumbnail = image?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { pixels in
            let source = CIImage(cgImage: pixels)
            let scale = min(1, 420 / source.extent.width, 230 / source.extent.height)
            return source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let updatePreview = ImageWorkspaceDialogAction {
            guard let thumbnail else { return }
            let adjusted = thumbnail.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure.doubleValue])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: contrast.doubleValue, kCIInputSaturationKey: saturation.doubleValue,
                ])
            if let pixels = context.createCGImage(adjusted, from: adjusted.extent.integral) {
                preview.image = NSImage(cgImage: pixels, size: adjusted.extent.size)
            }
        }
        let resetAction = ImageWorkspaceDialogAction {
            for (slider, value) in zip(sliders, [0.0, 1.0, 1.0]) { slider.doubleValue = value }
            updatePreview.invoke()
        }
        for slider in sliders {
            slider.target = updatePreview
            slider.action = #selector(ImageWorkspaceDialogAction.invoke)
            slider.isContinuous = true
        }
        reset.target = resetAction
        reset.action = #selector(ImageWorkspaceDialogAction.invoke)
        updatePreview.invoke()
        let controls = form([
            (strings.editorLabel("预览", "Preview"), preview),
            (strings.editorLabel("曝光", "Exposure"), exposure),
            (strings.editorLabel("对比度", "Contrast"), contrast),
            (strings.editorLabel("饱和度", "Saturation"), saturation),
            ("", reset),
        ])
        present(strings.editorLabel("调整颜色", "Adjust Color"), controls: controls, strings: strings, window: window) {
            withExtendedLifetime((resetAction, updatePreview)) {
                completion(.adjust(exposure: exposure.doubleValue, contrast: contrast.doubleValue, saturation: saturation.doubleValue))
            }
        }
    }

    static func extendCanvas(strings: AppStrings, window: NSWindow, completion: @escaping (ImageWorkspaceRasterOperation) -> Void) {
        let padding = field(32)
        let colors: [NSColor] = [.clear, .white, .black, .windowBackgroundColor]
        let color = popup([
            strings.editorLabel("透明", "Transparent"), strings.editorLabel("白色", "White"),
            strings.editorLabel("黑色", "Black"), strings.editorLabel("系统背景色", "System Background"),
        ])
        let controls = form([
            (strings.editorLabel("四周留白（像素）", "Padding (pixels)"), padding),
            (strings.editorLabel("背景", "Background"), color),
        ])
        present(strings.editorLabel("扩展画布", "Extend Canvas"), controls: controls, strings: strings, window: window) {
            guard let pixels = Int(padding.stringValue), (0...10_000).contains(pixels) else {
                showError(CocoaError(.fileWriteUnknown), strings: strings, window: window,
                          message: strings.editorLabel("留白范围为 0 到 10,000 像素。", "Enter padding from 0 to 10,000 pixels."))
                return
            }
            completion(.extend(padding: pixels, color: colors[color.indexOfSelectedItem]))
        }
    }

    static func showError(_ error: Error, strings: AppStrings, window: NSWindow?, message: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = strings.editorLabel("无法完成图片操作", "Couldn’t Complete Image Operation")
        alert.informativeText = message ?? error.localizedDescription
        alert.addButton(withTitle: strings.editorLabel("好", "OK"))
        if let window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private static func present(_ title: String, controls: NSView, strings: AppStrings, window: NSWindow, completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.accessoryView = controls
        alert.addButton(withTitle: strings.editorLabel("应用", "Apply"))
        alert.addButton(withTitle: strings.editorLabel("取消", "Cancel"))
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { completion() }
        }
    }

    private static func form(_ rows: [(String, NSView)]) -> NSView {
        let grid = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.rowSpacing = 9
        grid.columnSpacing = 12
        grid.frame.size = grid.fittingSize
        return grid
    }

    private static func popup(_ titles: [String]) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.addItems(withTitles: titles)
        return button
    }

    private static func field(_ initialValue: Double) -> NSTextField {
        let field = NSTextField(string: String(format: "%.0f", initialValue))
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 90).isActive = true
        return field
    }
}

@MainActor
private final class ImageWorkspaceDialogAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) { self.handler = handler }

    @objc func invoke() { handler() }
}

@MainActor
private final class ImageWorkspaceResizeForm: NSObject, NSTextFieldDelegate {
    private let size: CGSize
    private weak var units: NSPopUpButton?
    private weak var width: NSTextField?
    private weak var height: NSTextField?
    private weak var lock: NSButton?
    private var percentage = false

    init(size: CGSize, units: NSPopUpButton, width: NSTextField, height: NSTextField, lock: NSButton) {
        self.size = size
        self.units = units
        self.width = width
        self.height = height
        self.lock = lock
    }

    var pixelSize: (width: Int, height: Int)? {
        guard let width = width.flatMap({ Double($0.stringValue) }),
              let height = height.flatMap({ Double($0.stringValue) }) else { return nil }
        let x = width * (percentage ? size.width / 100 : 1)
        let y = height * (percentage ? size.height / 100 : 1)
        let max = Double(ImageWorkspaceRaster.maximumPixelCount)
        guard x.isFinite, y.isFinite, (1...max).contains(x.rounded()), (1...max).contains(y.rounded()) else { return nil }
        return (Int(x.rounded()), Int(y.rounded()))
    }

    @objc func changeUnits() {
        let current = pixelSize ?? (Int(size.width), Int(size.height))
        percentage = units?.indexOfSelectedItem == 1
        let w = Double(current.width)
        let h = Double(current.height)
        width?.stringValue = format(percentage ? w / size.width * 100 : w)
        height?.stringValue = format(percentage ? h / size.height * 100 : h)
    }

    @objc func changeLock() {
        if let width { updateSibling(of: width) }
    }

    func controlTextDidChange(_ notification: Notification) {
        if let field = notification.object as? NSTextField { updateSibling(of: field) }
    }

    private func updateSibling(of field: NSTextField) {
        guard lock?.state == .on, let value = Double(field.stringValue), value.isFinite else { return }
        let ratio = percentage ? 1 : size.width / size.height
        if field === width {
            height?.stringValue = format(value / ratio)
        } else {
            width?.stringValue = format(value * ratio)
        }
    }

    private func format(_ value: Double) -> String {
        String(format: percentage ? "%.2f" : "%.0f", value)
    }
}
