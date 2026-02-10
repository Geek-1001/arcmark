import AppKit

/// Base class for custom views with hover state management
@MainActor
class BaseView: NSView {

    // MARK: - Hover State Management

    private var trackingArea: NSTrackingArea?
    private(set) var isHovered = false

    // MARK: - Lifecycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    // MARK: - Tracking Areas

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

    // MARK: - Mouse Events

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        handleHoverStateChanged()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        handleHoverStateChanged()
    }

    /// Refresh hover state based on current mouse position
    func refreshHoverState() {
        guard let window else {
            if isHovered {
                isHovered = false
                handleHoverStateChanged()
            }
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let hovered = bounds.contains(point)
        if hovered != isHovered {
            isHovered = hovered
            handleHoverStateChanged()
        }
    }

    // MARK: - Subclass Override Point

    /// Called when hover state changes. Override to update appearance.
    func handleHoverStateChanged() {
        // Subclasses override
    }
}
