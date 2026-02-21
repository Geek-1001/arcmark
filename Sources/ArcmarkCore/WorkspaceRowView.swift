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
        var profileIconSize: CGFloat

        // Spacing
        var handleLeading: CGFloat
        var colorSquareLeading: CGFloat
        var titleLeading: CGFloat
        var titleTrailing: CGFloat
        var buttonsTrailing: CGFloat
        var buttonGap: CGFloat

        // Typography
        var titleFont: NSFont
        var titleColor: NSColor
        var setProfileFont: NSFont

        // Colors
        var handleTintColor: NSColor
        var colorSquareBorderColor: NSColor
        var deleteTintColor: NSColor
        var profileIconTintColor: NSColor
        var setProfileTextColor: NSColor
        var setProfileBorderColor: NSColor
        var hoverBackgroundColor: NSColor

        // Handle icon
        var handleIconName: String
        var handleIconSize: CGFloat
        var handleIconWeight: NSFont.Weight

        // Delete icon
        var deleteIconName: String
        var deleteIconSize: CGFloat
        var deleteIconWeight: NSFont.Weight

        // Profile icon (non-hovered indicator)
        var profileIconName: String
        var profileIconDisplaySize: CGFloat
        var profileIconWeight: NSFont.Weight

        // Set profile button
        var setProfileCornerRadius: CGFloat
        var setProfileBorderWidth: CGFloat
        var setProfilePaddingH: CGFloat
        var setProfileHeight: CGFloat

        static var `default`: Style {
            let baseColorValue: CGFloat = 20.0 / 255.0

            return Style(
                rowCornerRadius: ThemeConstants.CornerRadius.large,
                handleSize: ThemeConstants.Sizing.iconMedium,
                colorSquareSize: ThemeConstants.Sizing.iconMedium,
                colorSquareBorderWidth: 1.5,
                colorSquareCornerRadius: ThemeConstants.CornerRadius.small,
                deleteButtonSize: 20,
                profileIconSize: 20,
                handleLeading: 12,
                colorSquareLeading: ThemeConstants.Spacing.small,
                titleLeading: ThemeConstants.Spacing.medium,
                titleTrailing: ThemeConstants.Spacing.small,
                buttonsTrailing: ThemeConstants.Spacing.regular,
                buttonGap: ThemeConstants.Spacing.small,
                titleFont: ThemeConstants.Fonts.bodyRegular,
                titleColor: NSColor.black.withAlphaComponent(ThemeConstants.Opacity.high),
                setProfileFont: NSFont.systemFont(ofSize: 11, weight: .medium),
                handleTintColor: NSColor.black.withAlphaComponent(ThemeConstants.Opacity.low),
                colorSquareBorderColor: NSColor(calibratedRed: baseColorValue, green: baseColorValue, blue: baseColorValue, alpha: ThemeConstants.Opacity.subtle),
                deleteTintColor: NSColor.black.withAlphaComponent(0.5),
                profileIconTintColor: NSColor.black.withAlphaComponent(ThemeConstants.Opacity.low),
                setProfileTextColor: NSColor.black.withAlphaComponent(ThemeConstants.Opacity.medium),
                setProfileBorderColor: NSColor.black.withAlphaComponent(ThemeConstants.Opacity.subtle),
                hoverBackgroundColor: NSColor.black.withAlphaComponent(ThemeConstants.Opacity.extraSubtle),
                handleIconName: "line.3.horizontal",
                handleIconSize: ThemeConstants.Sizing.iconMedium,
                handleIconWeight: .medium,
                deleteIconName: "xmark",
                deleteIconSize: ThemeConstants.Sizing.iconSmall,
                deleteIconWeight: .bold,
                profileIconName: "person.crop.circle.fill",
                profileIconDisplaySize: ThemeConstants.Sizing.iconSmall,
                profileIconWeight: .medium,
                setProfileCornerRadius: ThemeConstants.CornerRadius.small,
                setProfileBorderWidth: 1,
                setProfilePaddingH: ThemeConstants.Spacing.small,
                setProfileHeight: 22
            )
        }
    }

    private let handleView = NSImageView()
    private let colorSquare = NSView()
    private let editableTitle = InlineEditableTextField()
    private let profileIconView = NSImageView()
    private let setProfileButton: PaddedTextButton
    private let deleteButton = NSButton()
    private var style: Style = .default
    private var onDelete: (() -> Void)?
    private var onProfile: (() -> Void)?
    private var hasProfile: Bool = false

    // Dynamic title trailing constraints (mutually exclusive)
    private var titleTrailingToEdge: NSLayoutConstraint!
    private var titleTrailingToProfileIcon: NSLayoutConstraint!
    private var titleTrailingToSetProfile: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        let s = Style.default
        setProfileButton = PaddedTextButton(hPadding: s.setProfilePaddingH)
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        let s = Style.default
        setProfileButton = PaddedTextButton(hPadding: s.setProfilePaddingH)
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
        editableTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Profile icon (visible when not hovered + has profile)
        profileIconView.translatesAutoresizingMaskIntoConstraints = false
        profileIconView.imageScaling = .scaleProportionallyDown
        let profileIconConfig = NSImage.SymbolConfiguration(pointSize: style.profileIconDisplaySize, weight: style.profileIconWeight)
        profileIconView.image = NSImage(systemSymbolName: style.profileIconName, accessibilityDescription: "Browser profile")?
            .withSymbolConfiguration(profileIconConfig)
        profileIconView.contentTintColor = style.profileIconTintColor
        profileIconView.isHidden = true

        // "Set profile..." text button (visible on hover)
        setProfileButton.translatesAutoresizingMaskIntoConstraints = false
        setProfileButton.title = "Set Profile"
        setProfileButton.bezelStyle = .texturedRounded
        setProfileButton.isBordered = false
        setProfileButton.font = style.setProfileFont
        setProfileButton.contentTintColor = style.setProfileTextColor
        setProfileButton.wantsLayer = true
        setProfileButton.layer?.cornerRadius = style.setProfileCornerRadius
        setProfileButton.layer?.borderWidth = style.setProfileBorderWidth
        setProfileButton.layer?.borderColor = style.setProfileBorderColor.cgColor
        setProfileButton.target = self
        setProfileButton.action = #selector(handleProfileAction)
        setProfileButton.setButtonType(.momentaryChange)
        setProfileButton.isHidden = true
        setProfileButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Delete button (visible on hover)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .texturedRounded
        deleteButton.isBordered = false
        let deleteIconConfig = NSImage.SymbolConfiguration(pointSize: style.deleteIconSize, weight: style.deleteIconWeight)
        deleteButton.image = NSImage(systemSymbolName: style.deleteIconName, accessibilityDescription: "Delete workspace")?
            .withSymbolConfiguration(deleteIconConfig)
        deleteButton.contentTintColor = style.deleteTintColor
        deleteButton.target = self
        deleteButton.action = #selector(handleDeleteAction)
        deleteButton.setButtonType(.momentaryChange)
        deleteButton.isHidden = true

        addSubview(handleView)
        addSubview(colorSquare)
        addSubview(editableTitle)
        addSubview(profileIconView)
        addSubview(setProfileButton)
        addSubview(deleteButton)

        // Three mutually exclusive title trailing constraints
        titleTrailingToEdge = editableTitle.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingAnchor, constant: -style.buttonsTrailing)
        titleTrailingToProfileIcon = editableTitle.trailingAnchor.constraint(
            lessThanOrEqualTo: profileIconView.leadingAnchor, constant: -style.titleTrailing)
        titleTrailingToSetProfile = editableTitle.trailingAnchor.constraint(
            lessThanOrEqualTo: setProfileButton.leadingAnchor, constant: -style.titleTrailing)

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

            // Title (leading + center only, trailing is dynamic)
            editableTitle.leadingAnchor.constraint(equalTo: colorSquare.trailingAnchor, constant: style.titleLeading),
            editableTitle.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Profile icon (at trailing edge, shown when not hovered + has profile)
            profileIconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -style.buttonsTrailing),
            profileIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            profileIconView.widthAnchor.constraint(equalToConstant: style.profileIconSize),
            profileIconView.heightAnchor.constraint(equalToConstant: style.profileIconSize),

            // "Set profile..." button (to the left of delete, shown on hover)
            setProfileButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -style.buttonGap),
            setProfileButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            setProfileButton.heightAnchor.constraint(equalToConstant: style.setProfileHeight),

            // Delete button (at trailing edge, shown on hover)
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -style.buttonsTrailing),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: style.deleteButtonSize),
            deleteButton.heightAnchor.constraint(equalToConstant: style.deleteButtonSize),
        ])
    }

    func configure(workspaceName: String,
                   workspaceColor: NSColor,
                   showDelete: Bool,
                   canDelete: Bool,
                   hasProfile: Bool,
                   onDelete: (() -> Void)?,
                   onProfile: (() -> Void)?) {
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

        self.hasProfile = hasProfile
        self.onDelete = onDelete
        self.onProfile = onProfile
        updateVisualState()
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

    @objc private func handleDeleteAction() {
        onDelete?()
    }

    @objc private func handleProfileAction() {
        onProfile?()
    }

    override func handleHoverStateChanged() {
        updateVisualState()
    }

    private func updateVisualState() {
        // Deactivate all title trailing constraints first
        titleTrailingToEdge.isActive = false
        titleTrailingToProfileIcon.isActive = false
        titleTrailingToSetProfile.isActive = false

        if isHovered {
            // Hovered: show "Set profile..." button + X, hide profile icon
            profileIconView.isHidden = true
            setProfileButton.isHidden = false
            deleteButton.isHidden = false
            titleTrailingToSetProfile.isActive = true
        } else if hasProfile {
            // Not hovered, has profile: show profile icon only
            profileIconView.isHidden = false
            setProfileButton.isHidden = true
            deleteButton.isHidden = true
            titleTrailingToProfileIcon.isActive = true
        } else {
            // Not hovered, no profile: nothing on right
            profileIconView.isHidden = true
            setProfileButton.isHidden = true
            deleteButton.isHidden = true
            titleTrailingToEdge.isActive = true
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = ThemeConstants.Animation.durationFast
            context.timingFunction = ThemeConstants.Animation.timingFunction

            if isHovered {
                layer?.backgroundColor = style.hoverBackgroundColor.cgColor
                setProfileButton.animator().alphaValue = 1.0
                deleteButton.animator().alphaValue = 1.0
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                if hasProfile {
                    profileIconView.animator().alphaValue = 0.5
                }
                setProfileButton.animator().alphaValue = 0.0
                deleteButton.animator().alphaValue = 0.0
            }
        })
    }
}

// MARK: - PaddedTextButton

/// An NSButton that adds horizontal padding to its intrinsic content size,
/// so layer-based borders have visible spacing around the title text.
private final class PaddedTextButton: NSButton {
    private let hPadding: CGFloat

    init(hPadding: CGFloat) {
        self.hPadding = hPadding
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += hPadding * 2
        return size
    }
}
