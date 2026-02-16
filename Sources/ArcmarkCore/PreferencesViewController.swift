//
//  PreferencesViewController.swift
//  Arcmark
//

import AppKit

final class PreferencesViewController: NSViewController {
    // Browser section
    private let browserPopup = NSPopUpButton()
    private var browsers: [BrowserInfo] = []

    // Window settings section
    private let alwaysOnTopCheckbox = NSButton(checkboxWithTitle: "Always on Top", target: nil, action: nil)
    private let attachSidebarCheckbox = NSButton(checkboxWithTitle: "Attach to Window as Sidebar", target: nil, action: nil)
    private let attachmentInfoLabel = NSTextField(labelWithString: "Disabled when Always on Top is enabled")
    private let sidebarPositionLabel = NSTextField(labelWithString: "Sidebar Position:")
    private let leftSideRadio = NSButton(radioButtonWithTitle: "Left side", target: nil, action: nil)
    private let rightSideRadio = NSButton(radioButtonWithTitle: "Right side", target: nil, action: nil)

    // Permissions section
    private let permissionStatusLabel = NSTextField(labelWithString: "")
    private let openSettingsButton = NSButton(title: "Open System Settings", target: nil, action: nil)
    private let refreshStatusButton = NSButton(title: "Refresh Status", target: nil, action: nil)
    private let permissionInfoLabel = NSTextField(labelWithString: "Required for window attachment")

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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
        // Re-check permissions when window appears
        updatePermissionStatus()
    }

    @objc private func applicationDidBecomeActive() {
        // Re-check permissions when app becomes active (user may have granted in System Settings)
        updatePermissionStatus()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func createSectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
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

        alwaysOnTopCheckbox.target = self
        alwaysOnTopCheckbox.action = #selector(alwaysOnTopChanged)
        alwaysOnTopCheckbox.translatesAutoresizingMaskIntoConstraints = false

        attachSidebarCheckbox.target = self
        attachSidebarCheckbox.action = #selector(attachSidebarChanged)
        attachSidebarCheckbox.translatesAutoresizingMaskIntoConstraints = false

        attachmentInfoLabel.font = NSFont.systemFont(ofSize: 11)
        attachmentInfoLabel.textColor = NSColor.secondaryLabelColor
        attachmentInfoLabel.translatesAutoresizingMaskIntoConstraints = false

        sidebarPositionLabel.translatesAutoresizingMaskIntoConstraints = false

        leftSideRadio.target = self
        leftSideRadio.action = #selector(sidebarPositionChanged)
        leftSideRadio.translatesAutoresizingMaskIntoConstraints = false

        rightSideRadio.target = self
        rightSideRadio.action = #selector(sidebarPositionChanged)
        rightSideRadio.translatesAutoresizingMaskIntoConstraints = false

        let separator1 = createSeparator()

        // Browser Section
        let browserHeader = createSectionHeader("Browser")

        let browserLabel = NSTextField(labelWithString: "Default Browser")
        browserLabel.translatesAutoresizingMaskIntoConstraints = false

        browserPopup.translatesAutoresizingMaskIntoConstraints = false
        browserPopup.target = self
        browserPopup.action = #selector(browserChanged)

        let separator2 = createSeparator()

        // Permissions Section
        let permissionsHeader = createSectionHeader("Permissions")

        permissionStatusLabel.translatesAutoresizingMaskIntoConstraints = false

        openSettingsButton.target = self
        openSettingsButton.action = #selector(openAccessibilitySettings)
        openSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        openSettingsButton.bezelStyle = .rounded

        refreshStatusButton.target = self
        refreshStatusButton.action = #selector(refreshPermissionStatus)
        refreshStatusButton.translatesAutoresizingMaskIntoConstraints = false
        refreshStatusButton.bezelStyle = .rounded

        permissionInfoLabel.font = NSFont.systemFont(ofSize: 11)
        permissionInfoLabel.textColor = NSColor.secondaryLabelColor
        permissionInfoLabel.translatesAutoresizingMaskIntoConstraints = false

        // Add all subviews
        view.addSubview(windowSettingsHeader)
        view.addSubview(alwaysOnTopCheckbox)
        view.addSubview(attachSidebarCheckbox)
        view.addSubview(attachmentInfoLabel)
        view.addSubview(sidebarPositionLabel)
        view.addSubview(leftSideRadio)
        view.addSubview(rightSideRadio)
        view.addSubview(separator1)
        view.addSubview(browserHeader)
        view.addSubview(browserLabel)
        view.addSubview(browserPopup)
        view.addSubview(separator2)
        view.addSubview(permissionsHeader)
        view.addSubview(permissionStatusLabel)
        view.addSubview(openSettingsButton)
        view.addSubview(refreshStatusButton)
        view.addSubview(permissionInfoLabel)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Window Settings Header
            windowSettingsHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            windowSettingsHeader.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),

            // Always on Top Checkbox
            alwaysOnTopCheckbox.leadingAnchor.constraint(equalTo: windowSettingsHeader.leadingAnchor),
            alwaysOnTopCheckbox.topAnchor.constraint(equalTo: windowSettingsHeader.bottomAnchor, constant: 12),

            // Attach Sidebar Checkbox
            attachSidebarCheckbox.leadingAnchor.constraint(equalTo: alwaysOnTopCheckbox.leadingAnchor),
            attachSidebarCheckbox.topAnchor.constraint(equalTo: alwaysOnTopCheckbox.bottomAnchor, constant: 8),

            // Attachment Info Label
            attachmentInfoLabel.leadingAnchor.constraint(equalTo: attachSidebarCheckbox.leadingAnchor, constant: 20),
            attachmentInfoLabel.topAnchor.constraint(equalTo: attachSidebarCheckbox.bottomAnchor, constant: 4),

            // Sidebar Position Label
            sidebarPositionLabel.leadingAnchor.constraint(equalTo: attachSidebarCheckbox.leadingAnchor),
            sidebarPositionLabel.topAnchor.constraint(equalTo: attachmentInfoLabel.bottomAnchor, constant: 12),

            // Radio buttons
            leftSideRadio.leadingAnchor.constraint(equalTo: sidebarPositionLabel.leadingAnchor, constant: 20),
            leftSideRadio.topAnchor.constraint(equalTo: sidebarPositionLabel.bottomAnchor, constant: 6),

            rightSideRadio.leadingAnchor.constraint(equalTo: leftSideRadio.trailingAnchor, constant: 20),
            rightSideRadio.topAnchor.constraint(equalTo: leftSideRadio.topAnchor),

            // Separator 1
            separator1.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            separator1.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            separator1.topAnchor.constraint(equalTo: leftSideRadio.bottomAnchor, constant: 16),
            separator1.heightAnchor.constraint(equalToConstant: 1),

            // Browser Header
            browserHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            browserHeader.topAnchor.constraint(equalTo: separator1.bottomAnchor, constant: 16),

            // Browser Label
            browserLabel.leadingAnchor.constraint(equalTo: browserHeader.leadingAnchor),
            browserLabel.topAnchor.constraint(equalTo: browserHeader.bottomAnchor, constant: 12),

            // Browser Popup
            browserPopup.leadingAnchor.constraint(equalTo: browserLabel.leadingAnchor),
            browserPopup.topAnchor.constraint(equalTo: browserLabel.bottomAnchor, constant: 8),
            browserPopup.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Separator 2
            separator2.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            separator2.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            separator2.topAnchor.constraint(equalTo: browserPopup.bottomAnchor, constant: 16),
            separator2.heightAnchor.constraint(equalToConstant: 1),

            // Permissions Header
            permissionsHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            permissionsHeader.topAnchor.constraint(equalTo: separator2.bottomAnchor, constant: 16),

            // Permission Status Label
            permissionStatusLabel.leadingAnchor.constraint(equalTo: permissionsHeader.leadingAnchor),
            permissionStatusLabel.topAnchor.constraint(equalTo: permissionsHeader.bottomAnchor, constant: 12),

            // Open Settings Button
            openSettingsButton.leadingAnchor.constraint(equalTo: permissionStatusLabel.leadingAnchor),
            openSettingsButton.topAnchor.constraint(equalTo: permissionStatusLabel.bottomAnchor, constant: 8),

            // Refresh Status Button (next to Open Settings)
            refreshStatusButton.leadingAnchor.constraint(equalTo: openSettingsButton.trailingAnchor, constant: 8),
            refreshStatusButton.centerYAnchor.constraint(equalTo: openSettingsButton.centerYAnchor),

            // Permission Info Label
            permissionInfoLabel.leadingAnchor.constraint(equalTo: openSettingsButton.leadingAnchor),
            permissionInfoLabel.topAnchor.constraint(equalTo: openSettingsButton.bottomAnchor, constant: 4),
        ])
    }

    private func loadPreferences() {
        // Load Always on Top state
        let alwaysOnTopEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.alwaysOnTopEnabled)
        alwaysOnTopCheckbox.state = alwaysOnTopEnabled ? .on : .off

        // Load Attach to Sidebar state
        let attachmentEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.sidebarAttachmentEnabled)
        attachSidebarCheckbox.state = attachmentEnabled ? .on : .off

        // Load sidebar position
        let positionString = UserDefaults.standard.string(forKey: UserDefaultsKeys.sidebarPosition) ?? "right"
        if positionString == "left" {
            leftSideRadio.state = .on
            rightSideRadio.state = .off
        } else {
            leftSideRadio.state = .off
            rightSideRadio.state = .on
        }

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
    }

    private func updatePermissionStatus() {
        let hasPermission = WindowAttachmentService.shared.checkAccessibilityPermissions()

        if hasPermission {
            permissionStatusLabel.stringValue = "Accessibility Access: ✓ Granted"
            permissionStatusLabel.textColor = NSColor.systemGreen
            openSettingsButton.isHidden = true
        } else {
            permissionStatusLabel.stringValue = "Accessibility Access: ✗ Not Granted"
            permissionStatusLabel.textColor = NSColor.systemRed
            openSettingsButton.isHidden = false
        }
    }

    private func updateControlStates() {
        let alwaysOnTopEnabled = alwaysOnTopCheckbox.state == .on
        let attachmentEnabled = attachSidebarCheckbox.state == .on

        // Mutual exclusion
        if alwaysOnTopEnabled {
            attachSidebarCheckbox.isEnabled = false
            sidebarPositionLabel.isEnabled = false
            leftSideRadio.isEnabled = false
            rightSideRadio.isEnabled = false
        } else {
            attachSidebarCheckbox.isEnabled = true
            sidebarPositionLabel.isEnabled = attachmentEnabled
            leftSideRadio.isEnabled = attachmentEnabled
            rightSideRadio.isEnabled = attachmentEnabled
        }

        if attachmentEnabled {
            alwaysOnTopCheckbox.isEnabled = false
        } else {
            alwaysOnTopCheckbox.isEnabled = true
        }
    }

    // MARK: - Actions

    @objc private func alwaysOnTopChanged() {
        let enabled = alwaysOnTopCheckbox.state == .on

        // If enabling, disable attachment first
        if enabled && attachSidebarCheckbox.state == .on {
            attachSidebarCheckbox.state = .off
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
        let enabled = attachSidebarCheckbox.state == .on

        // Check permissions
        if enabled && !WindowAttachmentService.shared.checkAccessibilityPermissions() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permissions Required"
            alert.informativeText = "Arcmark needs Accessibility permissions to attach to windows. Please grant access in System Settings."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()

            attachSidebarCheckbox.state = .off
            return
        }

        // If enabling, disable always on top first
        if enabled && alwaysOnTopCheckbox.state == .on {
            alwaysOnTopCheckbox.state = .off
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.alwaysOnTopEnabled)

            // Notify to disable always on top
            NotificationCenter.default.post(name: .alwaysOnTopSettingChanged, object: nil, userInfo: ["enabled": false])
        }

        UserDefaults.standard.set(enabled, forKey: UserDefaultsKeys.sidebarAttachmentEnabled)

        // Get current position
        let position = leftSideRadio.state == .on ? "left" : "right"

        // Notify to enable/disable attachment
        NotificationCenter.default.post(
            name: .attachmentSettingChanged,
            object: nil,
            userInfo: ["enabled": enabled, "position": position]
        )

        updateControlStates()
    }

    @objc private func sidebarPositionChanged() {
        let isLeft = leftSideRadio.state == .on

        // Update radio button states
        if isLeft {
            leftSideRadio.state = .on
            rightSideRadio.state = .off
        } else {
            leftSideRadio.state = .off
            rightSideRadio.state = .on
        }

        let position = isLeft ? "left" : "right"
        UserDefaults.standard.set(position, forKey: UserDefaultsKeys.sidebarPosition)

        // If attachment is currently enabled, notify to update position
        if attachSidebarCheckbox.state == .on {
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
}

// MARK: - Notification Names

extension Notification.Name {
    static let alwaysOnTopSettingChanged = Notification.Name("alwaysOnTopSettingChanged")
    static let attachmentSettingChanged = Notification.Name("attachmentSettingChanged")
    static let sidebarPositionChanged = Notification.Name("sidebarPositionChanged")
    static let toggleSidebarShortcutChanged = Notification.Name("toggleSidebarShortcutChanged")
}
