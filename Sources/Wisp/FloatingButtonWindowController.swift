import AppKit

private let bubbleSize: CGFloat = 52
private let actionBubbleSize: CGFloat = 38
private let radialPanelSize = NSSize(width: 116, height: 104)

@MainActor
final class FloatingButtonWindowController: NSWindowController {
    private let bubbleView = FloatingBubbleView(frame: NSRect(x: 0, y: 0, width: bubbleSize, height: bubbleSize))
    private let pickerView = RadialModePickerView(frame: NSRect(origin: .zero, size: radialPanelSize))
    private var pickerPanel: NSPanel?
    private var hidePickerWorkItem: DispatchWorkItem?
    private var isRecording = false

    var onStartMode: ((DictationMode) -> Void)? {
        didSet {
            bubbleView.onStartMode = onStartMode
            pickerView.onStartMode = onStartMode
        }
    }

    var onStop: (() -> Void)? {
        didSet {
            bubbleView.onStop = onStop
        }
    }

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: bubbleSize, height: bubbleSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        panel.contentView = bubbleView

        super.init(window: panel)

        bubbleView.onHoverChanged = { [weak self] isHovering in
            if isHovering {
                self?.showPicker()
            } else {
                self?.schedulePickerHide()
            }
        }

        pickerView.onHoverChanged = { [weak self] isHovering in
            if isHovering {
                self?.cancelPickerHide()
            } else {
                self?.schedulePickerHide()
            }
        }

        positionWindow(panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showFloatingButton() {
        showWindow(nil)
        window?.orderFrontRegardless()
    }

    func update(isRecording: Bool, isTranscribing: Bool, statusMessage: String) {
        self.isRecording = isRecording
        bubbleView.update(isRecording: isRecording, isTranscribing: isTranscribing)
        window?.contentView?.toolTip = statusMessage

        if isRecording || isTranscribing {
            hidePicker()
        }
    }

    private func positionWindow(_ window: NSWindow) {
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            return
        }

        let x = screenFrame.maxX - bubbleSize - 16
        let y = screenFrame.midY - (bubbleSize / 2)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func showPicker() {
        guard !isRecording, let bubbleWindow = window else {
            return
        }

        cancelPickerHide()

        let panel = pickerPanel ?? makePickerPanel()
        pickerPanel = panel
        positionPicker(panel, beside: bubbleWindow.frame, on: bubbleWindow.screen)
        panel.orderFrontRegardless()
        bubbleWindow.orderFrontRegardless()
    }

    private func makePickerPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: radialPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.contentView = pickerView
        return panel
    }

    private func positionPicker(_ panel: NSPanel, beside bubbleFrame: NSRect, on screen: NSScreen?) {
        guard let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            return
        }

        let overlap: CGFloat = 42
        let sideMargin: CGFloat = 8
        let availableRight = visibleFrame.maxX - bubbleFrame.maxX
        let availableLeft = bubbleFrame.minX - visibleFrame.minX
        let availableAbove = visibleFrame.maxY - bubbleFrame.maxY
        let placement: RadialPlacement

        if availableRight >= radialPanelSize.width - overlap + sideMargin {
            placement = .right
        } else if availableLeft >= radialPanelSize.width - overlap + sideMargin {
            placement = .left
        } else if availableAbove >= radialPanelSize.height - overlap + sideMargin {
            placement = .above
        } else {
            placement = .below
        }

        let size = radialPanelSize
        panel.setContentSize(radialPanelSize)
        pickerView.frame = NSRect(origin: .zero, size: radialPanelSize)
        pickerView.configure(placement: placement)

        let x: CGFloat
        let y: CGFloat

        switch placement {
        case .right:
            x = bubbleFrame.maxX - overlap
            y = max(
                visibleFrame.minY + sideMargin,
                min(bubbleFrame.midY - size.height / 2, visibleFrame.maxY - size.height - sideMargin)
            )
        case .left:
            x = bubbleFrame.minX - size.width + overlap
            y = max(
                visibleFrame.minY + sideMargin,
                min(bubbleFrame.midY - size.height / 2, visibleFrame.maxY - size.height - sideMargin)
            )
        case .above:
            x = max(
                visibleFrame.minX + sideMargin,
                min(bubbleFrame.midX - size.width / 2, visibleFrame.maxX - size.width - sideMargin)
            )
            y = bubbleFrame.maxY - overlap
        case .below:
            x = max(
                visibleFrame.minX + sideMargin,
                min(bubbleFrame.midX - size.width / 2, visibleFrame.maxX - size.width - sideMargin)
            )
            y = bubbleFrame.minY - size.height + overlap
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func schedulePickerHide() {
        hidePickerWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.hidePicker()
            }
        }
        hidePickerWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func cancelPickerHide() {
        hidePickerWorkItem?.cancel()
        hidePickerWorkItem = nil
    }

    private func hidePicker() {
        cancelPickerHide()
        pickerPanel?.orderOut(nil)
    }
}

