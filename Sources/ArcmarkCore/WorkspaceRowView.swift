import AppKit

final class WorkspaceRowView: NSView {
    struct Style {
        // Layout
        var rowCornerRadius: CGFloat
        var handleSize: CGFloat
        var colorSquareSize: CGFloat
        var colorSquareBorderWidth: CGFloat
        var colorSquareCornerRadius: CGFloat
        var deleteButtonSize: CGFloat

        // Spacing
        var handleLeading: CGFloat
        var colorSquareLeading: CGFloat
        var titleLeading: CGFloat
        var titleTrailing: CGFloat
        var deleteTrailing: CGFloat

        // Typography
        var titleFont: NSFont
        var titleColor: NSColor

        // Colors
        var handleTintColor: NSColor
        var colorSquareBorderColor: NSColor
        var deleteTintColor: NSColor
        var hoverBackgroundColor: NSColor

        // Handle icon
        var handleIconName: String
        var handleIconSize: CGFloat
        var handleIconWeight: NSFont.Weight

        // Delete icon
        var deleteIconName: String
        var deleteIconSize: CGFloat
        var deleteIconWeight: NSFont.Weight

        static var `default`: Style {
            // Base color reference: #141414 = RGB(20, 20, 20)
            let baseColorValue: CGFloat = 20.0 / 255.0

            return Style(
                rowCornerRadius: 12,
                handleSize: 18,
                colorSquareSize: 20,
                colorSquareBorderWidth: 1.5,
                colorSquareCornerRadius: 6,
                deleteButtonSize: 20,
                handleLeading: 16,
                colorSquareLeading: 8,
                titleLeading: 14,
                titleTrailing: 14,
                deleteTrailing: 16,
                titleFont: NSFont.systemFont(ofSize: 14, weight: .regular),
                titleColor: NSColor.black.withAlphaComponent(0.8),
                handleTintColor: NSColor.black.withAlphaComponent(0.4),
                colorSquareBorderColor: NSColor(calibratedRed: baseColorValue, green: baseColorValue, blue: baseColorValue, alpha: 0.15),
                deleteTintColor: NSColor.black.withAlphaComponent(0.5),
                hoverBackgroundColor: NSColor.black.withAlphaComponent(0.1),
                handleIconName: "line.3.horizontal",
                handleIconSize: 18,
                handleIconWeight: .medium,
                deleteIconName: "xmark",
                deleteIconSize: 14,
                deleteIconWeight: .bold
            )
        }
    }

    private let handleView = NSImageView()
    private let colorSquare = NSView()
    private let titleField = NSTextField(string: "")
    private let deleteButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var style: Style = .default
    private var onDelete: (() -> Void)?
    private var isEditingTitle = false
    private var editingOriginalTitle: String?
    private var onEditCommit: ((String) -> Void)?
    private var onEditCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = style.rowCornerRadius
        layer?.masksToBounds = true

        // Handle icon
        handleView.translatesAutoresizingMaskIntoConstraints = false
        handleView.imageScaling = .scaleProportionallyDown
        let handleConfig = NSImage.SymbolConfiguration(pointSize: style.handleIconSize, weight: style.handleIconWeight)
        handleView.image = NSImage(systemSymbolName: style.handleIconName, accessibilityDescription: "Drag to reorder")?
            .withSymbolConfiguration(handleConfig)
        handleView.contentTintColor = style.handleTintColor

        // Color square
        colorSquare.translatesAutoresizingMaskIntoConstraints = false
        colorSquare.wantsLayer = true
        colorSquare.layer?.cornerRadius = style.colorSquareCornerRadius
        colorSquare.layer?.masksToBounds = true
        colorSquare.layer?.borderWidth = style.colorSquareBorderWidth
        colorSquare.layer?.borderColor = style.colorSquareBorderColor.cgColor

        // Title field
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.delegate = self
        titleField.font = style.titleFont
        titleField.textColor = style.titleColor

        // Delete button
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .texturedRounded
        deleteButton.isBordered = false
        let deleteIconConfig = NSImage.SymbolConfiguration(pointSize: style.deleteIconSize, weight: style.deleteIconWeight)
        deleteButton.image = NSImage(systemSymbolName: style.deleteIconName, accessibilityDescription: "Delete workspace")?
            .withSymbolConfiguration(deleteIconConfig)
        deleteButton.contentTintColor = style.deleteTintColor
        deleteButton.target = self
        deleteButton.action = #selector(handleDelete)
        deleteButton.setButtonType(.momentaryChange)
        deleteButton.isHidden = true

