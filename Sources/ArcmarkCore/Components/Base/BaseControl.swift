import AppKit

/// Base class for all interactive controls with hover and pressed states.
///
/// `BaseControl` provides a foundation for creating custom interactive controls with built-in
/// hover and pressed state management. It eliminates the need for repetitive tracking area setup
/// and mouse event handling code in subclasses.
///
/// ## Features
/// - Automatic hover state detection using tracking areas
/// - Pressed state tracking with proper drag-out behavior
/// - Mouse tracking loop for button-like controls
/// - Automatic state refresh on layout and window changes
///
/// ## Usage
/// Subclass `BaseControl` and override the handler methods to respond to state changes:
///
/// ```swift
/// final class MyButton: BaseControl {
///     override func handleHoverStateChanged() {
///         updateAppearance()
///     }
///
///     override func handlePressedStateChanged() {
///         updateAppearance()
///     }
///
///     private func updateAppearance() {
///         if isPressed {
///             // Show pressed appearance
///         } else if isHovered {
///             // Show hover appearance
///         } else {
///             // Show default appearance
///         }
///     }
/// }
/// ```
///
/// ## Subclassing Notes
/// - Override `handleHoverStateChanged()` to respond to hover state changes
/// - Override `handlePressedStateChanged()` to respond to pressed state changes
/// - Override `performAction()` if you need custom action behavior (default sends action to target)
/// - The `isHovered` and `isPressed` properties are automatically managed
///
/// - SeeAlso: `BaseView` for non-control views with hover state only
@MainActor
class BaseControl: NSControl {

    // MARK: - State Properties

    /// The tracking area used for hover detection. Automatically managed.
    private var trackingArea: NSTrackingArea?

    /// Indicates whether the mouse is currently hovering over the control.
    /// This property is automatically updated by the base class.
    private(set) var isHovered = false

    /// Indicates whether the control is currently being pressed.
    /// This property is automatically updated during mouse tracking.
    private(set) var isPressed = false

    // MARK: - Lifecycle

    /// Initializes the control with the specified frame rectangle.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    /// Initializes the control from a coder (for Interface Builder support).
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    /// Common initialization logic. Enables layer backing for better performance.
    private func commonInit() {
        wantsLayer = true
    }

    /// Prevents the control from moving the window when clicked.
    override var mouseDownCanMoveWindow: Bool {
        false
    }

    // MARK: - Tracking Areas

    /// Updates the tracking area to match the current bounds.
    /// This method is called automatically when the view's geometry changes.
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

    /// Called when the view's layout is updated. Refreshes hover state to handle geometry changes.
    override func layout() {
        super.layout()
        refreshHoverState()
    }

    /// Called when the view is added to or removed from a window. Refreshes hover state.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshHoverState()
    }

    // MARK: - Mouse Events

    /// Called when the mouse enters the control's tracking area.
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        handleHoverStateChanged()
    }

    /// Called when the mouse exits the control's tracking area.
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        handleHoverStateChanged()
    }

    /// Handles mouse down events and tracks the mouse until mouse up.
    ///
    /// This method implements a standard button-like tracking loop:
    /// - Sets pressed state to true
    /// - Tracks the mouse, updating pressed state based on whether the cursor is inside the bounds
    /// - Calls `performAction()` if the mouse is released inside the bounds
    /// - Updates hover state after tracking completes
    ///
    /// The control is disabled during tracking if `isEnabled` is false.
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        handlePressedStateChanged()

        guard let window else { return }
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { continue }
            let point = convert(nextEvent.locationInWindow, from: nil)
            let inside = bounds.contains(point)

            switch nextEvent.type {
            case .leftMouseDragged:
                let newPressed = inside
                let newHovered = inside
                if isPressed != newPressed || isHovered != newHovered {
                    isPressed = newPressed
                    isHovered = newHovered
                    handlePressedStateChanged()
                }
            case .leftMouseUp:
                isPressed = false
                handlePressedStateChanged()
                if inside {
                    performAction()
                }
                keepTracking = false
            default:
                break
            }
        }

        refreshHoverState()
    }

    /// Refreshes the hover state based on the current mouse position.
    ///
    /// This method is called automatically after layout changes and window attachment.
    /// It can also be called manually if the hover state needs to be synchronized
    /// with the current mouse position (e.g., after programmatic view changes).
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

    // MARK: - Subclass Override Points

    /// Called when the hover state changes.
    ///
    /// Override this method to update the control's appearance based on the `isHovered` property.
    /// This method is called automatically whenever the mouse enters or exits the control,
    /// or when the hover state is refreshed programmatically.
    ///
    /// Example:
    /// ```swift
    /// override func handleHoverStateChanged() {
    ///     layer?.backgroundColor = isHovered
    ///         ? ThemeConstants.Colors.darkGray.withAlphaComponent(0.1).cgColor
    ///         : NSColor.clear.cgColor
    /// }
    /// ```
    func handleHoverStateChanged() {
        // Subclasses override
    }

    /// Called when the pressed state changes.
    ///
    /// Override this method to update the control's appearance based on the `isPressed` property.
    /// This method is called during mouse tracking whenever the pressed state changes.
    ///
    /// Example:
    /// ```swift
    /// override func handlePressedStateChanged() {
    ///     layer?.backgroundColor = isPressed
    ///         ? ThemeConstants.Colors.darkGray.withAlphaComponent(0.2).cgColor
    ///         : NSColor.clear.cgColor
    /// }
    /// ```
    func handlePressedStateChanged() {
        // Subclasses override
    }

    /// Called when the control should perform its action.
    ///
    /// This method is called when the mouse is released inside the control's bounds
    /// after a mouse down event. The default implementation sends the control's action
    /// to its target.
    ///
    /// Override this method if you need custom action behavior:
    /// ```swift
    /// override func performAction() {
    ///     // Custom action logic
    ///     myCustomAction()
    ///     // Optionally still send the action
    ///     super.performAction()
    /// }
    /// ```
    func performAction() {
        sendAction(action, to: target)
    }
}
