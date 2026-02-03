import AppKit

final class NodeRowView: NSView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var showsDeleteButton = false
    private var metrics = ListMetrics()
    private var onDelete: (() -> Void)?
    private var onClick: (() -> Void)?
    private var onDoubleClick: (() -> Void)?
    private var iconLeadingConstraint: NSLayoutConstraint?
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 8
        iconView.layer?.masksToBounds = true

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingTail

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .texturedRounded
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        deleteButton.target = self
        deleteButton.action = #selector(handleDelete)
        deleteButton.setButtonType(.momentaryChange)

        addSubview(iconView)
        addSubview(titleField)
        addSubview(deleteButton)

        iconLeadingConstraint = iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 26)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 26)

        NSLayoutConstraint.activate([
            iconLeadingConstraint!,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint!,
            iconHeightConstraint!,

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -14),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22)
        ])

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        addGestureRecognizer(doubleClick)

        let singleClick = NSClickGestureRecognizer(target: self, action: #selector(handleSingleClick))
        addGestureRecognizer(singleClick)
    }

    func configure(title: String,
                   icon: NSImage?,
                   showDelete: Bool,
                   metrics: ListMetrics,
                   onDelete: (() -> Void)?,
                   onClick: (() -> Void)?,
                   onDoubleClick: (() -> Void)?) {
        self.metrics = metrics
        titleField.stringValue = title
        titleField.font = metrics.titleFont
        titleField.textColor = metrics.titleColor

        iconView.image = icon
        if let icon {
            iconView.contentTintColor = icon.isTemplate ? metrics.iconTintColor : nil
        }

        deleteButton.contentTintColor = metrics.deleteTintColor
        iconWidthConstraint?.constant = metrics.iconSize
        iconHeightConstraint?.constant = metrics.iconSize

        showsDeleteButton = showDelete
        self.onDelete = onDelete
        self.onClick = onClick
        self.onDoubleClick = onDoubleClick

        if let window {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            isHovered = bounds.contains(point)
        } else {
            isHovered = false
        }
        updateHoverState()
    }

    func setIndentation(depth: Int, metrics: ListMetrics) {
        iconLeadingConstraint?.constant = metrics.leftPadding + CGFloat(depth) * metrics.indentWidth
    }

    @objc private func handleDelete() {
        onDelete?()
    }

    @objc private func handleSingleClick() {
        if let event = NSApp.currentEvent, event.clickCount > 1 { return }
        onClick?()
    }

    @objc private func handleDoubleClick() {
        onDoubleClick?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateHoverState()
    }

    private func updateHoverState() {
        layer?.backgroundColor = isHovered ? metrics.hoverBackgroundColor.cgColor : NSColor.clear.cgColor
        deleteButton.isHidden = !(showsDeleteButton && isHovered)
    }
}
