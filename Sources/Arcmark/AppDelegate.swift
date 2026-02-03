import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var mainViewController: MainViewController?
    private var preferencesWindowController: PreferencesWindowController?
    private var alwaysOnTopMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenus()

        let model = AppModel()
        let mainViewController = MainViewController(model: model)
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
        window.maxSize = NSSize(width: 520, height: 1200)
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
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let window {
            saveWindowSize(window)
        }
    }

    func windowDidResize(_ notification: Notification) {
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    @objc private func showMainWindow() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleAlwaysOnTop() {
        let enabled = !(UserDefaults.standard.bool(forKey: UserDefaultsKeys.alwaysOnTopEnabled))
        UserDefaults.standard.set(enabled, forKey: UserDefaultsKeys.alwaysOnTopEnabled)
        alwaysOnTopMenuItem?.state = enabled ? .on : .off
        window?.level = enabled ? .floating : .normal
    }

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func newWorkspace() {
        mainViewController?.promptCreateWorkspace()
    }

    @objc private func newFolder() {
        mainViewController?.createFolderAndBeginRename(parentId: nil)
    }
}
