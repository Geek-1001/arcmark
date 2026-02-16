//
//  WindowAttachmentService.swift
//  Arcmark
//
//  Service for attaching Arcmark window to browser windows using macOS Accessibility API.
//

import AppKit
@preconcurrency import ApplicationServices

@MainActor
protocol WindowAttachmentServiceDelegate: AnyObject {
    func attachmentService(_ service: WindowAttachmentService, shouldPositionWindow frame: NSRect, animated: Bool)
    func attachmentServiceShouldHideWindow(_ service: WindowAttachmentService)
    func attachmentServiceShouldShowWindow(_ service: WindowAttachmentService)
}

@MainActor
final class WindowAttachmentService {
    static let shared = WindowAttachmentService()

    weak var delegate: WindowAttachmentServiceDelegate?

    // State tracking
    private var browserApp: NSRunningApplication?
    private var browserWindowElement: AXUIElement?
    private var observers: [AXObserver] = []
    private var isEnabled: Bool = false
    private var currentBrowserBundleId: String?
    private var sidebarPosition: SidebarPosition = .right
    private var lastFrontmostBundleId: String?

    // Notification observers
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenChangeObserver: NSObjectProtocol?

    // Debouncing - reduced from 0.05 to 0.016 (~60fps) for smoother tracking
    private var positionUpdateTimer: Timer?
    private let positionDebounceInterval: TimeInterval = 0.016

    // Frame caching to skip redundant updates
    private var lastBrowserFrame: NSRect?
    private var lastArcmarkFrame: NSRect?

    // Screen caching to reduce detection overhead
    private var cachedScreen: NSScreen?
    private var cachedScreenFrame: NSRect?

    // Smooth animation using NSAnimationContext
    private var isAnimating: Bool = false
    private let animationDuration: TimeInterval = 0.12 // 120ms smooth animation

    private init() {}

    // MARK: - Public Interface

    func enable(browserBundleId: String, position: SidebarPosition) {
        guard checkAccessibilityPermissions() else {
            print("WindowAttachmentService: Accessibility permissions not granted")
            requestAccessibilityPermissions()
            return
        }

        print("WindowAttachmentService: Enabling attachment to \(browserBundleId), position: \(position)")

        self.currentBrowserBundleId = browserBundleId
        self.sidebarPosition = position
        self.isEnabled = true

        setupWorkspaceObservers()
        setupScreenChangeObserver()
        attachToBrowser()
    }

    func forceUpdate() {
        guard isEnabled else { return }
        updateArcmarkPosition(forceShow: true)
    }

    func disable() {
        print("WindowAttachmentService: Disabling attachment")

        isEnabled = false
        cleanupObservers()
        cleanupWorkspaceObservers()
        cleanupScreenChangeObserver()

        browserApp = nil
        browserWindowElement = nil
        currentBrowserBundleId = nil
        lastBrowserFrame = nil
        lastArcmarkFrame = nil
        lastFrontmostBundleId = nil
    }

