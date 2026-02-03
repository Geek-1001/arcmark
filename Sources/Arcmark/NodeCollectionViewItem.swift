import AppKit

final class NodeCollectionViewItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("NodeCollectionViewItem")
    private let rowView = NodeRowView()

    override func loadView() {
        view = rowView
    }

    func configure(title: String,
                   icon: NSImage?,
                   depth: Int,
                   metrics: ListMetrics,
                   showDelete: Bool,
                   onDelete: (() -> Void)?,
                   onClick: (() -> Void)?,
                   onDoubleClick: (() -> Void)?) {
        rowView.setIndentation(depth: depth, metrics: metrics)
        rowView.configure(
            title: title,
            icon: icon,
            showDelete: showDelete,
            metrics: metrics,
            onDelete: onDelete,
            onClick: onClick,
            onDoubleClick: onDoubleClick
        )
    }
}
