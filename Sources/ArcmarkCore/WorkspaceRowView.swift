import AppKit

final class WorkspaceRowView: BaseView {
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
                colorSquareSize: 18,
                colorSquareBorderWidth: 1.5,
                colorSquareCornerRadius: 6,
                deleteButtonSize: 20,
                handleLeading: 12,
                colorSquareLeading: 6,
                titleLeading: 8,
                titleTrailing: 14,
                deleteTrailing: 12,
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
    private let editableTitle = InlineEditableTextField()
    private let deleteButton = NSButton()
    private var style: Style = .default
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
        editableTitle.translatesAutoresizingMaskIntoConstraints = false
        editableTitle.font = style.titleFont
        editableTitle.textColor = style.titleColor
        editableTitle.commitsOnFocusLoss = true

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
        addSubview(editableTitle)
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
            editableTitle.leadingAnchor.constraint(equalTo: colorSquare.trailingAnchor, constant: style.titleLeading),
            editableTitle.centerYAnchor.constraint(equalTo: centerYAnchor),
            editableTitle.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -style.titleTrailing),

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
        if editableTitle.isEditing {
            if editableTitle.text != workspaceName {
                cancelInlineRename()
                editableTitle.text = workspaceName
            }
        } else {
            editableTitle.text = workspaceName
        }

        colorSquare.layer?.backgroundColor = workspaceColor.cgColor
        deleteButton.isEnabled = canDelete
        deleteButton.toolTip = canDelete ? nil : "Cannot delete the last workspace"

        self.onDelete = onDelete
        refreshHoverState()
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

    @objc private func handleDelete() {
        onDelete?()
    }

    override func handleHoverStateChanged() {
        updateVisualState()
    }

    private func updateVisualState() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = ThemeConstants.Animation.durationFast
            context.timingFunction = ThemeConstants.Animation.timingFunction

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
}
