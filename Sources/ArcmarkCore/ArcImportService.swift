import Foundation
import AppKit

// MARK: - Arc Data Models

/// Represents the root structure of Arc's StorableSidebar.json
struct ArcData: Codable {
    let sidebar: ArcSidebar
    let version: Int
}

/// Contains Arc's sidebar structure with containers
struct ArcSidebar: Codable {
    let containers: [ArcContainer]
}

/// Represents a container which can be an object or empty
enum ArcContainer: Codable {
    case object(ArcContainerObject)
    case empty

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode as an object first
        if let object = try? container.decode(ArcContainerObject.self) {
            self = .object(object)
        } else {
            // If it fails, treat it as empty
            _ = try? container.decode([String: String].self)
            self = .empty
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let obj):
            try container.encode(obj)
        case .empty:
            try container.encode([String: String]())
        }
    }
}

/// Arc container object containing spaces and items
struct ArcContainerObject: Codable {
    let spaces: [ArcSpaceOrString]?
    let items: [ArcItemOrString]?
    let topAppsContainerIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case spaces
        case items
        case topAppsContainerIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode each field, but don't fail if any are missing or invalid
        self.spaces = try? container.decode([ArcSpaceOrString].self, forKey: .spaces)
        self.items = try? container.decode([ArcItemOrString].self, forKey: .items)
        self.topAppsContainerIDs = try? container.decode([String].self, forKey: .topAppsContainerIDs)
    }
}

/// Arc space can be either a SpaceModel object or a string reference
enum ArcSpaceOrString: Codable {
    case space(ArcSpace)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let space = try? container.decode(ArcSpace.self) {
            self = .space(space)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected String or ArcSpace"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .space(let space):
            try container.encode(space)
        case .string(let string):
            try container.encode(string)
        }
    }
}

/// Represents an Arc space (workspace)
struct ArcSpace: Codable {
    let id: String
    let title: String
    let containerIDs: [String]

    // Helper to get pinned container ID
    var pinnedContainerId: String? {
        guard let pinnedIndex = containerIDs.firstIndex(of: "pinned"),
              pinnedIndex + 1 < containerIDs.count else {
            return nil
        }
        return containerIDs[pinnedIndex + 1]
    }
}

/// Arc item can be either an Item object or a string reference
enum ArcItemOrString: Codable {
    case item(ArcItem)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let item = try? container.decode(ArcItem.self) {
            self = .item(item)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected String or ArcItem"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .item(let item):
            try container.encode(item)
        case .string(let string):
            try container.encode(string)
        }
    }
}

/// Represents an Arc item (folder or link)
struct ArcItem: Codable {
    let id: String
    let title: String?
    let parentID: String?
    let childrenIds: [String]?
    let data: ArcItemData?
}

/// Contains tab data for a link item
struct ArcItemData: Codable {
    let tab: ArcTabData?
}

/// Tab information including URL and title
struct ArcTabData: Codable {
    let savedTitle: String
    let savedURL: String
    let timeLastActiveAt: Double?
}

// MARK: - Import Result Models

/// Represents a workspace to be imported
struct ImportWorkspace: Sendable {
    let name: String
    let colorId: WorkspaceColorId
    let nodes: [Node]
}

/// Result of an Arc import operation
struct ArcImportResult: Sendable {
    let workspaces: [ImportWorkspace]
    let workspacesCreated: Int
    let linksImported: Int
    let foldersImported: Int
}

/// Errors that can occur during Arc import
enum ArcImportError: Error {
    case fileNotFound
    case invalidJSON
    case noDataContainer
    case parsingFailed(String)
}

extension ArcImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Arc bookmark file not found. Please locate StorableSidebar.json in Arc's data directory."
        case .invalidJSON:
            return "Invalid Arc bookmark file format. The file may be corrupted."
        case .noDataContainer:
            return "No bookmark data found in Arc file. Make sure you have bookmarks in Arc."
        case .parsingFailed(let detail):
            return "Failed to parse Arc bookmarks: \(detail)"
        }
    }
}

// MARK: - Arc Import Service

final class ArcImportService: Sendable {
    static let shared = ArcImportService()

    private init() {}

    // MARK: - Public API

