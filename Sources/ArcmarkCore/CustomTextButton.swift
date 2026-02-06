import AppKit

/// A simple text-only button with hover state, styled like a hyperlink
final class CustomTextButton: NSControl {
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

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
        setAccessibilityRole(.button)
        setAccessibilityLabel(titleLabel.stringValue)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 0.8)
        titleLabel.alignment = .left

        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

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

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        NSCursor.pointingHand.push()
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        NSCursor.pop()
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
                if isPressed != inside {
                    isPressed = inside
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
    }

    private func updateAppearance() {
        let darkGray = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)

        if isPressed {
            titleLabel.textColor = darkGray.withAlphaComponent(0.6)
        } else if isHovered {
            titleLabel.textColor = darkGray.withAlphaComponent(1.0)
        } else {
            titleLabel.textColor = darkGray.withAlphaComponent(0.8)
        }

        if !isEnabled {
            titleLabel.textColor = darkGray.withAlphaComponent(0.4)
        }
    }
}
