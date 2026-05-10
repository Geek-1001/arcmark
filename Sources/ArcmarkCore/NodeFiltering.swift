import Foundation

enum NodeFiltering {
    static func filter(nodes: [Node], query: String) -> [Node] {
        let lower = query.lowercased()
        return nodes.compactMap { node in
            switch node {
            case .link(let link):
                let matches = link.title.lowercased().contains(lower)
                return matches ? node : nil
            case .note(let note):
                let matches = note.title.lowercased().contains(lower)
                return matches ? node : nil
            case .folder(var folder):
                let children = filter(nodes: folder.children, query: query)
                if !children.isEmpty {
                    folder.children = children
                    folder.isExpanded = true
                    return .folder(folder)
                }
                return nil
            }
        }
    }
}
