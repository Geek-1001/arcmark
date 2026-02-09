import AppKit

@MainActor
final class MainViewController: NSViewController {
    let model: AppModel

    private let workspaceSwitcher = WorkspaceSwitcherView(style: .defaultStyle)
    private let searchField = SearchBarView(style: .defaultSearch)
    private let pasteButton = IconTitleButton(
        title: "Add links from clipboard",
        symbolName: "plus",
        style: .pasteAction
    )
    private let collectionView = ContextMenuCollectionView()
    private let scrollView = NSScrollView()
    private let contextMenu = NSMenu()
    private let listMetrics = ListMetrics()
    private let dropIndicator = DropIndicatorView()
    private let settingsViewController = SettingsContentViewController()

    private var filteredItems: [Node] = []
    private var visibleRows: [NodeListRow] = []
    private var currentQuery: String = ""
    private var contextNodeId: UUID?
    private var contextIndexPath: IndexPath?
    private var isReloadScheduled = false
    private var isDraggingItems = false
    private var hasLoaded = false
    private var pendingInsertedIds: Set<UUID> = []
    private let rowAnimationDuration: TimeInterval = 0.16
    private let rowAnimationOffset: CGFloat = 10
    private weak var inlineRenameItem: NodeCollectionViewItem?
    private var inlineRenameNodeId: UUID?
    private var pendingInlineRenameId: UUID?
    private var pendingWorkspaceRenameId: UUID?
    private var suppressNextSelection = false
    fileprivate var selectedNodeIds: Set<UUID> = []
    private var lastWorkspaceId: UUID?
    fileprivate var isBulkContextMenu = false

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
        setupUI()
        bindModel()
        reloadData()
    }

    private func setupUI() {
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

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = "Search in workspace"
        searchField.onTextChange = { [weak self] text in
            self?.clearSelections()
            self?.currentQuery = text
            self?.reloadData()
        }

        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        pasteButton.target = self
        pasteButton.action = #selector(pasteLink)

        collectionView.translatesAutoresizingMaskIntoConstraints = true
        collectionView.autoresizingMask = [.width, .height]
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.wantsLayer = true
        collectionView.backgroundColors = [.clear]
        collectionView.collectionViewLayout = makeCollectionLayout()
        collectionView.register(NodeCollectionViewItem.self, forItemWithIdentifier: NodeCollectionViewItem.identifier)
        collectionView.registerForDraggedTypes([nodePasteboardType])
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.onContextRequest = { [weak self] indexPath in
            self?.contextIndexPath = indexPath
        }
        collectionView.onDragExit = { [weak self] in
            self?.hideDropIndicator()
        }
        collectionView.onBackgroundClick = { [weak self] in
            self?.clearSelections()
        }
        dropIndicator.isHidden = true
        collectionView.addSubview(dropIndicator)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        collectionView.frame = scrollView.bounds
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        contextMenu.delegate = self
        collectionView.menu = contextMenu

        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(workspaceSwitcher)

        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(pasteButton)

        let stack = NSStackView(views: [topBar, searchField, scrollView, bottomBar])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alignment = .centerX

        // Setup settings view (initially hidden)
        addChild(settingsViewController)
        settingsViewController.view.translatesAutoresizingMaskIntoConstraints = false
        settingsViewController.view.isHidden = true

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
            searchField.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -2)
        ])

        // Settings view constraints (positioned to replace workspace content area)
        NSLayoutConstraint.activate([
            settingsViewController.view.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            settingsViewController.view.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            settingsViewController.view.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            settingsViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -LayoutConstants.windowPadding)
        ])

        // Background click handling is done in ContextMenuCollectionView.mouseDown
    }

    private func makeCollectionLayout() -> NSCollectionViewLayout {
        ListFlowLayout(metrics: listMetrics)
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

    private func reloadData() {
        if inlineRenameNodeId != nil, inlineRenameItem == nil {
            clearInlineRenameState()
        }
        reloadWorkspaceMenu()

        // Clear selections when workspace changes
        let currentWorkspaceId = model.currentWorkspace.id
        if hasLoaded && currentWorkspaceId != lastWorkspaceId {
            clearSelections()
            lastWorkspaceId = currentWorkspaceId
        }

        // Check if settings is selected
        if model.state.isSettingsSelected {
            clearSelections()
            showSettingsContent()
        } else {
            showWorkspaceContent()
            applyWorkspaceStyling()
            applyFilter()
            let forceExpand = !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let newRows = buildVisibleRows(nodes: filteredItems, depth: 0, forceExpand: forceExpand)
            applyVisibleRows(newRows)
            handlePendingInlineRename()
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
            // Use settings background color for overscroll shadow
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
        pasteButton.isHidden = true
        scrollView.isHidden = true

        // Show settings content
        settingsViewController.view.isHidden = false

        // Apply settings background color
        let settingsColor = NSColor(calibratedRed: 0.898, green: 0.906, blue: 0.922, alpha: 1.0) // #E5E7EB
        view.layer?.backgroundColor = settingsColor.cgColor
        view.window?.backgroundColor = settingsColor
    }

    private func showWorkspaceContent() {
        // Show workspace content
        searchField.isHidden = false
        pasteButton.isHidden = false
        scrollView.isHidden = false

        // Hide settings content
        settingsViewController.view.isHidden = true
    }

    private func applyFilter() {
        let query = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredItems = model.currentWorkspace.items
        } else {
            filteredItems = NodeFiltering.filter(nodes: model.currentWorkspace.items, query: query)
        }
    }

    private func buildVisibleRows(nodes: [Node], depth: Int, forceExpand: Bool) -> [NodeListRow] {
        var rows: [NodeListRow] = []
        for node in nodes {
            rows.append(NodeListRow(node: node, depth: depth))
            if case .folder(let folder) = node, folder.isExpanded || forceExpand {
                rows.append(contentsOf: buildVisibleRows(nodes: folder.children, depth: depth + 1, forceExpand: forceExpand))
            }
        }
        return rows
    }

    private func applyVisibleRows(_ newRows: [NodeListRow]) {
        let queryActive = !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasLoaded || queryActive || collectionView.window == nil {
            visibleRows = newRows
            collectionView.reloadData()
            return
        }

        let oldRows = visibleRows
        let oldIds = oldRows.map { $0.id }
        let newIds = newRows.map { $0.id }
        let oldSet = Set(oldIds)
        let newSet = Set(newIds)

        if oldSet == newSet {
            visibleRows = newRows
            collectionView.reloadData()
            return
        }

        var deletedIndexPaths: [IndexPath] = []
        for (index, row) in oldRows.enumerated() where !newSet.contains(row.id) {
            deletedIndexPaths.append(IndexPath(item: index, section: 0))
        }

        var insertedIndexPaths: [IndexPath] = []
        for (index, row) in newRows.enumerated() where !oldSet.contains(row.id) {
            insertedIndexPaths.append(IndexPath(item: index, section: 0))
        }

        let deletionSnapshots = makeDeletionSnapshots(for: deletedIndexPaths)

        performListUpdates(
            newRows: newRows,
            insertedIndexPaths: insertedIndexPaths,
            deletedIndexPaths: deletedIndexPaths
        )
        animateDeletionSnapshots(deletionSnapshots)
    }

    private func performListUpdates(newRows: [NodeListRow],
                                    insertedIndexPaths: [IndexPath],
                                    deletedIndexPaths: [IndexPath]) {
        pendingInsertedIds = Set(insertedIndexPaths.compactMap { indexPath in
            guard indexPath.item < newRows.count else { return nil }
            return newRows[indexPath.item].id
        })
        visibleRows = newRows
        collectionView.performBatchUpdates({
            if !deletedIndexPaths.isEmpty {
                collectionView.deleteItems(at: Set(deletedIndexPaths))
            }
            if !insertedIndexPaths.isEmpty {
                collectionView.insertItems(at: Set(insertedIndexPaths))
            }
        }, completionHandler: nil)
    }

    @objc private func handleScrollBoundsChanged() {
        for item in collectionView.visibleItems() {
            (item as? NodeCollectionViewItem)?.refreshHoverState()
        }
    }

    fileprivate func row(at indexPath: IndexPath) -> NodeListRow? {
        guard indexPath.item >= 0, indexPath.item < visibleRows.count else { return nil }
        return visibleRows[indexPath.item]
    }

    private func showDropIndicator(at indexPath: IndexPath, operation: NSCollectionView.DropOperation) {
        switch operation {
        case .on:
            guard let frame = frameForItem(at: indexPath) else {
                hideDropIndicator()
                return
            }
            dropIndicator.showHighlight(in: frame.insetBy(dx: 2, dy: 2))
        case .before:
            guard let frame = insertionLineFrame(for: indexPath) else {
                hideDropIndicator()
                return
            }
            dropIndicator.showLine(in: frame)
        default:
            hideDropIndicator()
        }
    }

    private func hideDropIndicator() {
        dropIndicator.hide()
    }

    private func frameForItem(at indexPath: IndexPath) -> NSRect? {
        collectionView.layoutAttributesForItem(at: indexPath)?.frame
    }

    private func insertionLineFrame(for indexPath: IndexPath) -> NSRect? {
        let lineHeight: CGFloat = 2
        var depth = 0
        var y: CGFloat = listMetrics.verticalGap / 2

        if indexPath.item < visibleRows.count,
           let frame = frameForItem(at: indexPath) {
            depth = visibleRows[indexPath.item].depth
            y = frame.minY - listMetrics.verticalGap / 2
        } else if let lastIndex = visibleRows.indices.last,
                  let frame = frameForItem(at: IndexPath(item: lastIndex, section: 0)) {
            depth = 0
            y = frame.maxY + listMetrics.verticalGap / 2
        }

        let x = listMetrics.leftPadding + CGFloat(depth) * listMetrics.indentWidth
        let width = max(8, collectionView.bounds.width - x - listMetrics.leftPadding)
        return NSRect(x: x, y: y - lineHeight / 2, width: width, height: lineHeight)
    }

    private func animateInsert(item: NSCollectionViewItem) {
        let view = item.view
        view.wantsLayer = true
        let finalOrigin = view.frame.origin
        view.alphaValue = 0
        view.frame.origin = NSPoint(x: finalOrigin.x, y: finalOrigin.y - rowAnimationOffset)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = rowAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            view.animator().setFrameOrigin(finalOrigin)
            view.animator().alphaValue = 1
        }
    }

    private func makeDeletionSnapshots(for indexPaths: [IndexPath]) -> [NSImageView] {
        var snapshots: [NSImageView] = []
        for indexPath in indexPaths {
            guard let item = collectionView.item(at: indexPath) else { continue }
            let view = item.view
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(rep)
            let frame = view.convert(view.bounds, to: collectionView)
            let imageView = NSImageView(frame: frame)
            imageView.image = image
            imageView.imageScaling = .scaleAxesIndependently
            collectionView.addSubview(imageView)
            view.alphaValue = 0
            snapshots.append(imageView)
        }
        return snapshots
    }

    private func animateDeletionSnapshots(_ snapshots: [NSImageView]) {
        guard !snapshots.isEmpty else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = rowAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            for snapshot in snapshots {
                let finalOrigin = NSPoint(x: snapshot.frame.origin.x, y: snapshot.frame.origin.y - rowAnimationOffset)
                snapshot.animator().setFrameOrigin(finalOrigin)
                snapshot.animator().alphaValue = 0
            }
        } completionHandler: {
            DispatchQueue.main.async {
                for snapshot in snapshots {
                    snapshot.removeFromSuperview()
                }
            }
        }
    }

    private func shouldDropOnItem(at indexPath: IndexPath, draggingInfo: NSDraggingInfo) -> Bool {
        let location = collectionView.convert(draggingInfo.draggingLocation, from: nil)
        guard let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else {
            return true
        }
        let upper = frame.minY + frame.height * 0.25
        let lower = frame.maxY - frame.height * 0.25
        return location.y >= upper && location.y <= lower
    }

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

    @objc private func createWorkspaceFromMenu() {
        promptCreateWorkspace()
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

    func createFolderAndBeginRename(parentId: UUID?) {
        if let parentId {
            model.setFolderExpanded(id: parentId, isExpanded: true)
        }
        let newId = model.addFolder(name: "Untitled", parentId: parentId)
        scheduleInlineRename(for: newId)
    }

    private func promptRenameNode(id: UUID, currentName: String) {
        guard let newName = promptForText(title: "Rename", message: "Enter a new name.", defaultValue: currentName) else { return }
        model.renameNode(id: id, newName: newName)
    }

    private func beginInlineRename(nodeId: UUID, indexPath: IndexPath) {
        cancelInlineRename()
        guard model.nodeById(nodeId) != nil,
              let item = collectionView.item(at: indexPath) as? NodeCollectionViewItem else {
            clearInlineRenameState()
            return
        }

        inlineRenameNodeId = nodeId
        inlineRenameItem = item
        item.beginInlineRename(onCommit: { [weak self] newName in
            self?.commitInlineRename(newName)
        }, onCancel: { [weak self] in
            self?.handleInlineRenameCancelled()
        })
    }

    private func commitInlineRename(_ newName: String) {
        guard let nodeId = inlineRenameNodeId else {
            clearInlineRenameState()
            return
        }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            handleInlineRenameCancelled()
            return
        }
        model.renameNode(id: nodeId, newName: trimmed)
        clearInlineRenameState()
    }

    private func handleInlineRenameCancelled() {
        suppressNextSelection = true
        clearInlineRenameState()
    }

    private func cancelInlineRename() {
        if let item = inlineRenameItem {
            item.cancelInlineRename()
        } else {
            clearInlineRenameState()
        }
    }

    private func clearInlineRenameState() {
        inlineRenameItem = nil
        inlineRenameNodeId = nil
    }

    private func scheduleInlineRename(for nodeId: UUID) {
        pendingInlineRenameId = nodeId
    }

    private func toggleSelection(for nodeId: UUID) {
        if selectedNodeIds.contains(nodeId) {
            selectedNodeIds.remove(nodeId)
        } else {
            selectedNodeIds.insert(nodeId)
        }
        reloadVisibleSelection()
    }

    private func clearSelections() {
        guard !selectedNodeIds.isEmpty else { return }
        selectedNodeIds.removeAll()
        reloadVisibleSelection()
    }

    private func reloadVisibleSelection() {
        for (index, _) in visibleRows.enumerated() {
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.reloadItems(at: [indexPath])
        }
    }


    private func handlePendingInlineRename() {
        guard let nodeId = pendingInlineRenameId else { return }
        guard let index = visibleRows.firstIndex(where: { $0.id == nodeId }) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        pendingInlineRenameId = nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
            if self.collectionView.item(at: indexPath) is NodeCollectionViewItem {
                self.beginInlineRename(nodeId: nodeId, indexPath: indexPath)
            } else {
                self.pendingInlineRenameId = nodeId
            }
        }
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

    private func promptForText(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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

    private func toggleFolder(_ folder: Folder) {
        if !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        model.setFolderExpanded(id: folder.id, isExpanded: !folder.isExpanded)
    }
}

