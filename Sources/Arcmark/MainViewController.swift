import AppKit

final class MainViewController: NSViewController {
    private let model: AppModel

    private let workspacePopup = NSPopUpButton()
    private let workspaceActionsButton = NSButton()
    private let searchField = NSSearchField()
    private let urlField = NSTextField()
    private let addButton = NSButton(title: "Add", target: nil, action: nil)
    private let pasteButton = NSButton(title: "Paste", target: nil, action: nil)
    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let contextMenu = NSMenu()

    private var filteredItems: [Node] = []
    private var currentQuery: String = ""
    private var contextNodeId: UUID?
    private var isRestoringExpansion = false
    private var isReloadScheduled = false

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        workspacePopup.translatesAutoresizingMaskIntoConstraints = false
        workspacePopup.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        workspacePopup.bezelStyle = .texturedRounded
        workspacePopup.target = self
        workspacePopup.action = #selector(workspaceChanged)

        workspaceActionsButton.translatesAutoresizingMaskIntoConstraints = false
        workspaceActionsButton.bezelStyle = .texturedRounded
        workspaceActionsButton.isBordered = false
        workspaceActionsButton.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
        workspaceActionsButton.contentTintColor = NSColor.labelColor.withAlphaComponent(0.7)
        workspaceActionsButton.target = self
        workspaceActionsButton.action = #selector(showWorkspaceActionsMenu)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search in workspace"
        searchField.delegate = self

        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.placeholderString = "Paste or type a URL"
        urlField.delegate = self
        urlField.target = self
        urlField.action = #selector(addLinkFromField)

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addLinkFromField)

        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        pasteButton.bezelStyle = .rounded
        pasteButton.target = self
        pasteButton.action = #selector(pasteLink)

        outlineView.translatesAutoresizingMaskIntoConstraints = true
        outlineView.autoresizingMask = [.width, .height]
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.rowHeight = 40
        outlineView.intercellSpacing = NSSize(width: 0, height: 8)
        outlineView.floatsGroupRows = false
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.style = .sourceList
        outlineView.backgroundColor = .clear
        outlineView.indentationPerLevel = 14
        outlineView.doubleAction = #selector(handleDoubleClick)
        outlineView.registerForDraggedTypes([nodePasteboardType])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        outlineView.frame = scrollView.bounds

        contextMenu.delegate = self
        outlineView.menu = contextMenu

        let topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(workspacePopup)
        topBar.addSubview(workspaceActionsButton)

        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(urlField)
        bottomBar.addSubview(addButton)
        bottomBar.addSubview(pasteButton)

        let stack = NSStackView(views: [topBar, searchField, scrollView, bottomBar])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            workspacePopup.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            workspacePopup.trailingAnchor.constraint(equalTo: workspaceActionsButton.leadingAnchor, constant: -6),
            workspacePopup.topAnchor.constraint(equalTo: topBar.topAnchor),
            workspacePopup.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),

            workspaceActionsButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            workspaceActionsButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            workspaceActionsButton.widthAnchor.constraint(equalToConstant: 20),
            workspaceActionsButton.heightAnchor.constraint(equalToConstant: 20),

            urlField.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            urlField.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            addButton.leadingAnchor.constraint(equalTo: urlField.trailingAnchor, constant: 8),
            addButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            pasteButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 8),
            pasteButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
            pasteButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            urlField.heightAnchor.constraint(equalToConstant: 26),

            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            topBar.heightAnchor.constraint(equalToConstant: 30),
            bottomBar.heightAnchor.constraint(equalToConstant: 36)
        ])

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 4),
            searchField.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -4)
        ])
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
        reloadWorkspaceMenu()
        applyWorkspaceStyling()
        applyFilter()
        outlineView.reloadData()
        isRestoringExpansion = true
        expandPersistedFolders()
        isRestoringExpansion = false
    }

    private func reloadWorkspaceMenu() {
        workspacePopup.removeAllItems()
        let menu = NSMenu()
        let workspaces = model.workspaces
        let selectedId = model.currentWorkspace.id

        for workspace in workspaces {
            let item = NSMenuItem(title: "\(workspace.emoji) \(workspace.name)", action: nil, keyEquivalent: "")
            item.representedObject = workspace.id
            menu.addItem(item)
        }

        workspacePopup.menu = menu
        if let index = workspaces.firstIndex(where: { $0.id == selectedId }) {
            workspacePopup.selectItem(at: index)
        }

        updateWorkspaceActionsMenu(canDelete: workspaces.count > 1)
    }

    private func updateWorkspaceActionsMenu(canDelete: Bool) {
        let menu = NSMenu()
        let newItem = NSMenuItem(title: "New Workspace…", action: #selector(createWorkspaceFromMenu), keyEquivalent: "")
        newItem.target = self
        menu.addItem(newItem)

        let renameItem = NSMenuItem(title: "Rename Workspace…", action: #selector(renameWorkspaceFromMenu), keyEquivalent: "")
        renameItem.target = self
        menu.addItem(renameItem)

        let emojiItem = NSMenuItem(title: "Change Emoji…", action: #selector(changeEmojiFromMenu), keyEquivalent: "")
        emojiItem.target = self
        menu.addItem(emojiItem)

        let colorItem = NSMenuItem(title: "Change Color…", action: #selector(changeColorFromMenu), keyEquivalent: "")
        colorItem.target = self
        menu.addItem(colorItem)

        let deleteItem = NSMenuItem(title: "Delete Workspace…", action: #selector(deleteWorkspaceFromMenu), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.isEnabled = canDelete
        menu.addItem(deleteItem)

        workspaceActionsButton.menu = menu
    }

    private func applyWorkspaceStyling() {
        view.layer?.backgroundColor = model.currentWorkspace.colorId.backgroundColor.cgColor
        view.window?.backgroundColor = model.currentWorkspace.colorId.backgroundColor
    }

    private func applyFilter() {
        let query = currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredItems = model.currentWorkspace.items
        } else {
            filteredItems = NodeFiltering.filter(nodes: model.currentWorkspace.items, query: query)
        }
    }

    private func expandPersistedFolders() {
        let forceExpand = !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        expandFolders(filteredItems, force: forceExpand)
    }


    private func expandFolders(_ nodes: [Node], force: Bool) {
        for node in nodes {
            switch node {
            case .folder(let folder):
                if folder.isExpanded || force {
                    outlineView.expandItem(node)
                }
                expandFolders(folder.children, force: force)
            case .link:
                break
            }
        }
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

    @objc private func workspaceChanged() {
        guard let item = workspacePopup.selectedItem else { return }
        if let workspaceId = item.representedObject as? UUID {
            model.selectWorkspace(id: workspaceId)
        } else {
            workspacePopup.selectItem(at: model.workspaces.firstIndex(where: { $0.id == model.currentWorkspace.id }) ?? 0)
        }
    }

    @objc private func createWorkspaceFromMenu() {
        promptCreateWorkspace()
    }

    @objc private func showWorkspaceActionsMenu() {
        guard let menu = workspaceActionsButton.menu else { return }
        let location = NSPoint(x: workspaceActionsButton.bounds.midX, y: workspaceActionsButton.bounds.minY - 6)
        menu.popUp(positioning: nil, at: location, in: workspaceActionsButton)
    }

    @objc private func renameWorkspaceFromMenu() {
        let workspace = model.currentWorkspace
        guard let newName = promptForText(title: "Rename Workspace", message: "Enter a new name.", defaultValue: workspace.name) else { return }
        model.renameWorkspace(id: workspace.id, newName: newName)
    }

    @objc private func changeEmojiFromMenu() {
        let workspace = model.currentWorkspace
        guard let newEmoji = promptForText(title: "Change Emoji", message: "Enter a new emoji.", defaultValue: workspace.emoji) else { return }
        model.updateWorkspaceEmoji(id: workspace.id, emoji: newEmoji)
    }

    @objc private func changeColorFromMenu() {
        let workspace = model.currentWorkspace
        let alert = NSAlert()
        alert.messageText = "Change Workspace Color"
        alert.informativeText = "Pick a new color."

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 26))
        if popup.menu == nil {
            popup.menu = NSMenu()
        }
        for color in WorkspaceColorId.allCases {
            let item = NSMenuItem(title: color.name, action: nil, keyEquivalent: "")
            item.representedObject = color
            popup.menu?.addItem(item)
        }
        if let index = WorkspaceColorId.allCases.firstIndex(of: workspace.colorId) {
            popup.selectItem(at: index)
        }

        alert.accessoryView = popup
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn,
           let selected = popup.selectedItem?.representedObject as? WorkspaceColorId {
            model.updateWorkspaceColor(id: workspace.id, colorId: selected)
        }
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

    func promptCreateWorkspace() {
        let alert = NSAlert()
        alert.messageText = "New Workspace"
        alert.informativeText = "Create a new workspace."

        let nameField = NSTextField(string: "")
        nameField.placeholderString = "Name"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        let emojiField = NSTextField(string: "📌")
        emojiField.placeholderString = "Emoji"
        emojiField.translatesAutoresizingMaskIntoConstraints = false
        let colorPopup = NSPopUpButton()
        colorPopup.translatesAutoresizingMaskIntoConstraints = false
        if colorPopup.menu == nil {
            colorPopup.menu = NSMenu()
        }
        for color in WorkspaceColorId.allCases {
            let item = NSMenuItem(title: color.name, action: nil, keyEquivalent: "")
            item.representedObject = color
            colorPopup.menu?.addItem(item)
        }
        colorPopup.selectItem(at: 0)

        let stack = NSStackView(views: [nameField, emojiField, colorPopup])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 110))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            nameField.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            emojiField.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            emojiField.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            colorPopup.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            colorPopup.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
        alert.accessoryView = container

        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let emoji = emojiField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let selectedColor = (colorPopup.selectedItem?.representedObject as? WorkspaceColorId) ?? .defaultColor()
            model.createWorkspace(name: name, emoji: emoji.isEmpty ? "📌" : emoji, colorId: selectedColor)
        }
    }

    func promptCreateFolder(parentId: UUID?) {
        guard let name = promptForText(title: "New Folder", message: "Enter a folder name.", defaultValue: "New Folder") else { return }
        model.addFolder(name: name, parentId: parentId)
    }

    private func promptRenameNode(id: UUID, currentName: String) {
        guard let newName = promptForText(title: "Rename", message: "Enter a new name.", defaultValue: currentName) else { return }
        model.renameNode(id: id, newName: newName)
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

    @objc private func addLinkFromField() {
        guard let url = normalizedUrl(from: urlField.stringValue) else { return }
        let linkId = model.addLink(urlString: url.absoluteString, title: titleForUrl(url), parentId: nil)
        fetchTitleForNewLink(id: linkId, url: url)
        urlField.stringValue = ""
    }

    @objc private func pasteLink() {
        if let pasted = NSPasteboard.general.string(forType: .string),
           let url = normalizedUrl(from: pasted) {
            let linkId = model.addLink(urlString: url.absoluteString, title: titleForUrl(url), parentId: nil)
            fetchTitleForNewLink(id: linkId, url: url)
            urlField.stringValue = ""
        } else if let pasted = NSPasteboard.general.string(forType: .string) {
            urlField.stringValue = pasted
        }
    }

    @objc private func handleDoubleClick() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? Node else { return }
        if case .link(let link) = node, let url = URL(string: link.url) {
            BrowserManager.open(url: url)
        }
    }
}

