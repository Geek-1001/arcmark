import AppKit

final class NodeRowView: BaseView {
    private let content = NodeRowContent()
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
    private var contentTrailingToDeleteButton: NSLayoutConstraint!
    private var contentTrailingToEdge: NSLayoutConstraint!

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

        content.translatesAutoresizingMaskIntoConstraints = false

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

        addSubview(content)
        addSubview(deleteButton)
        addSubview(clockBadgeContainer)
        clockBadgeContainer.addSubview(clockBadgeHoverOverlay)
        clockBadgeContainer.addSubview(clockIconView)

        contentTrailingToDeleteButton = content.trailingAnchor.constraint(
            equalTo: deleteButton.leadingAnchor, constant: -14)
        contentTrailingToEdge = content.trailingAnchor.constraint(
            equalTo: trailingAnchor, constant: -16)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentTrailingToEdge,

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22),

            clockBadgeContainer.centerXAnchor.constraint(equalTo: content.iconView.trailingAnchor),
            clockBadgeContainer.centerYAnchor.constraint(equalTo: content.iconView.bottomAnchor),
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

        content.configure(title: title, icon: icon, titleFont: titleFont, metrics: metrics)

        layer?.cornerRadius = metrics.rowCornerRadius
        deleteButton.contentTintColor = metrics.deleteTintColor

        showsDeleteButton = showDelete
        self.onDelete = onDelete

        refreshHoverState()
    }

    func setIndentation(depth: Int, metrics: ListMetrics) {
        content.setIndentation(depth: depth)
    }

    var isInlineRenaming: Bool {
        content.titleField.isEditing
    }

    func beginInlineRename(onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        content.titleField.beginInlineRename(onCommit: onCommit, onCancel: onCancel)
    }

    func cancelInlineRename() {
        content.titleField.cancelInlineRename()
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

        contentTrailingToDeleteButton.isActive = showDelete
        contentTrailingToEdge.isActive = !showDelete
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
