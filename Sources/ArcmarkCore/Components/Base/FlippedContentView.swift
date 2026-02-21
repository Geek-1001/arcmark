import AppKit

/// A custom NSView that uses flipped coordinates so content is anchored to the top.
///
/// Use this as the document view in an `NSScrollView` when you want content to flow
/// from the top down, matching the natural reading direction.
final class FlippedContentView: NSView {
    override var isFlipped: Bool {
        true
    }
}
