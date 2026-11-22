import AppKit
import FrameCore

@MainActor
final class ImageWorkspaceInspector: NSView {
    enum Action {
        case crop, resize, transform(NSButton)
        case zoom(CGFloat), fit, actualSize
        case cropRatio(Int), cancelCrop, applyCrop
        case mosaic(ImageAnnotationMosaicMode)
        case style((inout ImageAnnotationStyle) -> Void)
        case duplicate, reorder(forward: Bool)
    }

    private let strings: AppStrings
    private let perform: (Action) -> Void
    private let section = NSStackView()
    private let contextTitle = NSTextField(labelWithString: "")
    private weak var zoomDisplay: NSButton?
    private let cropSize = NSTextField(labelWithString: "")
    private let colorRow = NSStackView()
    private var swatches: [(ImageAnnotationColor, NSButton)] = []
    private let fonts = ["Helvetica Neue", "Georgia", "Menlo", "Avenir Next", "PingFang SC"]
    private let lineWidths: [CGFloat] = [1, 2, 4, 8, 12, 16, 24]
    private let fontSizes: [CGFloat] = [12, 14, 16, 18, 22, 28, 36, 48, 64, 80, 96]
    private let intensities: [CGFloat] = [4, 6, 12, 20, 24, 40, 64]
    private let brushWidths: [CGFloat] = [12, 24, 40, 64]
    private var imageSection: NSView!
    private var cropSection: NSView!
    private var typeChoices: NSView!
    private var mosaicButtons: [NSButton] = []
    private var styleRows: [ObjectIdentifier: NSView] = [:]
    private var sectionHost: NSView!
    private weak var scrollDocument: InspectorDocumentView?
    private var isCropping = false
    private var displayedMosaicMode: ImageAnnotationMosaicMode?
    private var objectActions: NSView!
    private var automaticWidth: NSButton!
    private var applyCropButton: NSButton!
    private var cropRatio: InspectorPopup!
    private var width: InspectorPopup!
    private var font: InspectorPopup!
    private var size: InspectorPopup!
    private var traits: NSSegmentedControl!
    private var alignment: NSSegmentedControl!
    private var textPreset: InspectorPopup!
    private var linePattern: InspectorPopup!
    private var arrowStyle: InspectorPopup!
    private var fill: InspectorPopup!
    private var intensity: InspectorPopup!
    private var brushWidth: InspectorPopup!

    init(strings: AppStrings, perform: @escaping (Action) -> Void) {
        self.strings = strings
        self.perform = perform
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityLabel("Image Workspace Inspector")
        configure()
    }

    required init?(coder: NSCoder) { nil }