    /// Import bookmarks from Arc browser's StorableSidebar.json file
    /// - Parameter fileURL: URL to the Arc StorableSidebar.json file
    /// - Returns: Result containing import statistics or error
    func importFromArc(fileURL: URL) async -> Result<ArcImportResult, ArcImportError> {
        // Yield to allow UI to update (show loading spinner)
        await Task.yield()

        // Perform the heavy work on a background task to avoid blocking the main thread
        return await Task.detached {
            do {
                // Read file data
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return .failure(.fileNotFound)
                }

                let data = try Data(contentsOf: fileURL)

                // Parse Arc data - this is CPU intensive
                let arcData = try self.parseArcData(data)

                // Convert to Arcmark workspaces - also CPU intensive
                let workspaces = try self.convertToWorkspaces(arcData)

                // Calculate statistics
                var totalLinks = 0
                var totalFolders = 0

                for workspace in workspaces {
                    let stats = self.countNodes(workspace.nodes)
                    totalLinks += stats.links
                    totalFolders += stats.folders
                }

                let result = ArcImportResult(
                    workspaces: workspaces,
                    workspacesCreated: workspaces.count,
                    linksImported: totalLinks,
                    foldersImported: totalFolders
                )

                return .success(result)

            } catch let error as ArcImportError {
                return .failure(error)
            } catch {
                return .failure(.parsingFailed(error.localizedDescription))
            }
        }.value
    }

    // MARK: - Private Methods

    /// Parse Arc JSON data
    private func parseArcData(_ data: Data) throws -> ArcData {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ArcData.self, from: data)
        } catch {
            throw ArcImportError.invalidJSON
        }
    }

    /// Convert Arc data to Arcmark workspaces
    private func convertToWorkspaces(_ arcData: ArcData) throws -> [ImportWorkspace] {
        // Find container with spaces and items
        var containerObject: ArcContainerObject?

        for container in arcData.sidebar.containers {
            if case .object(let obj) = container,
               obj.spaces != nil,
               obj.items != nil {
                containerObject = obj
                break
            }
        }

        guard let container = containerObject else {
            throw ArcImportError.noDataContainer
        }

        guard let spacesData = container.spaces,
              let itemsData = container.items else {
            throw ArcImportError.noDataContainer
        }

        // Build item lookup map
        let itemsMap = buildItemsMap(itemsData)

        // Parse spaces
        let spaces = spacesData.compactMap { spaceOrString -> ArcSpace? in
            if case .space(let space) = spaceOrString {
                return space
            }
            return nil
        }

        // Track used workspace names to handle duplicates
        var usedNames: [String: Int] = [:]

        // Convert each space to a workspace
        var workspaces: [ImportWorkspace] = []

        for (index, space) in spaces.enumerated() {
            // Get pinned container ID
            guard let pinnedContainerId = space.pinnedContainerId else {
                continue
            }

            // Build node hierarchy
            let nodes = buildNodeHierarchy(parentId: pinnedContainerId, items: itemsMap)

            // Skip empty spaces
            guard !nodes.isEmpty else {
                continue
            }

            // Handle duplicate workspace names
            var workspaceName = space.title
            if let count = usedNames[workspaceName] {
                workspaceName = "\(space.title) \(count + 1)"
                usedNames[space.title] = count + 1
            } else {
                usedNames[workspaceName] = 1
            }

            // Assign color based on index
            let colorId = assignColor(for: index)

            let workspace = ImportWorkspace(
                name: workspaceName,
                colorId: colorId,
                nodes: nodes
            )

            workspaces.append(workspace)
        }

        return workspaces
    }

    /// Build a map of item ID to item object
    private func buildItemsMap(_ items: [ArcItemOrString]) -> [String: ArcItem] {
        var map: [String: ArcItem] = [:]

        for itemOrString in items {
            if case .item(let item) = itemOrString {
                map[item.id] = item
            }
        }

        return map
    }

    /// Recursively build node hierarchy from Arc items
    private func buildNodeHierarchy(parentId: String, items: [String: ArcItem]) -> [Node] {
        var nodes: [Node] = []

        // Find all items with this parentId
        let children = items.values.filter { $0.parentID == parentId }

        for item in children {
            // Check if it's a folder
            if let childrenIds = item.childrenIds, !childrenIds.isEmpty {
                let childNodes = buildNodeHierarchy(parentId: item.id, items: items)
                let folder = Folder(
                    id: UUID(),
                    name: item.title ?? "Untitled Folder",
                    children: childNodes,
                    isExpanded: true
                )
                nodes.append(.folder(folder))
            }
            // Check if it's a link
            else if let tabData = item.data?.tab {
                // Validate URL
                guard !tabData.savedURL.isEmpty,
                      URL(string: tabData.savedURL) != nil else {
                    continue
                }

                let link = Link(
                    id: UUID(),
                    title: tabData.savedTitle.isEmpty ? tabData.savedURL : tabData.savedTitle,
                    url: tabData.savedURL,
                    faviconPath: nil
                )
                nodes.append(.link(link))
            }
        }

        return nodes
    }

    /// Assign a color to a workspace based on its index
    private func assignColor(for index: Int) -> WorkspaceColorId {
        let colors: [WorkspaceColorId] = [
            .ember, .ruby, .coral, .tangerine, .moss, .ocean, .indigo, .graphite
        ]
        return colors[index % colors.count]
    }

    /// Count links and folders in a node array
    private func countNodes(_ nodes: [Node]) -> (links: Int, folders: Int) {
        var links = 0
        var folders = 0

        for node in nodes {
            switch node {
            case .link:
                links += 1
            case .folder(let folder):
                folders += 1
                let childStats = countNodes(folder.children)
                links += childStats.links
                folders += childStats.folders
            }
        }

        return (links, folders)
    }
}
