import AppKit

@MainActor
final class ScheduledLinkRowView: BaseControl {
    private let content = NodeRowContent()
    private let dateField = NSTextField(labelWithString: "")

    private(set) var linkId: UUID?

    var onSelected: ((UUID) -> Void)?
    var onRightClick: ((UUID, NSEvent) -> Void)?

    private let metrics = ListMetrics()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        layer?.cornerRadius = metrics.rowCornerRadius
        layer?.masksToBounds = true

        content.translatesAutoresizingMaskIntoConstraints = false

        dateField.translatesAutoresizingMaskIntoConstraints = false
        dateField.font = ThemeConstants.Fonts.systemFont(size: 12, weight: .medium)
        dateField.textColor = metrics.titleColor.withAlphaComponent(0.6)
        dateField.alignment = .right
        dateField.lineBreakMode = .byTruncatingTail
        dateField.maximumNumberOfLines = 1
        dateField.setContentHuggingPriority(.required, for: .horizontal)
        dateField.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(content)
        addSubview(dateField)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.trailingAnchor.constraint(equalTo: dateField.leadingAnchor, constant: -ThemeConstants.Spacing.small),

            dateField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            dateField.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: metrics.rowHeight)
        ])
    }

    func configure(entry: ScheduledLinkEntry) {
        linkId = entry.link.id
        dateField.stringValue = Self.formattedFireDate(entry.fireAt)
        let icon = Self.faviconImage(for: entry.link, size: metrics.iconSize)
        content.configure(
            title: entry.link.title,
            icon: icon,
            titleFont: metrics.linkTitleFont,
            metrics: metrics
        )
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
        if isPressed {
            layer?.backgroundColor = metrics.selectedBackgroundColor.cgColor
        } else if isHovered {
            layer?.backgroundColor = metrics.hoverBackgroundColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    // MARK: - Helpers

    private static func faviconImage(for link: Link, size: CGFloat) -> NSImage? {
        if let customIcon = link.customIcon {
            switch customIcon {
            case .emoji(let emoji):
                return NodeListViewController.imageFromEmoji(emoji, size: size)
            case .sfSymbol(let name):
                let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
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
                return globeImage(size: size)
            }
        }
        if let path = link.faviconPath,
           FileManager.default.fileExists(atPath: path),
           let image = NSImage(contentsOfFile: path) {
            image.isTemplate = false
            return image
        }
        return globeImage(size: size)
    }

    private static func globeImage(size: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
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
