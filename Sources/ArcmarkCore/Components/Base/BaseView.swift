import AppKit

/// Base class for custom views with hover state management.
///
/// `BaseView` provides a foundation for creating custom views that need hover state detection.
/// Unlike `BaseControl`, this class is designed for non-interactive views (like row views in lists)
/// that need to show hover feedback but don't implement button-like pressed state behavior.
///
/// ## Features
/// - Automatic hover state detection using tracking areas
/// - Automatic state refresh on layout and window changes
/// - No pressed state tracking (use `BaseControl` for interactive controls)
///
/// ## Usage
/// Subclass `BaseView` and override `handleHoverStateChanged()` to respond to hover state changes:
///
/// ```swift
/// final class MyRowView: BaseView {
///     override func handleHoverStateChanged() {
///         updateAppearance()
///     }
///
///     private func updateAppearance() {
///         layer?.backgroundColor = isHovered
///             ? ThemeConstants.Colors.darkGray.withAlphaComponent(0.06).cgColor
///             : NSColor.clear.cgColor
///     }
/// }
/// ```
///
/// ## Subclassing Notes
/// - Override `handleHoverStateChanged()` to respond to hover state changes
/// - The `isHovered` property is automatically managed
/// - Use `refreshHoverState()` if you need to manually sync the hover state
///
/// - SeeAlso: `BaseControl` for interactive controls with pressed state support
@MainActor
class BaseView: NSView {

    // MARK: - State Properties

    /// The tracking area used for hover detection. Automatically managed.
    private var trackingArea: NSTrackingArea?

    /// Indicates whether the mouse is currently hovering over the view.
    /// This property is automatically updated by the base class.
    private(set) var isHovered = false

    // MARK: - Lifecycle

    /// Initializes the view with the specified frame rectangle.
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    /// Initializes the view from a coder (for Interface Builder support).
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    /// Common initialization logic. Enables layer backing for better performance.
    private func commonInit() {
        wantsLayer = true
    }

    /// Prevents the view from moving the window when clicked.
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

    /// Called when the mouse enters the view's tracking area.
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        handleHoverStateChanged()
    }

    /// Called when the mouse exits the view's tracking area.
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        handleHoverStateChanged()
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

    // MARK: - Subclass Override Point

    /// Called when the hover state changes.
    ///
    /// Override this method to update the view's appearance based on the `isHovered` property.
    /// This method is called automatically whenever the mouse enters or exits the view,
    /// or when the hover state is refreshed programmatically.
    ///
    /// Example:
    /// ```swift
    /// override func handleHoverStateChanged() {
    ///     layer?.backgroundColor = isHovered
    ///         ? ThemeConstants.Colors.darkGray.withAlphaComponent(0.06).cgColor
    ///         : NSColor.clear.cgColor
    /// }
    /// ```
    func handleHoverStateChanged() {
        // Subclasses override
    }
}