extension MainViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleRows.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NodeCollectionViewItem.identifier, for: indexPath)
        guard let nodeItem = item as? NodeCollectionViewItem else { return item }
        guard let row = row(at: indexPath) else { return item }

        let isSelected = selectedNodeIds.contains(row.node.id)

        switch row.node {
        case .folder(let folder):
            let icon = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            icon?.isTemplate = true
            nodeItem.configure(
                title: folder.name,
                icon: icon,
                titleFont: listMetrics.folderTitleFont,
                depth: row.depth,
                metrics: listMetrics,
                showDelete: false,
                onDelete: nil,
                isSelected: isSelected
            )
        case .link(let link):
            let globeIconConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            let placeholder = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?.withSymbolConfiguration(globeIconConfig)
            placeholder?.isTemplate = true
            var iconToUse = placeholder
            var shouldFetch = true
            if let path = link.faviconPath,
               FileManager.default.fileExists(atPath: path),
               let image = NSImage(contentsOfFile: path) {
                image.isTemplate = false
                iconToUse = image
                shouldFetch = false
            }

            nodeItem.configure(
                title: link.title,
                icon: iconToUse,
                titleFont: listMetrics.linkTitleFont,
                depth: row.depth,
                metrics: listMetrics,
                showDelete: true,
                onDelete: { [weak self] in
                    self?.model.deleteNode(id: link.id)
                    self?.clearSelections()
                },
                isSelected: isSelected
            )

            if shouldFetch, let url = URL(string: link.url) {
                FaviconService.shared.favicon(for: url, cachedPath: link.faviconPath) { [weak self] _, path in
                    guard let self else { return }
                    if let path {
                        self.model.updateLinkFaviconPath(id: link.id, path: path)
                    }
                }
            }
        }

        return nodeItem
    }

    func collectionView(_ collectionView: NSCollectionView,
                        willDisplay item: NSCollectionViewItem,
                        forRepresentedObjectAt indexPath: IndexPath) {
        guard let row = row(at: indexPath) else { return }
        if pendingInsertedIds.remove(row.id) != nil {
            animateInsert(item: item)
        } else {
            item.view.alphaValue = 1
        }
    }

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        guard currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        guard selectedNodeIds.isEmpty else {
            return false
        }

        return true
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first, let row = row(at: indexPath) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isDraggingItems { return }
            if self.suppressNextSelection {
                self.suppressNextSelection = false
                self.collectionView.deselectItems(at: indexPaths)
                return
            }
            if self.inlineRenameNodeId != nil {
                self.collectionView.deselectItems(at: indexPaths)
                return
            }
            if !self.collectionView.selectionIndexPaths.contains(indexPath) { return }

            // Check for Cmd key modifier for multi-selection
            if NSEvent.modifierFlags.contains(.command) {
                self.toggleSelection(for: row.node.id)
                self.collectionView.deselectItems(at: indexPaths)
                return
            }

            // Clear selections on regular click
            if !self.selectedNodeIds.isEmpty {
                self.clearSelections()
            }

            switch row.node {
            case .folder(let folder):
                self.toggleFolder(folder)
            case .link(let link):
                self.openLink(link)
            }

            self.collectionView.deselectItems(at: indexPaths)
        }
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard let row = row(at: indexPath) else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(row.node.id.uuidString, forType: nodePasteboardType)
        return pasteboardItem
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        willBeginAt screenPoint: NSPoint,
                        forItemsAt indexPaths: Set<IndexPath>) {
        isDraggingItems = true
    }

    func collectionView(_ collectionView: NSCollectionView,
                        draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint,
                        dragOperation operation: NSDragOperation) {
        isDraggingItems = false
        hideDropIndicator()
    }

    func collectionView(_ collectionView: NSCollectionView,
                        validateDrop draggingInfo: NSDraggingInfo,
                        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        if !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hideDropIndicator()
            return []
        }

        let indexPath = proposedDropIndexPath.pointee as IndexPath
        if indexPath.item < visibleRows.count,
           let row = row(at: indexPath),
           case .folder = row.node,
           shouldDropOnItem(at: indexPath, draggingInfo: draggingInfo) {
            proposedDropOperation.pointee = .on
        } else {
            proposedDropOperation.pointee = .before
        }

        showDropIndicator(at: indexPath, operation: proposedDropOperation.pointee)

        return .move
    }

    func collectionView(_ collectionView: NSCollectionView,
                        acceptDrop draggingInfo: NSDraggingInfo,
                        indexPath: IndexPath,
                        dropOperation: NSCollectionView.DropOperation) -> Bool {
        hideDropIndicator()
        guard let idString = draggingInfo.draggingPasteboard.string(forType: nodePasteboardType),
              let nodeId = UUID(uuidString: idString) else { return false }

        var targetParentId: UUID?
        var targetIndex: Int

        if indexPath.item < visibleRows.count, let row = row(at: indexPath) {
            switch row.node {
            case .folder(let folder):
                if dropOperation == .on {
                    targetParentId = folder.id
                    targetIndex = folder.children.count
                } else if let location = model.location(of: folder.id) {
                    targetParentId = location.parentId
                    targetIndex = location.index
                } else {
                    targetParentId = nil
                    targetIndex = model.currentWorkspace.items.count
                }
            case .link(let link):
                if let location = model.location(of: link.id) {
                    targetParentId = location.parentId
                    targetIndex = location.index
                } else {
                    targetParentId = nil
                    targetIndex = model.currentWorkspace.items.count
                }
            }
        } else {
            targetParentId = nil
            targetIndex = model.currentWorkspace.items.count
        }

        if targetIndex < 0 { targetIndex = model.currentWorkspace.items.count }
        model.moveNode(id: nodeId, toParentId: targetParentId, index: targetIndex)
        return true
    }
}

