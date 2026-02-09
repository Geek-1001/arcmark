//
//  SettingsContentViewController.swift
//  Arcmark
//

import AppKit

final class SettingsContentViewController: NSViewController {
    // Layout constants
    private let horizontalPadding: CGFloat = 8
    private let sectionSpacing: CGFloat = 12        // Distance between sections
    private let sectionHeaderSpacing: CGFloat = 8   // Distance between section name and content
    private let itemSpacing: CGFloat = 8           // Distance between items within a section
    private let controlLabelSpacing: CGFloat = 4    // Distance between label and control

    // Color constants
    private let sectionHeaderColor = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 0.5)
    private let regularTextColor = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)

    // Browser section
    private let browserPopupContainer = NSView()
    private let browserPopup = NSPopUpButton()
    private var browsers: [BrowserInfo] = []

    // Window settings section - custom components
    private let alwaysOnTopToggle = CustomToggle(title: "Always on Top")
    private let attachSidebarToggle = CustomToggle(title: "Attach to Window as Sidebar")
    private let sidebarPositionSelector = SidebarPositionSelector()

    // Permissions section
    private let permissionStatusLabel = NSTextField(labelWithString: "")
    private let openSettingsButton = SettingsButton(title: "Open System Settings")
    private let refreshStatusButton = SettingsButton(title: "Refresh Status")

    // Import & Export section
    private let importButton = SettingsButton(title: "Import from Arc Browser")
    private let importStatusLabel = NSTextField(labelWithString: "")

    // Reference to AppModel (will be set from MainViewController)
    weak var appModel: AppModel?

    // Scroll view
    private let scrollView = NSScrollView()
    private let contentView = FlippedContentView()

    // Dynamic constraints
    private var separator1ToSelectorConstraint: NSLayoutConstraint?
    private var separator1ToToggleConstraint: NSLayoutConstraint?

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupScrollView()
        setupUI()
        loadPreferences()
        loadBrowsers()
        updatePermissionStatus()

        // Observe app activation to refresh permission status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Re-check permissions when view appears
        updatePermissionStatus()
    }

    @objc private func applicationDidBecomeActive() {
        // Re-check permissions when app becomes active (user may have granted in System Settings)
        updatePermissionStatus()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        contentView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func createSectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        label.textColor = sectionHeaderColor
        label.translatesAutoresizingMaskIntoConstraints = false

        // Set letter spacing
        if let attrString = label.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
            attrString.addAttribute(.kern, value: 0.5, range: NSRange(location: 0, length: attrString.length))
            label.attributedStringValue = attrString
        }

        return label
    }

    private func createSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        return separator
    }

    private func setupUI() {
        // Window Settings Section
        let windowSettingsHeader = createSectionHeader("Window Settings")

        alwaysOnTopToggle.target = self
        alwaysOnTopToggle.action = #selector(alwaysOnTopChanged)
        alwaysOnTopToggle.translatesAutoresizingMaskIntoConstraints = false

        attachSidebarToggle.target = self
        attachSidebarToggle.action = #selector(attachSidebarChanged)
        attachSidebarToggle.translatesAutoresizingMaskIntoConstraints = false

        // Setup position selector
        sidebarPositionSelector.translatesAutoresizingMaskIntoConstraints = false
        sidebarPositionSelector.onPositionChanged = { [weak self] _ in
            self?.sidebarPositionChanged()
        }

        let separator1 = createSeparator()

        // Browser Section
        let browserHeader = createSectionHeader("Browser")

        // Browser popup container with styled background
        browserPopupContainer.translatesAutoresizingMaskIntoConstraints = false
        browserPopupContainer.wantsLayer = true
        browserPopupContainer.layer?.backgroundColor = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 0.08).cgColor
        browserPopupContainer.layer?.cornerRadius = 8

        browserPopup.translatesAutoresizingMaskIntoConstraints = false
        browserPopup.target = self
        browserPopup.action = #selector(browserChanged)
        browserPopup.font = NSFont.systemFont(ofSize: 13)
        browserPopup.isBordered = false
        browserPopup.focusRingType = .none

        // Set content tint color for the chevron arrow
        if #available(macOS 14.0, *) {
            browserPopup.contentTintColor = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 0.80)
        }

        let separator2 = createSeparator()

        // Permissions Section
        let permissionsHeader = createSectionHeader("Permissions")

        permissionStatusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        permissionStatusLabel.translatesAutoresizingMaskIntoConstraints = false

        openSettingsButton.target = self
        openSettingsButton.action = #selector(openAccessibilitySettings)
        openSettingsButton.translatesAutoresizingMaskIntoConstraints = false

        refreshStatusButton.target = self
        refreshStatusButton.action = #selector(refreshPermissionStatus)
        refreshStatusButton.translatesAutoresizingMaskIntoConstraints = false

        let separator3 = createSeparator()

        // Import & Export Section
        let importHeader = createSectionHeader("Import & Export")

        importButton.target = self
        importButton.action = #selector(importFromArc)
        importButton.translatesAutoresizingMaskIntoConstraints = false

        importStatusLabel.font = NSFont.systemFont(ofSize: 11)
        importStatusLabel.textColor = NSColor.secondaryLabelColor
        importStatusLabel.maximumNumberOfLines = 0
        importStatusLabel.lineBreakMode = .byWordWrapping
        importStatusLabel.alignment = .center
        importStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        importStatusLabel.isHidden = true
        importStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Add all subviews to contentView
        contentView.addSubview(windowSettingsHeader)
        contentView.addSubview(alwaysOnTopToggle)
        contentView.addSubview(attachSidebarToggle)
        contentView.addSubview(sidebarPositionSelector)
        contentView.addSubview(separator1)
        contentView.addSubview(browserHeader)
        contentView.addSubview(browserPopupContainer)
        browserPopupContainer.addSubview(browserPopup)
        contentView.addSubview(separator2)
        contentView.addSubview(permissionsHeader)
        contentView.addSubview(permissionStatusLabel)
        contentView.addSubview(openSettingsButton)
        contentView.addSubview(refreshStatusButton)
        contentView.addSubview(separator3)
        contentView.addSubview(importHeader)
        contentView.addSubview(importButton)
        contentView.addSubview(importStatusLabel)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Content view width should match scroll view width
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Window Settings Header
            windowSettingsHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            windowSettingsHeader.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),

            // Always on Top Toggle
            alwaysOnTopToggle.leadingAnchor.constraint(equalTo: windowSettingsHeader.leadingAnchor),
            alwaysOnTopToggle.topAnchor.constraint(equalTo: windowSettingsHeader.bottomAnchor, constant: sectionHeaderSpacing),
            alwaysOnTopToggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
            alwaysOnTopToggle.heightAnchor.constraint(equalToConstant: 28),

            // Attach Sidebar Toggle
            attachSidebarToggle.leadingAnchor.constraint(equalTo: alwaysOnTopToggle.leadingAnchor),
            attachSidebarToggle.topAnchor.constraint(equalTo: alwaysOnTopToggle.bottomAnchor, constant: itemSpacing),
            attachSidebarToggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
            attachSidebarToggle.heightAnchor.constraint(equalToConstant: 28),

            // Position selector buttons (directly below toggle)
            sidebarPositionSelector.leadingAnchor.constraint(equalTo: attachSidebarToggle.leadingAnchor),
            sidebarPositionSelector.topAnchor.constraint(equalTo: attachSidebarToggle.bottomAnchor, constant: itemSpacing),
            sidebarPositionSelector.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),

            // Separator 1
            separator1.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            separator1.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
            separator1.heightAnchor.constraint(equalToConstant: 1),

            // Browser Header
            browserHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            browserHeader.topAnchor.constraint(equalTo: separator1.bottomAnchor, constant: sectionSpacing),

            // Browser Popup Container (directly below header)
            browserPopupContainer.leadingAnchor.constraint(equalTo: browserHeader.leadingAnchor),
            browserPopupContainer.topAnchor.constraint(equalTo: browserHeader.bottomAnchor, constant: sectionHeaderSpacing),
            browserPopupContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
            browserPopupContainer.heightAnchor.constraint(equalToConstant: 36),

            // Browser Popup inside container
            browserPopup.leadingAnchor.constraint(equalTo: browserPopupContainer.leadingAnchor, constant: 12),
            browserPopup.trailingAnchor.constraint(equalTo: browserPopupContainer.trailingAnchor, constant: -12),
            browserPopup.centerYAnchor.constraint(equalTo: browserPopupContainer.centerYAnchor),

            // Separator 2
            separator2.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            separator2.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
            separator2.topAnchor.constraint(equalTo: browserPopupContainer.bottomAnchor, constant: sectionSpacing),
            separator2.heightAnchor.constraint(equalToConstant: 1),

            // Permissions Header
            permissionsHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            permissionsHeader.topAnchor.constraint(equalTo: separator2.bottomAnchor, constant: sectionSpacing),

            // Permission Status Label
            permissionStatusLabel.leadingAnchor.constraint(equalTo: permissionsHeader.leadingAnchor),
            permissionStatusLabel.topAnchor.constraint(equalTo: permissionsHeader.bottomAnchor, constant: sectionHeaderSpacing),

            // Refresh Status Button (below status label)
            refreshStatusButton.leadingAnchor.constraint(equalTo: permissionStatusLabel.leadingAnchor),
            refreshStatusButton.topAnchor.constraint(equalTo: permissionStatusLabel.bottomAnchor, constant: itemSpacing),
            refreshStatusButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
            refreshStatusButton.heightAnchor.constraint(equalToConstant: 36),

            // Open Settings Button (below refresh button)
            openSettingsButton.leadingAnchor.constraint(equalTo: refreshStatusButton.leadingAnchor),
            openSettingsButton.topAnchor.constraint(equalTo: refreshStatusButton.bottomAnchor, constant: itemSpacing),
            openSettingsButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
            openSettingsButton.heightAnchor.constraint(equalToConstant: 36),

            // Separator 3
            separator3.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            separator3.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
            separator3.topAnchor.constraint(equalTo: refreshStatusButton.bottomAnchor, constant: sectionSpacing),
            separator3.heightAnchor.constraint(equalToConstant: 1),

            // Import & Export Header
            importHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            importHeader.topAnchor.constraint(equalTo: separator3.bottomAnchor, constant: sectionSpacing),

            // Import Button (below header)
            importButton.leadingAnchor.constraint(equalTo: importHeader.leadingAnchor),
            importButton.topAnchor.constraint(equalTo: importHeader.bottomAnchor, constant: sectionHeaderSpacing),
            importButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
            importButton.heightAnchor.constraint(equalToConstant: 36),

            // Import Status Label (below import button)
            importStatusLabel.leadingAnchor.constraint(equalTo: importButton.leadingAnchor),
            importStatusLabel.topAnchor.constraint(equalTo: importButton.bottomAnchor, constant: itemSpacing),
            importStatusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),

            // Bottom constraint to define content height - use greaterThanOrEqualTo to allow content to be anchored at top
            contentView.bottomAnchor.constraint(greaterThanOrEqualTo: importStatusLabel.bottomAnchor, constant: 24),
        ])

        // Setup dynamic constraints for separator1
        separator1ToSelectorConstraint = separator1.topAnchor.constraint(equalTo: sidebarPositionSelector.bottomAnchor, constant: sectionSpacing)
        separator1ToToggleConstraint = separator1.topAnchor.constraint(equalTo: attachSidebarToggle.bottomAnchor, constant: sectionSpacing)

        // Activate the appropriate constraint based on initial state
        separator1ToSelectorConstraint?.isActive = true
    }

    private func loadPreferences() {
        // Load Always on Top state
        let alwaysOnTopEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.alwaysOnTopEnabled)
        alwaysOnTopToggle.isOn = alwaysOnTopEnabled

        // Load Attach to Sidebar state
        let attachmentEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.sidebarAttachmentEnabled)
        attachSidebarToggle.isOn = attachmentEnabled

        // Load sidebar position
        let positionString = UserDefaults.standard.string(forKey: UserDefaultsKeys.sidebarPosition) ?? "right"
        sidebarPositionSelector.selectedPosition = positionString

        // Apply mutual exclusion and enable states
        updateControlStates()
    }

    private func loadBrowsers() {
        browsers = BrowserManager.installedBrowsers()
        browserPopup.removeAllItems()
        if browserPopup.menu == nil {
            browserPopup.menu = NSMenu()
        }

        for browser in browsers {
            let item = NSMenuItem(title: browser.name, action: nil, keyEquivalent: "")
            item.representedObject = browser.bundleId
            if let icon = browser.icon {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            browserPopup.menu?.addItem(item)
        }

        let defaultId = BrowserManager.resolveDefaultBrowserBundleId()
        if let defaultId, let index = browsers.firstIndex(where: { $0.bundleId == defaultId }) {
            browserPopup.selectItem(at: index)
        } else if !browsers.isEmpty {
            browserPopup.selectItem(at: 0)
            UserDefaults.standard.set(browsers[0].bundleId, forKey: UserDefaultsKeys.defaultBrowserBundleId)
        }

        // Update the title color after selection
        updateBrowserPopupAppearance()
    }

    private func updateBrowserPopupAppearance() {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: regularTextColor,
            .font: NSFont.systemFont(ofSize: 13)
        ]

        if let title = browserPopup.titleOfSelectedItem {
            browserPopup.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        }
    }

    private func updatePermissionStatus() {
        let hasPermission = WindowAttachmentService.shared.checkAccessibilityPermissions()

        if hasPermission {
            permissionStatusLabel.stringValue = "Accessibility Access: ✓ Granted"
            // Use a darker green for better readability
            permissionStatusLabel.textColor = NSColor(calibratedRed: 0.13, green: 0.67, blue: 0.29, alpha: 1.0)
            openSettingsButton.isHidden = true
        } else {
            permissionStatusLabel.stringValue = "Accessibility Access: ✗ Not Granted"
            // Use a darker red for better readability
            permissionStatusLabel.textColor = NSColor(calibratedRed: 0.85, green: 0.23, blue: 0.23, alpha: 1.0)
            openSettingsButton.isHidden = false
        }
    }

    private func updateControlStates() {
        let alwaysOnTopEnabled = alwaysOnTopToggle.isOn
        let attachmentEnabled = attachSidebarToggle.isOn

        // Determine if sidebar position should be visible
        let shouldShowSidebarPosition = !alwaysOnTopEnabled && attachmentEnabled

        // Mutual exclusion
        if alwaysOnTopEnabled {
            attachSidebarToggle.isEnabled = false
        } else {
            attachSidebarToggle.isEnabled = true
        }

        if attachmentEnabled {
            alwaysOnTopToggle.isEnabled = false
        } else {
            alwaysOnTopToggle.isEnabled = true
        }

        // Update visibility and layout constraints
        sidebarPositionSelector.isHidden = !shouldShowSidebarPosition

        // Switch constraints based on visibility
        if shouldShowSidebarPosition {
            separator1ToToggleConstraint?.isActive = false
            separator1ToSelectorConstraint?.isActive = true
        } else {
            separator1ToSelectorConstraint?.isActive = false
            separator1ToToggleConstraint?.isActive = true
        }
    }

    // MARK: - Actions

    @objc private func alwaysOnTopChanged() {
        let enabled = alwaysOnTopToggle.isOn

        // If enabling, disable attachment first
        if enabled && attachSidebarToggle.isOn {
            attachSidebarToggle.isOn = false
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.sidebarAttachmentEnabled)

            // Notify to disable attachment
            NotificationCenter.default.post(name: .attachmentSettingChanged, object: nil, userInfo: ["enabled": false])
        }

        UserDefaults.standard.set(enabled, forKey: UserDefaultsKeys.alwaysOnTopEnabled)

        // Notify to apply always on top
        NotificationCenter.default.post(name: .alwaysOnTopSettingChanged, object: nil, userInfo: ["enabled": enabled])

        updateControlStates()
    }

    @objc private func attachSidebarChanged() {
        let enabled = attachSidebarToggle.isOn

        // Check permissions
        if enabled && !WindowAttachmentService.shared.checkAccessibilityPermissions() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permissions Required"
            alert.informativeText = "Arcmark needs Accessibility permissions to attach to windows. Please grant access in System Settings."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()

            attachSidebarToggle.isOn = false
            return
        }

        // If enabling, disable always on top first
        if enabled && alwaysOnTopToggle.isOn {
            alwaysOnTopToggle.isOn = false
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.alwaysOnTopEnabled)

            // Notify to disable always on top
            NotificationCenter.default.post(name: .alwaysOnTopSettingChanged, object: nil, userInfo: ["enabled": false])
        }

        UserDefaults.standard.set(enabled, forKey: UserDefaultsKeys.sidebarAttachmentEnabled)

        // Get current position
        let position = sidebarPositionSelector.selectedPosition ?? "right"

        // Notify to enable/disable attachment
        NotificationCenter.default.post(
            name: .attachmentSettingChanged,
            object: nil,
            userInfo: ["enabled": enabled, "position": position]
        )

        updateControlStates()
    }

    @objc private func sidebarPositionChanged() {
        guard let position = sidebarPositionSelector.selectedPosition else { return }

        UserDefaults.standard.set(position, forKey: UserDefaultsKeys.sidebarPosition)

        // If attachment is currently enabled, notify to update position
        if attachSidebarToggle.isOn {
            NotificationCenter.default.post(
                name: .sidebarPositionChanged,
                object: nil,
                userInfo: ["position": position]
            )
        }
    }

    @objc private func browserChanged() {
        if let bundleId = browserPopup.selectedItem?.representedObject as? String {
            UserDefaults.standard.set(bundleId, forKey: UserDefaultsKeys.defaultBrowserBundleId)

            // Update appearance after change
            updateBrowserPopupAppearance()

            // Notify about browser change
            NotificationCenter.default.post(
                name: .defaultBrowserChanged,
                object: nil,
                userInfo: ["bundleId": bundleId]
            )
        }
    }

    @objc private func openAccessibilitySettings() {
        WindowAttachmentService.shared.requestAccessibilityPermissions()

        let alert = NSAlert()
        alert.messageText = "Grant Accessibility Access"
        alert.informativeText = "Please grant Arcmark access in System Settings > Privacy & Security > Accessibility, then return to this window."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func refreshPermissionStatus() {
        updatePermissionStatus()
    }

    @objc private func importFromArc() {
        // Construct default Arc path
        let arcPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")

        // Check if file exists
        guard FileManager.default.fileExists(atPath: arcPath.path) else {
            showImportStatus("Arc browser not found or no bookmarks available. Please ensure Arc is installed and has bookmarks.", isError: true)
            return
        }

        // Import directly
        Task { @MainActor [weak self] in
            await self?.handleArcImport(fileURL: arcPath)
        }
    }

    private func handleArcImport(fileURL: URL) async {
        // Show loading state
        showImportStatus("Importing from Arc...", isError: false)

        // Perform import
        let result = await ArcImportService.shared.importFromArc(fileURL: fileURL)

        switch result {
        case .success(let importResult):
            // Apply to AppModel
            applyImport(importResult)

            // Show success message
            let message = """
            Successfully imported:
            • \(importResult.workspacesCreated) workspaces
            • \(importResult.linksImported) links
            • \(importResult.foldersImported) folders
            """
            showImportStatus(message, isError: false)

            // Hide message after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.hideImportStatus()
            }

        case .failure(let error):
            showImportStatus(error.localizedDescription, isError: true)
        }
    }

    private func applyImport(_ result: ArcImportResult) {
        guard let appModel = appModel else { return }

        // Remember the currently selected workspace
        let previousWorkspaceId = appModel.state.selectedWorkspaceId

        for workspace in result.workspaces {
            // Create the workspace using AppModel's method
            _ = appModel.createWorkspace(name: workspace.name, colorId: workspace.colorId)

            // The workspace is now selected, add all nodes to it
            for node in workspace.nodes {
                addNodeToWorkspace(node, parentId: nil, appModel: appModel)
            }
        }

        // Restore the previously selected workspace
        if let previousWorkspaceId = previousWorkspaceId {
            appModel.selectWorkspace(id: previousWorkspaceId)
        }
    }

    private func addNodeToWorkspace(_ node: Node, parentId: UUID?, appModel: AppModel) {
        switch node {
        case .link(let link):
            appModel.addLink(urlString: link.url, title: link.title, parentId: parentId)
        case .folder(let folder):
            let folderId = appModel.addFolder(name: folder.name, parentId: parentId)
            // Recursively add children
            for child in folder.children {
                addNodeToWorkspace(child, parentId: folderId, appModel: appModel)
            }
        }
    }

    private func showImportStatus(_ message: String, isError: Bool) {
        importStatusLabel.stringValue = message
        importStatusLabel.textColor = isError ? NSColor.systemRed : regularTextColor
        importStatusLabel.isHidden = false
    }

    private func hideImportStatus() {
        importStatusLabel.isHidden = true
    }
}

// MARK: - Flipped Content View

/// A custom NSView that uses flipped coordinates so content is anchored to the top
private final class FlippedContentView: NSView {
    override var isFlipped: Bool {
        return true
    }
}

// MARK: - Settings Button

/// A custom button with background and hover effect, styled like the dropdown container
private final class SettingsButton: NSButton {
    private let baseBackgroundColor = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 0.08)
    private let hoverBackgroundColor = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 0.12)
    private let textColor = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1.0)

    private var trackingArea: NSTrackingArea?

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        setupButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
    }

    private func setupButton() {
        wantsLayer = true
        isBordered = false
        bezelStyle = .regularSquare
        font = NSFont.systemFont(ofSize: 13)

        // Setup layer
        layer?.backgroundColor = baseBackgroundColor.cgColor
        layer?.cornerRadius = 8

        // Set text color
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: NSFont.systemFont(ofSize: 13)
        ]
        attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        layer?.backgroundColor = hoverBackgroundColor.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        layer?.backgroundColor = baseBackgroundColor.cgColor
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 36)
    }
}
