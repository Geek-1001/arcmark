//
//  WorkspaceManagementView.swift
//  Arcmark
//

import AppKit

/// Manages the workspace list in settings
@MainActor
final class WorkspaceManagementView: NSView {

    // MARK: - Properties

    private let workspaceCollectionView = WorkspaceContextMenuCollectionView()
    private let workspaceDropIndicator = WorkspaceDropIndicatorView()
    private var workspaceCollectionViewHeightConstraint: NSLayoutConstraint?
    private var contextWorkspaceId: UUID?
    private var inlineRenameWorkspaceId: UUID?

    // Callbacks
    var onWorkspaceDeleted: ((UUID) -> Void)?
    var onWorkspaceRenamed: ((UUID, String) -> Void)?
    var onWorkspaceColorChanged: ((UUID, WorkspaceColorId) -> Void)?
    var onWorkspaceReordered: ((UUID, Int) -> Void)?
    var workspacesProvider: (() -> [Workspace])?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupCollectionView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCollectionView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupCollectionView() {
        let layout = ListFlowLayout(metrics: ListMetrics())
        workspaceCollectionView.collectionViewLayout = layout
        workspaceCollectionView.translatesAutoresizingMaskIntoConstraints = false
        workspaceCollectionView.dataSource = self
        workspaceCollectionView.delegate = self
        workspaceCollectionView.isSelectable = true
        workspaceCollectionView.allowsMultipleSelection = false
        workspaceCollectionView.backgroundColors = [.clear]
        workspaceCollectionView.managementView = self

        // Set up context menu handler
        workspaceCollectionView.onRightClick = { [weak self] workspaceId, event in
            self?.showWorkspaceContextMenu(for: workspaceId, at: event)
        }

        // Register the workspace item
        workspaceCollectionView.register(
            WorkspaceCollectionViewItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier("WorkspaceItem")
        )

        // Register for drag types
        workspaceCollectionView.registerForDraggedTypes([workspacePasteboardType])
        workspaceCollectionView.setDraggingSourceOperationMask(.move, forLocal: true)

        // Setup drop indicator
        workspaceDropIndicator.translatesAutoresizingMaskIntoConstraints = false
        workspaceCollectionView.addSubview(workspaceDropIndicator)

        // Add collection view
        addSubview(workspaceCollectionView)

        // Setup constraints
        workspaceCollectionViewHeightConstraint = workspaceCollectionView.heightAnchor.constraint(equalToConstant: 0)
        workspaceCollectionViewHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            workspaceCollectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            workspaceCollectionView.topAnchor.constraint(equalTo: topAnchor),
            workspaceCollectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            workspaceCollectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Observe scroll bounds changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkspaceScrollBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: workspaceCollectionView.enclosingScrollView?.contentView
        )
    }

    // MARK: - Public Methods

    func reloadWorkspaces() {
        guard let workspaces = workspacesProvider?() else { return }

        // Update collection view height based on workspace count
        let metrics = ListMetrics()
        let rowCount = workspaces.count
        let totalHeight = CGFloat(rowCount) * metrics.rowHeight + CGFloat(max(0, rowCount - 1)) * metrics.verticalGap
        workspaceCollectionViewHeightConstraint?.constant = totalHeight

        // Invalidate layout before reloading
        workspaceCollectionView.collectionViewLayout?.invalidateLayout()

        workspaceCollectionView.reloadData()
    }

    // MARK: - Private Methods

    private func handleWorkspaceDelete(id: UUID) {
        guard let workspaces = workspacesProvider?() else { return }

        // Check if only one workspace
        if workspaces.count <= 1 {
            return
        }

        onWorkspaceDeleted?(id)
    }

    private func handleWorkspaceRename(id: UUID, newName: String) {
        onWorkspaceRenamed?(id, newName)
    }

    private func showWorkspaceContextMenu(for workspaceId: UUID, at event: NSEvent) {
        guard let workspaces = workspacesProvider?() else { return }
        guard let workspace = workspaces.first(where: { $0.id == workspaceId }) else { return }

        contextWorkspaceId = workspaceId

        let menu = NSMenu()

        // Rename option
        let renameItem = NSMenuItem(title: "Rename Workspace...", action: #selector(beginInlineRenameForContextWorkspace), keyEquivalent: "")
        renameItem.target = self
        menu.addItem(renameItem)

        // Change Color submenu
        let colorSubmenu = NSMenu()
        for colorId in WorkspaceColorId.allCases {
            let item = NSMenuItem(title: colorId.name, action: #selector(changeWorkspaceColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = colorId

            // Add checkmark if current color
            if workspace.colorId == colorId {
                item.state = .on
            }

            // Add color indicator
            let colorCircle = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
                colorId.color.setFill()
                let path = NSBezierPath(ovalIn: rect)
                path.fill()
                return true
            }
            item.image = colorCircle

            colorSubmenu.addItem(item)
        }

        let colorItem = NSMenuItem(title: "Change Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colorSubmenu
        menu.addItem(colorItem)

        // Delete option
        menu.addItem(.separator())
        let deleteItem = NSMenuItem(title: "Delete Workspace...", action: #selector(deleteContextWorkspace), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.isEnabled = workspaces.count > 1
        menu.addItem(deleteItem)

        NSMenu.popUpContextMenu(menu, with: event, for: workspaceCollectionView)
    }

    @objc private func beginInlineRenameForContextWorkspace() {
        guard let workspaceId = contextWorkspaceId else { return }
        guard let workspaces = workspacesProvider?() else { return }
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceId }) else { return }

        inlineRenameWorkspaceId = workspaceId

        DispatchQueue.main.async {
            let indexPath = IndexPath(item: index, section: 0)
            if let item = self.workspaceCollectionView.item(at: indexPath) as? WorkspaceCollectionViewItem {
                item.beginInlineRename()
            }
        }
    }

    @objc private func changeWorkspaceColor(_ sender: NSMenuItem) {
        guard let workspaceId = contextWorkspaceId else { return }
        guard let colorId = sender.representedObject as? WorkspaceColorId else { return }

        onWorkspaceColorChanged?(workspaceId, colorId)
        reloadWorkspaces()
    }

    @objc private func deleteContextWorkspace() {
        guard let workspaceId = contextWorkspaceId else { return }
        guard let workspaces = workspacesProvider?() else { return }

        // Check if only one workspace
        if workspaces.count <= 1 {
            return
        }

        // Show confirmation alert
        let alert = NSAlert()
        alert.messageText = "Delete Workspace?"
        alert.informativeText = "Are you sure you want to delete this workspace? All links and folders will be permanently removed."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete")

        // Make Delete button destructive
        if let deleteButton = alert.buttons.last {
            deleteButton.hasDestructiveAction = true
        }

        if let window = window {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertSecondButtonReturn {
                    self?.handleWorkspaceDelete(id: workspaceId)
                    self?.reloadWorkspaces()
                }
            }
        }
    }

    @objc private func handleWorkspaceScrollBoundsChanged() {
        for item in workspaceCollectionView.visibleItems() {
            (item as? WorkspaceCollectionViewItem)?.refreshHoverState()
        }
    }
}