        addSubview(handleView)
        addSubview(colorSquare)
        addSubview(titleField)
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            // Handle icon
            handleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: style.handleLeading),
            handleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            handleView.widthAnchor.constraint(equalToConstant: style.handleSize),
            handleView.heightAnchor.constraint(equalToConstant: style.handleSize),

            // Color square
            colorSquare.leadingAnchor.constraint(equalTo: handleView.trailingAnchor, constant: style.colorSquareLeading),
            colorSquare.centerYAnchor.constraint(equalTo: centerYAnchor),
            colorSquare.widthAnchor.constraint(equalToConstant: style.colorSquareSize),
            colorSquare.heightAnchor.constraint(equalToConstant: style.colorSquareSize),

            // Title
            titleField.leadingAnchor.constraint(equalTo: colorSquare.trailingAnchor, constant: style.titleLeading),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -style.titleTrailing),

            // Delete button
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -style.deleteTrailing),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: style.deleteButtonSize),
            deleteButton.heightAnchor.constraint(equalToConstant: style.deleteButtonSize)
        ])
    }

    func configure(workspaceName: String,
                   workspaceColor: NSColor,
                   showDelete: Bool,
                   canDelete: Bool,
                   onDelete: (() -> Void)?) {
        if isEditingTitle {
            if let original = editingOriginalTitle, original != workspaceName {
                cancelInlineRename()
                titleField.stringValue = workspaceName
            }
        } else {
            titleField.stringValue = workspaceName
        }

        colorSquare.layer?.backgroundColor = workspaceColor.cgColor
        deleteButton.isEnabled = canDelete
        deleteButton.toolTip = canDelete ? nil : "Cannot delete the last workspace"

        self.onDelete = onDelete
        refreshHoverState()
    }

    var isInlineRenaming: Bool {
        isEditingTitle
    }

    func beginInlineRename(onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        guard !isEditingTitle else { return }
        isEditingTitle = true
        editingOriginalTitle = titleField.stringValue
        onEditCommit = onCommit
        onEditCancel = onCancel
        titleField.isEditable = true
        titleField.isSelectable = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.titleField)
            if let editor = self.titleField.currentEditor() {
                let length = (self.titleField.stringValue as NSString).length
                editor.selectedRange = NSRange(location: 0, length: length)
            }
        }
    }

    func cancelInlineRename() {
        guard isEditingTitle else { return }
        titleField.stringValue = editingOriginalTitle ?? titleField.stringValue
        finishInlineRename(commit: false)
        if window?.firstResponder == titleField.currentEditor() {
            window?.makeFirstResponder(nil)
        }
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
        updateVisualState()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateVisualState()
    }

    func refreshHoverState() {
        guard let window else {
            if isHovered {
                isHovered = false
                updateVisualState()
            }
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let hovered = bounds.contains(point)
        if hovered != isHovered {
            isHovered = hovered
            updateVisualState()
        }
    }

    private func updateVisualState() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            if isHovered {
                layer?.backgroundColor = style.hoverBackgroundColor.cgColor
                deleteButton.animator().alphaValue = 1.0
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                deleteButton.animator().alphaValue = 0.0
            }
        })

        deleteButton.isHidden = !isHovered
    }

    private func finishInlineRename(commit: Bool) {
        let commitHandler = onEditCommit
        let cancelHandler = onEditCancel
        let finalValue = titleField.stringValue
        isEditingTitle = false
        editingOriginalTitle = nil
        onEditCommit = nil
        onEditCancel = nil
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        if commit {
            commitHandler?(finalValue)
        } else {
            cancelHandler?()
        }
    }
}

extension WorkspaceRowView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard isEditingTitle else { return }
        let movement = obj.userInfo?["NSTextMovement"] as? Int ?? NSOtherTextMovement
        let trimmed = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if movement == NSReturnTextMovement, !trimmed.isEmpty {
            titleField.stringValue = trimmed
            finishInlineRename(commit: true)
        } else {
            titleField.stringValue = editingOriginalTitle ?? titleField.stringValue
            finishInlineRename(commit: false)
        }
    }
}