    func update(document: ImageAnnotationDocument) {
        let selected = document.elements.first { $0.id == document.selectedElementID }
        let style = selected?.style ?? document.editingOptions.style
        let kind = selected?.kind
        let shape: ImageAnnotationShapeKind?
        if case let .shape(selectedShape) = kind {
            shape = selectedShape
        } else {
            shape = kind == nil && document.selectedTool == .shape ? document.editingOptions.shapeKind : nil
        }
        let mosaic: ImageAnnotationMosaicMode?
        if case let .mosaic(selectedMode) = kind {
            mosaic = selectedMode
        } else {
            mosaic = kind == nil && document.selectedTool == .mosaic ? document.editingOptions.mosaicMode : nil
        }

        displayedMosaicMode = mosaic
        let text: Bool
        let stroke: Bool
        let title: String
        switch kind {
        case .text: (text, stroke, title) = (true, false, label("文本", "Text"))
        case .brush: (text, stroke, title) = (false, true, label("画笔", "Brush"))
        case .highlight: (text, stroke, title) = (false, true, label("高亮", "Highlight"))
        case .counter: (text, stroke, title) = (false, false, label("编号", "Numbered Stamp"))
        case .spotlight: (text, stroke, title) = (false, false, label("聚光", "Spotlight"))
        case .image: (text, stroke, title) = (false, false, label("图片对象", "Image Object"))
        case .shape, .mosaic, nil:
            switch document.selectedTool {
            case .text where kind == nil: (text, stroke, title) = (true, false, label("文本", "Text"))
            case .brush where kind == nil: (text, stroke, title) = (false, true, label("画笔", "Brush"))
            case .highlight where kind == nil: (text, stroke, title) = (false, true, label("高亮", "Highlight"))
            default:
                text = false
                stroke = shape != nil
                title = shape.map { strings.workspaceShapeKindTitle($0) } ?? (mosaic == nil ? "" : label("马赛克与遮挡", "Redaction"))
            }
        }
        contextTitle.stringValue = title
        sectionHost.isHidden = isCropping || title.isEmpty
        colorRow.isHidden = !(stroke || text || kind?.isNumberedStamp == true)
        swatches.forEach { color, button in
            let selected = color == style.strokeColor
            button.state = selected ? .on : .off
            button.layer?.borderWidth = selected ? 1.5 : 0
        }

        let activeRows: [NSView] = [
            stroke ? styleRows[ObjectIdentifier(width!)] : nil,
            text ? styleRows[ObjectIdentifier(font!)] : nil,
            text ? styleRows[ObjectIdentifier(size!)] : nil,
            text ? styleRows[ObjectIdentifier(traits!)] : nil,
            text ? styleRows[ObjectIdentifier(alignment!)] : nil,
            text ? styleRows[ObjectIdentifier(textPreset!)] : nil,
            shape != nil && shape != .arrow ? styleRows[ObjectIdentifier(linePattern!)] : nil,
            shape == .arrow ? styleRows[ObjectIdentifier(arrowStyle!)] : nil,
            shape == .rectangle || shape == .ellipse ? styleRows[ObjectIdentifier(fill!)] : nil,
            mosaic == .rectangle || mosaic == .brush || mosaic == .blur ? styleRows[ObjectIdentifier(intensity!)] : nil,
            mosaic == .brush ? styleRows[ObjectIdentifier(brushWidth!)] : nil,
        ].compactMap { $0 }
        for row in styleRows.values { row.isHidden = !activeRows.contains { $0 === row } }
        typeChoices.isHidden = mosaic == nil
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for (button, mode) in zip(mosaicButtons, ImageAnnotationMosaicMode.allCases) {
                let selected = mode == mosaic
                button.state = selected ? .on : .off
                button.layer?.backgroundColor = selected
                    ? NSColor.controlAccentColor.withAlphaComponent(0.26).cgColor
                    : NSColor.labelColor.withAlphaComponent(0.045).cgColor
                button.layer?.borderColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.65).cgColor : nil
                button.layer?.borderWidth = selected ? 1 : 0
            }
        }
        objectActions.isHidden = selected == nil
        automaticWidth.isHidden = !text || style.textBoxWidth == nil

        width.selectNearest(style.lineWidth, in: lineWidths)
        font.selectItem(at: style.fontName.flatMap { fonts.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        size.selectNearest(style.fontSize, in: fontSizes)
        traits.setSelected(style.fontWeight == .bold, forSegment: 0)
        traits.setSelected(style.textItalic == true, forSegment: 1)
        alignment.selectedSegment = [ImageAnnotationTextAlignment.left, .center, .right].firstIndex(of: style.textAlignment) ?? 0
        textPreset.selectItem(at: style.textOutline != nil ? 2 : style.fillColor == .black ? 1 : 0)
        linePattern.selectItem(at: ImageAnnotationLinePattern.allCases.firstIndex(of: style.linePattern ?? .solid) ?? 0)
        arrowStyle.selectItem(at: [ImageAnnotationArrowStyle.wedge, .open, .doubleHeaded].firstIndex(of: style.arrowStyle ?? .wedge) ?? 0)
        fill.selectItem(at: style.fillColor == nil ? 0 : style.fillColor == .white ? 2 : style.fillColor == .black ? 3 : 1)
        if mosaic == .blur {
            let radius = style.mosaicStrength <= 1 ? style.mosaicBlockSize * style.mosaicStrength : style.mosaicStrength
            intensity.selectNearest(radius, in: intensities)
            intensity.rowTitle?.stringValue = label("模糊强度", "Blur Strength")
        } else {
            intensity.selectNearest(style.mosaicBlockSize, in: intensities)
            intensity.rowTitle?.stringValue = label("块大小", "Block Size")
        }
        brushWidth.selectNearest(style.mosaicBrushWidth ?? style.mosaicBlockSize * 2, in: brushWidths)
        scrollDocument?.needsLayout = true
    }

    func updateCrop(size: CGSize?, selectedRatio: Int) {
        isCropping = size != nil
        imageSection.isHidden = isCropping
        cropSection.isHidden = !isCropping
        sectionHost.isHidden = isCropping || contextTitle.stringValue.isEmpty
        if let size {
            cropRatio.selectItem(at: selectedRatio)
            cropSize.stringValue = "\(Int(size.width)) × \(Int(size.height)) px"
            applyCropButton.isEnabled = size.width > 0 && size.height > 0
        }
        scrollDocument?.needsLayout = true
    }

    func updateZoom(_ zoom: Int) {
        zoomDisplay?.title = "\(zoom)%"
    }

    private func configure() {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let document = InspectorDocumentView()
        scrollDocument = document
        document.autoresizingMask = [.width]
        let body = stack([], spacing: 20)
        document.addSubview(body)
        scroll.documentView = document
        addSubview(scroll)
        let zoomBar = makeZoomSection()
        let zoomRule = NSBox()
        zoomRule.boxType = .separator
        zoomRule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomBar)
        addSubview(zoomRule)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: zoomRule.topAnchor),
            zoomRule.heightAnchor.constraint(equalToConstant: 1),
            zoomRule.leadingAnchor.constraint(equalTo: zoomBar.leadingAnchor),
            zoomRule.trailingAnchor.constraint(equalTo: zoomBar.trailingAnchor),
            zoomRule.bottomAnchor.constraint(equalTo: zoomBar.topAnchor, constant: -10),
            zoomBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            zoomBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            zoomBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            zoomBar.heightAnchor.constraint(equalToConstant: 30),
            body.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 14),
            body.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -14),
            body.topAnchor.constraint(equalTo: document.topAnchor, constant: 16),
        ])
        document.content = body

        imageSection = makeImageSection()
        cropSection = makeCropSection()
        cropSection.isHidden = true
        configureStyleSection()
        sectionHost = stack([contextTitle, InspectorSurface(content: section)], spacing: 10)
        if let card = (sectionHost as? NSStackView)?.arrangedSubviews.last {
            card.widthAnchor.constraint(equalTo: sectionHost.widthAnchor).isActive = true
        }
        for view in [imageSection!, sectionHost!, cropSection!] {
            body.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func makeImageSection() -> NSView {
        let crop = button(label("裁剪", "Crop"), action: .crop)
        let resize = button(label("调整大小", "Resize"), action: .resize)
        let transform = InspectorButton(title: label("变换", "Transform")) { [weak self] sender in
            self?.perform(.transform(sender))
        }
        transform.setAccessibilityLabel(transform.title)
        let commands = row([crop, resize, transform])
        commands.spacing = 6
        commands.distribution = .fillEqually
        for (button, symbol) in [(crop, "crop"), (resize, "arrow.up.left.and.arrow.down.right"), (transform, "rotate.right")] {
            button.isBordered = false
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.symbolConfiguration = .init(pointSize: 15, weight: .medium)
            button.imagePosition = .imageAbove
            button.contentTintColor = .labelColor
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        }
        let panel = InspectorSurface(content: commands, inset: 5)
        let image = stack([heading(label("图片", "Image")), panel], spacing: 8)
        panel.widthAnchor.constraint(equalTo: image.widthAnchor).isActive = true
        return image
    }

    private func makeCropSection() -> NSView {
        cropRatio = popup(label("比例", "Aspect Ratio"), [
            label("自由比例", "Freeform"), label("原图比例", "Original"), "1:1", "4:3", "16:9",
        ]) { [weak self] index in self?.perform(.cropRatio(index)) }
        cropSize.textColor = .secondaryLabelColor
        cropSize.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        applyCropButton = button(label("应用裁剪", "Apply Crop"), action: .applyCrop)
        applyCropButton.keyEquivalent = "\r"
        return stack([
            heading(label("裁剪", "Crop")), labeledRow(label("比例", "Aspect Ratio"), cropRatio), cropSize,
            row([button(label("取消", "Cancel"), action: .cancelCrop), applyCropButton]),
        ])
    }

    private func makeZoomSection() -> NSView {
        let out = button("−", action: .zoom(-0.20))
        let more = button("+", action: .zoom(0.25))
        let fit = button(label("适合窗口", "Fit"), action: .fit)
        let actual = InspectorButton(title: "100%") { [weak self] _ in self?.perform(.actualSize) }
        actual.setAccessibilityLabel(label("实际像素", "Actual Pixels"))
        actual.toolTip = label("点按恢复到 100%", "Click to return to 100%")
        actual.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        actual.isBordered = false
        actual.widthAnchor.constraint(equalToConstant: 52).isActive = true
        zoomDisplay = actual
        out.setAccessibilityLabel(label("缩小画布", "Zoom Out"))
        more.setAccessibilityLabel(label("放大画布", "Zoom In"))
        for control in [out, more] {
            control.bezelStyle = .accessoryBarAction
            control.widthAnchor.constraint(equalToConstant: 24).isActive = true
        }
        let cluster = InspectorSurface(content: row([out, actual, more]), inset: 2)
        let footer = row([cluster, NSView(), fit])
        footer.translatesAutoresizingMaskIntoConstraints = false
        return footer
    }

    private func configureStyleSection() {
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        contextTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        colorRow.orientation = .horizontal
        colorRow.alignment = .centerY
        colorRow.spacing = 5
        for color: ImageAnnotationColor in [.red, .yellow, .blue, .green, .white, .black] {
            let swatch = button(strings.workspaceColorTitle(color), action: .style { $0.strokeColor = color })
            swatch.setButtonType(.toggle)
            swatch.isBordered = false
            swatch.wantsLayer = true
            swatch.layer?.cornerRadius = 13
            swatch.layer?.borderColor = NSColor.controlAccentColor.cgColor
            swatch.title = ""
            swatch.image = swatchImage(color)
            swatch.imagePosition = .imageOnly
            swatch.setAccessibilityLabel(strings.workspaceColorTitle(color))
            swatch.toolTip = strings.workspaceColorTitle(color)
            swatch.widthAnchor.constraint(equalToConstant: 26).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 26).isActive = true
            colorRow.addArrangedSubview(swatch)
            swatches.append((color, swatch))
        }

        width = stylePopup(label("线宽", "Width"), lineWidths.map { strings.workspaceLineWidth($0) }) { [lineWidths] style, index in style.lineWidth = lineWidths[index] }
        font = stylePopup(label("字体", "Font"), [label("系统字体", "System Font")] + fonts) { [fonts] style, index in style.fontName = index == 0 ? nil : fonts[index - 1] }
        size = stylePopup(label("字号", "Size"), fontSizes.map { strings.workspaceFontSize($0) }) { [fontSizes] style, index in style.fontSize = fontSizes[index] }
        traits = NSSegmentedControl(labels: [label("粗体", "Bold"), label("斜体", "Italic")], trackingMode: .selectAny, target: self, action: #selector(changeTraits))
        traits.controlSize = .small
        traits.setAccessibilityLabel(label("字形", "Typeface style"))
        styleRows[ObjectIdentifier(traits)] = labeledRow(label("字形", "Typeface"), traits)
        let alignments = [label("左对齐", "Align Left"), label("居中", "Center"), label("右对齐", "Align Right")]
        let alignIcons = zip(["text.alignleft", "text.aligncenter", "text.alignright"], alignments).map {
            NSImage(systemSymbolName: $0, accessibilityDescription: $1) ?? NSImage()
        }
        alignment = NSSegmentedControl(images: alignIcons, trackingMode: .selectOne, target: self, action: #selector(changeAlignment))
        alignment.controlSize = .small
        alignment.setAccessibilityLabel(label("对齐", "Align"))
        for (index, name) in alignments.enumerated() { alignment.setToolTip(name, forSegment: index) }
        styleRows[ObjectIdentifier(alignment)] = labeledRow(label("对齐", "Align"), alignment)
        textPreset = stylePopup(label("样式", "Style"), [label("纯文字", "Plain"), label("深色底标签", "Dark Label"), label("反差描边", "Outline")]) {
            $0.fillColor = $1 == 1 ? .black : nil
            $0.textOutline = $1 == 2 ? .black : nil
            if $1 > 0 { $0.strokeColor = .white }
        }
        linePattern = stylePopup(label("线型", "Line"), [label("实线", "Solid"), label("虚线", "Dash"), label("点线", "Dot")]) {
            $0.linePattern = ImageAnnotationLinePattern.allCases[$1]
        }
        arrowStyle = stylePopup(label("箭头", "Arrow"), [label("楔形", "Wedge"), label("线形", "Open"), label("双向", "Two-Headed")]) {
            $0.arrowStyle = [ImageAnnotationArrowStyle.wedge, .open, .doubleHeaded][$1]
        }
        fill = stylePopup(label("填充", "Fill"), [label("无", "None"), label("半透明同色", "Translucent"), label("白色", "White"), label("黑色", "Black")]) {
            $0.fillColor = [nil, $0.strokeColor.withAlpha(0.25), .white, .black][$1]
        }
        intensity = stylePopup(label("块大小", "Block Size"), intensities.map { "\(Int($0))" }) {
            [weak self, intensities] style, index in
            if self?.displayedMosaicMode == .blur {
                style.mosaicStrength = intensities[index]
            } else {
                style.mosaicBlockSize = intensities[index]
            }
        }
        brushWidth = stylePopup(label("笔刷宽度", "Brush Width"), brushWidths.map { strings.workspaceLineWidth($0) }) {
            [brushWidths] style, index in style.mosaicBrushWidth = brushWidths[index]
        }
        mosaicButtons = ImageAnnotationMosaicMode.allCases.map { mode in
            let control = InspectorButton(title: strings.workspaceMosaicModeTitle(mode)) { [weak self] _ in
                self?.perform(.mosaic(mode))
            }
            control.setButtonType(.toggle)
            control.controlSize = .small
            control.isBordered = false
            control.wantsLayer = true
            control.layer?.cornerCurve = .continuous
            control.layer?.cornerRadius = 13
            control.heightAnchor.constraint(equalToConstant: 26).isActive = true
            control.setAccessibilityLabel(strings.workspaceMosaicModeTitle(mode))
            return control
        }
        let topModes = row(Array(mosaicButtons.prefix(2)))
        let bottomModes = row(Array(mosaicButtons.suffix(2)))
        for modes in [topModes, bottomModes] {
            modes.distribution = .fillEqually
        }
        let modeGrid = stack([topModes, bottomModes], spacing: 5)
        for modes in [topModes, bottomModes] {
            modes.widthAnchor.constraint(equalTo: modeGrid.widthAnchor).isActive = true
        }
        typeChoices = modeGrid
        automaticWidth = button(label("恢复自动宽度", "Restore Automatic Width"), action: .style { $0.textBoxWidth = nil })
        objectActions = row([
            button(label("复制对象", "Duplicate"), action: .duplicate),
            button("↑", action: .reorder(forward: true), help: label("移到最前", "Bring to Front")),
            button("↓", action: .reorder(forward: false), help: label("移到最后", "Send to Back")),
        ])
        let orderedControls: [NSView] = [width, font, size, traits, alignment, textPreset, linePattern, arrowStyle, fill, intensity, brushWidth]
        for view in [colorRow, typeChoices!] + orderedControls.compactMap({ styleRows[ObjectIdentifier($0)] }) + [automaticWidth!, objectActions!] {
            section.addArrangedSubview(view)
        }
        for view in styleRows.values { view.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true }
        typeChoices.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
    }

    @objc private func changeAlignment() {
        let choices: [ImageAnnotationTextAlignment] = [.left, .center, .right]
        let index = alignment.selectedSegment
        guard choices.indices.contains(index) else { return }
        perform(.style { $0.textAlignment = choices[index] })
    }

    @objc private func changeTraits() {
        let bold = traits.isSelected(forSegment: 0)
        let italic = traits.isSelected(forSegment: 1)
        perform(.style {
            $0.fontWeight = bold ? .bold : .regular
            $0.textItalic = italic ? true : nil
        })
    }

    private func stylePopup(_ title: String, _ values: [String], update: @escaping (inout ImageAnnotationStyle, Int) -> Void) -> InspectorPopup {
        let control = popup(title, values) { [weak self] index in
            self?.perform(.style { update(&$0, index) })
        }
        styleRows[ObjectIdentifier(control)] = labeledRow(title, control)
        return control
    }

    private func popup(_ title: String, _ values: [String], changed: @escaping (Int) -> Void) -> InspectorPopup {
        let control = InspectorPopup(titles: values, changed: changed)
        control.setAccessibilityLabel(title)
        return control
    }

    private func labeledRow(_ title: String, _ control: NSView) -> NSView {
        let text = NSTextField(labelWithString: title)
        text.font = .systemFont(ofSize: 12)
        text.textColor = .secondaryLabelColor
        let view = row([text, NSView(), control])
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 27).isActive = true
        text.widthAnchor.constraint(equalToConstant: 70).isActive = true
        control.widthAnchor.constraint(equalToConstant: 114).isActive = true
        if let control = control as? InspectorPopup {
            control.rowTitle = text
        }
        return view
    }

    private func heading(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.font = .systemFont(ofSize: 14, weight: .semibold)
        return field
    }

    private func button(_ title: String, action: Action, help: String? = nil) -> NSButton {
        let control = InspectorButton(title: title) { [weak self] _ in self?.perform(action) }
        control.controlSize = .small
        control.setAccessibilityLabel(help ?? title)
        if let help {
            control.toolTip = help
            control.setAccessibilityLabel(help)
        }
        return control
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let view = NSStackView(views: views)
        view.orientation = .horizontal
        view.alignment = .centerY
        view.spacing = 5
        return view
    }

    private func stack(_ views: [NSView], spacing: CGFloat = 7) -> NSStackView {
        let view = NSStackView(views: views)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = spacing
        return view
    }

    private func swatchImage(_ color: ImageAnnotationColor) -> NSImage {
        NSImage(size: NSSize(width: 15, height: 15), flipped: false) { rect in
            color.nsColor.setFill()
            let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            dot.fill()
            NSColor.separatorColor.setStroke()
            dot.lineWidth = 1
            dot.stroke()
            return true
        }
    }

    private func label(_ chinese: String, _ english: String) -> String { strings.editorLabel(chinese, english) }
}

