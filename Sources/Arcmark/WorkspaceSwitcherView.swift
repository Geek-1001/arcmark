import AppKit

final class WorkspaceSwitcherView: NSView {
    struct Style {
        var textSize: CGFloat
        var textWeight: NSFont.Weight
        var unselectedTextColor: NSColor
        var unselectedTextOpacity: CGFloat
        var selectedBackgroundColor: NSColor
        var selectedTextColor: NSColor
        var hoverBackgroundOpacity: CGFloat
        var circleSize: CGFloat
        var circleBorderWidth: CGFloat
        var circleBorderColor: NSColor
        var circleBorderOpacity: CGFloat
        var circleTextGap: CGFloat
        var buttonHorizontalPadding: CGFloat
        var buttonVerticalPadding: CGFloat
        var buttonCornerRadius: CGFloat
        var buttonSpacing: CGFloat
        var addButtonIconPointSize: CGFloat
        var addButtonIconWeight: NSFont.Weight
        var addButtonIconTitleSpacing: CGFloat

        static var defaultStyle: Style {
            Style(
                textSize: 14,
                textWeight: .semibold,
                unselectedTextColor: NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0), // #141414
                unselectedTextOpacity: 0.80,
                selectedBackgroundColor: NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0), // #141414
                selectedTextColor: NSColor.white,
                hoverBackgroundOpacity: 0.06,
                circleSize: 12,
                circleBorderWidth: 2,
                circleBorderColor: NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0), // #141414
                circleBorderOpacity: 0.20,
                circleTextGap: 6,
                buttonHorizontalPadding: 10,
                buttonVerticalPadding: 10,
                buttonCornerRadius: 8,
                buttonSpacing: 4,
                addButtonIconPointSize: 14,
                addButtonIconWeight: .medium,
                addButtonIconTitleSpacing: 6
            )
        }

        var height: CGFloat {
            let font = NSFont.systemFont(ofSize: textSize, weight: textWeight)
            let textHeight = ceil(font.ascender - font.descender)
            return textHeight + (buttonVerticalPadding * 2)
        }
    }

    struct WorkspaceItem {
        let id: UUID
        let name: String
        let emoji: String
        let colorId: WorkspaceColorId
    }

    private let scrollView = NSScrollView()
    private let contentView = NSView()
    private var workspaceButtons: [UUID: WorkspaceButton] = [:]
    private var addButton: AddWorkspaceButton?

    var style: Style {
        didSet {
            applyStyle()
        }
    }

    var workspaces: [WorkspaceItem] = [] {
        didSet {
            rebuildButtons()
        }
    }

    var selectedWorkspaceId: UUID? {
        didSet {
            updateSelection()
        }
    }

    var onWorkspaceSelected: ((UUID) -> Void)?
    var onWorkspaceRightClick: ((UUID, NSPoint) -> Void)?
    var onAddWorkspace: (() -> Void)?

    init(style: Style = .defaultStyle) {
        self.style = style
        super.init(frame: .zero)
        setupView()
        applyStyle()
    }

    required init?(coder: NSCoder) {
        self.style = .defaultStyle
        super.init(coder: coder)
        setupView()
        applyStyle()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: style.height)
    }

    private func setupView() {
        wantsLayer = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        contentView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = contentView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }

    private func applyStyle() {
        invalidateIntrinsicContentSize()
        rebuildButtons()
    }

    private func rebuildButtons() {
        // Remove all existing buttons
        for (_, button) in workspaceButtons {
            button.removeFromSuperview()
        }
        workspaceButtons.removeAll()
        addButton?.removeFromSuperview()
        addButton = nil

        // Create workspace buttons
        var previousView: NSView?
        for workspace in workspaces {
            let button = WorkspaceButton(
                workspaceId: workspace.id,
                name: workspace.name,
                emoji: workspace.emoji,
                colorId: workspace.colorId,
                style: style
            )
            button.translatesAutoresizingMaskIntoConstraints = false
            button.onTap = { [weak self] id in
                self?.onWorkspaceSelected?(id)
            }
            button.onRightClick = { [weak self] id, point in
                self?.onWorkspaceRightClick?(id, point)
            }

            contentView.addSubview(button)
            workspaceButtons[workspace.id] = button

            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: contentView.topAnchor),
                button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])

            if let prev = previousView {
                NSLayoutConstraint.activate([
                    button.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: style.buttonSpacing)
                ])
            } else {
                NSLayoutConstraint.activate([
                    button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
                ])
            }

            previousView = button
        }

        // Create "Add new workspace" button
        let addBtn = AddWorkspaceButton(style: style)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addBtn.onTap = { [weak self] in
            self?.onAddWorkspace?()
        }

        contentView.addSubview(addBtn)
        addButton = addBtn

        NSLayoutConstraint.activate([
            addBtn.topAnchor.constraint(equalTo: contentView.topAnchor),
            addBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        if let prev = previousView {
            NSLayoutConstraint.activate([
                addBtn.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: style.buttonSpacing)
            ])
        } else {
            NSLayoutConstraint.activate([
                addBtn.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            addBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        updateSelection()
    }

    private func updateSelection() {
        for (id, button) in workspaceButtons {
            button.isSelected = (id == selectedWorkspaceId)
        }
    }
}

// MARK: - WorkspaceButton

private final class WorkspaceButton: NSControl {
    private let workspaceId: UUID
    private let circleView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let style: WorkspaceSwitcherView.Style
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    var onTap: ((UUID) -> Void)?
    var onRightClick: ((UUID, NSPoint) -> Void)?

    init(workspaceId: UUID, name: String, emoji: String, colorId: WorkspaceColorId, style: WorkspaceSwitcherView.Style) {
        self.workspaceId = workspaceId
        self.style = style
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true

        // Setup circle
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.wantsLayer = true
        circleView.layer?.masksToBounds = true
        circleView.layer?.cornerRadius = style.circleSize / 2
        circleView.layer?.backgroundColor = colorId.color.cgColor
        circleView.layer?.borderWidth = style.circleBorderWidth
        circleView.layer?.borderColor = style.circleBorderColor.withAlphaComponent(style.circleBorderOpacity).cgColor

        // Setup title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.stringValue = name
        titleLabel.font = NSFont.systemFont(ofSize: style.textSize, weight: style.textWeight)

        addSubview(circleView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            circleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: style.buttonHorizontalPadding),
            circleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            circleView.widthAnchor.constraint(equalToConstant: style.circleSize),
            circleView.heightAnchor.constraint(equalToConstant: style.circleSize),

            titleLabel.leadingAnchor.constraint(equalTo: circleView.trailingAnchor, constant: style.circleTextGap),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -style.buttonHorizontalPadding),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onTap?(workspaceId)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(workspaceId, event.locationInWindow)
    }

    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = style.selectedBackgroundColor.cgColor
            titleLabel.textColor = style.selectedTextColor
            layer?.cornerRadius = style.buttonCornerRadius
        } else if isHovered {
            layer?.backgroundColor = style.unselectedTextColor.withAlphaComponent(style.hoverBackgroundOpacity).cgColor
            titleLabel.textColor = style.unselectedTextColor.withAlphaComponent(style.unselectedTextOpacity)
            layer?.cornerRadius = style.buttonCornerRadius
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = style.unselectedTextColor.withAlphaComponent(style.unselectedTextOpacity)
            layer?.cornerRadius = style.buttonCornerRadius
        }
    }
}

