import AppKit

/// An NSCollectionView subclass that intercepts right-clicks to show context menus
/// for workspace items. Uses a `workspacesProvider` closure to resolve which workspace
/// was clicked.
final class WorkspaceContextMenuCollectionView: NSCollectionView {
    var onRightClick: ((UUID, NSEvent) -> Void)?
    var workspacesProvider: (() -> [Workspace])?

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: point),
           let workspaces = workspacesProvider?() {
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
