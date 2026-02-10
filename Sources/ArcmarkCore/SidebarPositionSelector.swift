import AppKit

/// A custom button group for selecting sidebar position with styled buttons and icons
final class SidebarPositionSelector: NSControl {
    private let leftButton = NSView()
    private let rightButton = NSView()
    private let leftIcon = NSImageView()
    private let leftLabel = NSTextField(labelWithString: "Left side")
    private let rightIcon = NSImageView()
    private let rightLabel = NSTextField(labelWithString: "Right side")

    private var trackingArea: NSTrackingArea?
    private var hoveredButton: NSView?
    private var pressedButton: NSView?

    private let buttonHeight: CGFloat = ThemeConstants.Sizing.buttonHeight + 4
    private let spacing: CGFloat = ThemeConstants.Spacing.medium
    private let cornerRadius: CGFloat = ThemeConstants.CornerRadius.medium

    var selectedPosition: String? {
        didSet {
            if oldValue != selectedPosition {
                updateAppearance(animated: true)
            }
        }
    }

    var onPositionChanged: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Sidebar Position")

        // Left button setup
        leftButton.translatesAutoresizingMaskIntoConstraints = false
        leftButton.wantsLayer = true
        leftButton.layer?.cornerRadius = cornerRadius

        leftIcon.translatesAutoresizingMaskIntoConstraints = false
        leftIcon.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        leftIcon.contentTintColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.high)

        leftLabel.translatesAutoresizingMaskIntoConstraints = false
        leftLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        leftLabel.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.high)
        leftLabel.isEditable = false
        leftLabel.isBordered = false
        leftLabel.backgroundColor = .clear

        // Right button setup
        rightButton.translatesAutoresizingMaskIntoConstraints = false
        rightButton.wantsLayer = true
        rightButton.layer?.cornerRadius = cornerRadius

        rightIcon.translatesAutoresizingMaskIntoConstraints = false
        rightIcon.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        rightIcon.contentTintColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.high)

        rightLabel.translatesAutoresizingMaskIntoConstraints = false
        rightLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        rightLabel.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.high)
        rightLabel.isEditable = false
        rightLabel.isBordered = false
        rightLabel.backgroundColor = .clear

        // Add subviews
        addSubview(leftButton)
        leftButton.addSubview(leftIcon)
        leftButton.addSubview(leftLabel)

        addSubview(rightButton)
        rightButton.addSubview(rightIcon)
        rightButton.addSubview(rightLabel)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Left button
            leftButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftButton.topAnchor.constraint(equalTo: topAnchor),
            leftButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftButton.heightAnchor.constraint(equalToConstant: buttonHeight),

            // Right button
            rightButton.leadingAnchor.constraint(equalTo: leftButton.trailingAnchor, constant: spacing),
            rightButton.topAnchor.constraint(equalTo: topAnchor),
            rightButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            rightButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightButton.widthAnchor.constraint(equalTo: leftButton.widthAnchor),

            // Left icon and label
            leftIcon.leadingAnchor.constraint(equalTo: leftButton.leadingAnchor, constant: 12),
            leftIcon.centerYAnchor.constraint(equalTo: leftButton.centerYAnchor),
            leftIcon.widthAnchor.constraint(equalToConstant: 16),
            leftIcon.heightAnchor.constraint(equalToConstant: 16),

            leftLabel.leadingAnchor.constraint(equalTo: leftIcon.trailingAnchor, constant: 6),
            leftLabel.centerYAnchor.constraint(equalTo: leftButton.centerYAnchor),
            leftLabel.trailingAnchor.constraint(lessThanOrEqualTo: leftButton.trailingAnchor, constant: -12),

            // Right icon and label
            rightIcon.leadingAnchor.constraint(equalTo: rightButton.leadingAnchor, constant: 12),
            rightIcon.centerYAnchor.constraint(equalTo: rightButton.centerYAnchor),
            rightIcon.widthAnchor.constraint(equalToConstant: 16),
            rightIcon.heightAnchor.constraint(equalToConstant: 16),

            rightLabel.leadingAnchor.constraint(equalTo: rightIcon.trailingAnchor, constant: 6),
            rightLabel.centerYAnchor.constraint(equalTo: rightButton.centerYAnchor),
            rightLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightButton.trailingAnchor, constant: -12),
        ])

        updateAppearance(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateHoveredButton(at: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHoveredButton(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoveredButton = nil
        updateAppearance(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        let point = convert(event.locationInWindow, from: nil)
        if leftButton.frame.contains(point) {
            pressedButton = leftButton
        } else if rightButton.frame.contains(point) {
            pressedButton = rightButton
        }

        updateAppearance(animated: false)

        guard let window else { return }
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            let nextPoint = convert(nextEvent.locationInWindow, from: nil)

            switch nextEvent.type {
            case .leftMouseDragged:
                let newPressed: NSView?
                if leftButton.frame.contains(nextPoint) {
                    newPressed = leftButton
                } else if rightButton.frame.contains(nextPoint) {
                    newPressed = rightButton
                } else {
                    newPressed = nil
                }

                if pressedButton !== newPressed {
                    pressedButton = newPressed
                    updateAppearance(animated: false)
                }

            case .leftMouseUp:
                if let pressedButton {
                    if pressedButton === leftButton && leftButton.frame.contains(nextPoint) {
                        selectedPosition = "left"
                        onPositionChanged?("left")
                        sendAction(action, to: target)
                    } else if pressedButton === rightButton && rightButton.frame.contains(nextPoint) {
                        selectedPosition = "right"
                        onPositionChanged?("right")
                        sendAction(action, to: target)
                    }
                }
                pressedButton = nil
                updateHoveredButton(at: nextEvent.locationInWindow)
                keepTracking = false

            default:
                break
            }
        }
    }

    private func updateHoveredButton(at locationInWindow: CGPoint) {
        guard isEnabled else {
            hoveredButton = nil
            return
        }

        let point = convert(locationInWindow, from: nil)
        let newHovered: NSView?

        if leftButton.frame.contains(point) {
            newHovered = leftButton
        } else if rightButton.frame.contains(point) {
            newHovered = rightButton
        } else {
            newHovered = nil
        }

        if hoveredButton !== newHovered {
            hoveredButton = newHovered
            updateAppearance(animated: true)
        }
    }

    private func updateAppearance(animated: Bool) {
        let darkGray = ThemeConstants.Colors.darkGray

        let updateButton: (NSView, NSImageView, NSTextField, String) -> Void = { button, icon, label, value in
            let isSelected = self.selectedPosition == value
            let isHovered = self.hoveredButton === button && self.isEnabled
            let isPressed = self.pressedButton === button

            // Background color
            let backgroundColor: NSColor
            if isSelected {
                backgroundColor = darkGray
            } else if isPressed {
                backgroundColor = darkGray.withAlphaComponent(ThemeConstants.Opacity.extraSubtle)
            } else if isHovered {
                backgroundColor = darkGray.withAlphaComponent(ThemeConstants.Opacity.minimal)
            } else {
                backgroundColor = darkGray.withAlphaComponent(ThemeConstants.Opacity.subtle)
            }

            // Text and icon color
            let foregroundColor: NSColor
            if isSelected {
                foregroundColor = ThemeConstants.Colors.white
            } else {
                foregroundColor = darkGray.withAlphaComponent(self.isEnabled ? ThemeConstants.Opacity.high : ThemeConstants.Opacity.low)
            }

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = ThemeConstants.Animation.durationFast
                    context.timingFunction = ThemeConstants.Animation.timingFunction
                    button.layer?.backgroundColor = backgroundColor.cgColor
                    icon.contentTintColor = foregroundColor
                    label.textColor = foregroundColor
                }
            } else {
                button.layer?.backgroundColor = backgroundColor.cgColor
                icon.contentTintColor = foregroundColor
                label.textColor = foregroundColor
            }
        }

        updateButton(leftButton, leftIcon, leftLabel, "left")
        updateButton(rightButton, rightIcon, rightLabel, "right")

        // Update accessibility
        setAccessibilityValue(selectedPosition)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            hoveredButton = nil
            pressedButton = nil
        }
        updateAppearance(animated: false)
    }
}
