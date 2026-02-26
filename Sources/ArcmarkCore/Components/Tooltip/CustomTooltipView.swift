import AppKit

final class CustomTooltipView: NSPanel {
    private static let maxWidth: CGFloat = 300
    private let label = NSTextField(labelWithString: "")

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        hasShadow = true
        level = .floating
        ignoresMouseEvents = true
        backgroundColor = .clear

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = ThemeConstants.Colors.darkGray.cgColor
        container.layer?.cornerRadius = ThemeConstants.CornerRadius.medium
        container.translatesAutoresizingMaskIntoConstraints = false

        label.font = ThemeConstants.Fonts.systemFont(size: 12, weight: .regular)
        label.textColor = ThemeConstants.Colors.white
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.preferredMaxLayoutWidth = Self.maxWidth - ThemeConstants.Spacing.medium * 2
        label.translatesAutoresizingMaskIntoConstraints = false

        contentView = NSView()
        contentView?.addSubview(container)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            container.topAnchor.constraint(equalTo: contentView!.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth),

            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: ThemeConstants.Spacing.medium),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -ThemeConstants.Spacing.medium),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: ThemeConstants.Spacing.small),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -ThemeConstants.Spacing.small),
        ])
    }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    }

    func show(text: String, cursorPosition: NSPoint, parentWindow: NSWindow) {
        label.stringValue = text
        label.preferredMaxLayoutWidth = Self.maxWidth - ThemeConstants.Spacing.medium * 2
        contentView?.layoutSubtreeIfNeeded()

        let fittingSize = contentView?.fittingSize ?? .zero
        let cursorOffset = ThemeConstants.Spacing.extraLarge

        var origin = NSPoint(x: cursorPosition.x, y: cursorPosition.y - fittingSize.height - cursorOffset)

        // Clamp to visible screen bounds
        if let screen = parentWindow.screen ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            if origin.x + fittingSize.width > visibleFrame.maxX {
                origin.x = visibleFrame.maxX - fittingSize.width
            }
            if origin.x < visibleFrame.minX {
                origin.x = visibleFrame.minX
            }
            if origin.y < visibleFrame.minY {
                origin.y = cursorPosition.y + cursorOffset
            }
            if origin.y + fittingSize.height > visibleFrame.maxY {
                origin.y = visibleFrame.maxY - fittingSize.height
            }
        }

        setFrame(NSRect(origin: origin, size: fittingSize), display: true)
        alphaValue = 0
        parentWindow.addChildWindow(self, ordered: .above)
        orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = ThemeConstants.Animation.durationFast
            self.animator().alphaValue = 1
        }
    }

    func hide() {
        if let parent = parent {
            parent.removeChildWindow(self)
        }
        orderOut(nil)
        alphaValue = 0
    }
}