    func checkAccessibilityPermissions() -> Bool {
        let optionKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [optionKey: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestAccessibilityPermissions() {
        let optionKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [optionKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Browser Window Discovery

    private func findFrontmostBrowserWindow() -> AXUIElement? {
        guard let bundleId = currentBrowserBundleId else { return nil }

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            return nil
        }

        guard app.isActive else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowList: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowList)
        guard result == .success else { return nil }

        guard let windows = windowList as? [AXUIElement], let firstWindow = windows.first else {
            return nil
        }

        // Check if window is minimized
        var minimized: CFTypeRef?
        AXUIElementCopyAttributeValue(firstWindow, kAXMinimizedAttribute as CFString, &minimized)
        if let isMinimized = minimized as? Bool, isMinimized {
            return nil
        }

        return firstWindow
    }

    // MARK: - Window Frame Extraction

    private func getWindowFrame(_ windowElement: AXUIElement) -> NSRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let position = positionRef,
              let size = sizeRef else {
            return nil
        }

        var cgPoint = CGPoint.zero
        var cgSize = CGSize.zero

        AXValueGetValue(position as! AXValue, .cgPoint, &cgPoint)
        AXValueGetValue(size as! AXValue, .cgSize, &cgSize)

        // Convert from Accessibility coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
        if let screen = NSScreen.main {
            let screenHeight = screen.frame.height
            let flippedY = screenHeight - cgPoint.y - cgSize.height
            return NSRect(x: cgPoint.x, y: flippedY, width: cgSize.width, height: cgSize.height)
        }

        return NSRect(origin: cgPoint, size: cgSize)
    }

    // MARK: - Position Calculation

    private func calculateArcmarkFrame(browserFrame: NSRect, arcmarkWidth: CGFloat) -> NSRect? {
        // Check minimum browser width requirement
        let minBrowserWidth: CGFloat = 600
        guard browserFrame.width >= minBrowserWidth else { return nil }

        // Detect which screen contains the browser window
        guard let screen = detectScreen(for: browserFrame) else { return nil }

        let screenFrame = screen.visibleFrame

        // Calculate Arcmark X position based on sidebar position
        let arcmarkX: CGFloat
        switch sidebarPosition {
        case .left:
            arcmarkX = browserFrame.minX - arcmarkWidth
            // Check if there's enough space on the left
            if arcmarkX < screenFrame.minX { return nil }
        case .right:
            arcmarkX = browserFrame.maxX
            // Check if there's enough space on the right
            if arcmarkX + arcmarkWidth > screenFrame.maxX { return nil }
        }

        // Match browser height exactly
        let arcmarkY = browserFrame.minY
        let arcmarkHeight = browserFrame.height

        return NSRect(x: arcmarkX, y: arcmarkY, width: arcmarkWidth, height: arcmarkHeight)
    }

    private func detectScreen(for frame: NSRect) -> NSScreen? {
        // Use cached screen if the frame is still within the same screen bounds
        if let cached = cachedScreen,
           let cachedBounds = cachedScreenFrame,
           cachedBounds.contains(CGPoint(x: frame.midX, y: frame.midY)) {
            return cached
        }

        // Recalculate if cache miss
        let screens = NSScreen.screens
        var bestScreen: NSScreen?
        var bestOverlap: CGFloat = 0

        for screen in screens {
            let intersection = frame.intersection(screen.frame)
            let overlap = intersection.width * intersection.height
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestScreen = screen
            }
        }

        let result = bestScreen ?? NSScreen.main
        cachedScreen = result
        cachedScreenFrame = result?.frame

        return result
    }

    // MARK: - Main Update Loop