@MainActor
private final class InspectorSurface: NSView {
    init(content: NSView, inset: CGFloat = 10) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            content.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
        updateSurface()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurface()
    }

    private func updateSurface() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.045).cgColor
        }
    }
}

@MainActor
private final class InspectorDocumentView: NSView {
    weak var content: NSView?
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let size = NSSize(width: superview?.bounds.width ?? bounds.width,
                          height: max((content?.fittingSize.height ?? 0) + 28, superview?.bounds.height ?? 0))
        if frame.size != size { setFrameSize(size) }
    }
}

@MainActor
private final class InspectorButton: NSButton {
    private let handler: (NSButton) -> Void

    init(title: String, handler: @escaping (NSButton) -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        target = self
        action = #selector(invoke)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func invoke() { handler(self) }
}

@MainActor
private final class InspectorPopup: NSPopUpButton {
    private let changed: (Int) -> Void
    weak var rowTitle: NSTextField?

    init(titles: [String], changed: @escaping (Int) -> Void) {
        self.changed = changed
        super.init(frame: .zero, pullsDown: false)
        addItems(withTitles: titles)
        controlSize = .small
        bezelStyle = .accessoryBarAction
        target = self
        action = #selector(invoke)
    }

    required init?(coder: NSCoder) { nil }

    func selectNearest(_ value: CGFloat, in values: [CGFloat]) {
        if let index = values.indices.min(by: { abs(values[$0] - value) < abs(values[$1] - value) }) {
            selectItem(at: index)
        }
    }

    @objc private func invoke() {
        guard indexOfSelectedItem >= 0 else { return }
        changed(indexOfSelectedItem)
    }
}

private extension ImageAnnotationElementKind {
    var isNumberedStamp: Bool {
        if case .counter = self { return true }
        return false
    }
}
