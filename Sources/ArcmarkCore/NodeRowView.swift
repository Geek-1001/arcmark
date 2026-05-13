import AppKit

final class NodeRowView: BaseView {
    private let iconView = NSImageView()
    private let editableTitle = InlineEditableTextField()
    private let deleteButton = NSButton()
    private let clockIconView = NSImageView()
    private var isSelected = false
    private var showsDeleteButton = false
    private var isScheduled = false
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
    private var titleTrailingToClock: NSLayoutConstraint!

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

        clockIconView.translatesAutoresizingMaskIntoConstraints = false
        clockIconView.imageScaling = .scaleProportionallyDown
        clockIconView.isHidden = true

        addSubview(iconView)
        addSubview(editableTitle)
        addSubview(deleteButton)
        addSubview(clockIconView)

        iconLeadingConstraint = iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 26)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 26)

        titleTrailingToDeleteButton = editableTitle.trailingAnchor.constraint(
            lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -14)
        titleTrailingToEdge = editableTitle.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingAnchor, constant: -16)
        titleTrailingToClock = editableTitle.trailingAnchor.constraint(
            lessThanOrEqualTo: clockIconView.leadingAnchor, constant: -8)

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

            clockIconView.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            clockIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            clockIconView.widthAnchor.constraint(equalToConstant: ThemeConstants.Sizing.iconSmall),
            clockIconView.heightAnchor.constraint(equalToConstant: ThemeConstants.Sizing.iconSmall)
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
                   tooltipURL: String? = nil) {
        tooltipShowTask?.cancel()
        tooltipShowTask = nil
        self.tooltipURL = tooltipURL
        self.metrics = metrics
        self.isSelected = isSelected
        self.isScheduled = isScheduled
        configureClockIcon()
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
        if isSelected {
            layer?.backgroundColor = metrics.selectedBackgroundColor.cgColor
            showDelete = false
        } else if isHovered {
            layer?.backgroundColor = metrics.hoverBackgroundColor.cgColor
            showDelete = showsDeleteButton
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            showDelete = false
        }

        deleteButton.isHidden = !showDelete
        clockIconView.isHidden = !isScheduled

        titleTrailingToClock.isActive = isScheduled
        titleTrailingToDeleteButton.isActive = !isScheduled && showDelete
        titleTrailingToEdge.isActive = !isScheduled && !showDelete
    }

    private func configureClockIcon() {
        guard isScheduled else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        clockIconView.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: "Scheduled")?
            .withSymbolConfiguration(config)
        clockIconView.contentTintColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(ThemeConstants.Opacity.medium)
    }
}
