import AppKit

/// Shared icon + title subview used by both the main node list rows and the
/// reminders accordion. Encapsulates the standard `ListMetrics`-driven
/// styling so callers don't need to recreate icon sizing, title font, color,
/// or truncation behavior.
///
/// `NodeRowContent` deliberately does not own its trailing edge constraint —
/// callers add trailing-side accessories (delete button, date label, etc.)
/// and constrain this view's trailing edge themselves.
@MainActor
final class NodeRowContent: NSView {

    let iconView = NSImageView()
    let titleField = InlineEditableTextField()

    private(set) var metrics = ListMetrics()

    private var iconLeadingConstraint: NSLayoutConstraint!
    private var iconWidthConstraint: NSLayoutConstraint!
    private var iconHeightConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = metrics.iconCornerRadius
        iconView.layer?.masksToBounds = true

        titleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleField)

        iconLeadingConstraint = iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: metrics.leftPadding)
        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: metrics.iconSize)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: metrics.iconSize)

        NSLayoutConstraint.activate([
            iconLeadingConstraint,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
    }

    func configure(title: String, icon: NSImage?, titleFont: NSFont, metrics: ListMetrics) {
        self.metrics = metrics

        iconView.layer?.cornerRadius = metrics.iconCornerRadius
        iconWidthConstraint.constant = metrics.iconSize
        iconHeightConstraint.constant = metrics.iconSize

        if titleField.isEditing {
            if titleField.text != title {
                titleField.cancelInlineRename()
                titleField.text = title
            }
        } else {
            titleField.text = title
        }
        titleField.font = titleFont
        titleField.textColor = metrics.titleColor

        iconView.image = icon
        if let icon {
            iconView.contentTintColor = icon.isTemplate ? metrics.iconTintColor : nil
        } else {
            iconView.contentTintColor = nil
        }
    }

    func setIndentation(depth: Int) {
        iconLeadingConstraint.constant = metrics.leftPadding + CGFloat(depth) * metrics.indentWidth
    }
}
