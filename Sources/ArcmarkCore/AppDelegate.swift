import AppKit
@preconcurrency import Sparkle

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WindowAttachmentServiceDelegate, GlobalHotkeyServiceDelegate {
    public override init() {
        super.init()
    }
    private var window: NSWindow?
    private var mainViewController: MainViewController?
    private var preferencesWindowController: PreferencesWindowController?
    private var alwaysOnTopMenuItem: NSMenuItem?
    private var updaterController: SPUStandardUpdaterController!

    // Attachment state
    private var isAttachmentMode: Bool = false
    private var lastManualFrame: NSRect?

    // Shortcut toggle state
    private var isUserHidden: Bool = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )

        setupMenus()

        let model = AppModel()
        let mainViewController = MainViewController(model: model)
        mainViewController.updater = updaterController.updater
        self.mainViewController = mainViewController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Arcmark"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = model.currentWorkspace.colorId.backgroundColor
        window.minSize = NSSize(width: 280, height: 420)
        window.maxSize = NSSize(width: 520, height: 10000) // Unlimited height for attachment mode
        let windowAutosaveName = "ArcmarkMainWindow"
        window.setFrameAutosaveName(windowAutosaveName)
        let restoredSize = applySavedWindowSize(to: window)
        let restoredFrame = restoredSize ? false : window.setFrameUsingName(windowAutosaveName)
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentViewController = mainViewController
        if !restoredSize && !restoredFrame {
            window.center()
        }
        ensureWindowVisible(window)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        self.window = window
        applyAlwaysOnTopFromDefaults()
        setupAttachmentService()
        setupGlobalHotkey()
        observeBrowserChanges()
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if let window {
            saveWindowSize(window)
        }
    }

    public func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        saveWindowSize(window)
    }

    private func ensureWindowVisible(_ window: NSWindow) {
        guard let screenFrame = NSScreen.main?.visibleFrame else { return }
        if screenFrame.intersects(window.frame) { return }

        let origin = NSPoint(
            x: screenFrame.midX - window.frame.width / 2,
            y: screenFrame.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
    }

    private func applySavedWindowSize(to window: NSWindow) -> Bool {
        guard let sizeString = UserDefaults.standard.string(forKey: UserDefaultsKeys.mainWindowSize) else {
            return false
        }
        let savedSize = NSSizeFromString(sizeString)
        guard savedSize.width > 0, savedSize.height > 0 else { return false }

        let clampedWidth = min(max(savedSize.width, window.minSize.width), window.maxSize.width)
        let clampedHeight = min(max(savedSize.height, window.minSize.height), window.maxSize.height)
        var frame = window.frame
        frame.size = NSSize(width: clampedWidth, height: clampedHeight)
        window.setFrame(frame, display: false)
        return true
    }

    private func saveWindowSize(_ window: NSWindow) {
        let sizeString = NSStringFromSize(window.frame.size)
        UserDefaults.standard.set(sizeString, forKey: UserDefaultsKeys.mainWindowSize)
    }

    private func setupMenus() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdatesItem.target = updaterController
        appMenu.addItem(checkForUpdatesItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Arcmark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New Workspace…", action: #selector(newWorkspace), keyEquivalent: "n")
        let newFolderItem = NSMenuItem(title: "New Folder…", action: #selector(newFolder), keyEquivalent: "N")
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(newFolderItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        NSApplication.shared.windowsMenu = windowMenu
        let showWindowItem = NSMenuItem(title: "Show Arcmark", action: #selector(showMainWindow), keyEquivalent: "")
        showWindowItem.target = self
        windowMenu.addItem(showWindowItem)
        let alwaysOnTopItem = NSMenuItem(title: "Always on Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "t")
        alwaysOnTopItem.keyEquivalentModifierMask = [.command, .option]
        windowMenu.addItem(alwaysOnTopItem)
        alwaysOnTopMenuItem = alwaysOnTopItem
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

        NSApplication.shared.mainMenu = mainMenu
    }

    private func applyAlwaysOnTopFromDefaults() {
        let enabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.alwaysOnTopEnabled)
        alwaysOnTopMenuItem?.state = enabled ? .on : .off
        window?.level = enabled ? .floating : .normal
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    @objc private func showMainWindow() {
        guard let window else { return }
        isUserHidden = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleAlwaysOnTop() {
        let enabled = !(UserDefaults.standard.bool(forKey: UserDefaultsKeys.alwaysOnTopEnabled))

        // Reset user-hidden state when toggling always on top
        if enabled {
            isUserHidden = false
        }

        // If enabling always on top, disable attachment first
        if enabled && isAttachmentMode {
            // Save current frame before disabling attachment
            if let window = window {
                lastManualFrame = window.frame
            }

            WindowAttachmentService.shared.disable()
            isAttachmentMode = false
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.sidebarAttachmentEnabled)
            updateWindowConstraints()
        }

        UserDefaults.standard.set(enabled, forKey: UserDefaultsKeys.alwaysOnTopEnabled)
        alwaysOnTopMenuItem?.state = enabled ? .on : .off
        window?.level = enabled ? .floating : .normal
    }

    @objc private func openPreferences() {
        // Select the settings tab in the main window instead of opening a separate preferences window
        guard let mainVC = mainViewController else { return }
        mainVC.model.selectSettings()
        showMainWindow()
    }

    @objc private func newWorkspace() {
        mainViewController?.promptCreateWorkspace()
    }

    @objc private func newFolder() {
        mainViewController?.createFolderAndBeginRename(parentId: nil)
    }

    // MARK: - Global Hotkey

    private func setupGlobalHotkey() {
        GlobalHotkeyService.shared.delegate = self

        if let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.toggleSidebarShortcut) {
            // Key exists: decode saved shortcut, or treat as explicitly cleared
            if let saved = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
                GlobalHotkeyService.shared.register(shortcut: saved)
            }
        } else {
            // No data = first launch, use default
            GlobalHotkeyService.shared.register(shortcut: .defaultToggleSidebar)
        }
    }

    func hotkeyServiceDidTrigger(_ service: GlobalHotkeyService) {
        // Silently ignore when Always on Top is enabled
        let alwaysOnTopEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.alwaysOnTopEnabled)
        guard !alwaysOnTopEnabled else { return }

        guard let window = window else { return }

        if window.isVisible && !isUserHidden {
            // Hide window
            isUserHidden = true
            window.orderOut(nil)
        } else {
            // Show window
            isUserHidden = false
            if isAttachmentMode {
                WindowAttachmentService.shared.forceUpdate()
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Window Attachment

    private func setupAttachmentService() {
        WindowAttachmentService.shared.delegate = self

        // Check for mutual exclusion with always on top
        let alwaysOnTopEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.alwaysOnTopEnabled)
        if alwaysOnTopEnabled {
            // Don't enable attachment if always on top is enabled
            return
        }

        let attachmentEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.sidebarAttachmentEnabled)
        guard attachmentEnabled else { return }

        // Load preferences
        let positionString = UserDefaults.standard.string(forKey: UserDefaultsKeys.sidebarPosition) ?? "right"
        let position: SidebarPosition = positionString == "left" ? .left : .right

        guard let browserBundleId = BrowserManager.resolveDefaultBrowserBundleId() else {
            print("AppDelegate: No browser bundle ID available for attachment")
            return
        }

        // Save current frame before entering attachment mode
        if let window = window {
            lastManualFrame = window.frame
        }

        isAttachmentMode = true
        updateWindowConstraints()

        WindowAttachmentService.shared.enable(browserBundleId: browserBundleId, position: position)
    }

    private func updateWindowConstraints() {
        guard let window = window else { return }

        if isAttachmentMode {
            // In attachment mode: allow unlimited height, disable manual movement
            window.minSize = NSSize(width: 280, height: 100)
            window.maxSize = NSSize(width: 520, height: 10000)
            window.isMovable = false
            window.isMovableByWindowBackground = false
        } else {
            // Manual mode: restore original constraints, enable movement
            window.minSize = NSSize(width: 280, height: 420)
            window.maxSize = NSSize(width: 520, height: 10000)
            window.isMovable = true
            window.isMovableByWindowBackground = true

            // Restore last manual frame if available
            if let lastFrame = lastManualFrame {
                window.setFrame(lastFrame, display: true, animate: false)
            }
        }
    }

    private func observeBrowserChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBrowserChanged),
            name: .defaultBrowserChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAlwaysOnTopSettingChanged),
            name: .alwaysOnTopSettingChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAttachmentSettingChanged),
            name: .attachmentSettingChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSidebarPositionChanged),
            name: .sidebarPositionChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleSidebarShortcutChanged),
            name: .toggleSidebarShortcutChanged,
            object: nil
        )
    }

    @objc private func handleBrowserChanged(_ notification: Notification) {
        guard isAttachmentMode,
              let bundleId = notification.userInfo?["bundleId"] as? String else {
            return
        }

        let positionString = UserDefaults.standard.string(forKey: UserDefaultsKeys.sidebarPosition) ?? "right"
        let position: SidebarPosition = positionString == "left" ? .left : .right

        WindowAttachmentService.shared.disable()
        WindowAttachmentService.shared.enable(browserBundleId: bundleId, position: position)
    }

    @objc private func handleAlwaysOnTopSettingChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }

        alwaysOnTopMenuItem?.state = enabled ? .on : .off
        window?.level = enabled ? .floating : .normal

        // Reset user-hidden state when Always on Top changes
        if enabled {
            isUserHidden = false
        }

        // If enabling and attachment is active, disable attachment
        if enabled && isAttachmentMode {
            if let window = window {
                lastManualFrame = window.frame
            }
            WindowAttachmentService.shared.disable()
            isAttachmentMode = false
            updateWindowConstraints()
        }
    }

    @objc private func handleAttachmentSettingChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }

        if enabled {
            // Enable attachment
            guard let browserBundleId = BrowserManager.resolveDefaultBrowserBundleId() else {
                print("AppDelegate: No browser bundle ID available for attachment")
                return
            }

            let positionString = notification.userInfo?["position"] as? String ?? "right"
            let position: SidebarPosition = positionString == "left" ? .left : .right

            if let window = window {
                lastManualFrame = window.frame
            }

            isAttachmentMode = true
            updateWindowConstraints()
            WindowAttachmentService.shared.enable(browserBundleId: browserBundleId, position: position)
        } else {
            // Disable attachment
            WindowAttachmentService.shared.disable()
            isAttachmentMode = false
            isUserHidden = false
            updateWindowConstraints()

            // Show window in case it was hidden
            window?.orderFront(nil)
        }
    }

    @objc private func handleSidebarPositionChanged(_ notification: Notification) {
        guard isAttachmentMode,
              let positionString = notification.userInfo?["position"] as? String,
              let browserBundleId = BrowserManager.resolveDefaultBrowserBundleId() else {
            return
        }

        let position: SidebarPosition = positionString == "left" ? .left : .right

        // Re-enable with new position
        WindowAttachmentService.shared.disable()
        WindowAttachmentService.shared.enable(browserBundleId: browserBundleId, position: position)
    }

    @objc private func handleToggleSidebarShortcutChanged() {
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.toggleSidebarShortcut),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            GlobalHotkeyService.shared.register(shortcut: shortcut)
        } else {
            GlobalHotkeyService.shared.unregister()
        }
    }

    // MARK: - WindowAttachmentServiceDelegate

    func attachmentService(_ service: WindowAttachmentService, shouldPositionWindow frame: NSRect, animated: Bool) {
        guard let window = window else { return }

        // Always show window if hidden, even if frame hasn't changed
        if !window.isVisible {
            // Don't auto-show if user explicitly hid via shortcut
            guard !isUserHidden else { return }
            window.setFrame(frame, display: true, animate: false)
            window.orderFront(nil)
            return
        }

        // Skip if frame hasn't changed and window is already visible
        if window.frame == frame { return }

        // Apply frame with smooth animation
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
            })
        } else {
            window.setFrame(frame, display: true, animate: false)
        }
    }

    func attachmentServiceShouldHideWindow(_ service: WindowAttachmentService) {
        window?.orderOut(nil)
    }

    func attachmentServiceShouldShowWindow(_ service: WindowAttachmentService) {
        guard !isUserHidden else { return }
        window?.orderFront(nil)
    }
}
