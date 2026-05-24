import AppKit

@MainActor
final class ScheduledLinkRowView: BaseControl {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let dateField = NSTextField(labelWithString: "")

    private(set) var linkId: UUID?

    var onSelected: ((UUID) -> Void)?
    var onRightClick: ((UUID, NSEvent) -> Void)?

    private static let iconSize: CGFloat = 18

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
        layer?.masksToBounds = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = ThemeConstants.CornerRadius.small * 0.5
        iconView.layer?.masksToBounds = true

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = ThemeConstants.Fonts.bodyRegular
        titleField.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.high)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.cell?.usesSingleLineMode = true

        dateField.translatesAutoresizingMaskIntoConstraints = false
        dateField.font = ThemeConstants.Fonts.systemFont(size: 12, weight: .medium)
        dateField.textColor = ThemeConstants.Colors.darkGray.withAlphaComponent(ThemeConstants.Opacity.medium)
        dateField.alignment = .right
        dateField.lineBreakMode = .byTruncatingTail
        dateField.maximumNumberOfLines = 1
        dateField.setContentHuggingPriority(.required, for: .horizontal)
        dateField.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(iconView)
        addSubview(titleField)
        addSubview(dateField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ThemeConstants.Spacing.medium),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: ThemeConstants.Spacing.medium),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: dateField.leadingAnchor, constant: -ThemeConstants.Spacing.small),

            dateField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ThemeConstants.Spacing.medium),
            dateField.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    func configure(entry: ScheduledLinkEntry) {
        linkId = entry.link.id
        titleField.stringValue = entry.link.title
        dateField.stringValue = Self.formattedFireDate(entry.fireAt)
        iconView.image = Self.faviconImage(for: entry.link)
    }

    // MARK: - Mouse Events

    override func performAction() {
        guard let linkId else { return }
        onSelected?(linkId)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let linkId else { return }
        onRightClick?(linkId, event)
    }

    // MARK: - Appearance

    override func handleHoverStateChanged() {
        updateBackground()
    }

    override func handlePressedStateChanged() {
        updateBackground()
    }

    private func updateBackground() {
        let opacity: CGFloat
        if isPressed {
            opacity = ThemeConstants.Opacity.subtle
        } else if isHovered {
            opacity = ThemeConstants.Opacity.minimal
        } else {
            opacity = 0
        }
        if opacity > 0 {
            layer?.backgroundColor = ThemeConstants.Colors.darkGray.withAlphaComponent(opacity).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    // MARK: - Helpers

    private static func faviconImage(for link: Link) -> NSImage? {
        if let customIcon = link.customIcon {
            switch customIcon {
            case .emoji(let emoji):
                return NodeListViewController.imageFromEmoji(emoji, size: iconSize)
            case .sfSymbol(let name):
                let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
                let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
                image?.isTemplate = true
                return image
            case .cachedFavicon(let path):
                if FileManager.default.fileExists(atPath: path),
                   let image = NSImage(contentsOfFile: path) {
                    image.isTemplate = false
                    return image
                }
                return globeImage()
            }
        }
        if let path = link.faviconPath,
           FileManager.default.fileExists(atPath: path),
           let image = NSImage(contentsOfFile: path) {
            image.isTemplate = false
            return image
        }
        return globeImage()
    }

    private static func globeImage() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
        let image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let dayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()

    static func formattedFireDate(_ date: Date, now: Date = Date()) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 {
            return "now"
        }
        let oneWeek: TimeInterval = 60 * 60 * 24 * 7
        if interval < oneWeek {
            // Use day+time for medium-range; relative for short-range.
            if interval < 60 * 60 * 24 {
                return relativeFormatter.localizedString(for: date, relativeTo: now)
            }
            return dayTimeFormatter.string(from: date)
        }
        return absoluteFormatter.string(from: date)
    }
}
