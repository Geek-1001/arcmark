import AppKit

@MainActor
final class IconPickerItemView: BaseControl {

    private let label = NSTextField(labelWithString: "")
    private let imageView = NSImageView()

    enum Content {
        case emoji(String)
        case sfSymbol(String)
        case favicon(NSImage)
    }

    var onItemSelected: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        layer?.cornerRadius = ThemeConstants.CornerRadius.small

        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 20)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        addSubview(label)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        addSubview(imageView)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    func configure(content: Content) {
        label.isHidden = true
        imageView.isHidden = true

        switch content {
        case .emoji(let emoji):
            label.stringValue = emoji
            label.isHidden = false
        case .sfSymbol(let name):
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            imageView.image = image
            imageView.contentTintColor = ThemeConstants.Colors.darkGray
                .withAlphaComponent(ThemeConstants.Opacity.high)
            imageView.isHidden = false
        case .favicon(let image):
            image.isTemplate = false
            imageView.image = image
            imageView.contentTintColor = nil
            imageView.isHidden = false
        }
    }

    override func handleHoverStateChanged() {
        layer?.backgroundColor = isHovered
            ? ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.minimal).cgColor
            : NSColor.clear.cgColor
    }

    override func handlePressedStateChanged() {
        layer?.backgroundColor = isPressed
            ? ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.subtle).cgColor
            : isHovered
                ? ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.minimal).cgColor
                : NSColor.clear.cgColor
    }

    override func performAction() {
        onItemSelected?()
    }
}