    private func schedulePositionUpdate() {
        positionUpdateTimer?.invalidate()
        positionUpdateTimer = Timer.scheduledTimer(withTimeInterval: positionDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updateArcmarkPosition()
            }
        }
    }

    private func updateArcmarkPosition(forceShow: Bool = false) {
        guard isEnabled else { return }

        // Find the frontmost browser window
        guard let windowElement = findFrontmostBrowserWindow() else {
            delegate?.attachmentServiceShouldHideWindow(self)
            return
        }

        // Get the browser window frame
        guard let browserFrame = getWindowFrame(windowElement) else {
            delegate?.attachmentServiceShouldHideWindow(self)
            return
        }

        // Check if frame has changed
        let frameChanged = lastBrowserFrame != browserFrame
        lastBrowserFrame = browserFrame

        // Get current Arcmark window width (user may have resized it)
        let arcmarkWidth: CGFloat = 340 // Default width, will be updated by delegate if needed

        // Calculate new Arcmark frame
        guard let newFrame = calculateArcmarkFrame(browserFrame: browserFrame, arcmarkWidth: arcmarkWidth) else {
            // Invalid frame (browser too narrow, not enough space, etc.)
            delegate?.attachmentServiceShouldHideWindow(self)
            return
        }

        // Check if calculated frame has changed
        let calculatedFrameChanged = lastArcmarkFrame != newFrame
        lastArcmarkFrame = newFrame

        // Only update if frame changed or if we're forcing show (e.g., app switch)
        if frameChanged || calculatedFrameChanged || forceShow {
            // Notify delegate to position window with smooth animation
            delegate?.attachmentService(self, shouldPositionWindow: newFrame, animated: true)
        }
    }

    // MARK: - Browser Attachment

    private func attachToBrowser() {
        guard let bundleId = currentBrowserBundleId else {
            print("WindowAttachmentService: No browser bundle ID configured")
            return
        }

        // Check if browser is running
        guard BrowserManager.isRunning(bundleId: bundleId) else {
            print("WindowAttachmentService: Browser not running")
            delegate?.attachmentServiceShouldHideWindow(self)
            return
        }

        // Check if browser is active (frontmost)
        guard let frontmost = BrowserManager.frontmostApp() else {
            print("WindowAttachmentService: Could not determine frontmost app")
            delegate?.attachmentServiceShouldHideWindow(self)
            return
        }

        guard frontmost.bundleIdentifier == bundleId else {
            print("WindowAttachmentService: Browser not active")
            delegate?.attachmentServiceShouldHideWindow(self)
            return
        }

        // Find browser window
        guard let windowElement = findFrontmostBrowserWindow() else {
            print("WindowAttachmentService: No browser window found")
            delegate?.attachmentServiceShouldHideWindow(self)
            return
        }

        // Check if we're already observing this exact window
        if let existingElement = browserWindowElement,
           CFEqual(existingElement, windowElement) {
            // Same window, just update position without re-registering observers
            // Force show in case window was hidden and we're switching to browser
            print("WindowAttachmentService: Already observing this window, updating position and showing")
            updateArcmarkPosition(forceShow: true)
            return
        }

        print("WindowAttachmentService: New window detected, setting up observers")

        // Different window - cleanup old observers and setup new ones
        cleanupObservers()
        browserWindowElement = windowElement
        browserApp = frontmost

        // Setup observers for this window
        observeBrowserWindow()

        // Perform initial position update and show window
        updateArcmarkPosition(forceShow: true)
    }

    // MARK: - AX Observers

    private func observeBrowserWindow() {
        guard let windowElement = browserWindowElement,
              let app = browserApp else { return }

        var observer: AXObserver?
        let error = AXObserverCreate(app.processIdentifier, { (_, element, notification, refcon) in
            guard let refcon = refcon else { return }
            let service = Unmanaged<WindowAttachmentService>.fromOpaque(refcon).takeUnretainedValue()

            Task { @MainActor in
                let notificationName = notification as String

                if notificationName == (kAXMovedNotification as String) || notificationName == (kAXResizedNotification as String) {
                    service.schedulePositionUpdate()
                } else if notificationName == (kAXUIElementDestroyedNotification as String) {
                    service.delegate?.attachmentServiceShouldHideWindow(service)
                    service.cleanupObservers()
                }
            }
        }, &observer)

        guard error == .success, let observer = observer else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Register for notifications
        AXObserverAddNotification(observer, windowElement, kAXMovedNotification as CFString, selfPtr)
        AXObserverAddNotification(observer, windowElement, kAXResizedNotification as CFString, selfPtr)
        AXObserverAddNotification(observer, windowElement, kAXUIElementDestroyedNotification as CFString, selfPtr)

        // Add observer to run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)

        observers.append(observer)
    }

    private func cleanupObservers() {
        for observer in observers {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        positionUpdateTimer?.invalidate()
        positionUpdateTimer = nil
        lastBrowserFrame = nil
        lastArcmarkFrame = nil
        cachedScreen = nil
        cachedScreenFrame = nil
        isAnimating = false
    }

    // MARK: - Workspace Observers

    private func setupWorkspaceObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        let activatedObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let bundleId = app.bundleIdentifier

                if bundleId == self.currentBrowserBundleId {
                    // Browser became active - attach and show
                    print("WindowAttachmentService: Browser activated, attaching")
                    self.lastFrontmostBundleId = bundleId
                    self.attachToBrowser()
                } else if bundleId == Bundle.main.bundleIdentifier {
                    // Arcmark itself activated
                    // If the previous app was the browser, keep Arcmark visible
                    // This handles clicking between browser and Arcmark
                    if self.lastFrontmostBundleId == self.currentBrowserBundleId {
                        print("WindowAttachmentService: Arcmark activated, but browser was previous - keeping visible")
                        return
                    }
                    // If previous app was not the browser, hide Arcmark
                    print("WindowAttachmentService: Arcmark activated from non-browser app - hiding")
                    self.delegate?.attachmentServiceShouldHideWindow(self)
                } else {
                    // Different app became active - hide Arcmark
                    print("WindowAttachmentService: Different app activated - hiding")
                    self.lastFrontmostBundleId = bundleId
                    self.delegate?.attachmentServiceShouldHideWindow(self)
                }
            }
        }

        let terminatedObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if app.bundleIdentifier == self.currentBrowserBundleId {
                    // Browser quit - hide and cleanup
                    self.delegate?.attachmentServiceShouldHideWindow(self)
                    self.cleanupObservers()
                }
            }
        }

        let launchedObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if app.bundleIdentifier == self.currentBrowserBundleId {
                    // Browser launched - wait for activation
                    // Will be handled by didActivateApplicationNotification
                }
            }
        }

        workspaceObservers = [activatedObserver, terminatedObserver, launchedObserver]
    }

    private func cleanupWorkspaceObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - Screen Change Observer

    private func setupScreenChangeObserver() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            // Use longer debounce for screen changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.updateArcmarkPosition()
            }
        }
    }

    private func cleanupScreenChangeObserver() {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
    }
}
