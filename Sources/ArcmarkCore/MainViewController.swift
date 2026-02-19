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

    // State
    private var isReloadScheduled = false
    private var hasLoaded = false
    private var lastWorkspaceId: UUID?
    private var pendingWorkspaceRenameId: UUID?

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

        let stack = NSStackView(views: [topBar, searchField, pinnedTabsView, nodeListViewController.view, bottomBar])
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

            bottomBar.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

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
            pinnedTabsView.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 2),
            pinnedTabsView.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -2),
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
            nodeListViewController.reloadData(with: filteredNodes, forceExpand: forceExpand)
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
        view.layer?.backgroundColor = model.currentWorkspace.colorId.backgroundColor.cgColor
        view.window?.backgroundColor = model.currentWorkspace.colorId.backgroundColor
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
        view.layer?.backgroundColor = settingsColor.cgColor
        view.window?.backgroundColor = settingsColor
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
        BrowserManager.open(url: url)
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
