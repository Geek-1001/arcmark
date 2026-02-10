import AppKit

/// A simple text-only button with hover state, styled like a hyperlink
final class CustomTextButton: BaseControl {
    private let titleLabel = NSTextField(labelWithString: "")

    var titleText: String {
        get { titleLabel.stringValue }
        set {
            titleLabel.stringValue = newValue
            setAccessibilityLabel(newValue)
        }
    }

    init(title: String) {
        super.init(frame: .zero)
        titleLabel.stringValue = title
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        setAccessibilityRole(.button)
        setAccessibilityLabel(titleLabel.stringValue)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = ThemeConstants.Fonts.systemFont(size: 13, weight: .medium)
        titleLabel.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.high)
        titleLabel.alignment = .left

        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateAppearance()
    }

    override func handleHoverStateChanged() {
        if isHovered {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
        updateAppearance()
    }

    override func handlePressedStateChanged() {
        updateAppearance()
    }

    private func updateAppearance() {
        if isPressed {
            titleLabel.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.medium)
        } else if isHovered {
            titleLabel.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.full)
        } else {
            titleLabel.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.high)
        }

        if !isEnabled {
            titleLabel.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.low)
        }
    }
}
