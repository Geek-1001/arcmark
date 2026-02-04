import Foundation

struct AppState: Codable, Equatable {
    var schemaVersion: Int
    var workspaces: [Workspace]
    var selectedWorkspaceId: UUID?
}

struct Workspace: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var colorId: WorkspaceColorId
    var items: [Node]
}

struct Link: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var url: String
    var faviconPath: String?
}

struct Folder: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var children: [Node]
    var isExpanded: Bool
}

enum Node: Codable, Identifiable, Equatable, Hashable {
    case folder(Folder)
    case link(Link)

    enum CodingKeys: String, CodingKey {
        case type
        case folder
        case link
    }

    enum NodeType: String, Codable {
        case folder
        case link
    }

    var id: UUID {
        switch self {
        case .folder(let folder):
            return folder.id
        case .link(let link):
            return link.id
        }
    }

    var displayName: String {
        switch self {
        case .folder(let folder):
            return folder.name
        case .link(let link):
            return link.title
        }
    }

    static func == (lhs: Node, rhs: Node) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(NodeType.self, forKey: .type)
        switch type {
        case .folder:
            let folder = try container.decode(Folder.self, forKey: .folder)
            self = .folder(folder)
        case .link:
            let link = try container.decode(Link.self, forKey: .link)
            self = .link(link)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .folder(let folder):
            try container.encode(NodeType.folder, forKey: .type)
            try container.encode(folder, forKey: .folder)
        case .link(let link):
            try container.encode(NodeType.link, forKey: .type)
            try container.encode(link, forKey: .link)
        }
    }
}

struct NodeLocation: Equatable {
    var parentId: UUID?
    var index: Int
}

enum WorkspaceMoveDirection {
    case left
    case right
}