// MARK: - AddWorkspaceButton

private final class AddWorkspaceButton: NSControl {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let style: WorkspaceSwitcherView.Style
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    var onTap: (() -> Void)?

    init(style: WorkspaceSwitcherView.Style) {
        self.style = style
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = style.buttonCornerRadius

        // Setup icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        let config = NSImage.SymbolConfiguration(pointSize: style.addButtonIconPointSize, weight: style.addButtonIconWeight)
        if let image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            iconView.image = image
            iconView.image?.isTemplate = true
        }

        // Setup title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.stringValue = "Add new workspace"
        titleLabel.font = NSFont.systemFont(ofSize: style.textSize, weight: style.textWeight)

        addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: style.buttonHorizontalPadding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: style.addButtonIconPointSize),
            iconView.heightAnchor.constraint(equalToConstant: style.addButtonIconPointSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: style.addButtonIconTitleSpacing),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -style.buttonHorizontalPadding),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onTap?()
    }

    private func updateAppearance() {
        if isHovered {
            layer?.backgroundColor = style.unselectedTextColor.withAlphaComponent(style.hoverBackgroundOpacity).cgColor
            titleLabel.textColor = style.unselectedTextColor.withAlphaComponent(style.unselectedTextOpacity)
            iconView.contentTintColor = style.unselectedTextColor.withAlphaComponent(style.unselectedTextOpacity)
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = style.unselectedTextColor.withAlphaComponent(style.unselectedTextOpacity)
            iconView.contentTintColor = style.unselectedTextColor.withAlphaComponent(style.unselectedTextOpacity)
        }
    }
}
