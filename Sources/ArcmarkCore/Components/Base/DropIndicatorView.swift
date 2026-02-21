import AppKit

/// A reusable drop indicator view for drag-and-drop operations.
///
/// Supports two display modes:
/// - **Line mode** (`showLine`): A thin accent-colored line shown between items
/// - **Highlight mode** (`showHighlight`): A rounded highlight shown over a drop target (e.g., a folder)
///
/// The view passes through all hit tests so it never intercepts mouse events.
final class DropIndicatorView: NSView {
    private let lineThickness: CGFloat = 2
    private let highlightCornerRadius: CGFloat = 8
    private let accentColor = NSColor.controlAccentColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        isHidden = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = true
        isHidden = true
    }

    /// Shows a thin accent-colored line at the given frame.
    func showLine(in frame: NSRect) {
        isHidden = false
        self.frame = frame
        layer?.cornerRadius = lineThickness / 2
        layer?.backgroundColor = accentColor.cgColor
        layer?.borderWidth = 0
    }

    /// Shows a rounded highlight rectangle at the given frame.
    func showHighlight(in frame: NSRect) {
        isHidden = false
        self.frame = frame
        layer?.cornerRadius = highlightCornerRadius
        layer?.backgroundColor = accentColor.withAlphaComponent(0.12).cgColor
        layer?.borderColor = accentColor.cgColor
        layer?.borderWidth = 2
    }

    /// Hides the indicator.
    func hide() {
        isHidden = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