private final class FloatingBubbleView: NSView {
    var onStartMode: ((DictationMode) -> Void)?
    var onStop: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var isRecording = false
    private var isTranscribing = false
    private let effectView = NSVisualEffectView()
    private let iconView = NSImageView()
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = frameRect.width / 2
        layer?.masksToBounds = true

        effectView.frame = bounds
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        addSubview(effectView)

        // Thin inner ring for definition against busy wallpapers.
        let ring = CAShapeLayer()
        ring.frame = bounds
        ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 0.75, dy: 0.75), transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor.black.withAlphaComponent(0.12).cgColor
        ring.lineWidth = 1.0
        layer?.addSublayer(ring)

        iconView.frame = bounds.insetBy(dx: 14, dy: 14)
        iconView.autoresizingMask = [.width, .height]
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.imageAlignment = .alignCenter
        addSubview(iconView)

        renderIcon()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(isRecording: Bool, isTranscribing: Bool) {
        if self.isRecording == isRecording && self.isTranscribing == isTranscribing {
            return
        }
        self.isRecording = isRecording
        self.isTranscribing = isTranscribing
        renderIcon()
    }

    private func renderIcon() {
        let symbolName: String
        let tint: NSColor
        if isTranscribing {
            symbolName = "ellipsis"
            tint = .systemOrange
        } else if isRecording {
            symbolName = "waveform"
            tint = .systemRed
        } else {
            symbolName = "mic.fill"
            tint = .systemGreen
        }

        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Wisp")?
            .withSymbolConfiguration(config)
        iconView.image = image
        iconView.contentTintColor = tint
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }

        // Let macOS own the drag loop — smoother than a manual mouseDragged
        // handler, and doesn't fall behind on a small hit area. After it
        // returns, decide whether the gesture was a click or a drag based on
        // how far the window actually moved.
        let originBefore = window.frame.origin
        window.performDrag(with: event)
        let originAfter = window.frame.origin
        let moved = hypot(originAfter.x - originBefore.x, originAfter.y - originBefore.y)

        if moved < 4 {
            DebugLogger.log("bubble click moved=\(moved)")
            if isRecording {
                onStop?()
            } else {
                onHoverChanged?(true)
            }
        } else {
            DebugLogger.log("bubble drag moved=\(moved)")
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private enum RadialPlacement {
    case left
    case right
    case above
    case below
}

private final class RadialModePickerView: NSView {
    var onStartMode: ((DictationMode) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private let dictateButton = RadialActionButton(mode: .dictate, symbolName: "text.cursor")
    private let composeButton = RadialActionButton(mode: .compose, symbolName: "sparkles")
    private var trackingArea: NSTrackingArea?
    private var placement: RadialPlacement = .left

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.masksToBounds = false

        dictateButton.target = self
        dictateButton.action = #selector(startMode(_:))
        composeButton.target = self
        composeButton.action = #selector(startMode(_:))

        addSubview(dictateButton)
        addSubview(composeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(placement: RadialPlacement) {
        self.placement = placement
        positionButtons()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        positionButtons()
    }

    private func positionButtons() {
        let top = NSRect(
            x: bounds.midX - actionBubbleSize / 2,
            y: bounds.maxY - actionBubbleSize - 6,
            width: actionBubbleSize,
            height: actionBubbleSize
        )
        let bottom = NSRect(
            x: bounds.midX - actionBubbleSize / 2,
            y: 6,
            width: actionBubbleSize,
            height: actionBubbleSize
        )
        let left = NSRect(
            x: 6,
            y: bounds.midY - actionBubbleSize / 2,
            width: actionBubbleSize,
            height: actionBubbleSize
        )
        let right = NSRect(
            x: bounds.maxX - actionBubbleSize - 6,
            y: bounds.midY - actionBubbleSize / 2,
            width: actionBubbleSize,
            height: actionBubbleSize
        )

        switch placement {
        case .left, .right:
            dictateButton.frame = top
            composeButton.frame = bottom
        case .above, .below:
            dictateButton.frame = left
            composeButton.frame = right
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    @objc private func startMode(_ sender: RadialActionButton) {
        onStartMode?(sender.mode)
    }
}

private final class RadialActionButton: NSButton {
    let mode: DictationMode
    private let symbolName: String
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    init(mode: DictationMode, symbolName: String) {
        self.mode = mode
        self.symbolName = symbolName
        super.init(frame: .zero)

        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        title = ""
        contentTintColor = .systemGreen
        wantsLayer = true
        layer?.cornerRadius = actionBubbleSize / 2
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.32
        layer?.shadowRadius = 9
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        toolTip = mode.title
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        render()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        render()
    }

    private func render() {
        layer?.backgroundColor = isHovering
            ? NSColor.systemGreen.withAlphaComponent(0.95).cgColor
            : NSColor(calibratedWhite: 0.12, alpha: 0.96).cgColor
        contentTintColor = isHovering ? .black : .systemGreen

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: mode.title)?
            .withSymbolConfiguration(config)
    }
}
