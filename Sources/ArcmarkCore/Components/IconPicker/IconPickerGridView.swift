import AppKit

@MainActor
final class IconPickerGridView: NSView {

    private let scrollView = NSScrollView()
    private let contentView = FlippedContentView()

    private let cellSize: CGFloat = 34
    private let cellSpacing: CGFloat = 4
    private let columns = 8

    private var itemViews: [IconPickerItemView] = []

    var onItemSelected: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func setItems(_ items: [IconPickerItemView.Content], selectionHandler: @escaping (Int) -> Void) {
        for view in itemViews {
            view.removeFromSuperview()
        }
        itemViews.removeAll()
        onItemSelected = selectionHandler

        for (index, content) in items.enumerated() {
            let itemView = IconPickerItemView(frame: .zero)
            itemView.configure(content: content)
            itemView.onItemSelected = { [weak self] in
                self?.onItemSelected?(index)
            }
            contentView.addSubview(itemView)
            itemViews.append(itemView)
        }

        layoutGrid()
    }

    override func layout() {
        super.layout()
        layoutGrid()
    }

    private func layoutGrid() {
        let totalWidth = bounds.width
        let availableWidth = totalWidth - CGFloat(columns - 1) * cellSpacing
        let actualCellSize = max(cellSize, floor(availableWidth / CGFloat(columns)))

        let rows = (itemViews.count + columns - 1) / columns
        let contentHeight = CGFloat(rows) * actualCellSize + CGFloat(max(0, rows - 1)) * cellSpacing

        contentView.frame = NSRect(x: 0, y: 0, width: totalWidth, height: contentHeight)

        for (index, view) in itemViews.enumerated() {
            let col = index % columns
            let row = index / columns
            let x = CGFloat(col) * (actualCellSize + cellSpacing)
            let y = CGFloat(row) * (actualCellSize + cellSpacing)
            view.frame = NSRect(x: x, y: y, width: actualCellSize, height: actualCellSize)
        }
    }
}
