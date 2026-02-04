import AppKit

final class IconTitleButton: NSControl {
    struct Style {
        var backgroundColor: NSColor
        var hoverBackgroundOpacity: CGFloat
        var pressedBackgroundOpacity: CGFloat
        var foregroundColor: NSColor
        var foregroundInactiveOpacity: CGFloat
        var foregroundActiveOpacity: CGFloat
        var font: NSFont
        var iconPointSize: CGFloat
        var iconWeight: NSFont.Weight
        var iconTitleSpacing: CGFloat
        var horizontalPadding: CGFloat
        var verticalPadding: CGFloat
        var cornerRadius: CGFloat
        var fillsWidth: Bool

        static var pasteAction: Style {
            Style(
                backgroundColor: NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0),
                hoverBackgroundOpacity: 0.06,
                pressedBackgroundOpacity: 0.10,
                foregroundColor: NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0),
                foregroundInactiveOpacity: 0.80,
                foregroundActiveOpacity: 1.00,
                font: NSFont.systemFont(ofSize: 14, weight: .medium),
                iconPointSize: 18,
                iconWeight: .medium,
                iconTitleSpacing: 8,
                horizontalPadding: 10,
                verticalPadding: 10,
                cornerRadius: 8,
                fillsWidth: true
            )
        }

        static var addWorkspace: Style {
            Style(
                backgroundColor: NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0),
                hoverBackgroundOpacity: 0.06,
                pressedBackgroundOpacity: 0.10,
                foregroundColor: NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0),
                foregroundInactiveOpacity: 0.80,
                foregroundActiveOpacity: 1.00,
                font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                iconPointSize: 14,
                iconWeight: .medium,
                iconTitleSpacing: 6,
                horizontalPadding: 10,
                verticalPadding: 10,
                cornerRadius: 8,
                fillsWidth: false
            )
        }

        var height: CGFloat {
            let textHeight = ceil(font.ascender - font.descender)
            let contentHeight = max(iconPointSize, textHeight)
            return contentHeight + (verticalPadding * 2)
        }
    }

    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var iconLeadingConstraint: NSLayoutConstraint?
    private var titleLeadingConstraint: NSLayoutConstraint?
    private var titleTrailingConstraint: NSLayoutConstraint?

    var style: Style {
        didSet {
            applyStyle()
        }
    }

    var symbolName: String {
        didSet {
            updateIcon()
        }
    }

    var titleText: String {
        get { titleField.stringValue }
        set {
            titleField.stringValue = newValue
            setAccessibilityLabel(newValue)
        }
    }

    init(title: String, symbolName: String, style: Style) {
        self.style = style
        self.symbolName = symbolName
        super.init(frame: .zero)
        titleField.stringValue = title
        setupView()
        updateIcon()
        applyStyle()
    }

    required init?(coder: NSCoder) {
        self.style = .pasteAction
        self.symbolName = "plus"
        super.init(coder: coder)
        setupView()
        updateIcon()
        applyStyle()
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityRole(.button)
        setAccessibilityLabel(titleField.stringValue)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingTail
        titleField.alignment = .left

        addSubview(imageView)
        addSubview(titleField)

        iconLeadingConstraint = imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: style.horizontalPadding)
        iconWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: style.iconPointSize)
        iconHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: style.iconPointSize)
        titleLeadingConstraint = titleField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: style.iconTitleSpacing)
        titleTrailingConstraint = titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -style.horizontalPadding)

        NSLayoutConstraint.activate([
            iconLeadingConstraint!,
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint!,
            iconHeightConstraint!,
            titleLeadingConstraint!,
            titleTrailingConstraint!,
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        if style.fillsWidth {
            titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        } else {
            titleField.setContentCompressionResistancePriority(.required, for: .horizontal)
            setContentHuggingPriority(.required, for: .horizontal)
        }
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func updateIcon() {
        let config = NSImage.SymbolConfiguration(pointSize: style.iconPointSize, weight: style.iconWeight)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        imageView.image?.isTemplate = true
    }

    private func applyStyle() {
        layer?.cornerRadius = style.cornerRadius
        titleField.font = style.font

        iconLeadingConstraint?.constant = style.horizontalPadding
        titleLeadingConstraint?.constant = style.iconTitleSpacing
        titleTrailingConstraint?.constant = -style.horizontalPadding
        iconWidthConstraint?.constant = style.iconPointSize
        iconHeightConstraint?.constant = style.iconPointSize

        updateIcon()
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func layout() {
        super.layout()
        refreshHoverState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        updateAppearance()

        guard let window else { return }
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            let point = convert(nextEvent.locationInWindow, from: nil)
            let inside = bounds.contains(point)

            switch nextEvent.type {
            case .leftMouseDragged:
                if isPressed != inside || isHovered != inside {
                    isPressed = inside
                    isHovered = inside
                    updateAppearance()
                }
            case .leftMouseUp:
                isPressed = false
                updateAppearance()
                if inside {
                    sendAction(action, to: target)
                }
                keepTracking = false
            default:
                break
            }
        }

        refreshHoverState()
    }

    private func refreshHoverState() {
        guard let window else {
            if isHovered {
                isHovered = false
                updateAppearance()
            }
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let hovered = bounds.contains(point)
        if hovered != isHovered {
            isHovered = hovered
            updateAppearance()
        }
    }

    private func updateAppearance() {
        let backgroundOpacity: CGFloat
        if isPressed {
            backgroundOpacity = style.pressedBackgroundOpacity
        } else if isHovered {
            backgroundOpacity = style.hoverBackgroundOpacity
        } else {
            backgroundOpacity = 0
        }

        if backgroundOpacity > 0 {
            layer?.backgroundColor = style.backgroundColor.withAlphaComponent(backgroundOpacity).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        let foregroundOpacity = (isPressed || isHovered) ? style.foregroundActiveOpacity : style.foregroundInactiveOpacity
        let foregroundColor = style.foregroundColor.withAlphaComponent(foregroundOpacity)
        titleField.textColor = foregroundColor
        imageView.contentTintColor = foregroundColor
    }
}
