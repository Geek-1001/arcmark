import AppKit

/// A custom toggle switch control that matches Arcmark's design aesthetic
final class CustomToggle: NSControl {
    private let titleLabel = NSTextField(labelWithString: "")
    private let switchContainer = NSView()
    private let switchThumb = NSView()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false
    private var thumbLeadingConstraint: NSLayoutConstraint?

    private let switchWidth: CGFloat = 32
    private let switchHeight: CGFloat = 18
    private let thumbSize: CGFloat = 14
    private let thumbInset: CGFloat = 2

    var isOn: Bool = false {
        didSet {
            if oldValue != isOn {
                updateAppearance(animated: true)
                sendAction(action, to: target)
            }
        }
    }

    var titleText: String {
        get { titleLabel.stringValue }
        set {
            titleLabel.stringValue = newValue
            setAccessibilityLabel(newValue)
        }
    }

    init(title: String) {
        super.init(frame: .zero)
        titleLabel.stringValue = title
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    private func setupView() {
        wantsLayer = true
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(titleLabel.stringValue)

        // Title label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        titleLabel.textColor = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)
        titleLabel.lineBreakMode = .byTruncatingTail

        // Switch container
        switchContainer.translatesAutoresizingMaskIntoConstraints = false
        switchContainer.wantsLayer = true
        switchContainer.layer?.cornerRadius = switchHeight / 2

        // Switch thumb
        switchThumb.translatesAutoresizingMaskIntoConstraints = false
        switchThumb.wantsLayer = true
        switchThumb.layer?.cornerRadius = thumbSize / 2

        addSubview(titleLabel)
        addSubview(switchContainer)
        switchContainer.addSubview(switchThumb)

        thumbLeadingConstraint = switchThumb.leadingAnchor.constraint(equalTo: switchContainer.leadingAnchor, constant: thumbInset)

        NSLayoutConstraint.activate([
            // Title label
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Switch container
            switchContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            switchContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            switchContainer.widthAnchor.constraint(equalToConstant: switchWidth),
            switchContainer.heightAnchor.constraint(equalToConstant: switchHeight),

            // Switch thumb
            thumbLeadingConstraint!,
            switchThumb.widthAnchor.constraint(equalToConstant: thumbSize),
            switchThumb.heightAnchor.constraint(equalToConstant: thumbSize),
            switchThumb.centerYAnchor.constraint(equalTo: switchContainer.centerYAnchor),
        ])

        updateAppearance(animated: false)
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

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateAppearance(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        updateAppearance(animated: false)

        guard let window else { return }
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            let point = convert(nextEvent.locationInWindow, from: nil)
            let inside = bounds.contains(point)

            switch nextEvent.type {
            case .leftMouseDragged:
                if isPressed != inside {
                    isPressed = inside
                    updateAppearance(animated: false)
                }
            case .leftMouseUp:
                isPressed = false
                if inside {
                    isOn.toggle()
                } else {
                    updateAppearance(animated: true)
                }
                keepTracking = false
            default:
                break
            }
        }
    }

    private func updateAppearance(animated: Bool) {
        let darkGray = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)

        // Switch background color
        let backgroundColor: NSColor
        if isOn {
            backgroundColor = darkGray
        } else {
            backgroundColor = darkGray.withAlphaComponent(0.15)
        }

        // Thumb color
        let thumbColor = NSColor.white

        // Position thumb
        let thumbLeadingOffset = isOn ? (switchWidth - thumbSize - thumbInset) : thumbInset

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

                switchContainer.layer?.backgroundColor = backgroundColor.cgColor
                switchThumb.layer?.backgroundColor = thumbColor.cgColor

                thumbLeadingConstraint?.constant = thumbLeadingOffset
                switchContainer.layoutSubtreeIfNeeded()
            }
        } else {
            switchContainer.layer?.backgroundColor = backgroundColor.cgColor
            switchThumb.layer?.backgroundColor = thumbColor.cgColor
            thumbLeadingConstraint?.constant = thumbLeadingOffset
        }

        // Update label opacity
        let labelOpacity: CGFloat = isEnabled ? 1.0 : 0.5
        titleLabel.alphaValue = labelOpacity

        // Update accessibility
        setAccessibilityValue(isOn ? "on" : "off")
    }
}
