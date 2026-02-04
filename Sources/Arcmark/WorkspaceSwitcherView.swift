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
                buttonSpacing: 4
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
        let colorId: WorkspaceColorId
    }

    private let scrollView = NSScrollView()
    private let contentView = NSView()
    private let leftShadowView = NSView()
    private let rightShadowView = NSView()
    private var workspaceButtons: [UUID: WorkspaceButton] = [:]
    private var addButton: IconTitleButton?

    // Inline rename tracking
    private weak var inlineRenameButton: WorkspaceButton?
    private var inlineRenameWorkspaceId: UUID?

    var style: Style {
        didSet {
            applyStyle()
        }
    }

    var workspaceColor: WorkspaceColorId = .defaultColor() {
        didSet {
            updateShadows()
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
    var onWorkspaceRename: ((UUID, String) -> Void)?

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
        scrollView.contentView.postsBoundsChangedNotifications = true

        contentView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = contentView
        addSubview(scrollView)

        // Setup shadow views
        leftShadowView.translatesAutoresizingMaskIntoConstraints = false
        leftShadowView.wantsLayer = true
        rightShadowView.translatesAutoresizingMaskIntoConstraints = false
        rightShadowView.wantsLayer = true

        addSubview(leftShadowView)
        addSubview(rightShadowView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

            leftShadowView.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftShadowView.topAnchor.constraint(equalTo: topAnchor),
            leftShadowView.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftShadowView.widthAnchor.constraint(equalToConstant: 32),

            rightShadowView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightShadowView.topAnchor.constraint(equalTo: topAnchor),
            rightShadowView.bottomAnchor.constraint(equalTo: bottomAnchor),
            rightShadowView.widthAnchor.constraint(equalToConstant: 32)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        updateShadows()
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
        let addBtn = IconTitleButton(
            title: "Add new workspace",
            symbolName: "plus",
            style: .addWorkspace
        )
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addBtn.target = self
        addBtn.action = #selector(addWorkspaceTapped)

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

    @objc private func scrollViewDidScroll() {
        updateShadows()
        // Refresh hover states for all buttons when scrolling
        for (_, button) in workspaceButtons {
            button.refreshHoverState()
        }
    }

    @objc private func addWorkspaceTapped() {
        onAddWorkspace?()
    }

    private func updateShadows() {
        let clipView = scrollView.contentView

        let visibleRect = clipView.documentVisibleRect
        let contentWidth = contentView.bounds.width

        let canScrollLeft = visibleRect.origin.x > 0
        let canScrollRight = visibleRect.origin.x + visibleRect.width < contentWidth

        // Create gradients based on workspace color
        let baseColor = workspaceColor.color

        let shadowGradientOpacity = 0.80

        if canScrollLeft {
            let leftGradient = CAGradientLayer()
            leftGradient.frame = leftShadowView.bounds
            leftGradient.colors = [
                baseColor.withAlphaComponent(shadowGradientOpacity).cgColor,
                baseColor.withAlphaComponent(0.0).cgColor
            ]
            leftGradient.startPoint = CGPoint(x: 0, y: 0.5)
            leftGradient.endPoint = CGPoint(x: 1, y: 0.5)
            leftShadowView.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
            leftShadowView.layer?.addSublayer(leftGradient)
            leftShadowView.isHidden = false
        } else {
            leftShadowView.isHidden = true
        }

        if canScrollRight {
            let rightGradient = CAGradientLayer()
            rightGradient.frame = rightShadowView.bounds
            rightGradient.colors = [
                baseColor.withAlphaComponent(0.0).cgColor,
                baseColor.withAlphaComponent(shadowGradientOpacity).cgColor
            ]
            rightGradient.startPoint = CGPoint(x: 0, y: 0.5)
            rightGradient.endPoint = CGPoint(x: 1, y: 0.5)
            rightShadowView.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
            rightShadowView.layer?.addSublayer(rightGradient)
            rightShadowView.isHidden = false
        } else {
            rightShadowView.isHidden = true
        }
    }

    override func layout() {
        super.layout()
        updateShadows()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Inline Rename

    func beginInlineRename(workspaceId: UUID) {
        cancelInlineRename()
        guard let button = workspaceButtons[workspaceId] else { return }

        inlineRenameWorkspaceId = workspaceId
        inlineRenameButton = button
        button.beginInlineRename(onCommit: { [weak self] newName in
            self?.commitInlineRename(newName)
        }, onCancel: { [weak self] in
            self?.handleInlineRenameCancelled()
        })
    }

    func cancelInlineRename() {
        guard inlineRenameWorkspaceId != nil else { return }
        inlineRenameButton?.cancelInlineRename()
        clearInlineRenameState()
    }

    private func commitInlineRename(_ newName: String) {
        guard let workspaceId = inlineRenameWorkspaceId else {
            clearInlineRenameState()
            return
        }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            handleInlineRenameCancelled()
            return
        }
        onWorkspaceRename?(workspaceId, trimmed)
        clearInlineRenameState()
    }

    private func handleInlineRenameCancelled() {
        clearInlineRenameState()
    }

    private func clearInlineRenameState() {
        inlineRenameButton = nil
        inlineRenameWorkspaceId = nil
    }
}

// MARK: - WorkspaceButton

private final class WorkspaceButton: NSControl {
    private let workspaceId: UUID
    private let circleView = NSView()
    private let titleLabel = NSTextField(string: "")
    private let style: WorkspaceSwitcherView.Style
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    // Inline editing state
    private var isEditingTitle = false
    private var editingOriginalTitle: String?
    private var onEditCommit: ((String) -> Void)?
    private var onEditCancel: (() -> Void)?
    private var titleLabelWidthConstraint: NSLayoutConstraint?

    // Fixed width for text field during inline editing (easily adjustable)
    private let editingTextFieldWidth: CGFloat = 170

    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    var isInlineRenaming: Bool {
        isEditingTitle
    }

    var onTap: ((UUID) -> Void)?
    var onRightClick: ((UUID, NSPoint) -> Void)?

    init(workspaceId: UUID, name: String, colorId: WorkspaceColorId, style: WorkspaceSwitcherView.Style) {
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
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.focusRingType = .none
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

        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func layout() {
        super.layout()
        refreshHoverState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshHoverState()
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

    func refreshHoverState() {
        guard let window else {
            if isHovered {
                isHovered = false
                updateAppearance()
            }
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let hovered = bounds.contains(point)
        if hovered != isHovered {
            isHovered = hovered
            updateAppearance()
        }
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

    func beginInlineRename(onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        guard !isEditingTitle else { return }
        isEditingTitle = true
        editingOriginalTitle = titleLabel.stringValue
        onEditCommit = onCommit
        onEditCancel = onCancel

        // Set fixed width for editing
        titleLabelWidthConstraint = titleLabel.widthAnchor.constraint(equalToConstant: editingTextFieldWidth)
        titleLabelWidthConstraint?.isActive = true

        // Preserve font when switching to editable mode
        let currentFont = titleLabel.font ?? NSFont.systemFont(ofSize: style.textSize, weight: style.textWeight)
        titleLabel.isEditable = true
        titleLabel.isSelectable = true
        titleLabel.font = currentFont
        titleLabel.delegate = self

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.titleLabel)
            if let editor = self.titleLabel.currentEditor() {
                // Ensure font is set on the field editor as well
                editor.font = currentFont
                let length = (self.titleLabel.stringValue as NSString).length
                editor.selectedRange = NSRange(location: 0, length: length)
            }
        }
    }

    func cancelInlineRename() {
        guard isEditingTitle else { return }
        titleLabel.stringValue = editingOriginalTitle ?? titleLabel.stringValue
        finishInlineRename(commit: false)
        if window?.firstResponder == titleLabel.currentEditor() {
            window?.makeFirstResponder(nil)
        }
    }

    private func finishInlineRename(commit: Bool) {
        let commitHandler = onEditCommit
        let cancelHandler = onEditCancel
        let finalValue = titleLabel.stringValue

        // Remove fixed width constraint
        titleLabelWidthConstraint?.isActive = false
        titleLabelWidthConstraint = nil

        isEditingTitle = false
        editingOriginalTitle = nil
        onEditCommit = nil
        onEditCancel = nil
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.delegate = nil

        // Ensure font is maintained after editing
        titleLabel.font = NSFont.systemFont(ofSize: style.textSize, weight: style.textWeight)

        if commit {
            commitHandler?(finalValue)
        } else {
            cancelHandler?()
        }
    }
}

// MARK: - WorkspaceButton + NSTextFieldDelegate

extension WorkspaceButton: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard isEditingTitle else { return }
        let movement = obj.userInfo?["NSTextMovement"] as? Int ?? NSOtherTextMovement
        let trimmed = titleLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if movement == NSReturnTextMovement, !trimmed.isEmpty {
            titleLabel.stringValue = trimmed
            finishInlineRename(commit: true)
        } else {
            titleLabel.stringValue = editingOriginalTitle ?? titleLabel.stringValue
            finishInlineRename(commit: false)
        }
    }
}

