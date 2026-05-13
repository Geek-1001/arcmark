import AppKit

final class NodeRowView: BaseView {
    private let iconView = NSImageView()
    private let editableTitle = InlineEditableTextField()
    private let deleteButton = NSButton()
    private let clockBadgeContainer = NSView()
    private let clockBadgeHoverOverlay = NSView()
    private let clockIconView = NSImageView()
    private var isSelected = false
    private var showsDeleteButton = false
    private var isScheduled = false
    private var scheduleBadgeBackgroundColor: NSColor?
    private var metrics = ListMetrics()
    private var onDelete: (() -> Void)?
    private var tooltipURL: String?
    private var tooltipShowTask: DispatchWorkItem?
    private static let sharedTooltip = CustomTooltipView()
    private static weak var activeTooltipTask: DispatchWorkItem?
    static var isDragging = false
    private var iconLeadingConstraint: NSLayoutConstraint?
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var titleTrailingToDeleteButton: NSLayoutConstraint!
    private var titleTrailingToEdge: NSLayoutConstraint!

    private static let scheduleBadgeSize: CGFloat = 14
    private static let scheduleBadgePadding: CGFloat = 1.5
    private static var scheduleBadgeIconSize: CGFloat { scheduleBadgeSize - scheduleBadgePadding * 2 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        layer?.cornerRadius = metrics.rowCornerRadius
        layer?.masksToBounds = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = metrics.iconCornerRadius
        iconView.layer?.masksToBounds = true

        editableTitle.translatesAutoresizingMaskIntoConstraints = false

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .texturedRounded
        deleteButton.isBordered = false
        let deleteIconConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        deleteButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(deleteIconConfig)
        deleteButton.target = self
        deleteButton.action = #selector(handleDelete)
        deleteButton.setButtonType(.momentaryChange)

        clockBadgeContainer.translatesAutoresizingMaskIntoConstraints = false
        clockBadgeContainer.wantsLayer = true
        clockBadgeContainer.isHidden = true
        clockBadgeContainer.layer?.cornerRadius = Self.scheduleBadgeSize / 2
        clockBadgeContainer.layer?.masksToBounds = true

        clockBadgeHoverOverlay.translatesAutoresizingMaskIntoConstraints = false
        clockBadgeHoverOverlay.wantsLayer = true
        clockBadgeHoverOverlay.isHidden = true

        clockIconView.translatesAutoresizingMaskIntoConstraints = false
        clockIconView.imageScaling = .scaleProportionallyDown

        addSubview(iconView)
        addSubview(editableTitle)
        addSubview(deleteButton)
        addSubview(clockBadgeContainer)
        clockBadgeContainer.addSubview(clockBadgeHoverOverlay)
        clockBadgeContainer.addSubview(clockIconView)

        iconLeadingConstraint = iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 26)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 26)

        titleTrailingToDeleteButton = editableTitle.trailingAnchor.constraint(
            lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -14)
        titleTrailingToEdge = editableTitle.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingAnchor, constant: -16)

        NSLayoutConstraint.activate([
            iconLeadingConstraint!,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint!,
            iconHeightConstraint!,

            editableTitle.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            editableTitle.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleTrailingToEdge,

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22),

            clockBadgeContainer.centerXAnchor.constraint(equalTo: iconView.trailingAnchor),
            clockBadgeContainer.centerYAnchor.constraint(equalTo: iconView.bottomAnchor),
            clockBadgeContainer.widthAnchor.constraint(equalToConstant: Self.scheduleBadgeSize),
            clockBadgeContainer.heightAnchor.constraint(equalToConstant: Self.scheduleBadgeSize),

            clockBadgeHoverOverlay.leadingAnchor.constraint(equalTo: clockBadgeContainer.leadingAnchor),
            clockBadgeHoverOverlay.trailingAnchor.constraint(equalTo: clockBadgeContainer.trailingAnchor),
            clockBadgeHoverOverlay.topAnchor.constraint(equalTo: clockBadgeContainer.topAnchor),
            clockBadgeHoverOverlay.bottomAnchor.constraint(equalTo: clockBadgeContainer.bottomAnchor),

            clockIconView.centerXAnchor.constraint(equalTo: clockBadgeContainer.centerXAnchor),
            clockIconView.centerYAnchor.constraint(equalTo: clockBadgeContainer.centerYAnchor),
            clockIconView.widthAnchor.constraint(equalToConstant: Self.scheduleBadgeIconSize),
            clockIconView.heightAnchor.constraint(equalToConstant: Self.scheduleBadgeIconSize)
        ])

    }

    func configure(title: String,
                   icon: NSImage?,
                   titleFont: NSFont,
                   showDelete: Bool,
                   metrics: ListMetrics,
                   onDelete: (() -> Void)?,
                   isSelected: Bool,
                   isScheduled: Bool = false,
                   scheduleBadgeBackgroundColor: NSColor? = nil,
                   tooltipURL: String? = nil) {
        tooltipShowTask?.cancel()
        tooltipShowTask = nil
        self.tooltipURL = tooltipURL
        self.metrics = metrics
        self.isSelected = isSelected
        self.isScheduled = isScheduled
        self.scheduleBadgeBackgroundColor = scheduleBadgeBackgroundColor
        configureClockBadge()
        updateVisualState()
        if editableTitle.isEditing {
            if editableTitle.text != title {
                cancelInlineRename()
                editableTitle.text = title
            }
        } else {
            editableTitle.text = title
        }
        editableTitle.font = titleFont
        editableTitle.textColor = metrics.titleColor

        iconView.image = icon
        if let icon {
            iconView.contentTintColor = icon.isTemplate ? metrics.iconTintColor : nil
        }

        layer?.cornerRadius = metrics.rowCornerRadius
        iconView.layer?.cornerRadius = metrics.iconCornerRadius
        deleteButton.contentTintColor = metrics.deleteTintColor
        iconWidthConstraint?.constant = metrics.iconSize
        iconHeightConstraint?.constant = metrics.iconSize

        showsDeleteButton = showDelete
        self.onDelete = onDelete

        refreshHoverState()
    }

    func setIndentation(depth: Int, metrics: ListMetrics) {
        iconLeadingConstraint?.constant = metrics.leftPadding + CGFloat(depth) * metrics.indentWidth
    }

    var isInlineRenaming: Bool {
        editableTitle.isEditing
    }

    func beginInlineRename(onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        editableTitle.beginInlineRename(onCommit: onCommit, onCancel: onCancel)
    }

    func cancelInlineRename() {
        editableTitle.cancelInlineRename()
    }

    static func hideSharedTooltip() {
        activeTooltipTask?.cancel()
        activeTooltipTask = nil
        sharedTooltip.hide()
    }

    @objc private func handleDelete() {
        onDelete?()
    }

    override func handleHoverStateChanged() {
        updateVisualState()

        tooltipShowTask?.cancel()
        tooltipShowTask = nil

        if isHovered, !NodeRowView.isDragging,
           let url = tooltipURL, !url.isEmpty,
           UserDefaults.standard.bool(forKey: UserDefaultsKeys.tooltipsEnabled) {
            let task = DispatchWorkItem { [weak self] in
                guard let self, self.isHovered, let parentWindow = self.window else { return }
                NodeRowView.sharedTooltip.show(text: url, cursorPosition: NSEvent.mouseLocation, parentWindow: parentWindow)
            }
            tooltipShowTask = task
            NodeRowView.activeTooltipTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + TooltipConstants.showDelay, execute: task)
        } else {
            NodeRowView.sharedTooltip.hide()
        }
    }

    private func updateVisualState() {
        let showDelete: Bool
        let showBadgeHoverOverlay: Bool
        if isSelected {
            layer?.backgroundColor = metrics.selectedBackgroundColor.cgColor
            showDelete = false
            showBadgeHoverOverlay = false
        } else if isHovered {
            layer?.backgroundColor = metrics.hoverBackgroundColor.cgColor
            showDelete = showsDeleteButton
            showBadgeHoverOverlay = true
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            showDelete = false
            showBadgeHoverOverlay = false
        }

        deleteButton.isHidden = !showDelete
        clockBadgeContainer.isHidden = !isScheduled
        clockBadgeHoverOverlay.isHidden = !showBadgeHoverOverlay
        clockBadgeHoverOverlay.layer?.backgroundColor = metrics.hoverBackgroundColor.cgColor

        titleTrailingToDeleteButton.isActive = showDelete
        titleTrailingToEdge.isActive = !showDelete
    }

    private func configureClockBadge() {
        guard isScheduled else { return }
        let config = NSImage.SymbolConfiguration(pointSize: Self.scheduleBadgeIconSize, weight: .bold)
        clockIconView.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "Scheduled")?
            .withSymbolConfiguration(config)
        clockIconView.contentTintColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(ThemeConstants.Opacity.high)
        clockBadgeContainer.layer?.backgroundColor = (scheduleBadgeBackgroundColor ?? .clear).cgColor
    }
}
