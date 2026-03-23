import AppKit
@preconcurrency import Sparkle

@MainActor
final class MainViewController: NSViewController {
    let model: AppModel

    // Coordinators and child view controllers
    private let searchCoordinator = SearchCoordinator()
    private let nodeListViewController = NodeListViewController()
    private let settingsViewController = SettingsContentViewController()

    // UI Components
    private let workspaceSwitcher = WorkspaceSwitcherView(style: .defaultStyle)
    private let searchField = SearchBarView(style: .defaultSearch)
    private let pinnedTabsView = PinnedTabsView()
    private let pasteButton = IconTitleButton(
        title: "Add links from clipboard",
        symbolName: "plus",
        style: .pasteAction
    )

    // Sparkle updater (passed from AppDelegate)
    var updater: SPUUpdater? {
        didSet { settingsViewController.updater = updater }
    }

    // Swipe animation views
    private var swipeClipContainer: NSView!         // Clips to bounds, contains content + preview
    private var workspaceContentStack: NSStackView! // The animated workspace content
    private var swipePreviewView: NSView?           // Container for preview snapshot + gradient
    private var swipePreviewSnapshot: NSImage?      // Cached snapshot of adjacent workspace
    private var swipePreviewDirection: SwipeDirection? // Direction the snapshot was captured for

    // State
    private var isReloadScheduled = false
    private var hasLoaded = false
    private var lastWorkspaceId: UUID?
    private var pendingWorkspaceRenameId: UUID?
    private var isSwipeAnimating = false
    private var suppressNodeAnimations = false          // Suppresses collection view animations during swipe transitions
    private var swipeColorAnimationFromColor: NSColor?  // Set before workspace switch to trigger animated color transition

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupChildViewControllers()
        setupUI()
        setupSearchCoordinator()
        setupNodeListCallbacks()
        bindModel()
        reloadData()

