import AppKit

final class IconTitleButton: BaseControl {
    struct Style {
        var backgroundColor: NSColor
        var hoverBackgroundOpacity: CGFloat
        var pressedBackgroundOpacity: CGFloat
        var foregroundColor: NSColor
        var foregroundInactiveOpacity: CGFloat
        var foregroundActiveOpacity: CGFloat
        var font: NSFont
        var iconPointSize: CGFloat
        var iconWeight: NSFont.Weight
        var iconTitleSpacing: CGFloat
        var horizontalPadding: CGFloat
        var verticalPadding: CGFloat
        var cornerRadius: CGFloat
        var fillsWidth: Bool

        static var pasteAction: Style {
            Style(
                backgroundColor: ThemeConstants.Colors.darkGray,
                hoverBackgroundOpacity: ThemeConstants.Opacity.minimal,
                pressedBackgroundOpacity: ThemeConstants.Opacity.extraSubtle,
                foregroundColor: ThemeConstants.Colors.darkGray,
                foregroundInactiveOpacity: ThemeConstants.Opacity.high,
                foregroundActiveOpacity: ThemeConstants.Opacity.full,
                font: ThemeConstants.Fonts.bodyMedium,
                iconPointSize: ThemeConstants.Sizing.iconMedium,
                iconWeight: .medium,
                iconTitleSpacing: ThemeConstants.Spacing.medium,
                horizontalPadding: ThemeConstants.Spacing.regular,
                verticalPadding: ThemeConstants.Spacing.regular,
                cornerRadius: ThemeConstants.CornerRadius.medium,
                fillsWidth: true
            )
        }

        static var addWorkspace: Style {
            Style(
                backgroundColor: ThemeConstants.Colors.darkGray,
                hoverBackgroundOpacity: ThemeConstants.Opacity.minimal,
                pressedBackgroundOpacity: ThemeConstants.Opacity.extraSubtle,
                foregroundColor: ThemeConstants.Colors.darkGray,
                foregroundInactiveOpacity: ThemeConstants.Opacity.high,
                foregroundActiveOpacity: ThemeConstants.Opacity.full,
                font: ThemeConstants.Fonts.bodySemibold,
                iconPointSize: ThemeConstants.Sizing.iconSmall,
                iconWeight: .medium,
                iconTitleSpacing: ThemeConstants.Spacing.small,
                horizontalPadding: ThemeConstants.Spacing.regular,
                verticalPadding: ThemeConstants.Spacing.regular,
                cornerRadius: ThemeConstants.CornerRadius.medium,
                fillsWidth: false
            )
        }

        var height: CGFloat {
            let textHeight = ceil(font.ascender - font.descender)
            let contentHeight = max(iconPointSize, textHeight)
            return contentHeight + (verticalPadding * 2)
        }
    }

    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var iconLeadingConstraint: NSLayoutConstraint?
    private var titleLeadingConstraint: NSLayoutConstraint?
    private var titleTrailingConstraint: NSLayoutConstraint?

    var style: Style {
        didSet {
            applyStyle()
        }
    }

    var symbolName: String {
        didSet {
            updateIcon()
        }
    }

    var titleText: String {
        get { titleField.stringValue }
        set {
            titleField.stringValue = newValue
            setAccessibilityLabel(newValue)
        }
    }

    init(title: String, symbolName: String, style: Style) {
        self.style = style
        self.symbolName = symbolName
        super.init(frame: .zero)
        titleField.stringValue = title
        setupView()
        updateIcon()
        applyStyle()
    }

    required init?(coder: NSCoder) {
        self.style = .pasteAction
        self.symbolName = "plus"
        super.init(coder: coder)
        setupView()
        updateIcon()
        applyStyle()
    }

    private func setupView() {
        layer?.masksToBounds = true
        setAccessibilityRole(.button)
        setAccessibilityLabel(titleField.stringValue)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingTail
        titleField.alignment = .left

        addSubview(imageView)
        addSubview(titleField)

        iconLeadingConstraint = imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: style.horizontalPadding)
        iconWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: style.iconPointSize)
        iconHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: style.iconPointSize)
        titleLeadingConstraint = titleField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: style.iconTitleSpacing)
        titleTrailingConstraint = titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -style.horizontalPadding)

        NSLayoutConstraint.activate([
            iconLeadingConstraint!,
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint!,
            iconHeightConstraint!,
            titleLeadingConstraint!,
            titleTrailingConstraint!,
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        if style.fillsWidth {
            titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        } else {
            titleField.setContentCompressionResistancePriority(.required, for: .horizontal)
            setContentHuggingPriority(.required, for: .horizontal)
        }
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func updateIcon() {
        let config = NSImage.SymbolConfiguration(pointSize: style.iconPointSize, weight: style.iconWeight)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        imageView.image?.isTemplate = true
    }

    private func applyStyle() {
        layer?.cornerRadius = style.cornerRadius
        titleField.font = style.font

        iconLeadingConstraint?.constant = style.horizontalPadding
        titleLeadingConstraint?.constant = style.iconTitleSpacing
        titleTrailingConstraint?.constant = -style.horizontalPadding
        iconWidthConstraint?.constant = style.iconPointSize
        iconHeightConstraint?.constant = style.iconPointSize

        updateIcon()
        updateAppearance()
    }

    override func handleHoverStateChanged() {
        updateAppearance()
    }

    override func handlePressedStateChanged() {
        updateAppearance()
    }

    private func updateAppearance() {
        let backgroundOpacity: CGFloat
        if isPressed {
            backgroundOpacity = style.pressedBackgroundOpacity
        } else if isHovered {
            backgroundOpacity = style.hoverBackgroundOpacity
        } else {
            backgroundOpacity = 0
        }

        if backgroundOpacity > 0 {
            layer?.backgroundColor = style.backgroundColor.withAlphaComponent(backgroundOpacity).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        let foregroundOpacity = (isPressed || isHovered) ? style.foregroundActiveOpacity : style.foregroundInactiveOpacity
        let foregroundColor = style.foregroundColor.withAlphaComponent(foregroundOpacity)
        titleField.textColor = foregroundColor
        imageView.contentTintColor = foregroundColor
    }
}
