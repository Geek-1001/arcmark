import AppKit

enum UserDefaultsKeys {
    static let defaultBrowserBundleId = "defaultBrowserBundleId"
    static let alwaysOnTopEnabled = "alwaysOnTopEnabled"
    static let lastSelectedWorkspaceId = "lastSelectedWorkspaceId"
}

let nodePasteboardType = NSPasteboard.PasteboardType("com.arcmark.node")

struct ListMetrics {
    let rowHeight: CGFloat = 42
    let verticalGap: CGFloat = 4
    let leftPadding: CGFloat = 8
    let iconSize: CGFloat = 20
    let indentWidth: CGFloat = 16
    let titleFont: NSFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    let titleColor: NSColor = NSColor.white.withAlphaComponent(0.92)
    let hoverBackgroundColor: NSColor = NSColor.black.withAlphaComponent(0.1)
    let deleteTintColor: NSColor = NSColor.black.withAlphaComponent(0.6)
    let iconTintColor: NSColor = NSColor.white.withAlphaComponent(0.9)
}
