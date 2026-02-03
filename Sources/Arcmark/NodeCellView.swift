import AppKit

final class NodeCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private let hoverBackgroundColor = NSColor.black.withAlphaComponent(0.2)
    private var isHovered = false
    private var showsDeleteButton = false
    private var trackingArea: NSTrackingArea?
    private var onDelete: (() -> Void)?

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
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.masksToBounds = true

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        titleField.textColor = NSColor.white.withAlphaComponent(0.92)
        titleField.lineBreakMode = .byTruncatingTail

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .texturedRounded
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        deleteButton.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        deleteButton.target = self
        deleteButton.action = #selector(handleDelete)
        deleteButton.setButtonType(.momentaryChange)

        addSubview(iconView)
        addSubview(titleField)
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -12),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    func configure(title: String, icon: NSImage?, showDelete: Bool, onDelete: (() -> Void)?) {
        titleField.stringValue = title
        iconView.image = icon
        if let icon {
            iconView.contentTintColor = icon.isTemplate ? NSColor.white.withAlphaComponent(0.9) : nil
        }
        showsDeleteButton = showDelete
        if let window {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            isHovered = bounds.contains(point)
        } else {
            isHovered = false
        }
        updateHoverState()
        self.onDelete = onDelete
    }

    @objc private func handleDelete() {
        onDelete?()
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
        layer?.backgroundColor = isHovered ? hoverBackgroundColor.cgColor : NSColor.clear.cgColor
        deleteButton.isHidden = !(showsDeleteButton && isHovered)
    }
}
