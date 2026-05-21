import AppKit
import UniformTypeIdentifiers

class PaddedTextFieldCell: NSTextFieldCell {
    private let inset = NSSize(width: 8, height: 2)
    var fieldBackgroundColor: NSColor?
    var fieldCornerRadius: CGFloat = 4

    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        if let bg = fieldBackgroundColor {
            let path = NSBezierPath(roundedRect: cellFrame, xRadius: fieldCornerRadius, yRadius: fieldCornerRadius)
            bg.setFill()
            path.fill()
        }
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let base = super.drawingRect(forBounds: rect)
        return base.insetBy(dx: inset.width, dy: inset.height)
    }

    private func configureEditor(_ textObj: NSText) {
        if let color = textColor {
            textObj.textColor = color
        }
        if let tv = textObj as? NSTextView {
            tv.insertionPointColor = textColor ?? .textColor
            tv.drawsBackground = false
            tv.backgroundColor = .clear
        }
        textObj.font = font
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        configureEditor(textObj)
        super.edit(withFrame: rect.insetBy(dx: inset.width, dy: inset.height), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        configureEditor(textObj)
        super.select(withFrame: rect.insetBy(dx: inset.width, dy: inset.height), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

final class ChatBubbleTextBlock: NSTextBlock {
    enum Side {
        case left
        case right
    }

    var side: Side = .left
    var fillColor: NSColor = .white
    var strokeColor: NSColor = .clear
    var accentColor: NSColor = .clear
    var stickerImageName: String?

    override func drawBackground(
        withFrame frameRect: NSRect,
        in controlView: NSView,
        characterRange charRange: NSRange,
        layoutManager: NSLayoutManager
    ) {
        let bubbleRect = frameRect.insetBy(dx: 1.5, dy: 1.5)
        let radius: CGFloat = 16
        let tailWidth: CGFloat = 9
        let tailHeight: CGFloat = 10
        let tailY = bubbleRect.minY + min(18, max(10, bubbleRect.height * 0.45))
        let path = NSBezierPath(roundedRect: bubbleRect, xRadius: radius, yRadius: radius)

        switch side {
        case .left:
            path.move(to: NSPoint(x: bubbleRect.minX + 2, y: tailY + tailHeight))
            path.line(to: NSPoint(x: bubbleRect.minX - tailWidth, y: tailY + tailHeight * 0.45))
            path.line(to: NSPoint(x: bubbleRect.minX + 2, y: tailY))
        case .right:
            path.move(to: NSPoint(x: bubbleRect.maxX - 2, y: tailY + tailHeight))
            path.line(to: NSPoint(x: bubbleRect.maxX + tailWidth, y: tailY + tailHeight * 0.45))
            path.line(to: NSPoint(x: bubbleRect.maxX - 2, y: tailY))
        }
        path.close()

        if let gradient = NSGradient(colors: [
            fillColor.blended(withFraction: 0.28, of: .white) ?? fillColor,
            fillColor
        ]) {
            gradient.draw(in: path, angle: 92)
        } else {
            fillColor.setFill()
            path.fill()
        }
        drawStickerIfAvailable(in: bubbleRect)
        drawFallbackDecoration(in: bubbleRect)
        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! ChatBubbleTextBlock
        copy.side = side
        copy.fillColor = fillColor
        copy.strokeColor = strokeColor
        copy.accentColor = accentColor
        copy.stickerImageName = stickerImageName
        return copy
    }

    private func drawStickerIfAvailable(in bubbleRect: NSRect) {
        guard let stickerImageName, let sticker = NSImage(named: stickerImageName) else {
            return
        }
        let size = NSSize(width: 30, height: 30)
        let origin: NSPoint
        switch side {
        case .left:
            origin = NSPoint(x: bubbleRect.minX + 7, y: bubbleRect.maxY - size.height - 5)
        case .right:
            origin = NSPoint(x: bubbleRect.maxX - size.width - 7, y: bubbleRect.maxY - size.height - 5)
        }
        sticker.draw(
            in: NSRect(origin: origin, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 0.28
        )
    }

    private func drawFallbackDecoration(in bubbleRect: NSRect) {
        let isAssistantBubble = side == .left
        let dotAlpha: CGFloat = isAssistantBubble ? 0.18 : 0.10
        let highlightAlpha: CGFloat = isAssistantBubble ? 0.24 : 0.16
        let dotColor = accentColor.withAlphaComponent(dotAlpha)
        let highlightColor = NSColor.white.withAlphaComponent(highlightAlpha)

        highlightColor.setFill()
        let shineRect = NSRect(
            x: bubbleRect.minX + 16,
            y: bubbleRect.maxY - 18,
            width: min(72, bubbleRect.width * 0.28),
            height: 5
        )
        NSBezierPath(roundedRect: shineRect, xRadius: 3, yRadius: 3).fill()

        dotColor.setFill()
        let dotBaseX = isAssistantBubble ? bubbleRect.maxX - 38 : bubbleRect.minX + 18
        let dotBaseY = bubbleRect.minY + 14
        for (index, size) in [5.5, 3.5, 4.5].enumerated() {
            let offsetX = CGFloat(index) * 10
            let offsetY = CGFloat(index % 2) * 7
            NSBezierPath(ovalIn: NSRect(x: dotBaseX + offsetX, y: dotBaseY + offsetY, width: size, height: size)).fill()
        }

        guard isAssistantBubble else {
            return
        }
        let leafColor = NSColor.white.withAlphaComponent(0.20)
        leafColor.setStroke()
        let leaf = NSBezierPath()
        leaf.lineWidth = 1.4
        leaf.move(to: NSPoint(x: bubbleRect.maxX - 23, y: bubbleRect.maxY - 25))
        leaf.curve(
            to: NSPoint(x: bubbleRect.maxX - 9, y: bubbleRect.maxY - 18),
            controlPoint1: NSPoint(x: bubbleRect.maxX - 20, y: bubbleRect.maxY - 12),
            controlPoint2: NSPoint(x: bubbleRect.maxX - 12, y: bubbleRect.maxY - 12)
        )
        leaf.stroke()
    }
}

class TerminalView: NSView, NSTextFieldDelegate {
    private struct ToolLogEntry {
        let timestamp: Date
        let title: String
        let summary: String
        let isError: Bool
    }

    private enum MessageSpeaker {
        case owner
        case assistant
    }

    private struct MessageRenderStyle {
        let speaker: MessageSpeaker
        let block: ChatBubbleTextBlock
        let headerParagraph: NSParagraphStyle
        let bodyParagraph: NSParagraphStyle
        let compactParagraph: NSParagraphStyle
    }

    private let contentCardView = NSView()
    private let inputCardView = NSView()
    private let attachmentTrayView = NSView()
    private let suggestionPanelView = NSView()
    let scrollView = NSScrollView()
    let textView = NSTextView()
    let inputField = NSTextField()
    private let emojiButton = NSButton()
    private let imageButton = NSButton()
    private let promptButton = NSButton()
    private let ttsButton = NSButton()
    private let micButton = NSButton()
    private let sendButton = NSButton()
    private let toolLogButton = NSButton()
    private let voiceStatusLabel = NSTextField(labelWithString: "")
    var onSendMessage: ((String) -> Void)?
    var onSendMessageWithAttachments: ((String, [AgentAttachment]) -> Void)?
    var onShowCapabilities: (() -> Void)?
    var onVoiceRecordToggle: (() -> Void)?
    var onVoiceTTSToggle: (() -> Void)?
    var suggestionProvider: ((String) -> [InputSuggestion])?
    private var placeholderText = AgentProvider.current.inputPlaceholder

    private var currentAssistantText = ""
    private var isStreaming = false
    private var streamingStartLocation: Int?
    private var streamingMessageStyle: MessageRenderStyle?
    private var currentSuggestions: [InputSuggestion] = []
    private var selectedSuggestionIndex = 0
    private var selectedAttachments: [AgentAttachment] = []
    private var toolLogEntries: [ToolLogEntry] = []
    private var toolLogPopover: NSPopover?
    private weak var toolLogTextView: NSTextView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    var characterColor: NSColor?
    var themeOverride: PopoverTheme?
    var theme: PopoverTheme {
        var t = themeOverride ?? PopoverTheme.current
        if let color = characterColor { t = t.withCharacterColor(color) }
        t = t.withCustomFont()
        return t
    }

    // MARK: - Setup

    private func setupViews() {
        let t = theme
        let sidePadding: CGFloat = 10
        let topPadding: CGFloat = 10
        let bottomPadding: CGFloat = 12
        let inputHeight: CGFloat = 58
        let inputGap: CGFloat = 10

        contentCardView.frame = NSRect(
            x: sidePadding,
            y: bottomPadding + inputHeight + inputGap,
            width: frame.width - sidePadding * 2,
            height: frame.height - (topPadding + bottomPadding + inputHeight + inputGap)
        )
        contentCardView.autoresizingMask = [.width, .height]
        contentCardView.wantsLayer = true
        addSubview(contentCardView)

        scrollView.frame = NSRect(
            x: 12,
            y: 12,
            width: contentCardView.frame.width - 24,
            height: contentCardView.frame.height - 58
        )
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        textView.frame = scrollView.contentView.bounds
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textColor = t.textPrimary
        textView.font = t.font
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 14, height: 14)
        let defaultPara = NSMutableParagraphStyle()
        defaultPara.paragraphSpacing = 10
        defaultPara.lineSpacing = 2
        textView.defaultParagraphStyle = defaultPara
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.linkTextAttributes = [
            .foregroundColor: t.accentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        scrollView.documentView = textView
        contentCardView.addSubview(scrollView)

        configureToolLogButton()
        contentCardView.addSubview(toolLogButton)

        inputCardView.frame = NSRect(
            x: sidePadding,
            y: bottomPadding,
            width: frame.width - sidePadding * 2,
            height: inputHeight
        )
        inputCardView.autoresizingMask = [.width, .maxYMargin]
        inputCardView.wantsLayer = true
        addSubview(inputCardView)

        inputField.frame = NSRect(x: 132, y: 18, width: inputCardView.frame.width - 322, height: 24)
        inputField.autoresizingMask = [.width]
        inputField.focusRingType = .none
        let paddedCell = PaddedTextFieldCell(textCell: "")
        paddedCell.isEditable = true
        paddedCell.isScrollable = true
        paddedCell.font = t.font
        paddedCell.textColor = t.textPrimary
        paddedCell.drawsBackground = false
        paddedCell.isBezeled = false
        paddedCell.fieldBackgroundColor = nil
        paddedCell.fieldCornerRadius = 0
        paddedCell.placeholderAttributedString = NSAttributedString(
            string: placeholderText,
            attributes: [.font: t.font, .foregroundColor: t.textDim]
        )
        inputField.cell = paddedCell
        inputField.delegate = self
        inputField.target = self
        inputField.action = #selector(inputSubmitted)
        inputCardView.addSubview(inputField)

        voiceStatusLabel.frame = NSRect(x: inputField.frame.minX + 150, y: 4, width: inputField.frame.width - 152, height: 12)
        voiceStatusLabel.autoresizingMask = [.width]
        voiceStatusLabel.font = .systemFont(ofSize: 10, weight: .bold)
        voiceStatusLabel.textColor = NSColor(red: 0.62, green: 0.34, blue: 0.12, alpha: 0.94)
        voiceStatusLabel.lineBreakMode = .byTruncatingTail
        voiceStatusLabel.isHidden = true
        inputCardView.addSubview(voiceStatusLabel)

        attachmentTrayView.frame = NSRect(
            x: sidePadding + 12,
            y: inputCardView.frame.maxY + 6,
            width: frame.width - sidePadding * 2 - 24,
            height: 30
        )
        attachmentTrayView.autoresizingMask = [.width, .maxYMargin]
        attachmentTrayView.wantsLayer = true
        attachmentTrayView.layer?.backgroundColor = NSColor(red: 1.0, green: 0.94, blue: 0.84, alpha: 0.72).cgColor
        attachmentTrayView.layer?.cornerRadius = 13
        attachmentTrayView.layer?.borderWidth = 1
        attachmentTrayView.layer?.borderColor = NSColor(red: 0.95, green: 0.64, blue: 0.32, alpha: 0.24).cgColor
        attachmentTrayView.isHidden = true
        addSubview(attachmentTrayView, positioned: .above, relativeTo: inputCardView)

        configureInputAccessory(emojiButton, symbolName: "sparkles", frame: NSRect(x: 12, y: 12, width: 34, height: 34))
        configureInputAccessory(imageButton, symbolName: "photo.on.rectangle.angled", frame: NSRect(x: 50, y: 12, width: 34, height: 34))
        configurePromptButton()
        configureVoiceToggleButton(ttsButton, frame: NSRect(x: inputCardView.frame.width - 182, y: 12, width: 78, height: 34))
        configureRoundActionButton(micButton, symbolName: "waveform", frame: NSRect(x: inputCardView.frame.width - 98, y: 12, width: 34, height: 34), fill: NSColor.clear)
        configureRoundActionButton(sendButton, title: "➤", frame: NSRect(x: inputCardView.frame.width - 52, y: 8, width: 42, height: 42), fill: NSColor(red: 0.43, green: 0.78, blue: 0.52, alpha: 1))
        ttsButton.autoresizingMask = [.minXMargin]
        micButton.autoresizingMask = [.minXMargin]
        sendButton.autoresizingMask = [.minXMargin]
        emojiButton.target = self
        emojiButton.action = #selector(showCapabilitiesPressed)
        emojiButton.toolTip = "查看当前入口能力"
        imageButton.target = self
        imageButton.action = #selector(chooseImageAttachment)
        imageButton.toolTip = "附加图片"
        promptButton.target = self
        promptButton.action = #selector(chooseFileAttachment)
        promptButton.toolTip = "附加文件路径"
        ttsButton.target = self
        ttsButton.action = #selector(voiceTTSPressed)
        ttsButton.toolTip = "朗读 ON/OFF"
        micButton.target = self
        micButton.action = #selector(voiceRecordPressed)
        micButton.toolTip = "Hermes 语音输入"
        sendButton.target = self
        sendButton.action = #selector(inputSubmitted)
        inputCardView.addSubview(emojiButton)
        inputCardView.addSubview(imageButton)
        inputCardView.addSubview(promptButton)
        inputCardView.addSubview(ttsButton)
        inputCardView.addSubview(micButton)
        inputCardView.addSubview(sendButton)

        configureSuggestionPanel()
        applyTheme()
        setVoiceStatus(HermesVoiceStatus())
    }

    private func configureInputAccessory(_ button: NSButton, symbolName: String, frame: NSRect) {
        button.frame = frame
        button.title = ""
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.font = .systemFont(ofSize: 18, weight: .medium)
        button.contentTintColor = NSColor(red: 0.34, green: 0.63, blue: 0.38, alpha: 1)
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func configurePromptButton() {
        promptButton.frame = NSRect(x: 88, y: 12, width: 34, height: 34)
        promptButton.title = ""
        promptButton.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
        promptButton.imagePosition = .imageOnly
        promptButton.imageScaling = .scaleProportionallyDown
        promptButton.isBordered = false
        promptButton.font = .systemFont(ofSize: 12, weight: .semibold)
        promptButton.contentTintColor = NSColor(red: 0.37, green: 0.50, blue: 0.22, alpha: 1)
        promptButton.wantsLayer = true
        promptButton.layer?.backgroundColor = NSColor.clear.cgColor
        promptButton.layer?.cornerRadius = 12
        promptButton.layer?.borderWidth = 1
        promptButton.layer?.borderColor = NSColor(red: 0.72, green: 0.81, blue: 0.58, alpha: 1).cgColor
    }

    private func configureRoundActionButton(_ button: NSButton, title: String, frame: NSRect, fill: NSColor) {
        button.frame = frame
        button.title = title
        button.isBordered = false
        button.font = .systemFont(ofSize: 22, weight: .bold)
        if title.isEmpty {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }
        button.contentTintColor = title == "➤" ? .white : NSColor(red: 0.40, green: 0.52, blue: 0.28, alpha: 1)
        button.wantsLayer = true
        button.layer?.backgroundColor = fill.cgColor
        button.layer?.cornerRadius = frame.height / 2
    }

    private func configureRoundActionButton(_ button: NSButton, symbolName: String, frame: NSRect, fill: NSColor) {
        button.frame = frame
        button.title = ""
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.font = .systemFont(ofSize: 18, weight: .semibold)
        button.contentTintColor = NSColor(red: 0.40, green: 0.52, blue: 0.28, alpha: 1)
        button.wantsLayer = true
        button.layer?.backgroundColor = fill.cgColor
        button.layer?.cornerRadius = frame.height / 2
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor(red: 0.78, green: 0.86, blue: 0.62, alpha: 0.45).cgColor
    }

    private func configureVoiceToggleButton(_ button: NSButton, frame: NSRect) {
        button.frame = frame
        button.title = "朗读 OFF"
        button.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.font = .systemFont(ofSize: 11, weight: .heavy)
        button.contentTintColor = NSColor(red: 0.40, green: 0.52, blue: 0.28, alpha: 1)
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.cornerRadius = frame.height / 2
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor(red: 0.78, green: 0.86, blue: 0.62, alpha: 0.45).cgColor
    }

    private func configureToolLogButton() {
        toolLogButton.frame = NSRect(
            x: 12,
            y: contentCardView.frame.height - 40,
            width: contentCardView.frame.width - 24,
            height: 30
        )
        toolLogButton.autoresizingMask = [.width, .minYMargin]
        toolLogButton.title = "工具/工作流：暂无"
        toolLogButton.image = NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: nil)
        toolLogButton.imagePosition = .imageLeading
        toolLogButton.imageScaling = .scaleProportionallyDown
        toolLogButton.isBordered = false
        toolLogButton.font = .systemFont(ofSize: 12, weight: .heavy)
        toolLogButton.contentTintColor = NSColor(red: 0.62, green: 0.34, blue: 0.12, alpha: 0.94)
        toolLogButton.wantsLayer = true
        toolLogButton.layer?.backgroundColor = NSColor(red: 1.0, green: 0.92, blue: 0.74, alpha: 0.46).cgColor
        toolLogButton.layer?.cornerRadius = 10
        toolLogButton.layer?.borderWidth = 1
        toolLogButton.layer?.borderColor = NSColor(red: 0.95, green: 0.64, blue: 0.32, alpha: 0.42).cgColor
        toolLogButton.target = self
        toolLogButton.action = #selector(showToolLogPressed)
        toolLogButton.toolTip = "展开或折叠最近工具/工作流记录"
        toolLogButton.cell?.lineBreakMode = .byTruncatingTail
        toolLogButton.isHidden = false
    }

    private func configureSuggestionPanel() {
        suggestionPanelView.frame = NSRect(x: 22, y: inputCardView.frame.maxY + 8, width: frame.width - 44, height: 0)
        suggestionPanelView.autoresizingMask = [.width, .maxYMargin]
        suggestionPanelView.wantsLayer = true
        suggestionPanelView.layer?.backgroundColor = NSColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 0.92).cgColor
        suggestionPanelView.layer?.cornerRadius = 16
        suggestionPanelView.layer?.borderWidth = 1
        suggestionPanelView.layer?.borderColor = NSColor(red: 0.95, green: 0.64, blue: 0.32, alpha: 0.30).cgColor
        suggestionPanelView.layer?.shadowColor = NSColor(red: 0.38, green: 0.25, blue: 0.12, alpha: 0.12).cgColor
        suggestionPanelView.layer?.shadowOpacity = 1
        suggestionPanelView.layer?.shadowRadius = 12
        suggestionPanelView.layer?.shadowOffset = CGSize(width: 0, height: -3)
        suggestionPanelView.isHidden = true
        addSubview(suggestionPanelView, positioned: .above, relativeTo: inputCardView)
    }

    // MARK: - Input

    @objc private func inputSubmitted() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = selectedAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        inputField.stringValue = ""
        selectedAttachments.removeAll()
        renderAttachmentTray()
        hideSuggestions()

        submitMessage(text, attachments: attachments)
    }

    func submitProgrammaticMessage(_ text: String) {
        submitMessage(text, attachments: [])
    }

    private func submitMessage(_ rawText: String, attachments: [AgentAttachment]) {
        let text = normalizedText(rawText, attachments: attachments)
        appendUser(text, attachments: attachments)
        isStreaming = true
        currentAssistantText = ""
        if let handler = onSendMessageWithAttachments {
            handler(text, attachments)
        } else {
            onSendMessage?(text)
        }
    }

    private func normalizedText(_ text: String, attachments: [AgentAttachment]) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        let imageCount = attachments.filter { $0.kind == .image }.count
        let fileCount = attachments.filter { $0.kind == .file }.count
        if imageCount > 0 && fileCount > 0 { return "请分析这些图片和文件附件。" }
        if imageCount > 1 { return "请分析这些图片。" }
        if imageCount == 1 { return "请分析这张图片。" }
        if fileCount > 0 { return "请读取并分析这些文件附件。" }
        return ""
    }

    @objc private func showCapabilitiesPressed() {
        onShowCapabilities?()
    }

    @objc private func chooseImageAttachment() {
        let panel = NSOpenPanel()
        panel.title = "选择图片给小橘子"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        runPanel(panel) { [weak self] urls in
            self?.addAttachments(urls.map { AgentAttachment(kind: .image, url: $0) })
        }
    }

    @objc private func chooseFileAttachment() {
        let panel = NSOpenPanel()
        panel.title = "选择文件路径给小橘子"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        runPanel(panel) { [weak self] urls in
            self?.addAttachments(urls.map { AgentAttachment(kind: .file, url: $0) })
        }
    }

    @objc private func voiceRecordPressed() {
        onVoiceRecordToggle?()
    }

    @objc private func voiceTTSPressed() {
        onVoiceTTSToggle?()
    }

    @objc private func showToolLogPressed() {
        if let popover = toolLogPopover, popover.isShown {
            popover.performClose(nil)
            return
        }

        let t = theme
        let controller = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 340))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1).cgColor

        let scroll = NSScrollView(frame: NSRect(x: 10, y: 10, width: 540, height: 320))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let logTextView = NSTextView(frame: scroll.contentView.bounds)
        logTextView.autoresizingMask = [.width]
        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.drawsBackground = false
        logTextView.textContainerInset = NSSize(width: 8, height: 10)
        logTextView.textContainer?.widthTracksTextView = true
        logTextView.isVerticallyResizable = true
        logTextView.isHorizontallyResizable = false
        logTextView.textStorage?.setAttributedString(toolLogAttributedText(theme: t))
        toolLogTextView = logTextView

        scroll.documentView = logTextView
        container.addSubview(scroll)
        controller.view = container

        let popover = NSPopover()
        popover.contentSize = container.frame.size
        popover.behavior = .transient
        popover.contentViewController = controller
        toolLogPopover = popover
        popover.show(relativeTo: toolLogButton.bounds, of: toolLogButton, preferredEdge: .maxY)
    }

    private func runPanel(_ panel: NSOpenPanel, completion: @escaping ([URL]) -> Void) {
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            completion(panel.urls)
        }
        if let window = window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    private func addAttachments(_ attachments: [AgentAttachment]) {
        guard !attachments.isEmpty else { return }
        for attachment in attachments where !selectedAttachments.contains(attachment) {
            selectedAttachments.append(attachment)
        }
        renderAttachmentTray()
        window?.makeFirstResponder(inputField)
    }

    private func renderAttachmentTray() {
        attachmentTrayView.subviews.forEach { $0.removeFromSuperview() }
        guard !selectedAttachments.isEmpty else {
            attachmentTrayView.isHidden = true
            return
        }

        attachmentTrayView.isHidden = false
        let label = NSTextField(labelWithString: "附件")
        label.frame = NSRect(x: 10, y: 8, width: 32, height: 14)
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = NSColor(red: 0.45, green: 0.30, blue: 0.16, alpha: 0.88)
        attachmentTrayView.addSubview(label)

        var x: CGFloat = 46
        let maxWidth = attachmentTrayView.frame.width - 54
        for (idx, attachment) in selectedAttachments.prefix(5).enumerated() {
            let name = clippedAttachmentName(attachment.displayName)
            let chipWidth = min(max(CGFloat(name.count) * 7 + 42, 92), 168)
            if x + chipWidth > maxWidth { break }

            let chip = NSView(frame: NSRect(x: x, y: 4, width: chipWidth, height: 22))
            chip.wantsLayer = true
            chip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.58).cgColor
            chip.layer?.cornerRadius = 10
            chip.layer?.borderWidth = 1
            chip.layer?.borderColor = NSColor(red: 0.95, green: 0.66, blue: 0.34, alpha: 0.28).cgColor

            let iconName = attachment.kind == .image ? "photo" : "doc.text"
            let icon = NSImageView(frame: NSRect(x: 8, y: 4, width: 14, height: 14))
            icon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            icon.contentTintColor = NSColor(red: 0.81, green: 0.42, blue: 0.15, alpha: 0.95)
            chip.addSubview(icon)

            let title = NSTextField(labelWithString: name)
            title.frame = NSRect(x: 26, y: 4, width: chipWidth - 46, height: 14)
            title.font = .systemFont(ofSize: 10, weight: .semibold)
            title.textColor = NSColor(red: 0.30, green: 0.22, blue: 0.14, alpha: 0.95)
            title.lineBreakMode = .byTruncatingMiddle
            chip.addSubview(title)

            let remove = NSButton(frame: NSRect(x: chipWidth - 20, y: 3, width: 16, height: 16))
            remove.tag = idx
            remove.title = ""
            remove.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
            remove.imagePosition = .imageOnly
            remove.imageScaling = .scaleProportionallyDown
            remove.isBordered = false
            remove.contentTintColor = NSColor(red: 0.63, green: 0.42, blue: 0.25, alpha: 0.78)
            remove.target = self
            remove.action = #selector(removeAttachment(_:))
            chip.addSubview(remove)

            attachmentTrayView.addSubview(chip)
            x += chipWidth + 6
        }
    }

    @objc private func removeAttachment(_ sender: NSButton) {
        guard selectedAttachments.indices.contains(sender.tag) else { return }
        selectedAttachments.remove(at: sender.tag)
        renderAttachmentTray()
    }

    private func clippedAttachmentName(_ name: String) -> String {
        guard name.count > 22 else { return name }
        return String(name.prefix(10)) + "..." + String(name.suffix(8))
    }

    func clearTranscript() {
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        currentAssistantText = ""
        streamingStartLocation = nil
        streamingMessageStyle = nil
        isStreaming = false
    }

    func copyTranscriptToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textView.string, forType: .string)
    }

    func insertDraft(_ text: String) {
        inputField.stringValue = text
        window?.makeFirstResponder(inputField)
        inputField.currentEditor()?.selectedRange = NSRange(location: text.count, length: 0)
        refreshSuggestions()
    }

    func requestImageAttachmentPicker() {
        chooseImageAttachment()
    }

    func requestFileAttachmentPicker() {
        chooseFileAttachment()
    }

    func updatePlaceholder(_ text: String) {
        let t = theme
        placeholderText = text
        if let cell = inputField.cell as? PaddedTextFieldCell {
            cell.placeholderAttributedString = NSAttributedString(
                string: text,
                attributes: [.font: t.font, .foregroundColor: t.textDim]
            )
        } else {
            inputField.placeholderString = text
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        refreshSuggestions()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !currentSuggestions.isEmpty else { return false }

        switch commandSelector {
        case #selector(NSResponder.insertTab(_:)):
            applySuggestion(at: selectedSuggestionIndex)
            return true
        case #selector(NSResponder.moveDown(_:)):
            selectedSuggestionIndex = min(selectedSuggestionIndex + 1, currentSuggestions.count - 1)
            renderSuggestionButtons()
            return true
        case #selector(NSResponder.moveUp(_:)):
            selectedSuggestionIndex = max(selectedSuggestionIndex - 1, 0)
            renderSuggestionButtons()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hideSuggestions()
            return true
        default:
            return false
        }
    }

    private func refreshSuggestions() {
        let text = inputField.stringValue
        currentSuggestions = suggestionProvider?(text) ?? []
        selectedSuggestionIndex = min(selectedSuggestionIndex, max(currentSuggestions.count - 1, 0))
        renderSuggestionButtons()
    }

    private func hideSuggestions() {
        currentSuggestions.removeAll()
        selectedSuggestionIndex = 0
        suggestionPanelView.subviews.forEach { $0.removeFromSuperview() }
        suggestionPanelView.isHidden = true
    }

    private func renderSuggestionButtons() {
        suggestionPanelView.subviews.forEach { $0.removeFromSuperview() }
        guard !currentSuggestions.isEmpty else {
            suggestionPanelView.isHidden = true
            return
        }

        let rowH: CGFloat = 36
        let visible = min(currentSuggestions.count, 7)
        let panelH = CGFloat(visible) * rowH + 12
        suggestionPanelView.frame = NSRect(
            x: 22,
            y: inputCardView.frame.maxY + 8,
            width: frame.width - 44,
            height: panelH
        )
        suggestionPanelView.isHidden = false

        for (idx, suggestion) in currentSuggestions.prefix(visible).enumerated() {
            let y = panelH - 6 - CGFloat(idx + 1) * rowH
            let selected = idx == selectedSuggestionIndex
            let button = NSButton(frame: NSRect(x: 6, y: y, width: suggestionPanelView.frame.width - 12, height: rowH - 4))
            button.tag = idx
            button.title = ""
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 10
            button.layer?.backgroundColor = selected
                ? NSColor(red: 1.0, green: 0.74, blue: 0.46, alpha: 0.74).cgColor
                : NSColor.white.withAlphaComponent(0.34).cgColor
            button.target = self
            button.action = #selector(suggestionButtonPressed(_:))

            let title = NSTextField(labelWithString: suggestion.title)
            title.frame = NSRect(x: 12, y: 14, width: button.frame.width - 24, height: 14)
            title.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            title.textColor = NSColor(red: 0.30, green: 0.21, blue: 0.13, alpha: 1)
            title.lineBreakMode = .byTruncatingTail
            button.addSubview(title)

            let subtitle = NSTextField(labelWithString: suggestion.subtitle)
            subtitle.frame = NSRect(x: 12, y: 2, width: button.frame.width - 24, height: 12)
            subtitle.font = .systemFont(ofSize: 9, weight: .medium)
            subtitle.textColor = NSColor(red: 0.48, green: 0.36, blue: 0.22, alpha: 0.82)
            subtitle.lineBreakMode = .byTruncatingTail
            button.addSubview(subtitle)

            suggestionPanelView.addSubview(button)
        }
    }

    @objc private func suggestionButtonPressed(_ sender: NSButton) {
        applySuggestion(at: sender.tag)
    }

    private func applySuggestion(at index: Int) {
        guard currentSuggestions.indices.contains(index) else { return }
        let replacement = currentSuggestions[index].replacement
        inputField.stringValue = replacement
        window?.makeFirstResponder(inputField)
        inputField.currentEditor()?.selectedRange = NSRange(location: replacement.count, length: 0)
        refreshSuggestions()
    }

    func applyTheme() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        contentCardView.layer?.backgroundColor = NSColor(red: 1.0, green: 0.94, blue: 0.82, alpha: 0.84).cgColor
        contentCardView.layer?.borderColor = NSColor(red: 0.96, green: 0.61, blue: 0.28, alpha: 0.46).cgColor
        contentCardView.layer?.borderWidth = 1
        contentCardView.layer?.cornerRadius = 18
        contentCardView.layer?.shadowColor = NSColor(red: 0.35, green: 0.22, blue: 0.12, alpha: 0.10).cgColor
        contentCardView.layer?.shadowOpacity = 1
        contentCardView.layer?.shadowRadius = 10
        contentCardView.layer?.shadowOffset = CGSize(width: 0, height: -2)

        inputCardView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
        inputCardView.layer?.borderColor = NSColor(red: 0.68, green: 0.90, blue: 0.72, alpha: 0.52).cgColor
        inputCardView.layer?.borderWidth = 1
        inputCardView.layer?.cornerRadius = 29
        inputCardView.layer?.shadowColor = NSColor(red: 0.42, green: 0.66, blue: 0.45, alpha: 0.07).cgColor
        inputCardView.layer?.shadowOpacity = 1
        inputCardView.layer?.shadowRadius = 12
        inputCardView.layer?.shadowOffset = CGSize(width: 0, height: -3)

        textView.textColor = NSColor(red: 0.23, green: 0.28, blue: 0.22, alpha: 1)
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(red: 0.24, green: 0.62, blue: 0.34, alpha: 1),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        inputField.textColor = NSColor(red: 0.23, green: 0.28, blue: 0.22, alpha: 1)

        if let cell = inputField.cell as? PaddedTextFieldCell {
            cell.font = .systemFont(ofSize: 15, weight: .medium)
            cell.textColor = NSColor(red: 0.23, green: 0.28, blue: 0.22, alpha: 1)
            cell.placeholderAttributedString = NSAttributedString(
                string: placeholderText,
                attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor(red: 0.50, green: 0.58, blue: 0.50, alpha: 1)]
            )
        }
    }

    func setVoiceStatus(_ status: HermesVoiceStatus) {
        if status.recording {
            micButton.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
            micButton.contentTintColor = .white
            micButton.layer?.backgroundColor = NSColor(red: 0.92, green: 0.28, blue: 0.23, alpha: 0.95).cgColor
            micButton.layer?.borderColor = NSColor(red: 0.72, green: 0.08, blue: 0.06, alpha: 1).cgColor
            micButton.toolTip = "停止录音并交给 Hermes 转写"
        } else if status.processing {
            micButton.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: nil)
            micButton.contentTintColor = NSColor(red: 0.82, green: 0.42, blue: 0.12, alpha: 1)
            micButton.layer?.backgroundColor = NSColor(red: 1.0, green: 0.78, blue: 0.48, alpha: 0.36).cgColor
            micButton.layer?.borderColor = NSColor(red: 0.95, green: 0.54, blue: 0.18, alpha: 1).cgColor
            micButton.toolTip = "Hermes 正在转写语音"
        } else if status.enabled {
            micButton.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: nil)
            micButton.contentTintColor = NSColor(red: 0.30, green: 0.58, blue: 0.34, alpha: 1)
            micButton.layer?.backgroundColor = NSColor(red: 0.76, green: 0.92, blue: 0.66, alpha: 0.34).cgColor
            micButton.layer?.borderColor = NSColor(red: 0.38, green: 0.70, blue: 0.35, alpha: 0.9).cgColor
            micButton.toolTip = "点击开始 Hermes 语音输入"
        } else {
            micButton.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
            micButton.contentTintColor = NSColor(red: 0.40, green: 0.52, blue: 0.28, alpha: 1)
            micButton.layer?.backgroundColor = NSColor.clear.cgColor
            micButton.layer?.borderColor = NSColor(red: 0.78, green: 0.86, blue: 0.62, alpha: 0.45).cgColor
            micButton.toolTip = "点击开启 Hermes 语音并录一句"
        }

        if status.speaking {
            ttsButton.image = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: nil)
            ttsButton.title = "朗读 ON"
            ttsButton.contentTintColor = .white
            ttsButton.layer?.backgroundColor = NSColor(red: 1.0, green: 0.58, blue: 0.28, alpha: 0.92).cgColor
            ttsButton.layer?.borderColor = NSColor(red: 0.85, green: 0.36, blue: 0.10, alpha: 1).cgColor
            ttsButton.toolTip = "小橘子正在朗读 Hermes 回复"
        } else if status.ttsEnabled {
            ttsButton.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)
            ttsButton.title = "朗读 ON"
            ttsButton.contentTintColor = NSColor(red: 0.30, green: 0.58, blue: 0.34, alpha: 1)
            ttsButton.layer?.backgroundColor = NSColor(red: 0.76, green: 0.92, blue: 0.66, alpha: 0.34).cgColor
            ttsButton.layer?.borderColor = NSColor(red: 0.38, green: 0.70, blue: 0.35, alpha: 0.9).cgColor
            ttsButton.toolTip = "Hermes 回复朗读已开启"
        } else {
            ttsButton.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
            ttsButton.title = "朗读 OFF"
            ttsButton.contentTintColor = NSColor(red: 0.40, green: 0.52, blue: 0.28, alpha: 1)
            ttsButton.layer?.backgroundColor = NSColor.clear.cgColor
            ttsButton.layer?.borderColor = NSColor(red: 0.78, green: 0.86, blue: 0.62, alpha: 0.45).cgColor
            ttsButton.toolTip = "Hermes 回复朗读已关闭"
        }

        let label = voiceStatusText(for: status)
        voiceStatusLabel.stringValue = label
        voiceStatusLabel.isHidden = label.isEmpty
    }

    private func voiceStatusText(for status: HermesVoiceStatus) -> String {
        if status.recording { return "语音：正在听，点麦克风停止并转写" }
        if status.processing { return "语音：正在转写，等小橘子听写完" }
        if status.speaking { return "朗读：小橘子正在念 Hermes 回复" }
        if let diagnostic = voiceDiagnosticText(for: status) { return "语音：\(diagnostic)" }
        if status.ttsEnabled { return "朗读：已开启，Hermes 回复会自动读出来" }
        if status.enabled { return "语音：点麦克风开始，说完再点一次停止" }
        return "语音：点麦克风开始，说完再点一次停止"
    }

    private func voiceDiagnosticText(for status: HermesVoiceStatus) -> String? {
        let detail = status.details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
            return detail
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if status.available == false {
            let firstLine = status.details
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return firstLine?.isEmpty == false ? firstLine : "Hermes 语音依赖或麦克风不可用"
        }
        if status.audioAvailable == false { return "没有可用麦克风或录音依赖" }
        if status.sttAvailable == false { return "没有可用语音转写 provider" }
        return nil
    }

    // MARK: - Append Methods

    private var messageSpacing: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = 10
        p.paragraphSpacing = 6
        p.lineSpacing = 2.5
        return p
    }

    private func makeMessageRenderStyle(for speaker: MessageSpeaker) -> MessageRenderStyle {
        let block = ChatBubbleTextBlock()
        block.side = speaker == .owner ? .right : .left
        block.fillColor = messageBubbleColor(for: speaker)
        block.strokeColor = messageBubbleBorderColor(for: speaker)
        block.accentColor = messageAccentColor(for: speaker)
        block.stickerImageName = speaker == .assistant ? "MorangeAssistantBubbleSticker" : nil
        block.setContentWidth(speaker == .owner ? 62 : 78, type: .percentageValueType)
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        block.setWidth(0, type: .absoluteValueType, for: .border)
        block.setWidth(8, type: .absoluteValueType, for: .margin)
        if speaker == .owner {
            block.setWidth(120, type: .absoluteValueType, for: .margin, edge: .minX)
            block.setWidth(14, type: .absoluteValueType, for: .margin, edge: .maxX)
        } else {
            block.setWidth(14, type: .absoluteValueType, for: .margin, edge: .minX)
            block.setWidth(92, type: .absoluteValueType, for: .margin, edge: .maxX)
        }
        block.verticalAlignment = .middleAlignment

        return MessageRenderStyle(
            speaker: speaker,
            block: block,
            headerParagraph: messageParagraphStyle(for: speaker, block: block, isHeader: true, isCompact: false),
            bodyParagraph: messageParagraphStyle(for: speaker, block: block, isHeader: false, isCompact: false),
            compactParagraph: messageParagraphStyle(for: speaker, block: block, isHeader: false, isCompact: true)
        )
    }

    private func messageParagraphStyle(
        for speaker: MessageSpeaker,
        block: ChatBubbleTextBlock,
        isHeader: Bool,
        isCompact: Bool
    ) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        if !isHeader {
            p.textBlocks = [block]
        }
        p.alignment = speaker == .owner ? .right : .left
        p.lineSpacing = isCompact ? 1.3 : 2.4
        p.paragraphSpacingBefore = isHeader ? 12 : 0
        p.paragraphSpacing = isHeader ? 3 : (isCompact ? 2 : 5)
        p.firstLineHeadIndent = 0
        p.headIndent = 0
        p.tailIndent = 0
        return p
    }

    private func messageBubbleColor(for speaker: MessageSpeaker) -> NSColor {
        switch speaker {
        case .owner:
            return NSColor(red: 0.73, green: 0.95, blue: 0.60, alpha: 0.98)
        case .assistant:
            return NSColor(red: 1.0, green: 0.60, blue: 0.22, alpha: 0.98)
        }
    }

    private func messageBubbleBorderColor(for speaker: MessageSpeaker) -> NSColor {
        switch speaker {
        case .owner:
            return NSColor(red: 0.38, green: 0.72, blue: 0.34, alpha: 0.82)
        case .assistant:
            return NSColor(red: 0.95, green: 0.34, blue: 0.08, alpha: 0.88)
        }
    }

    private func speakerNameAttributes(_ speaker: MessageSpeaker, style: MessageRenderStyle) -> [NSAttributedString.Key: Any] {
        let color: NSColor = speaker == .owner
            ? NSColor(red: 0.22, green: 0.50, blue: 0.27, alpha: 0.96)
            : NSColor(red: 0.86, green: 0.30, blue: 0.02, alpha: 0.98)
        return [
            .font: NSFont.systemFont(ofSize: 12, weight: .heavy),
            .foregroundColor: color,
            .paragraphStyle: style.headerParagraph
        ]
    }

    private func messageFont(for speaker: MessageSpeaker) -> NSFont {
        let t = theme
        switch speaker {
        case .owner:
            return NSFont.systemFont(ofSize: t.font.pointSize + 0.5, weight: .semibold)
        case .assistant:
            return NSFont.systemFont(ofSize: t.font.pointSize + 0.8, weight: .semibold)
        }
    }

    private func messageBoldFont(for speaker: MessageSpeaker) -> NSFont {
        let t = theme
        switch speaker {
        case .owner:
            return NSFont.systemFont(ofSize: t.font.pointSize + 0.4, weight: .bold)
        case .assistant:
            return NSFont.systemFont(ofSize: t.font.pointSize + 0.8, weight: .bold)
        }
    }

    private func messageTextColor(for speaker: MessageSpeaker) -> NSColor {
        switch speaker {
        case .owner:
            return NSColor(red: 0.10, green: 0.28, blue: 0.16, alpha: 1)
        case .assistant:
            return NSColor(red: 0.20, green: 0.11, blue: 0.04, alpha: 1)
        }
    }

    private func messageAccentColor(for speaker: MessageSpeaker) -> NSColor {
        switch speaker {
        case .owner:
            return NSColor(red: 0.24, green: 0.58, blue: 0.29, alpha: 1)
        case .assistant:
            return NSColor(red: 0.64, green: 0.18, blue: 0.02, alpha: 1)
        }
    }

    private func appendSpeakerHeader(_ speaker: MessageSpeaker, style: MessageRenderStyle) {
        ensureNewline()
        let title = speaker == .owner ? "主人" : "小橘子"
        textView.textStorage?.append(NSAttributedString(string: "\(title)\n", attributes: speakerNameAttributes(speaker, style: style)))
    }

    private func ensureNewline() {
        if let storage = textView.textStorage, storage.length > 0 {
            if !storage.string.hasSuffix("\n") {
                storage.append(NSAttributedString(string: "\n"))
            }
        }
    }

    func appendUser(_ text: String, attachments: [AgentAttachment] = []) {
        let t = theme
        let style = makeMessageRenderStyle(for: .owner)
        appendSpeakerHeader(.owner, style: style)
        let para = style.bodyParagraph
        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(string: "\(text)\n", attributes: [
            .font: messageFont(for: .owner),
            .foregroundColor: messageTextColor(for: .owner),
            .paragraphStyle: para
        ]))
        if !attachments.isEmpty {
            let summary = attachments.map { attachment in
                let prefix = attachment.kind == .image ? "图片" : "文件"
                return "\(prefix): \(attachment.displayName)"
            }.joined(separator: "；")
            attributed.append(NSAttributedString(string: "  附件 \(summary)\n", attributes: [
                .font: NSFont.systemFont(ofSize: t.font.pointSize - 1, weight: .medium),
                .foregroundColor: messageAccentColor(for: .owner),
                .paragraphStyle: style.compactParagraph
            ]))
        }
        textView.textStorage?.append(attributed)
        scrollToBottom()
    }

    private func appendAssistant(_ text: String) {
        let style = makeMessageRenderStyle(for: .assistant)
        appendSpeakerHeader(.assistant, style: style)
        textView.textStorage?.append(renderMarkdown(text + "\n", speaker: .assistant, style: style))
    }

    func appendStreamingText(_ text: String) {
        guard let storage = textView.textStorage else { return }
        var cleaned = sanitizedStreamingText(text)
        if currentAssistantText.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: "^\n+", with: "", options: .regularExpression)
            guard !cleaned.isEmpty else { return }
            let style = makeMessageRenderStyle(for: .assistant)
            appendSpeakerHeader(.assistant, style: style)
            streamingMessageStyle = style
            streamingStartLocation = storage.length
            isStreaming = true
        }
        guard !cleaned.isEmpty else { return }
        currentAssistantText += cleaned
        storage.append(NSAttributedString(string: cleaned, attributes: streamingAttributes(style: streamingMessageStyle)))
        scrollToBottom()
    }

    func endStreaming() {
        guard isStreaming || streamingStartLocation != nil else { return }
        if let storage = textView.textStorage,
           let start = streamingStartLocation,
           start >= 0,
           start <= storage.length {
            let length = max(0, storage.length - start)
            var finalText = currentAssistantText
            if !finalText.isEmpty && !finalText.hasSuffix("\n") {
                finalText += "\n"
            }
            storage.replaceCharacters(
                in: NSRange(location: start, length: length),
                with: renderMarkdown(finalText, speaker: .assistant, style: streamingMessageStyle ?? makeMessageRenderStyle(for: .assistant))
            )
        }
        currentAssistantText = ""
        streamingStartLocation = nil
        streamingMessageStyle = nil
        isStreaming = false
        scrollToBottom()
    }

    func appendError(_ text: String) {
        endStreaming()
        let t = theme
        textView.textStorage?.append(NSAttributedString(string: text + "\n", attributes: [
            .font: t.font, .foregroundColor: t.errorColor
        ]))
        scrollToBottom()
    }

    func appendToolUse(toolName: String, summary: String) {
        appendToolLogEntry(title: toolName, summary: summary, isError: false)
    }

    func appendToolResult(summary: String, isError: Bool) {
        appendToolLogEntry(title: isError ? "工具失败" : "工具完成", summary: summary, isError: isError)
    }

    private func appendToolLogEntry(title: String, summary: String, isError: Bool) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        toolLogEntries.append(ToolLogEntry(
            timestamp: Date(),
            title: cleanTitle.isEmpty ? "工具事件" : cleanTitle,
            summary: cleanSummary,
            isError: isError
        ))
        if toolLogEntries.count > 80 {
            toolLogEntries.removeFirst(toolLogEntries.count - 80)
        }
        updateToolLogButton()
        if let popover = toolLogPopover, popover.isShown {
            toolLogTextView?.textStorage?.setAttributedString(toolLogAttributedText(theme: theme))
            toolLogTextView?.scrollToBeginningOfDocument(nil)
        }
    }

    private func updateToolLogButton() {
        guard let latest = toolLogEntries.last else {
            toolLogButton.isHidden = false
            toolLogButton.title = "工具/工作流：暂无"
            toolLogButton.toolTip = "展开或折叠最近工具/工作流记录"
            toolLogButton.layer?.backgroundColor = NSColor(red: 1.0, green: 0.92, blue: 0.74, alpha: 0.46).cgColor
            toolLogButton.layer?.borderColor = NSColor(red: 0.95, green: 0.64, blue: 0.32, alpha: 0.42).cgColor
            return
        }
        toolLogButton.isHidden = false
        toolLogButton.title = latest.isError
            ? "工具/工作流 \(toolLogEntries.count) · 失败 · \(latest.title)"
            : "工具/工作流 \(toolLogEntries.count) · \(latest.title)"
        toolLogButton.toolTip = latest.summary.isEmpty ? latest.title : "\(latest.title)：\(latest.summary)"
        toolLogButton.layer?.backgroundColor = latest.isError
            ? NSColor(red: 1.0, green: 0.72, blue: 0.62, alpha: 0.66).cgColor
            : NSColor(red: 1.0, green: 0.84, blue: 0.42, alpha: 0.58).cgColor
        toolLogButton.layer?.borderColor = latest.isError
            ? NSColor(red: 0.88, green: 0.22, blue: 0.16, alpha: 0.58).cgColor
            : NSColor(red: 0.92, green: 0.50, blue: 0.12, alpha: 0.52).cgColor
    }

    private func sanitizedStreamingText(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0007}", with: "")
        let patterns = [
            "\u{001B}\\][^\u{0007}\u{001B}]*(?:\u{0007}|\u{001B}\\\\)",
            "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            "\u{001B}[()][A-Za-z0-9]",
            "\u{001B}[@-Z\\\\-_]"
        ]
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let scalars = cleaned.unicodeScalars.filter { scalar in
            scalar.value >= 32 || scalar.value == 10 || scalar.value == 9
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private func streamingAttributes(style: MessageRenderStyle?) -> [NSAttributedString.Key: Any] {
        return [
            .font: messageFont(for: .assistant),
            .foregroundColor: messageTextColor(for: .assistant),
            .paragraphStyle: style?.bodyParagraph ?? messageSpacing
        ]
    }

    private func toolLogAttributedText(theme t: PopoverTheme) -> NSAttributedString {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let body = NSMutableAttributedString()
        body.append(NSAttributedString(string: "小橘子工具记录\n", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .heavy),
            .foregroundColor: t.textPrimary
        ]))
        body.append(NSAttributedString(string: "默认折叠，保留最近 80 条。点选文本可以复制给我排查。\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: t.textDim
        ]))

        for entry in toolLogEntries.reversed() {
            let color = entry.isError ? t.errorColor : t.accentColor
            body.append(NSAttributedString(string: "[\(formatter.string(from: entry.timestamp))] \(entry.title)\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                .foregroundColor: color
            ]))
            if !entry.summary.isEmpty {
                body.append(NSAttributedString(string: "  \(entry.summary)\n", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: t.textPrimary
                ]))
            }
            body.append(NSAttributedString(string: "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 4),
                .foregroundColor: t.textDim
            ]))
        }
        return body
    }

    func appendVoiceTranscript(_ text: String) {
        let style = makeMessageRenderStyle(for: .owner)
        appendSpeakerHeader(.owner, style: style)
        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(string: "语音转写\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .heavy),
            .foregroundColor: messageAccentColor(for: .owner),
            .paragraphStyle: style.compactParagraph
        ]))
        attributed.append(NSAttributedString(string: "\(text)\n", attributes: [
            .font: messageFont(for: .owner),
            .foregroundColor: messageTextColor(for: .owner),
            .paragraphStyle: style.bodyParagraph
        ]))
        textView.textStorage?.append(attributed)
        scrollToBottom()
    }

    func replayHistory(_ messages: [AgentMessage]) {
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        currentAssistantText = ""
        streamingStartLocation = nil
        streamingMessageStyle = nil
        isStreaming = false
        toolLogEntries.removeAll()
        updateToolLogButton()
        for msg in messages {
            switch msg.role {
            case .user:
                appendUser(msg.text)
            case .assistant:
                appendAssistant(msg.text)
            case .error:
                continue
            case .toolUse:
                appendToolLogFromHistory(msg.text, isError: false)
            case .toolResult:
                appendToolLogFromHistory(msg.text, isError: false)
            }
        }
        scrollToBottom()
    }

    private func appendToolLogFromHistory(_ text: String, isError: Bool) {
        let lines = text.components(separatedBy: .newlines)
        let title = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "工具事件"
        let summary = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        appendToolLogEntry(title: title.isEmpty ? "工具事件" : title, summary: summary, isError: isError)
    }

    private func scrollToBottom() {
        textView.scrollToEndOfDocument(nil)
    }

    // MARK: - Markdown Rendering

    private func renderMarkdown(
        _ text: String,
        speaker: MessageSpeaker = .assistant,
        style: MessageRenderStyle? = nil
    ) -> NSAttributedString {
        let t = theme
        let activeStyle = style ?? makeMessageRenderStyle(for: speaker)
        let para = activeStyle.bodyParagraph
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeLines: [String] = []

        for (i, line) in lines.enumerated() {
            let suffix = i < lines.count - 1 ? "\n" : ""

            if line.hasPrefix("```") {
                if inCodeBlock {
                    let codeText = codeLines.joined(separator: "\n")
                    let codeFont = NSFont.monospacedSystemFont(ofSize: t.font.pointSize - 1, weight: .regular)
                    result.append(NSAttributedString(string: codeText + "\n", attributes: [
                        .font: codeFont,
                        .foregroundColor: messageTextColor(for: speaker),
                        .backgroundColor: t.inputBg,
                        .paragraphStyle: para
                    ]))
                    inCodeBlock = false
                    codeLines = []
                } else {
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            if line.hasPrefix("### ") {
                result.append(NSAttributedString(string: String(line.dropFirst(4)) + suffix, attributes: [
                    .font: NSFont.systemFont(ofSize: t.font.pointSize, weight: .bold),
                    .foregroundColor: messageAccentColor(for: speaker),
                    .paragraphStyle: para
                ]))
            } else if line.hasPrefix("## ") {
                result.append(NSAttributedString(string: String(line.dropFirst(3)) + suffix, attributes: [
                    .font: NSFont.systemFont(ofSize: t.font.pointSize + 1, weight: .bold),
                    .foregroundColor: messageAccentColor(for: speaker),
                    .paragraphStyle: para
                ]))
            } else if line.hasPrefix("# ") {
                result.append(NSAttributedString(string: String(line.dropFirst(2)) + suffix, attributes: [
                    .font: NSFont.systemFont(ofSize: t.font.pointSize + 2, weight: .bold),
                    .foregroundColor: messageAccentColor(for: speaker),
                    .paragraphStyle: para
                ]))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let content = String(line.dropFirst(2))
                result.append(NSAttributedString(string: "  \u{2022} ", attributes: [
                    .font: messageFont(for: speaker),
                    .foregroundColor: messageAccentColor(for: speaker),
                    .paragraphStyle: para
                ]))
                result.append(renderInlineMarkdown(content + suffix, theme: t, speaker: speaker, style: activeStyle))
            } else {
                result.append(renderInlineMarkdown(line + suffix, theme: t, speaker: speaker, style: activeStyle))
            }
        }

        if inCodeBlock && !codeLines.isEmpty {
            let codeText = codeLines.joined(separator: "\n")
            let codeFont = NSFont.monospacedSystemFont(ofSize: t.font.pointSize - 1, weight: .regular)
            result.append(NSAttributedString(string: codeText + "\n", attributes: [
                .font: codeFont,
                .foregroundColor: messageTextColor(for: speaker),
                .backgroundColor: t.inputBg,
                .paragraphStyle: para
            ]))
        }

        return result
    }

    private func renderInlineMarkdown(
        _ text: String,
        theme t: PopoverTheme,
        speaker: MessageSpeaker = .assistant,
        style: MessageRenderStyle? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let para = style?.bodyParagraph ?? messageSpacing
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "`" {
                let afterTick = text.index(after: i)
                if afterTick < text.endIndex, let closeIdx = text[afterTick...].firstIndex(of: "`") {
                    let code = String(text[afterTick..<closeIdx])
                    let codeFont = NSFont.monospacedSystemFont(ofSize: t.font.pointSize - 0.5, weight: .regular)
                    result.append(NSAttributedString(string: code, attributes: [
                        .font: codeFont,
                        .foregroundColor: messageAccentColor(for: speaker),
                        .backgroundColor: t.inputBg,
                        .paragraphStyle: para
                    ]))
                    i = text.index(after: closeIdx)
                    continue
                }
            }
            if text[i] == "*",
               text.index(after: i) < text.endIndex, text[text.index(after: i)] == "*" {
                let start = text.index(i, offsetBy: 2)
                if start < text.endIndex, let range = text.range(of: "**", range: start..<text.endIndex) {
                    let bold = String(text[start..<range.lowerBound])
                    result.append(NSAttributedString(string: bold, attributes: [
                        .font: messageBoldFont(for: speaker),
                        .foregroundColor: messageTextColor(for: speaker),
                        .paragraphStyle: para
                    ]))
                    i = range.upperBound
                    continue
                }
            }
            if text[i] == "[" {
                let afterBracket = text.index(after: i)
                if afterBracket < text.endIndex,
                   let closeBracket = text[afterBracket...].firstIndex(of: "]") {
                    let parenStart = text.index(after: closeBracket)
                    if parenStart < text.endIndex && text[parenStart] == "(" {
                        let afterParen = text.index(after: parenStart)
                        if afterParen < text.endIndex,
                           let closeParen = text[afterParen...].firstIndex(of: ")") {
                            let linkText = String(text[afterBracket..<closeBracket])
                            let urlStr = String(text[afterParen..<closeParen])
                            var attrs: [NSAttributedString.Key: Any] = [
                                .font: messageFont(for: speaker),
                                .foregroundColor: messageAccentColor(for: speaker),
                                .underlineStyle: NSUnderlineStyle.single.rawValue,
                                .paragraphStyle: para
                            ]
                            if let url = URL(string: urlStr) {
                                attrs[.link] = url
                                attrs[.cursor] = NSCursor.pointingHand
                            }
                            result.append(NSAttributedString(string: linkText, attributes: attrs))
                            i = text.index(after: closeParen)
                            continue
                        }
                    }
                }
            }
            if text[i] == "h" {
                let remaining = String(text[i...])
                if remaining.hasPrefix("https://") || remaining.hasPrefix("http://") {
                    var j = i
                    while j < text.endIndex && !text[j].isWhitespace && text[j] != ")" && text[j] != ">" {
                        j = text.index(after: j)
                    }
                    let urlStr = String(text[i..<j])
                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: messageFont(for: speaker),
                        .foregroundColor: messageAccentColor(for: speaker),
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .paragraphStyle: para
                    ]
                    if let url = URL(string: urlStr) {
                        attrs[.link] = url
                    }
                    result.append(NSAttributedString(string: urlStr, attributes: attrs))
                    i = j
                    continue
                }
            }
            result.append(NSAttributedString(string: String(text[i]), attributes: [
                .font: messageFont(for: speaker),
                .foregroundColor: messageTextColor(for: speaker),
                .paragraphStyle: para
            ]))
            i = text.index(after: i)
        }
        return result
    }
}
