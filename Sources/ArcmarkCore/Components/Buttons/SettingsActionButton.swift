import AppKit

/// A button with background color, hover effect, and optional loading state.
/// Used in settings pages for action buttons like "Import" or "Check for Updates".
final class SettingsActionButton: NSButton {
    private struct Style {
        static let baseBackgroundColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(ThemeConstants.Opacity.minimal)
        static let hoverBackgroundColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(ThemeConstants.Opacity.extraSubtle)
        static let textColor = ThemeConstants.Colors.darkGray
        static let disabledBackgroundColor = NSColor(
            calibratedRed: 191.0/255.0, green: 193.0/255.0, blue: 195.0/255.0, alpha: 1.0)
        static let disabledTextColor = ThemeConstants.Colors.darkGray
        static let cornerRadius = ThemeConstants.CornerRadius.medium
        nonisolated(unsafe) static let font = ThemeConstants.Fonts.systemFont(size: 13, weight: .regular)
        static let height: CGFloat = 36
    }

    private var trackingArea: NSTrackingArea?
    private var spinner: NSProgressIndicator?
    private let originalTitle: String
    private(set) var isLoading: Bool = false

    func getIsLoading() -> Bool { isLoading }

    init(title: String) {
        self.originalTitle = title
        super.init(frame: .zero)
        self.title = title
        setupButton()
    }

    required init?(coder: NSCoder) {
        self.originalTitle = ""
        super.init(coder: coder)
        setupButton()
    }

    private func setupButton() {
        wantsLayer = true
        isBordered = false
        bezelStyle = .regularSquare
        font = Style.font
        layer?.backgroundColor = Style.baseBackgroundColor.cgColor
        layer?.cornerRadius = Style.cornerRadius
        updateTextColor(Style.textColor)
    }

    private func updateTextColor(_ color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: Style.font
        ]
        attributedTitle = NSAttributedString(string: originalTitle, attributes: attributes)
    }

    func setLoading(_ loading: Bool) {
        self.isLoading = loading

        if loading {
            if spinner == nil {
                let progressIndicator = NSProgressIndicator()
                progressIndicator.style = .spinning
                progressIndicator.controlSize = .small
                progressIndicator.translatesAutoresizingMaskIntoConstraints = false
                progressIndicator.appearance = NSAppearance(named: .aqua)

                addSubview(progressIndicator)

                NSLayoutConstraint.activate([
                    progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
                    progressIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                    progressIndicator.widthAnchor.constraint(equalToConstant: 16),
                    progressIndicator.heightAnchor.constraint(equalToConstant: 16)
                ])

                spinner = progressIndicator
            }

            layer?.backgroundColor = Style.disabledBackgroundColor.cgColor
            updateTextColor(Style.disabledTextColor)
            spinner?.startAnimation(nil)
            spinner?.isHidden = false
        } else {
            spinner?.stopAnimation(nil)
            spinner?.isHidden = true
            layer?.backgroundColor = Style.baseBackgroundColor.cgColor
            updateTextColor(Style.textColor)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isLoading { return }
        super.mouseDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if !isLoading {
            layer?.backgroundColor = Style.hoverBackgroundColor.cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if isLoading {
            layer?.backgroundColor = Style.disabledBackgroundColor.cgColor
        } else {
            layer?.backgroundColor = Style.baseBackgroundColor.cgColor
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Style.height)
    }
}
