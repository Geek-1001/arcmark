import AppKit

enum UserDefaultsKeys {
    static let defaultBrowserBundleId = "defaultBrowserBundleId"
    static let alwaysOnTopEnabled = "alwaysOnTopEnabled"
    static let lastSelectedWorkspaceId = "lastSelectedWorkspaceId"
    static let mainWindowSize = "mainWindowSize"
}

let nodePasteboardType = NSPasteboard.PasteboardType("com.arcmark.node")

struct ListMetrics {
    let rowHeight: CGFloat = 40
    let verticalGap: CGFloat = 4
    let leftPadding: CGFloat = 8
    let iconSize: CGFloat = 20
    let indentWidth: CGFloat = 16
    let rowCornerRadius: CGFloat = 12
    let iconCornerRadius: CGFloat = 4
    let linkTitleFont: NSFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    let folderTitleFont: NSFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    let titleColor: NSColor = NSColor.white.withAlphaComponent(0.92)
    let hoverBackgroundColor: NSColor = NSColor.black.withAlphaComponent(0.1)
    let deleteTintColor: NSColor = NSColor.black.withAlphaComponent(0.6)
    let iconTintColor: NSColor = NSColor.white.withAlphaComponent(0.9)
}
