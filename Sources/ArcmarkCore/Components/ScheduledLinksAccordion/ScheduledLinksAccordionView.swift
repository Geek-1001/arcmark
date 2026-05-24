import AppKit

@MainActor
final class ScheduledLinksAccordionView: NSView {

    var onRowSelected: ((UUID) -> Void)?
    var onRowContextMenu: ((UUID, NSEvent) -> Void)?
    var onExpandChanged: ((Bool) -> Void)?

    private static let expandedHeight: CGFloat = 200
    private static let contentDividerGap: CGFloat = ThemeConstants.Spacing.medium

    private let contentContainer = NSView()
    private let scrollView = NSScrollView()
    private let rowsStack = NSStackView()
    private let bottomDivider = NSView()
    private let headerButton = HeaderButton()

    private var contentHeightConstraint: NSLayoutConstraint!
    private(set) var isExpanded = false
    private var entryCount = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        // Rows stack inside the scroll view document
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 2
        rowsStack.edgeInsets = NSEdgeInsets(
            top: ThemeConstants.Spacing.small,
            left: 0,
            bottom: ThemeConstants.Spacing.small,
            right: 0
        )
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = FlippedContentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(rowsStack)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.wantsLayer = true
        contentContainer.layer?.masksToBounds = true
        contentContainer.addSubview(scrollView)

        bottomDivider.translatesAutoresizingMaskIntoConstraints = false
        bottomDivider.wantsLayer = true
        bottomDivider.layer?.backgroundColor = ThemeConstants.Colors.darkGray
            .withAlphaComponent(ThemeConstants.Opacity.minimal).cgColor

        headerButton.translatesAutoresizingMaskIntoConstraints = false
        headerButton.onClick = { [weak self] in
            guard let self else { return }
            self.setExpanded(!self.isExpanded, animated: true)
        }

        addSubview(headerButton)
        addSubview(contentContainer)
        addSubview(bottomDivider)

        contentHeightConstraint = contentContainer.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            headerButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerButton.topAnchor.constraint(equalTo: topAnchor),

            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: headerButton.bottomAnchor),
            contentHeightConstraint,

            scrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),

            rowsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            rowsStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            bottomDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomDivider.topAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: Self.contentDividerGap),
            bottomDivider.heightAnchor.constraint(equalToConstant: 1),
            bottomDivider.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Public API

    func update(entries: [ScheduledLinkEntry]) {
        entryCount = entries.count
        isHidden = entries.isEmpty
        if entries.isEmpty {
            if isExpanded {
                setExpanded(false, animated: false)
            }
            rebuildRows([])
            return
        }
        let sorted = entries.sorted { $0.fireAt < $1.fireAt }
        rebuildRows(sorted)
        headerButton.update(count: entries.count, isExpanded: isExpanded)
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        let target: CGFloat = expanded ? Self.expandedHeight : 0
        headerButton.update(count: entryCount, isExpanded: expanded)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = ThemeConstants.Animation.durationNormal
                context.timingFunction = ThemeConstants.Animation.timingFunction
                context.allowsImplicitAnimation = true
                contentHeightConstraint.animator().constant = target
                superview?.layoutSubtreeIfNeeded()
            }
        } else {
            contentHeightConstraint.constant = target
        }

        onExpandChanged?(expanded)
    }

    // MARK: - Internal

    private func rebuildRows(_ entries: [ScheduledLinkEntry]) {
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for entry in entries {
            let row = ScheduledLinkRowView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.configure(entry: entry)
            row.onSelected = { [weak self] id in
                self?.onRowSelected?(id)
            }
            row.onRightClick = { [weak self] id, event in
                self?.onRowContextMenu?(id, event)
            }
            rowsStack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: rowsStack.leadingAnchor, constant: ThemeConstants.Spacing.small),
                row.trailingAnchor.constraint(equalTo: rowsStack.trailingAnchor, constant: -ThemeConstants.Spacing.small)
            ])
        }
    }
}

// MARK: - Header Button

@MainActor
private final class HeaderButton: BaseControl {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "Reminders")
    private let chevronView = NSImageView()

    var onClick: (() -> Void)?

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
        setAccessibilityRole(.button)
        setAccessibilityLabel("Reminders")

        let clockConfig = NSImage.SymbolConfiguration(pointSize: ThemeConstants.Sizing.iconSmall, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(clockConfig)
        iconView.image?.isTemplate = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = ThemeConstants.Fonts.bodyMedium
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1

        let chevronConfig = NSImage.SymbolConfiguration(pointSize: ThemeConstants.Sizing.iconSmall, weight: .medium)
        chevronView.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)?
            .withSymbolConfiguration(chevronConfig)
        chevronView.image?.isTemplate = true
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.imageScaling = .scaleProportionallyDown

        addSubview(iconView)
        addSubview(titleField)
        addSubview(chevronView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ThemeConstants.Spacing.regular),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: ThemeConstants.Sizing.iconSmall),
            iconView.heightAnchor.constraint(equalToConstant: ThemeConstants.Sizing.iconSmall),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: ThemeConstants.Spacing.medium),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -ThemeConstants.Spacing.small),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ThemeConstants.Spacing.regular),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: ThemeConstants.Sizing.iconSmall),
            chevronView.heightAnchor.constraint(equalToConstant: ThemeConstants.Sizing.iconSmall),

            heightAnchor.constraint(equalToConstant: ThemeConstants.Sizing.buttonHeight)
        ])

        updateForegroundOpacity()
    }

    func update(count: Int, isExpanded: Bool) {
        titleField.stringValue = "Reminders (\(count))"
        let symbolName = isExpanded ? "chevron.down" : "chevron.up"
        let chevronConfig = NSImage.SymbolConfiguration(pointSize: ThemeConstants.Sizing.iconSmall, weight: .medium)
        chevronView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(chevronConfig)
        chevronView.image?.isTemplate = true
        updateForegroundOpacity()
    }

    override func handleHoverStateChanged() {
        updateBackground()
        updateForegroundOpacity()
    }

    override func handlePressedStateChanged() {
        updateBackground()
        updateForegroundOpacity()
    }

    override func performAction() {
        onClick?()
    }

    private func updateBackground() {
        let opacity: CGFloat
        if isPressed {
            opacity = ThemeConstants.Opacity.extraSubtle
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

    private func updateForegroundOpacity() {
        let opacity: CGFloat = (isHovered || isPressed)
            ? ThemeConstants.Opacity.full
            : ThemeConstants.Opacity.high
        let color = ThemeConstants.Colors.darkGray.withAlphaComponent(opacity)
        titleField.textColor = color
        iconView.contentTintColor = color
        chevronView.contentTintColor = color
    }
}
