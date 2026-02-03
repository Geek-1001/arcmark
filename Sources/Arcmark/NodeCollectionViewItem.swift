import AppKit

final class NodeCollectionViewItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("NodeCollectionViewItem")
    private let rowView = NodeRowView()

    override func loadView() {
        view = rowView
    }

    func configure(title: String,
                   icon: NSImage?,
                   titleFont: NSFont,
                   depth: Int,
                   metrics: ListMetrics,
                   showDelete: Bool,
                   onDelete: (() -> Void)?) {
        view.alphaValue = 1
        view.layer?.transform = CATransform3DIdentity
        rowView.setIndentation(depth: depth, metrics: metrics)
        rowView.configure(
            title: title,
            icon: icon,
            titleFont: titleFont,
            showDelete: showDelete,
            metrics: metrics,
            onDelete: onDelete
        )
    }

    func refreshHoverState() {
        rowView.refreshHoverState()
    }

    var isInlineRenaming: Bool {
        rowView.isInlineRenaming
    }

    func beginInlineRename(onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        rowView.beginInlineRename(onCommit: onCommit, onCancel: onCancel)
    }

    func cancelInlineRename() {
        rowView.cancelInlineRename()
    }
}
