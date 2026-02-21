import AppKit

/// An NSButton that adds horizontal padding to its intrinsic content size,
/// so layer-based borders have visible spacing around the title text.
final class PaddedTextButton: NSButton {
    private let hPadding: CGFloat

    init(hPadding: CGFloat) {
        self.hPadding = hPadding
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += hPadding * 2
        return size
    }
}
