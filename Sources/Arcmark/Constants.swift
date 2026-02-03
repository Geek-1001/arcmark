import AppKit

enum UserDefaultsKeys {
    static let defaultBrowserBundleId = "defaultBrowserBundleId"
    static let alwaysOnTopEnabled = "alwaysOnTopEnabled"
    static let lastSelectedWorkspaceId = "lastSelectedWorkspaceId"
}

let nodePasteboardType = NSPasteboard.PasteboardType("com.arcmark.node")

struct ListMetrics {
    let rowHeight: CGFloat = 46
    let verticalGap: CGFloat = 12
    let leftPadding: CGFloat = 16
    let iconSize: CGFloat = 26
    let indentWidth: CGFloat = 18
    let titleFont: NSFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    let titleColor: NSColor = NSColor.white.withAlphaComponent(0.92)
    let hoverBackgroundColor: NSColor = NSColor.black.withAlphaComponent(0.2)
    let deleteTintColor: NSColor = NSColor.white.withAlphaComponent(0.55)
    let iconTintColor: NSColor = NSColor.white.withAlphaComponent(0.9)
}