extension MainViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Check for bulk selection context menu
        if isBulkContextMenu && selectedNodeIds.count > 0 {
            populateBulkContextMenu(menu)
            return
        }

        guard let indexPath = contextIndexPath,
              let row = row(at: indexPath) else {
            contextNodeId = nil
            let newFolder = NSMenuItem(title: "New Folder…", action: #selector(contextNewFolder), keyEquivalent: "")
            newFolder.target = self
            menu.addItem(newFolder)
            return
        }

        let node = row.node
        contextNodeId = node.id

        switch node {
        case .folder:
            let newNested = NSMenuItem(title: "New Nested Folder…", action: #selector(contextNewNestedFolder), keyEquivalent: "")
            newNested.target = self
            menu.addItem(newNested)

            let rename = NSMenuItem(title: "Rename…", action: #selector(contextRename), keyEquivalent: "")
            rename.target = self
            menu.addItem(rename)

            let delete = NSMenuItem(title: "Delete", action: #selector(contextDelete), keyEquivalent: "")
            delete.target = self
            menu.addItem(delete)
        case .link:
            let rename = NSMenuItem(title: "Rename…", action: #selector(contextRename), keyEquivalent: "")
            rename.target = self
            menu.addItem(rename)

            let moveMenu = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for workspace in model.workspaces where workspace.id != model.currentWorkspace.id {
                let item = NSMenuItem(title: workspace.name, action: #selector(contextMoveToWorkspace), keyEquivalent: "")
                item.target = self
                item.representedObject = workspace.id
                submenu.addItem(item)
            }
            moveMenu.submenu = submenu
            menu.addItem(moveMenu)

            let delete = NSMenuItem(title: "Delete", action: #selector(contextDelete), keyEquivalent: "")
            delete.target = self
            menu.addItem(delete)
        }
    }

    @objc private func contextNewFolder() {
        createFolderAndBeginRename(parentId: nil)
    }

    @objc private func contextNewNestedFolder() {
        guard let nodeId = contextNodeId else { return }
        createFolderAndBeginRename(parentId: nodeId)
    }

    @objc private func contextRename() {
        guard let indexPath = contextIndexPath,
              let row = row(at: indexPath) else { return }
        beginInlineRename(nodeId: row.id, indexPath: indexPath)
    }

    @objc private func contextDelete() {
        guard let nodeId = contextNodeId else { return }
        model.deleteNode(id: nodeId)
    }

    @objc private func contextMoveToWorkspace(_ sender: NSMenuItem) {
        guard let nodeId = contextNodeId,
              let workspaceId = sender.representedObject as? UUID else { return }
        model.moveNodeToWorkspace(id: nodeId, workspaceId: workspaceId)
    }

    private func populateBulkContextMenu(_ menu: NSMenu) {
        let count = selectedNodeIds.count

        // 1. Move to Workspace submenu
        let moveItem = NSMenuItem(title: "Move to…", action: nil, keyEquivalent: "")
        let moveSubmenu = NSMenu()
        for workspace in model.state.workspaces where workspace.id != model.currentWorkspace.id {
            let item = NSMenuItem(title: workspace.name, action: #selector(bulkMoveToWorkspace), keyEquivalent: "")
            item.target = self
            item.representedObject = workspace.id
            moveSubmenu.addItem(item)
        }
        moveItem.submenu = moveSubmenu
        menu.addItem(moveItem)

        // 2. Group in New Folder
        let groupItem = NSMenuItem(title: "Group in New Folder", action: #selector(bulkGroupInFolder), keyEquivalent: "")
        groupItem.target = self
        menu.addItem(groupItem)

        // 3. Copy Links (only if there are links)
        let nodes = selectedNodeIds.compactMap { id in
            model.findNode(id: id, in: model.currentWorkspace.items)
        }
        let linkCount = nodes.filter { node in
            if case .link = node { return true }
            return false
        }.count

        if linkCount > 0 {
            let copyItem = NSMenuItem(title: "Copy \(linkCount) Link\(linkCount > 1 ? "s" : "")", action: #selector(bulkCopyLinks), keyEquivalent: "")
            copyItem.target = self
            menu.addItem(copyItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 4. Delete All
        let deleteItem = NSMenuItem(title: "Delete \(count) Item\(count > 1 ? "s" : "")…", action: #selector(bulkDelete), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
    }

    @objc private func bulkMoveToWorkspace(_ sender: NSMenuItem) {
        guard let workspaceId = sender.representedObject as? UUID else { return }
        let nodeIds = Array(selectedNodeIds)
        model.moveNodesToWorkspace(nodeIds: nodeIds, toWorkspaceId: workspaceId)
        clearSelections()
    }

    @objc private func bulkGroupInFolder() {
        let nodeIds = Array(selectedNodeIds)
        guard !nodeIds.isEmpty else { return }

        let folderId = model.groupNodesInNewFolder(nodeIds: nodeIds, folderName: "Untitled")
        clearSelections()

        if let folderId = folderId {
            scheduleInlineRename(for: folderId)
        }
    }

    @objc private func bulkCopyLinks() {
        let nodes = selectedNodeIds.compactMap { id in
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

        clearSelections()
    }

    @objc private func bulkDelete() {
        let count = selectedNodeIds.count
        guard count > 0 else { return }

        let alert = NSAlert()
        alert.messageText = "Delete \(count) Item\(count > 1 ? "s" : "")"
        alert.informativeText = "This action cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            for nodeId in selectedNodeIds {
                model.deleteNode(id: nodeId)
            }
            clearSelections()
        }
    }
}


private struct NodeListRow {
    let node: Node
    let depth: Int

    var id: UUID {
        node.id
    }
}

private final class DropIndicatorView: NSView {
    private let lineThickness: CGFloat = 2
    private let highlightCornerRadius: CGFloat = 8
    private let accentColor = NSColor.controlAccentColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        isHidden = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = true
        isHidden = true
    }

    func showLine(in frame: NSRect) {
        isHidden = false
        self.frame = frame
        layer?.cornerRadius = lineThickness / 2
        layer?.backgroundColor = accentColor.cgColor
        layer?.borderWidth = 0
    }

    func showHighlight(in frame: NSRect) {
        isHidden = false
        self.frame = frame
        layer?.cornerRadius = highlightCornerRadius
        layer?.backgroundColor = accentColor.withAlphaComponent(0.12).cgColor
        layer?.borderColor = accentColor.cgColor
        layer?.borderWidth = 2
    }

    func hide() {
        isHidden = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}


private final class ContextMenuCollectionView: NSCollectionView {
    var onContextRequest: ((IndexPath?) -> Void)?
    var onDragExit: (() -> Void)?
    var onBackgroundClick: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: location)

        // If clicking on empty space, notify the callback
        if indexPath == nil {
            onBackgroundClick?()
        }

        // Always call super to allow normal click handling
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: location)

        // Check if clicked item is in selection for bulk context menu
        if let mainVC = delegate as? MainViewController {
            if let indexPath = indexPath,
               let row = mainVC.row(at: indexPath),
               mainVC.selectedNodeIds.contains(row.node.id),
               mainVC.selectedNodeIds.count > 0 {
                mainVC.isBulkContextMenu = true
            } else {
                mainVC.isBulkContextMenu = false
            }
        }

        onContextRequest?(indexPath)
        return menu
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        onDragExit?()
    }
}
