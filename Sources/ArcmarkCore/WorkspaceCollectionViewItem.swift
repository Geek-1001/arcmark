import AppKit

final class WorkspaceCollectionViewItem: NSCollectionViewItem {
    private var rowView: WorkspaceRowView?
    private var workspace: Workspace?
    var onDelete: ((UUID) -> Void)?
    var onRenameCommit: ((UUID, String) -> Void)?
    var onProfile: ((UUID) -> Void)?

    override func loadView() {
        let row = WorkspaceRowView(frame: .zero)
        self.view = row
        self.rowView = row
    }

    // Prevent selection highlight
    override var isSelected: Bool {
        didSet {
            // Don't show selection highlight
        }
    }

    func configure(workspace: Workspace, canDelete: Bool, onDelete: @escaping (UUID) -> Void, onRenameCommit: @escaping (UUID, String) -> Void, onProfile: @escaping (UUID) -> Void) {
        self.workspace = workspace
        self.onDelete = onDelete
        self.onRenameCommit = onRenameCommit
        self.onProfile = onProfile

        rowView?.configure(
            workspaceName: workspace.name,
            workspaceColor: workspace.colorId.color,
            showDelete: true,
            canDelete: canDelete,
            hasProfile: workspace.browserProfile != nil && !(workspace.browserProfile?.isEmpty ?? true),
            onDelete: { [weak self] in
                guard let self, let workspace = self.workspace else { return }
                self.onDelete?(workspace.id)
            },
            onProfile: { [weak self] in
                guard let self, let workspace = self.workspace else { return }
                self.onProfile?(workspace.id)
            }
        )
    }

    func beginInlineRename() {
        rowView?.beginInlineRename(
            onCommit: { [weak self] newName in
                guard let self, let workspace = self.workspace else { return }
                self.onRenameCommit?(workspace.id, newName)
            },
            onCancel: { }
        )
    }

    var isInlineRenaming: Bool {
        rowView?.isInlineRenaming ?? false
    }

    func refreshHoverState() {
        rowView?.refreshHoverState()
    }
}
