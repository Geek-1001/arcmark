import AppKit

@MainActor
final class PinnedTabTileView: BaseControl {

    private let faviconView = NSImageView()
    private(set) var linkId: UUID?

    var onTileClicked: ((UUID) -> Void)?
    var onTileRightClicked: ((UUID, NSEvent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        layer?.cornerRadius = ThemeConstants.CornerRadius.medium
        layer?.backgroundColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(ThemeConstants.Opacity.extraSubtle).cgColor

        faviconView.translatesAutoresizingMaskIntoConstraints = false
        faviconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(faviconView)

        let iconSize = ThemeConstants.Sizing.iconLarge
        NSLayoutConstraint.activate([
            faviconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            faviconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: iconSize),
            faviconView.heightAnchor.constraint(equalToConstant: iconSize),
        ])
    }

    func configure(link: Link, iconsDirectory: URL?) {
        linkId = link.id

        if let path = link.faviconPath,
           FileManager.default.fileExists(atPath: path),
           let image = NSImage(contentsOfFile: path) {
            image.isTemplate = false
            faviconView.image = image
            faviconView.contentTintColor = nil
        } else {
            let config = NSImage.SymbolConfiguration(pointSize: ThemeConstants.Sizing.iconLarge, weight: .semibold)
            let globe = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            globe?.isTemplate = true
            faviconView.image = globe
            faviconView.contentTintColor = ThemeConstants.Colors.darkGray
                .withAlphaComponent(ThemeConstants.Opacity.low)
        }
    }

    // MARK: - State Overrides

    override func handleHoverStateChanged() {
        updateBackground()
    }

    override func handlePressedStateChanged() {
        updateBackground()
    }

    private func updateBackground() {
        let opacity: CGFloat
        if isPressed {
            opacity = ThemeConstants.Opacity.low
        } else if isHovered {
            opacity = ThemeConstants.Opacity.subtle
        } else {
            opacity = ThemeConstants.Opacity.extraSubtle
        }
        layer?.backgroundColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(opacity).cgColor
    }

    override func performAction() {
        guard let linkId else { return }
        onTileClicked?(linkId)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let linkId else { return }
        onTileRightClicked?(linkId, event)
    }
}
