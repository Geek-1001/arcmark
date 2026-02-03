import AppKit

final class SearchBarView: NSView, NSTextFieldDelegate {
    struct Style {
        var baseColor: NSColor
        var backgroundOpacity: CGFloat
        var placeholderOpacity: CGFloat
        var textOpacity: CGFloat
        var iconOpacity: CGFloat
        var font: NSFont
        var iconPointSize: CGFloat
        var iconWeight: NSFont.Weight
        var clearIconPointSize: CGFloat
        var clearIconWeight: NSFont.Weight
        var iconTitleSpacing: CGFloat
        var clearSpacing: CGFloat
        var horizontalPadding: CGFloat
        var verticalPadding: CGFloat
        var cornerRadius: CGFloat

        static var defaultSearch: Style {
            Style(
                baseColor: NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0),
                backgroundOpacity: 0.10,
                placeholderOpacity: 0.60,
                textOpacity: 1.00,
                iconOpacity: 0.80,
                font: NSFont.systemFont(ofSize: 14, weight: .medium),
                iconPointSize: 18,
                iconWeight: .medium,
                clearIconPointSize: 12,
                clearIconWeight: .medium,
                iconTitleSpacing: 10,
                clearSpacing: 8,
                horizontalPadding: 10,
                verticalPadding: 10,
                cornerRadius: 8
            )
        }

        var height: CGFloat {
            let textHeight = ceil(font.ascender - font.descender)
            let contentHeight = max(iconPointSize, textHeight)
            return contentHeight + (verticalPadding * 2)
        }
    }

    private let iconView = NSImageView()
    private let textField = NSTextField(string: "")
    private let clearButton = NSButton()
    private var iconLeadingConstraint: NSLayoutConstraint?
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var clearTrailingConstraint: NSLayoutConstraint?
    private var clearWidthConstraint: NSLayoutConstraint?
    private var clearHeightConstraint: NSLayoutConstraint?
    private var textLeadingConstraint: NSLayoutConstraint?
    private var textTrailingConstraint: NSLayoutConstraint?

    var style: Style {
        didSet {
            applyStyle()
        }
    }

    var placeholder: String {
        get { textField.placeholderString ?? "" }
        set {
            textField.placeholderString = newValue
            updatePlaceholder()
        }
    }

    var text: String {
        get { textField.stringValue }
        set {
            textField.stringValue = newValue
            updateClearButtonVisibility()
        }
    }

    var onTextChange: ((String) -> Void)?

    init(style: Style = .defaultSearch) {
        self.style = style
        super.init(frame: .zero)
        setupView()
        applyStyle()
    }

    required init?(coder: NSCoder) {
        self.style = .defaultSearch
        super.init(coder: coder)
        setupView()
        applyStyle()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: style.height)
    }

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.delegate = self

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isBordered = false
        clearButton.title = ""
        clearButton.target = self
        clearButton.action = #selector(clearTapped)

        addSubview(iconView)
        addSubview(textField)
        addSubview(clearButton)

        iconLeadingConstraint = iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: style.horizontalPadding)
        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: style.iconPointSize)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: style.iconPointSize)
        clearTrailingConstraint = clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -style.horizontalPadding)
        clearWidthConstraint = clearButton.widthAnchor.constraint(equalToConstant: max(style.clearIconPointSize, 16))
        clearHeightConstraint = clearButton.heightAnchor.constraint(equalToConstant: max(style.clearIconPointSize, 16))
        textLeadingConstraint = textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: style.iconTitleSpacing)
        textTrailingConstraint = textField.trailingAnchor.constraint(lessThanOrEqualTo: clearButton.leadingAnchor, constant: -style.clearSpacing)

        NSLayoutConstraint.activate([
            iconLeadingConstraint!,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint!,
            iconHeightConstraint!,

            clearTrailingConstraint!,
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearWidthConstraint!,
            clearHeightConstraint!,

            textLeadingConstraint!,
            textTrailingConstraint!,
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func applyStyle() {
        layer?.cornerRadius = style.cornerRadius
        layer?.backgroundColor = style.baseColor.withAlphaComponent(style.backgroundOpacity).cgColor

        iconLeadingConstraint?.constant = style.horizontalPadding
        iconWidthConstraint?.constant = style.iconPointSize
        iconHeightConstraint?.constant = style.iconPointSize
        clearTrailingConstraint?.constant = -style.horizontalPadding
        let clearSize = max(style.clearIconPointSize, 16)
        clearWidthConstraint?.constant = clearSize
        clearHeightConstraint?.constant = clearSize
        textLeadingConstraint?.constant = style.iconTitleSpacing
        textTrailingConstraint?.constant = -style.clearSpacing

        iconView.image = symbolImage(name: "magnifyingglass", pointSize: style.iconPointSize, weight: style.iconWeight)
        iconView.contentTintColor = style.baseColor.withAlphaComponent(style.iconOpacity)

        clearButton.image = symbolImage(name: "xmark", pointSize: style.clearIconPointSize, weight: style.clearIconWeight)
        clearButton.contentTintColor = style.baseColor.withAlphaComponent(style.iconOpacity)

        textField.font = style.font
        textField.textColor = style.baseColor.withAlphaComponent(style.textOpacity)
        updatePlaceholder()
        updateClearButtonVisibility()
        invalidateIntrinsicContentSize()
    }

    private func updatePlaceholder() {
        guard let placeholder = textField.placeholderString, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: style.baseColor.withAlphaComponent(style.placeholderOpacity),
            .font: style.font
        ]
        textField.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: attributes)
    }

    private func updateClearButtonVisibility() {
        clearButton.isHidden = textField.stringValue.isEmpty
    }

    private func symbolImage(name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    @objc private func clearTapped() {
        textField.stringValue = ""
        updateClearButtonVisibility()
        onTextChange?("")
        window?.makeFirstResponder(textField)
    }

    func controlTextDidChange(_ obj: Notification) {
        updateClearButtonVisibility()
        onTextChange?(textField.stringValue)
    }
}