extension MainViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? Node {
            switch node {
            case .folder(let folder):
                return folder.children.count
            case .link:
                return 0
            }
        }
        return filteredItems.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? Node {
            switch node {
            case .folder(let folder):
                return folder.children[index]
            case .link:
                return node
            }
        }
        return filteredItems[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? Node else { return false }
        if case .folder = node { return true }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("NodeCell")
        let view = outlineView.makeView(withIdentifier: identifier, owner: self) as? NodeCellView ?? NodeCellView()
        view.identifier = identifier

        switch node {
        case .folder(let folder):
            let icon = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            icon?.isTemplate = true
            view.configure(title: folder.name, icon: icon, showDelete: false, onDelete: nil)
        case .link(let link):
            let placeholder = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
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
            view.configure(title: link.title, icon: iconToUse, showDelete: true) { [weak self] in
                self?.model.deleteNode(id: link.id)
            }

            if shouldFetch, let url = URL(string: link.url) {
                FaviconService.shared.favicon(for: url, cachedPath: link.faviconPath) { [weak self] image, path in
                    guard let self else { return }
                    if let path {
                        self.model.updateLinkFaviconPath(id: link.id, path: path)
                    }
                }
            }

        }

        return view
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] as? Node else { return }
        if isRestoringExpansion { return }
        if !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        if case .folder(let folder) = item {
            model.setFolderExpanded(id: folder.id, isExpanded: true)
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] as? Node else { return }
        if isRestoringExpansion { return }
        if !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        if case .folder(let folder) = item {
            model.setFolderExpanded(id: folder.id, isExpanded: false)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? Node else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(node.id.uuidString, forType: nodePasteboardType)
        return pasteboardItem
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        if !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let idString = info.draggingPasteboard.string(forType: nodePasteboardType),
              let nodeId = UUID(uuidString: idString) else { return false }

        var targetParentId: UUID?
        var targetIndex = index

        if let node = item as? Node {
            switch node {
            case .folder(let folder):
                if index == NSOutlineViewDropOnItemIndex {
                    targetParentId = folder.id
                    targetIndex = folder.children.count
                } else {
                    targetParentId = model.location(of: folder.id)?.parentId
                }
            case .link(let link):
                if let location = model.location(of: link.id) {
                    targetParentId = location.parentId
                    targetIndex = location.index
                }
            }
        } else {
            targetParentId = nil
            if targetIndex == NSOutlineViewDropOnItemIndex {
                targetIndex = model.currentWorkspace.items.count
            }
        }

        if targetIndex < 0 { targetIndex = model.currentWorkspace.items.count }
        model.moveNode(id: nodeId, toParentId: targetParentId, index: targetIndex)
        return true
    }
}

extension MainViewController: NSSearchFieldDelegate, NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSSearchField, field == searchField {
            currentQuery = field.stringValue
            reloadData()
        }
    }
}

extension MainViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clickedRow = outlineView.clickedRow
        if clickedRow < 0 {
            let newFolder = NSMenuItem(title: "New Folder…", action: #selector(contextNewFolder), keyEquivalent: "")
            newFolder.target = self
            menu.addItem(newFolder)
            return
        }

        guard let node = outlineView.item(atRow: clickedRow) as? Node else { return }
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
                let item = NSMenuItem(title: "\(workspace.emoji) \(workspace.name)", action: #selector(contextMoveToWorkspace), keyEquivalent: "")
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
        promptCreateFolder(parentId: nil)
    }

    @objc private func contextNewNestedFolder() {
        guard let nodeId = contextNodeId else { return }
        promptCreateFolder(parentId: nodeId)
    }

    @objc private func contextRename() {
        guard let nodeId = contextNodeId, let node = model.nodeById(nodeId) else { return }
        promptRenameNode(id: nodeId, currentName: node.displayName)
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
}
