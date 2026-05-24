import Foundation

enum ScheduledLinkFiltering {
    /// Returns the node tree with any link where `scheduledOpenAt != nil` removed.
    /// Folders are preserved even if they become empty — structure stays visible.
    static func hideScheduled(_ nodes: [Node]) -> [Node] {
        nodes.compactMap { node in
            switch node {
            case .link(let link):
                return link.scheduledOpenAt == nil ? node : nil
            case .note:
                return node
            case .folder(var folder):
                folder.children = hideScheduled(folder.children)
                return .folder(folder)
            }
        }
    }
}