// MARK: - NSCollectionViewDataSource

extension WorkspaceManagementView: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return workspacesProvider?().count ?? 0
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        guard let workspaces = workspacesProvider?() else {
            return NSCollectionViewItem()
        }

        let item = collectionView.makeItem(
            withIdentifier: NSUserInterfaceItemIdentifier("WorkspaceItem"),
            for: indexPath
        ) as! WorkspaceCollectionViewItem

        let workspace = workspaces[indexPath.item]
        let canDelete = workspaces.count > 1

        item.configure(
            workspace: workspace,
            canDelete: canDelete,
            onDelete: { [weak self] id in
                self?.handleWorkspaceDelete(id: id)
            },
            onRenameCommit: { [weak self] id, newName in
                self?.handleWorkspaceRename(id: id, newName: newName)
            },
            onProfile: { _ in }
        )

        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension WorkspaceManagementView: NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        return true
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard let workspaces = workspacesProvider?() else {
            return nil
        }
        let workspace = workspaces[indexPath.item]

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(workspace.id.uuidString, forType: workspacePasteboardType)
        return pasteboardItem
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        // Only allow drop before items (for reordering)
        proposedDropOperation.pointee = .before

        // Show drop indicator
        let indexPath = proposedDropIndexPath.pointee as IndexPath
        let metrics = ListMetrics()
        let workspaceCount = workspacesProvider?().count ?? 0

        if indexPath.item == 0 {
            // Drop at the beginning
            let indicatorFrame = CGRect(
                x: 0,
                y: 0,
                width: collectionView.bounds.width,
                height: 2
            )
            workspaceDropIndicator.showLine(in: indicatorFrame)
        } else if indexPath.item < workspaceCount {
            // Drop between items
            let y = CGFloat(indexPath.item) * (metrics.rowHeight + metrics.verticalGap) - metrics.verticalGap / 2
            let indicatorFrame = CGRect(
                x: 0,
                y: y,
                width: collectionView.bounds.width,
                height: 2
            )
            workspaceDropIndicator.showLine(in: indicatorFrame)
        } else {
            // Drop at the end
            let y = CGFloat(workspaceCount) * (metrics.rowHeight + metrics.verticalGap) - metrics.verticalGap / 2
            let indicatorFrame = CGRect(
                x: 0,
                y: y,
                width: collectionView.bounds.width,
                height: 2
            )
            workspaceDropIndicator.showLine(in: indicatorFrame)
        }

        return .move
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        // Hide drop indicator
        workspaceDropIndicator.hide()

        guard let workspaces = workspacesProvider?() else {
            return false
        }
        guard let pasteboardItem = draggingInfo.draggingPasteboard.pasteboardItems?.first else {
            return false
        }
        guard let uuidString = pasteboardItem.string(forType: workspacePasteboardType) else {
            return false
        }
        guard let workspaceId = UUID(uuidString: uuidString) else {
            return false
        }
        guard let currentIndex = workspaces.firstIndex(where: { $0.id == workspaceId }) else {
            return false
        }

        var targetIndex = indexPath.item

        // Adjust target index if dragging within the same list
        if currentIndex < targetIndex {
            targetIndex -= 1
        }

        // Perform the reorder
        onWorkspaceReordered?(workspaceId, targetIndex)
        reloadWorkspaces()

        return true
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        // Hide drop indicator when drag ends
        workspaceDropIndicator.hide()
    }
}

// MARK: - Supporting Types

private final class WorkspaceContextMenuCollectionView: NSCollectionView {
    var onRightClick: ((UUID, NSEvent) -> Void)?

    weak var managementView: WorkspaceManagementView?

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: point),
           let workspaces = managementView?.workspacesProvider?() {
            let workspace = workspaces[indexPath.item]
            onRightClick?(workspace.id, event)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // Call super to allow drag operations
        super.mouseDown(with: event)
    }
}

private final class WorkspaceDropIndicatorView: NSView {
    private let lineThickness: CGFloat = 2
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

    func hide() {
        isHidden = true
    }
}