        // Listen for favicon updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFaviconUpdate),
            name: .init("UpdateLinkFavicon"),
            object: nil
        )
    }

    // MARK: - Setup

    private func setupChildViewControllers() {
        addChild(nodeListViewController)
        addChild(settingsViewController)
    }

    private func setupUI() {
        // Workspace switcher
        workspaceSwitcher.translatesAutoresizingMaskIntoConstraints = false
        workspaceSwitcher.onWorkspaceSelected = { [weak self] workspaceId in
            self?.model.selectWorkspace(id: workspaceId)
        }
        workspaceSwitcher.onWorkspaceRightClick = { [weak self] workspaceId, point in
            self?.showWorkspaceContextMenu(for: workspaceId, at: point)
        }
        workspaceSwitcher.onAddWorkspace = { [weak self] in
            self?.promptCreateWorkspace()
        }
        workspaceSwitcher.onWorkspaceRename = { [weak self] workspaceId, newName in
            self?.model.renameWorkspace(id: workspaceId, newName: newName)
        }
        workspaceSwitcher.onSettingsSelected = { [weak self] in
            self?.model.selectSettings()
        }

        // Search field
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = "Search in workspace"
        searchField.onTextChange = { [weak self] text in
            self?.nodeListViewController.clearSelections()
            self?.searchCoordinator.updateQuery(text)
        }

        // Pinned tabs
        pinnedTabsView.onLinkClicked = { [weak self] linkId in
            guard let self, let link = self.model.pinnedLinkById(linkId) else { return }
            self.openLink(link)
        }
        pinnedTabsView.onLinkRightClicked = { [weak self] linkId, event in
            self?.showPinnedTabContextMenu(for: linkId, at: event)
        }

        // Paste button
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        pasteButton.target = self
        pasteButton.action = #selector(pasteLink)

        // Node list view
        nodeListViewController.view.translatesAutoresizingMaskIntoConstraints = false

        // Settings view
        settingsViewController.appModel = model
        settingsViewController.view.translatesAutoresizingMaskIntoConstraints = false
        settingsViewController.view.isHidden = true

        // Layout
        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(workspaceSwitcher)

        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(pasteButton)

        // Workspace content stack (animated during swipe)
        let contentStack = NSStackView(views: [pinnedTabsView, nodeListViewController.view, bottomBar])
        contentStack.orientation = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.alignment = .centerX
        contentStack.wantsLayer = true
        workspaceContentStack = contentStack

        // Clipping container for swipe animation
        let clipContainer = NSView()
        clipContainer.translatesAutoresizingMaskIntoConstraints = false
        clipContainer.wantsLayer = true
        clipContainer.layer?.masksToBounds = true
        swipeClipContainer = clipContainer
        clipContainer.addSubview(contentStack)

        // Outer stack: topBar, searchField, then the swipe clip container
        let stack = NSStackView(views: [topBar, searchField, clipContainer])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alignment = .centerX

        view.addSubview(stack)
        view.addSubview(settingsViewController.view)

        NSLayoutConstraint.activate([
            workspaceSwitcher.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            workspaceSwitcher.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            workspaceSwitcher.topAnchor.constraint(equalTo: topBar.topAnchor),
            workspaceSwitcher.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),

            pasteButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            pasteButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            pasteButton.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            pasteButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),

            // Content stack fills the clip container
            contentStack.leadingAnchor.constraint(equalTo: clipContainer.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: clipContainer.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: clipContainer.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: clipContainer.bottomAnchor),

            // Clip container fills width of outer stack
            clipContainer.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            clipContainer.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.windowPadding),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -LayoutConstants.windowPadding),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: LayoutConstants.windowPadding),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -LayoutConstants.windowPadding),

            topBar.heightAnchor.constraint(equalToConstant: 30),
            bottomBar.heightAnchor.constraint(equalToConstant: pasteButton.style.height)
        ])

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 2),
            searchField.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -2),
            pinnedTabsView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: 2),
            pinnedTabsView.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: -2),
        ])

        // Settings view constraints
        NSLayoutConstraint.activate([
            settingsViewController.view.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            settingsViewController.view.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            settingsViewController.view.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            settingsViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -LayoutConstants.windowPadding)
        ])
    }

    private func setupSearchCoordinator() {
        searchCoordinator.onQueryChanged = { [weak self] _ in
            self?.reloadData()
        }
    }

    private func setupNodeListCallbacks() {
        nodeListViewController.nodeProvider = { [weak self] in
            guard let self else { return [] }
            return self.searchCoordinator.filter(nodes: self.model.currentWorkspace.items)
        }

        nodeListViewController.workspacesProvider = { [weak self] in
            self?.model.workspaces ?? []
        }

        nodeListViewController.currentWorkspaceIdProvider = { [weak self] in
            self?.model.currentWorkspace.id
        }

        nodeListViewController.findNodeById = { [weak self] id in
            self?.model.nodeById(id)
        }

        nodeListViewController.findNodeLocation = { [weak self] id in
            self?.model.location(of: id)
        }

        nodeListViewController.findNodeInNodes = { [weak self] id, nodes in
            self?.model.findNode(id: id, in: nodes)
        }

        nodeListViewController.onNodeSelected = { [weak self] nodeId in
            guard let self, let node = self.model.nodeById(nodeId) else { return }
            if case .link(let link) = node {
                self.openLink(link)
            }
        }

        nodeListViewController.onFolderToggled = { [weak self] folderId, _ in
            guard let self else { return }
            if self.searchCoordinator.isSearchActive { return }
            if let node = self.model.nodeById(folderId), case .folder(let folder) = node {
                self.model.setFolderExpanded(id: folder.id, isExpanded: !folder.isExpanded)
            }
        }

        nodeListViewController.onNodeMoved = { [weak self] nodeId, targetParentId, targetIndex in
            self?.model.moveNode(id: nodeId, toParentId: targetParentId, index: targetIndex)
        }

        nodeListViewController.onNodeDeleted = { [weak self] nodeId in
            self?.model.deleteNode(id: nodeId)
        }

        nodeListViewController.onNodeRenamed = { [weak self] nodeId, newName in
            self?.model.renameNode(id: nodeId, newName: newName)
        }

        nodeListViewController.onNodeMovedToWorkspace = { [weak self] nodeId, workspaceId in
            self?.model.moveNodeToWorkspace(id: nodeId, workspaceId: workspaceId)
        }

        nodeListViewController.onBulkNodesMovedToWorkspace = { [weak self] nodeIds, workspaceId in
            self?.model.moveNodesToWorkspace(nodeIds: nodeIds, toWorkspaceId: workspaceId)
        }

        nodeListViewController.onBulkNodesGrouped = { [weak self] nodeIds, folderName in
            self?.model.groupNodesInNewFolder(nodeIds: nodeIds, folderName: folderName)
        }

        nodeListViewController.onBulkNodesCopied = { [weak self] nodeIds in
            self?.handleBulkCopyLinks(nodeIds)
        }

        nodeListViewController.onBulkNodesDeleted = { [weak self] nodeIds in
            guard let self else { return }
            for nodeId in nodeIds {
                self.model.deleteNode(id: nodeId)
            }
        }

        nodeListViewController.onNewFolderRequested = { [weak self] parentId in
            self?.createFolderAndBeginRename(parentId: parentId)
        }

        nodeListViewController.onLinkUrlEdited = { [weak self] nodeId, newUrl in
            self?.model.updateLinkUrl(id: nodeId, newUrl: newUrl)
        }

        nodeListViewController.onOpenFolderLinks = { [weak self] folderId in
            guard let self, let node = self.model.nodeById(folderId),
                  case .folder(let folder) = node else { return }
            for child in folder.children {
                if case .link(let link) = child {
                    self.openLink(link)
                }
            }
        }

        nodeListViewController.onBulkOpenLinks = { [weak self] nodeIds in
            guard let self else { return }
            for nodeId in nodeIds {
                guard let node = self.model.nodeById(nodeId) else { continue }
                switch node {
                case .link(let link):
                    self.openLink(link)
                case .folder(let folder):
                    for child in folder.children {
                        if case .link(let link) = child {
                            self.openLink(link)
                        }
                    }
                }
            }
        }

        nodeListViewController.onPinLink = { [weak self] nodeId in
            self?.model.pinLink(id: nodeId)
        }

        nodeListViewController.canPinLink = { [weak self] in
            self?.model.canPinMore ?? false
        }
    }

    private func bindModel() {
        model.onChange = { [weak self] in
            guard let self else { return }
            if self.isReloadScheduled { return }
            self.isReloadScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isReloadScheduled = false
                self.reloadData()
            }
        }
    }

    // MARK: - Data Reload

    private func reloadData() {
        // Cancel any in-progress inline rename if node is deleted
        if let renameId = nodeListViewController.inlineRenameNodeId,
           model.nodeById(renameId) == nil {
            nodeListViewController.cancelInlineRename()
        }

        reloadWorkspaceMenu()

        // Notify settings view that workspaces may have changed
        settingsViewController.notifyWorkspacesChanged()

        // Clear selections when workspace changes
        let currentWorkspaceId = model.currentWorkspace.id
        if hasLoaded && currentWorkspaceId != lastWorkspaceId {
            nodeListViewController.clearSelections()
            lastWorkspaceId = currentWorkspaceId
        }

        // Check if settings is selected
        if model.state.isSettingsSelected {
            nodeListViewController.clearSelections()
            showSettingsContent()
        } else {
            showWorkspaceContent()
            applyWorkspaceStyling()
            pinnedTabsView.update(pinnedLinks: model.currentWorkspace.pinnedLinks)
            let filteredNodes = searchCoordinator.filter(nodes: model.currentWorkspace.items)
            let forceExpand = searchCoordinator.isSearchActive
            nodeListViewController.isSearchActive = searchCoordinator.isSearchActive
            let animated = !suppressNodeAnimations
            nodeListViewController.reloadData(with: filteredNodes, forceExpand: forceExpand, animated: animated)
        }
        hasLoaded = true
    }

    private func reloadWorkspaceMenu() {
        let workspaces = model.workspaces

        workspaceSwitcher.workspaces = workspaces.map { workspace in
            WorkspaceSwitcherView.WorkspaceItem(
                id: workspace.id,
                name: workspace.name,
                colorId: workspace.colorId
            )
        }

        workspaceSwitcher.isSettingsSelected = model.state.isSettingsSelected

        if model.state.isSettingsSelected {
            workspaceSwitcher.selectedWorkspaceId = nil
            workspaceSwitcher.workspaceColor = .settingsBackground
        } else {
            let selectedId = model.currentWorkspace.id
            workspaceSwitcher.selectedWorkspaceId = selectedId
            workspaceSwitcher.workspaceColor = model.currentWorkspace.colorId
        }

        handlePendingWorkspaceRename()
    }

    private func applyWorkspaceStyling() {
        let newColor = model.currentWorkspace.colorId.backgroundColor
        nodeListViewController.workspaceColor = model.currentWorkspace.colorId

        if let fromColor = swipeColorAnimationFromColor {
            // Animate background color transition during swipe
            swipeColorAnimationFromColor = nil
            view.layer?.backgroundColor = fromColor.cgColor
            view.window?.backgroundColor = fromColor

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = ThemeConstants.Animation.durationSlow
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                self.view.layer?.backgroundColor = newColor.cgColor
                self.view.window?.backgroundColor = newColor
            })
        } else {
            view.layer?.backgroundColor = newColor.cgColor
            view.window?.backgroundColor = newColor
        }
    }

    private func showSettingsContent() {
        // Hide workspace content
        searchField.isHidden = true
        pinnedTabsView.isHidden = true
        pasteButton.isHidden = true
        nodeListViewController.view.isHidden = true

        // Show settings content
        settingsViewController.view.isHidden = false

        // Apply settings background color
        let settingsColor = NSColor(calibratedRed: 0.898, green: 0.906, blue: 0.922, alpha: 1.0)

        if let fromColor = swipeColorAnimationFromColor {
            swipeColorAnimationFromColor = nil
            view.layer?.backgroundColor = fromColor.cgColor
            view.window?.backgroundColor = fromColor

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = ThemeConstants.Animation.durationSlow
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                self.view.layer?.backgroundColor = settingsColor.cgColor
                self.view.window?.backgroundColor = settingsColor
            })
        } else {
            view.layer?.backgroundColor = settingsColor.cgColor
            view.window?.backgroundColor = settingsColor
        }
    }

    private func showWorkspaceContent() {
        // Show workspace content
        searchField.isHidden = false
        pinnedTabsView.isHidden = model.currentWorkspace.pinnedLinks.isEmpty
        pasteButton.isHidden = false
        nodeListViewController.view.isHidden = false

        // Hide settings content
        settingsViewController.view.isHidden = true
    }

    // MARK: - Workspace Management

    private func showWorkspaceContextMenu(for workspaceId: UUID, at point: NSPoint) {
        // Temporarily select the workspace for context menu actions
        let previousWorkspaceId = model.currentWorkspace.id
        if previousWorkspaceId != workspaceId {
            model.selectWorkspace(id: workspaceId)
        }

        let menu = NSMenu()
        let canDelete = model.workspaces.count > 1
        guard let workspaceIndex = model.workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }
        let canMoveLeft = workspaceIndex > 0
        let canMoveRight = workspaceIndex < model.workspaces.count - 1

        let renameItem = NSMenuItem(title: "Rename Workspace…", action: #selector(renameWorkspaceFromMenu), keyEquivalent: "")
        renameItem.target = self
        menu.addItem(renameItem)

        let colorItem = NSMenuItem(title: "Change Color", action: nil, keyEquivalent: "")
        let colorSubmenu = NSMenu()
        for colorId in WorkspaceColorId.allCases {
            let colorMenuItem = NSMenuItem(title: colorId.name, action: #selector(changeColorTo(_:)), keyEquivalent: "")
            colorMenuItem.target = self
            colorMenuItem.representedObject = colorId
            colorMenuItem.image = createColorPreviewImage(color: colorId.color)
            if colorId == model.currentWorkspace.colorId {
                colorMenuItem.state = .on
            }
            colorSubmenu.addItem(colorMenuItem)
        }
        colorItem.submenu = colorSubmenu
        menu.addItem(colorItem)

        if canMoveLeft || canMoveRight {
            menu.addItem(NSMenuItem.separator())

            if canMoveLeft {
                let moveLeftItem = NSMenuItem(title: "Move Left", action: #selector(moveWorkspaceLeft), keyEquivalent: "")
                moveLeftItem.target = self
                menu.addItem(moveLeftItem)
            }

            if canMoveRight {
                let moveRightItem = NSMenuItem(title: "Move Right", action: #selector(moveWorkspaceRight), keyEquivalent: "")
                moveRightItem.target = self
                menu.addItem(moveRightItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let deleteItem = NSMenuItem(title: "Delete Workspace…", action: #selector(deleteWorkspaceFromMenu), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.isEnabled = canDelete
        menu.addItem(deleteItem)

        if view.window != nil {
            let pointInView = view.convert(point, from: nil)
            menu.popUp(positioning: nil, at: pointInView, in: view)
        }
    }

    @objc private func renameWorkspaceFromMenu() {
        let workspace = model.currentWorkspace
        workspaceSwitcher.beginInlineRename(workspaceId: workspace.id)
    }

    @objc private func changeColorTo(_ sender: NSMenuItem) {
        guard let colorId = sender.representedObject as? WorkspaceColorId else { return }
        let workspace = model.currentWorkspace
        model.updateWorkspaceColor(id: workspace.id, colorId: colorId)
    }

    private func createColorPreviewImage(color: NSColor, size: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let path = NSBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()

        // Add subtle border
        let borderColor = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 0.20)
        borderColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        image.unlockFocus()
        return image
    }

    @objc private func deleteWorkspaceFromMenu() {
        let workspace = model.currentWorkspace
        let alert = NSAlert()
        alert.messageText = "Delete Workspace"
        alert.informativeText = "This will delete the workspace and everything inside it."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.deleteWorkspace(id: workspace.id)
        }
    }

    @objc private func moveWorkspaceLeft() {
        let workspace = model.currentWorkspace
        model.moveWorkspace(id: workspace.id, direction: .left)
    }

    @objc private func moveWorkspaceRight() {
        let workspace = model.currentWorkspace
        model.moveWorkspace(id: workspace.id, direction: .right)
    }

    /// The workspace switcher view, exposed for swipe gesture exclusion.
    var workspaceSwitcherView: NSView { workspaceSwitcher }

    func navigateToPreviousWorkspace() {
        let workspaces = model.workspaces
        if model.state.isSettingsSelected {
            return
        }
        let currentId = model.currentWorkspace.id
        guard let currentIndex = workspaces.firstIndex(where: { $0.id == currentId }) else { return }
        if currentIndex > 0 {
            let prevId = workspaces[currentIndex - 1].id
            model.selectWorkspace(id: prevId)
            workspaceSwitcher.scrollToWorkspace(id: prevId)
        } else {
            model.selectSettings()
            workspaceSwitcher.scrollToSettings()
        }
    }

    func navigateToNextWorkspace() {
        let workspaces = model.workspaces
        if model.state.isSettingsSelected {
            guard let firstWorkspace = workspaces.first else { return }
            model.selectWorkspace(id: firstWorkspace.id)
            workspaceSwitcher.scrollToWorkspace(id: firstWorkspace.id)
            return
        }
        let currentId = model.currentWorkspace.id
        guard let currentIndex = workspaces.firstIndex(where: { $0.id == currentId }) else { return }
        if currentIndex < workspaces.count - 1 {
            let nextId = workspaces[currentIndex + 1].id
            model.selectWorkspace(id: nextId)
            workspaceSwitcher.scrollToWorkspace(id: nextId)
        }
    }

    func promptCreateWorkspace() {
        let workspaceId = model.createWorkspace(name: "Untitled Workspace", colorId: .randomColor())
        scheduleWorkspaceInlineRename(for: workspaceId)
    }

    private func scheduleWorkspaceInlineRename(for workspaceId: UUID) {
        pendingWorkspaceRenameId = workspaceId
    }

    private func handlePendingWorkspaceRename() {
        guard let workspaceId = pendingWorkspaceRenameId else { return }
        pendingWorkspaceRenameId = nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.workspaceSwitcher.beginInlineRename(workspaceId: workspaceId)
        }
    }

    // MARK: - Node Management

    func createFolderAndBeginRename(parentId: UUID?) {
        if let parentId {
            model.setFolderExpanded(id: parentId, isExpanded: true)
        }
        let newId = model.addFolder(name: "Untitled", parentId: parentId)
        nodeListViewController.scheduleInlineRename(for: newId)
    }

    @objc func paste(_ sender: Any?) {
        pasteLink()
    }

    @objc private func pasteLink() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        let urls = extractUrls(from: pasted)
        guard !urls.isEmpty else { return }
        for url in urls {
            let linkId = model.addLink(urlString: url.absoluteString, title: titleForUrl(url), parentId: nil)
            fetchTitleForNewLink(id: linkId, url: url)
        }
    }

    private func openLink(_ link: Link) {
        guard let url = URL(string: link.url) else { return }
        let profile: String? = {
            guard let bundleId = BrowserManager.resolveDefaultBrowserBundleId() else { return nil }
            return model.currentWorkspace.browserProfiles[bundleId]
        }()
        BrowserManager.open(url: url, profile: profile)
    }

    // MARK: - URL Utilities

    private func normalizedUrl(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        if lower.hasPrefix("localhost") {
            return URL(string: "http://\(trimmed)")
        }

        return nil
    }

    private func extractUrls(from text: String) -> [URL] {
        let pattern = #"(?i)\b(?:https?://[^\s<>"',;]+|localhost(?::\d+)?(?:/[^\s<>"',;]*)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var urls: [URL] = []

        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let matchRange = match?.range,
                  let stringRange = Range(matchRange, in: text) else { return }
            let candidate = stripTrailingPunctuation(from: String(text[stringRange]))
            if let url = normalizedUrl(from: candidate) {
                urls.append(url)
            }
        }

        return urls
    }

    private func stripTrailingPunctuation(from value: String) -> String {
        var trimmed = value
        while let last = trimmed.last, ".,;:)]}?!".contains(last) {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func titleForUrl(_ url: URL) -> String {
        if let host = url.host {
            return host
        }
        return url.absoluteString
    }

    private func fetchTitleForNewLink(id: UUID, url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        LinkTitleService.shared.fetchTitle(for: url, linkId: id) { [weak self] title in
            guard let self, let title else { return }
            _ = self.model.updateLinkTitleIfDefault(id: id, newTitle: title)
        }
    }

    @objc private func handleFaviconUpdate(_ notification: Notification) {
        guard let linkId = notification.userInfo?["linkId"] as? UUID,
              let path = notification.userInfo?["path"] as? String else { return }
        if model.pinnedLinkById(linkId) != nil {
            model.updatePinnedLinkFaviconPath(id: linkId, path: path)
        } else {
            model.updateLinkFaviconPath(id: linkId, path: path)
        }
    }

    // MARK: - Pinned Tabs

    private func showPinnedTabContextMenu(for linkId: UUID, at event: NSEvent) {
        let menu = NSMenu()
        let unpinItem = NSMenuItem(title: "Unpin", action: #selector(unpinTab(_:)), keyEquivalent: "")
        unpinItem.target = self
        unpinItem.representedObject = linkId
        menu.addItem(unpinItem)
        NSMenu.popUpContextMenu(menu, with: event, for: pinnedTabsView)
    }

    @objc private func unpinTab(_ sender: NSMenuItem) {
        guard let linkId = sender.representedObject as? UUID else { return }
        model.unpinLink(id: linkId)
    }

    // MARK: - Bulk Operations

    private func handleBulkCopyLinks(_ nodeIds: [UUID]) {
        let nodes = nodeIds.compactMap { id in
            model.findNode(id: id, in: model.currentWorkspace.items)
        }
        let urls = nodes.compactMap { node -> String? in
            if case .link(let link) = node {
                return link.url
            }
            return nil
        }

        guard !urls.isEmpty else { return }

        let joined = urls.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(joined, forType: .string)
    }
}

// MARK: - SwipeGestureServiceDelegate

extension MainViewController: SwipeGestureServiceDelegate {

    func swipeGestureDidBegin(_ service: SwipeGestureService) {
        guard !isSwipeAnimating else { return }
        workspaceContentStack.layer?.removeAllAnimations()
        removeSwipePreview()
    }

    func swipeGestureDidUpdate(_ service: SwipeGestureService, translationX: CGFloat) {
        guard !isSwipeAnimating else { return }
        guard let layer = workspaceContentStack.layer else { return }

        let canGoRight = canNavigatePrevious()  // finger right = previous
        let canGoLeft = canNavigateNext()        // finger left = next

        var clampedX = translationX
        // Apply rubber-band dampening if no adjacent workspace in that direction
        if translationX > 0 && !canGoRight {
            clampedX = translationX * 0.7
        } else if translationX < 0 && !canGoLeft {
            clampedX = translationX * 0.7
        }

        // Capture preview snapshot on first significant movement
        let direction: SwipeDirection = translationX > 0 ? .right : .left
        if swipePreviewSnapshot == nil || swipePreviewDirection != direction {
            capturePreviewSnapshot(for: direction)
        }

        // Show/update preview of adjacent workspace
        updateSwipePreview(translationX: clampedX, direction: direction)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(clampedX, 0, 0)
        CATransaction.commit()
    }

    func swipeGestureDidComplete(_ service: SwipeGestureService, direction: SwipeDirection) {
        guard !isSwipeAnimating else { return }
        guard let layer = workspaceContentStack.layer else { return }

        let containerWidth = swipeClipContainer.bounds.width
        let containerHeight = swipeClipContainer.bounds.height

        // Determine if we can actually navigate
        let canNavigate: Bool
        switch direction {
        case .right: canNavigate = canNavigatePrevious()
        case .left: canNavigate = canNavigateNext()
        }

        guard canNavigate else {
            animateSpringBounce()
            return
        }

        isSwipeAnimating = true

        // Save current color so applyWorkspaceStyling can animate the transition
        let currentBgColor: NSColor
        if model.state.isSettingsSelected {
            currentBgColor = ThemeConstants.Colors.settingsBackground
        } else {
            currentBgColor = model.currentWorkspace.colorId.backgroundColor
        }

        // --- Snapshot-based animation ---
        // Capture a snapshot of the current workspace content at its current drag position
        let currentSnapshotView = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))
        currentSnapshotView.wantsLayer = true
        let contentBounds = workspaceContentStack.bounds
        if let bitmap = workspaceContentStack.bitmapImageRepForCachingDisplay(in: contentBounds) {
            workspaceContentStack.cacheDisplay(in: contentBounds, to: bitmap)
            let image = NSImage(size: contentBounds.size)
            image.addRepresentation(bitmap)
            let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))
            imageView.imageScaling = .scaleNone
            imageView.imageAlignment = .alignTopLeft
            imageView.image = image
            currentSnapshotView.addSubview(imageView)
        }

        // Build the incoming snapshot from the already-captured preview
        let incomingSnapshotView = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))
        incomingSnapshotView.wantsLayer = true
        if let previewImage = swipePreviewSnapshot {
            let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))
            imageView.imageScaling = .scaleNone
            imageView.imageAlignment = .alignTopLeft
            imageView.image = previewImage
            incomingSnapshotView.addSubview(imageView)
        }

        // Capture current drag offset before resetting
        let currentOffset = layer.presentation()?.transform.m41 ?? layer.transform.m41
        let slideOffX: CGFloat = direction == .right ? containerWidth : -containerWidth
        let incomingStartX: CGFloat = direction == .right ? currentOffset - containerWidth : currentOffset + containerWidth

        // Remove the drag preview and reset the real content layer
        removeSwipePreview()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()

        // Hide the real content and place snapshots in the clip container
        workspaceContentStack.isHidden = true

        currentSnapshotView.frame.origin.x = currentOffset
        incomingSnapshotView.frame.origin.x = incomingStartX
        swipeClipContainer.addSubview(currentSnapshotView)
        swipeClipContainer.addSubview(incomingSnapshotView)

        // Animate both snapshots with spring physics (matches edge bounce feel)
        let currentSpring = CASpringAnimation(keyPath: "position.x")
        currentSpring.fromValue = currentSnapshotView.layer!.position.x
        currentSpring.toValue = slideOffX + containerWidth / 2
        currentSpring.mass = 1.0
        currentSpring.stiffness = 400
        currentSpring.damping = 22
        currentSpring.initialVelocity = 0
        currentSpring.duration = currentSpring.settlingDuration
        currentSpring.isRemovedOnCompletion = false
        currentSpring.fillMode = .forwards

        let incomingSpring = CASpringAnimation(keyPath: "position.x")
        incomingSpring.fromValue = incomingSnapshotView.layer!.position.x
        incomingSpring.toValue = containerWidth / 2
        incomingSpring.mass = 1.0
        incomingSpring.stiffness = 400
        incomingSpring.damping = 22
        incomingSpring.initialVelocity = 0
        incomingSpring.duration = incomingSpring.settlingDuration
        incomingSpring.isRemovedOnCompletion = false
        incomingSpring.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }

            // Remove snapshots
            currentSnapshotView.removeFromSuperview()
            incomingSnapshotView.removeFromSuperview()

            // Set the from-color so reloadData → applyWorkspaceStyling animates the color
            self.swipeColorAnimationFromColor = currentBgColor

            // Suppress collection view animations — we already animated via snapshots
            self.suppressNodeAnimations = true

            // Suppress async onChange to prevent extra reload
            let savedOnChange = self.model.onChange
            self.model.onChange = nil

            // Switch workspace
            switch direction {
            case .right: self.navigateToPreviousWorkspace()
            case .left: self.navigateToNextWorkspace()
            }

            // Synchronously update UI with new workspace data
            self.reloadData()

            // Restore onChange for future state changes
            self.model.onChange = savedOnChange

            // Show the real content (now displaying new workspace)
            self.workspaceContentStack.isHidden = false
            self.suppressNodeAnimations = false
            self.isSwipeAnimating = false
        }
        currentSnapshotView.layer!.add(currentSpring, forKey: "swipeTransition")
        incomingSnapshotView.layer!.add(incomingSpring, forKey: "swipeTransition")
        CATransaction.commit()
    }

    func swipeGestureDidCancel(_ service: SwipeGestureService) {
        animateSnapBack()
    }

    // MARK: - Swipe Helpers

    private func canNavigatePrevious() -> Bool {
        // Swipe disabled from/to settings — only between workspaces
        if model.state.isSettingsSelected { return false }
        let workspaces = model.workspaces
        guard let currentIndex = workspaces.firstIndex(where: { $0.id == model.currentWorkspace.id }) else { return false }
        return currentIndex > 0
    }

    private func canNavigateNext() -> Bool {
        // Swipe disabled from/to settings — only between workspaces
        if model.state.isSettingsSelected { return false }
        let workspaces = model.workspaces
        guard let currentIndex = workspaces.firstIndex(where: { $0.id == model.currentWorkspace.id }) else { return false }
        return currentIndex < workspaces.count - 1
    }

    private func animateSnapBack() {
        guard let layer = workspaceContentStack.layer else { return }
        isSwipeAnimating = true

        CATransaction.begin()
        CATransaction.setAnimationDuration(ThemeConstants.Animation.durationSlow)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock { [weak self] in
            self?.isSwipeAnimating = false
            self?.removeSwipePreview()
        }
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    /// Spring bounce used when swiping at an edge with no adjacent workspace.
    private func animateSpringBounce() {
        guard let layer = workspaceContentStack.layer else { return }
        isSwipeAnimating = true

        let spring = CASpringAnimation(keyPath: "transform.translation.x")
        spring.fromValue = layer.transform.m41
        spring.toValue = 0
        spring.mass = 1.0
        spring.stiffness = 400
        spring.damping = 22
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        spring.isRemovedOnCompletion = false
        spring.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            layer.removeAnimation(forKey: "springBounce")
            layer.transform = CATransform3DIdentity
            self?.isSwipeAnimating = false
            self?.removeSwipePreview()
        }
        layer.add(spring, forKey: "springBounce")
        CATransaction.commit()
    }

    // MARK: - Swipe Preview

    private func adjacentWorkspace(for direction: SwipeDirection) -> Workspace? {
        // Swipe only between workspaces, not to/from settings
        if model.state.isSettingsSelected { return nil }
        let workspaces = model.workspaces
        guard let currentIndex = workspaces.firstIndex(where: { $0.id == model.currentWorkspace.id }) else { return nil }
        switch direction {
        case .right:
            return currentIndex > 0 ? workspaces[currentIndex - 1] : nil
        case .left:
            return currentIndex < workspaces.count - 1 ? workspaces[currentIndex + 1] : nil
        }
    }

    /// Captures a bitmap snapshot of the adjacent workspace's content by temporarily
    /// switching the model and rendering the content views (without animations).
    private func capturePreviewSnapshot(for direction: SwipeDirection) {
        swipePreviewSnapshot = nil
        swipePreviewDirection = direction

        guard let nextWorkspace = adjacentWorkspace(for: direction) else { return }

        let currentId = model.currentWorkspace.id

        // Suppress onChange to prevent external UI updates
        let savedOnChange = model.onChange
        model.onChange = nil

        // Switch to the adjacent workspace and update views without animation
        model.selectWorkspace(id: nextWorkspace.id)
        pinnedTabsView.update(pinnedLinks: nextWorkspace.pinnedLinks)
        let filteredNodes = searchCoordinator.filter(nodes: nextWorkspace.items)
        nodeListViewController.reloadData(with: filteredNodes, forceExpand: false, animated: false)

        // Force layout so the views render with new data
        workspaceContentStack.layoutSubtreeIfNeeded()

        // Capture bitmap
        let bounds = workspaceContentStack.bounds
        if let bitmap = workspaceContentStack.bitmapImageRepForCachingDisplay(in: bounds) {
            workspaceContentStack.cacheDisplay(in: bounds, to: bitmap)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(bitmap)
            swipePreviewSnapshot = image
        }

        // Restore original workspace and content without animation
        model.selectWorkspace(id: currentId)
        let currentWorkspace = model.currentWorkspace
        pinnedTabsView.update(pinnedLinks: currentWorkspace.pinnedLinks)
        let currentNodes = searchCoordinator.filter(nodes: currentWorkspace.items)
        nodeListViewController.reloadData(with: currentNodes, forceExpand: searchCoordinator.isSearchActive, animated: false)
        workspaceContentStack.layoutSubtreeIfNeeded()

        // Restore onChange
        model.onChange = savedOnChange
    }

    private func updateSwipePreview(translationX: CGFloat, direction: SwipeDirection) {
        let containerWidth = swipeClipContainer.bounds.width
        let containerHeight = swipeClipContainer.bounds.height

        // Use the CURRENT workspace's background color so the preview blends seamlessly
        let currentBgColor: NSColor
        if model.state.isSettingsSelected {
            currentBgColor = ThemeConstants.Colors.settingsBackground
        } else {
            currentBgColor = model.currentWorkspace.colorId.backgroundColor
        }

        if swipePreviewView == nil {
            let preview = NSView()
            preview.wantsLayer = true
            swipeClipContainer.addSubview(preview, positioned: .below, relativeTo: workspaceContentStack)
            swipePreviewView = preview
        }

        guard let preview = swipePreviewView else { return }

        // Same background as current workspace — color change happens via fade after switch
        preview.layer?.backgroundColor = currentBgColor.cgColor

        // Position preview adjacent to the sliding content
        if translationX > 0 {
            preview.frame = NSRect(x: translationX - containerWidth, y: 0, width: containerWidth, height: containerHeight)
        } else {
            preview.frame = NSRect(x: containerWidth + translationX, y: 0, width: containerWidth, height: containerHeight)
        }

        // Add or update the content snapshot image view
        let imageView: NSImageView
        if let existing = preview.subviews.first(where: { $0 is NSImageView }) as? NSImageView {
            imageView = existing
        } else {
            imageView = NSImageView()
            imageView.imageScaling = .scaleNone
            imageView.imageAlignment = .alignTopLeft
            preview.addSubview(imageView)
        }
        imageView.image = swipePreviewSnapshot
        imageView.frame = NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
    }

    private func removeSwipePreview() {
        swipePreviewView?.removeFromSuperview()
        swipePreviewView = nil
        swipePreviewSnapshot = nil
        swipePreviewDirection = nil
    }
}
