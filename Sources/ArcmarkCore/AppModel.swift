import Foundation
import os

final class AppModel {
    private let store: DataStore
    let noteStorage: NoteStorage
    private(set) var state: AppState
    var onChange: (() -> Void)?
    private let logger = Logger(subsystem: "com.arcmark.app", category: "model")

    init(store: DataStore = DataStore()) {
        self.store = store
        self.noteStorage = NoteStorage(store: store)
        self.state = store.load()

        if !state.isSettingsSelected {
            if let savedId = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastSelectedWorkspaceId),
               let uuid = UUID(uuidString: savedId),
               state.workspaces.contains(where: { $0.id == uuid }) {
                state.selectedWorkspaceId = uuid
            }
            if state.selectedWorkspaceId == nil {
                state.selectedWorkspaceId = state.workspaces.first?.id
            }
        }
    }

    var workspaces: [Workspace] {
        state.workspaces
    }

    var currentWorkspace: Workspace {
        if let selected = state.selectedWorkspaceId,
           let workspace = state.workspaces.first(where: { $0.id == selected }) {
            return workspace
        }
        if let first = state.workspaces.first {
            return first
        }
        let fallback = Workspace(id: UUID(), name: "Inbox", colorId: .defaultColor(), items: [], pinnedLinks: [])
        state.workspaces = [fallback]
        state.selectedWorkspaceId = fallback.id
        persist()
        return fallback
    }

    func selectWorkspace(id: UUID) {
        guard state.workspaces.contains(where: { $0.id == id }) else { return }
        state.selectedWorkspaceId = id
        state.isSettingsSelected = false
        UserDefaults.standard.set(id.uuidString, forKey: UserDefaultsKeys.lastSelectedWorkspaceId)
        persist()
    }

    func selectSettings() {
        state.isSettingsSelected = true
        state.selectedWorkspaceId = nil
        persist()
    }

    @discardableResult
    func createWorkspace(name: String, colorId: WorkspaceColorId) -> UUID {
        let workspace = Workspace(id: UUID(), name: name, colorId: colorId, items: [])
        state.workspaces.append(workspace)
        state.selectedWorkspaceId = workspace.id
        UserDefaults.standard.set(workspace.id.uuidString, forKey: UserDefaultsKeys.lastSelectedWorkspaceId)
        persist()
        return workspace.id
    }

    func renameWorkspace(id: UUID, newName: String) {
        updateWorkspace(id: id) { workspace in
            workspace.name = newName
        }
    }

    func updateWorkspaceColor(id: UUID, colorId: WorkspaceColorId) {
        updateWorkspace(id: id) { workspace in
            workspace.colorId = colorId
        }
    }

    func updateWorkspaceBrowserProfile(id: UUID, bundleId: String, profile: String?) {
        let trimmed = profile?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        updateWorkspace(id: id) { workspace in
            if let value {
                workspace.browserProfiles[bundleId] = value
            } else {
                workspace.browserProfiles.removeValue(forKey: bundleId)
            }
        }
    }

    func deleteWorkspace(id: UUID) {
        guard state.workspaces.count > 1 else { return }
        state.workspaces.removeAll { $0.id == id }
        if state.selectedWorkspaceId == id {
            state.selectedWorkspaceId = state.workspaces.first?.id
            if let newId = state.selectedWorkspaceId {
                UserDefaults.standard.set(newId.uuidString, forKey: UserDefaultsKeys.lastSelectedWorkspaceId)
            }
        }
        persist()
    }

    func moveWorkspace(id: UUID, direction: WorkspaceMoveDirection) {
        guard let currentIndex = state.workspaces.firstIndex(where: { $0.id == id }) else { return }

        let newIndex: Int
        switch direction {
        case .left:
            guard currentIndex > 0 else { return }
            newIndex = currentIndex - 1
        case .right:
            guard currentIndex < state.workspaces.count - 1 else { return }
            newIndex = currentIndex + 1
        }

        let workspace = state.workspaces.remove(at: currentIndex)
        state.workspaces.insert(workspace, at: newIndex)
        persist()
    }

    func reorderWorkspace(id: UUID, toIndex: Int) {
        guard let currentIndex = state.workspaces.firstIndex(where: { $0.id == id }) else { return }
        guard toIndex >= 0 && toIndex < state.workspaces.count else { return }
        guard currentIndex != toIndex else { return }

        let workspace = state.workspaces.remove(at: currentIndex)
        state.workspaces.insert(workspace, at: toIndex)
        persist()
    }

    @discardableResult
    func addFolder(name: String, parentId: UUID?, isExpanded: Bool = true) -> UUID {
        addFolder(name: name, workspaceId: currentWorkspace.id, parentId: parentId, isExpanded: isExpanded) ?? UUID()
    }

    @discardableResult
    func addFolder(name: String, workspaceId: UUID, parentId: UUID?, isExpanded: Bool = true) -> UUID? {
        guard state.workspaces.contains(where: { $0.id == workspaceId }) else { return nil }
        let folder = Folder(id: UUID(), name: name, children: [], isExpanded: isExpanded)
        updateWorkspace(id: workspaceId) { workspace in
            insertNode(.folder(folder), parentId: parentId, index: nil, nodes: &workspace.items)
        }
        return folder.id
    }

    @discardableResult
    func addLink(urlString: String, title: String, parentId: UUID?) -> UUID {
        addLink(urlString: urlString, title: title, workspaceId: currentWorkspace.id, parentId: parentId) ?? UUID()
    }

    @discardableResult
    func addLink(urlString: String, title: String, workspaceId: UUID, parentId: UUID?) -> UUID? {
        guard state.workspaces.contains(where: { $0.id == workspaceId }) else { return nil }
        let link = Link(id: UUID(), title: title, url: urlString, faviconPath: nil)
        updateWorkspace(id: workspaceId) { workspace in
            insertNode(.link(link), parentId: parentId, index: nil, nodes: &workspace.items)
        }
        logger.debug("Added link \(title, privacy: .public) -> \(urlString, privacy: .public)")
        return link.id
    }

    @discardableResult
    func addNote(title: String, parentId: UUID?, content: String = "") -> UUID {
        addNote(title: title, workspaceId: currentWorkspace.id, parentId: parentId, content: content) ?? UUID()
    }

    @discardableResult
    func addNote(title: String, workspaceId: UUID, parentId: UUID?, content: String = "") -> UUID? {
        guard state.workspaces.contains(where: { $0.id == workspaceId }) else { return nil }
        let note = Note(id: UUID(), title: title, customIcon: nil)
        try? noteStorage.write(id: note.id, content: content)
        updateWorkspace(id: workspaceId) { workspace in
            insertNode(.note(note), parentId: parentId, index: nil, nodes: &workspace.items)
        }
        return note.id
    }

    func renameNode(id: UUID, newName: String) {
        updateNode(id: id) { node in
            switch node {
            case .folder(var folder):
                folder.name = newName
                node = .folder(folder)
            case .link(var link):
                link.title = newName
                node = .link(link)
            case .note(var note):
                note.title = newName
                node = .note(note)
            }
        }
    }

    func deleteNode(id: UUID) {
        guard let wsId = workspaceIdContaining(nodeId: id) else { return }
        var removed: Node?
        updateWorkspace(id: wsId) { workspace in
            removed = removeNode(id: id, nodes: &workspace.items)
        }
        if let node = removed {
            cleanupFiles(for: node)
        }
    }

    private func cleanupFiles(for node: Node) {
        switch node {
        case .note(let note):
            noteStorage.delete(id: note.id)
        case .link:
            // Favicons are cached per host and shared across every link to
            // that host, so deleting one link must not remove the file.
            break
        case .folder(let folder):
            for child in folder.children {
                cleanupFiles(for: child)
            }
        }
    }

    func moveNode(id: UUID, toParentId: UUID?, index: Int) {
        guard let sourceWsId = workspaceIdContaining(nodeId: id),
              let sourceWs = state.workspaces.first(where: { $0.id == sourceWsId }),
              let location = findNodeLocation(id: id, nodes: sourceWs.items) else { return }
        if let toParentId, isDescendant(nodeId: toParentId, ofAncestor: id, in: sourceWs.items) { return }

        updateWorkspace(id: sourceWsId) { workspace in
            guard let removedNode = removeNode(id: id, nodes: &workspace.items) else { return }

            var targetIndex = max(0, index)
            if location.parentId == toParentId, location.index < targetIndex {
                targetIndex -= 1
            }

            insertNode(removedNode, parentId: toParentId, index: targetIndex, nodes: &workspace.items)
        }
    }

    func moveNodeToWorkspace(id: UUID, workspaceId: UUID) {
        moveNodeToWorkspace(id: id, workspaceId: workspaceId, parentId: nil, index: nil)
    }

    func moveNodeToWorkspace(id: UUID, workspaceId: UUID, parentId: UUID?, index: Int?) {
        guard state.workspaces.contains(where: { $0.id == workspaceId }) else { return }
        guard let sourceWsId = workspaceIdContaining(nodeId: id) else { return }
        guard sourceWsId != workspaceId else {
            // Same-workspace move — delegate to moveNode if a target was provided.
            if let index {
                moveNode(id: id, toParentId: parentId, index: index)
            }
            return
        }
        if let parentId,
           let destWs = state.workspaces.first(where: { $0.id == workspaceId }),
           findNodeLocation(id: parentId, nodes: destWs.items) == nil {
            return
        }

        var removedNode: Node?
        updateWorkspace(id: sourceWsId, notify: false) { workspace in
            removedNode = removeNode(id: id, nodes: &workspace.items)
        }
        guard let node = removedNode else {
            // Restore notification so observers see the no-op revert if any.
            persist()
            return
        }

        updateWorkspace(id: workspaceId) { workspace in
            insertNode(node, parentId: parentId, index: index, nodes: &workspace.items)
        }
    }

    func setFolderExpanded(id: UUID, isExpanded: Bool) {
        updateNode(id: id) { node in
            switch node {
            case .folder(var folder):
                folder.isExpanded = isExpanded
                node = .folder(folder)
            case .link, .note:
                break
            }
        }
    }

    func updateLinkFaviconPath(id: UUID, path: String?) {
        if let node = nodeById(id), case .link(let link) = node, link.faviconPath == path {
            return
        }
        updateNode(id: id) { node in
            switch node {
            case .link(var link):
                link.faviconPath = path
                node = .link(link)
            case .folder, .note:
                break
            }
        }
    }

    func scheduleLink(id: UUID, at date: Date) {
        updateNode(id: id) { node in
            if case .link(var link) = node {
                link.scheduledOpenAt = date
                node = .link(link)
            }
        }
    }

    func cancelSchedule(id: UUID) {
        updateNode(id: id) { node in
            if case .link(var link) = node {
                link.scheduledOpenAt = nil
                node = .link(link)
            }
        }
    }

    func allScheduledLinks() -> [ScheduledLinkRef] {
        var result: [ScheduledLinkRef] = []
        for workspace in state.workspaces {
            collectScheduled(in: workspace.items, workspaceId: workspace.id, into: &result)
        }
        return result
    }

    private func collectScheduled(in nodes: [Node], workspaceId: UUID, into result: inout [ScheduledLinkRef]) {
        for node in nodes {
            switch node {
            case .link(let link):
                if let fireAt = link.scheduledOpenAt {
                    result.append(ScheduledLinkRef(workspaceId: workspaceId, linkId: link.id, url: link.url, fireAt: fireAt))
                }
            case .folder(let folder):
                collectScheduled(in: folder.children, workspaceId: workspaceId, into: &result)
            case .note:
                break
            }
        }
    }

    func updateLinkUrl(id: UUID, newUrl: String) {
        updateNode(id: id) { node in
            switch node {
            case .link(var link):
                link.url = newUrl
                link.faviconPath = nil
                node = .link(link)
            case .folder, .note:
                break
            }
        }
    }

    func updateLinkTitleIfDefault(id: UUID, newTitle: String) -> Bool {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard let node = nodeById(id), case .link(let link) = node else { return false }
        let defaultTitle = URL(string: link.url)?.host ?? link.url
        guard link.title == defaultTitle else { return false }
        guard link.title != trimmed else { return false }

        updateNode(id: id) { node in
            switch node {
            case .link(var link):
                link.title = trimmed
                node = .link(link)
            case .folder, .note:
                break
            }
        }
        logger.debug("Updated title for \(link.url, privacy: .public) -> \(trimmed, privacy: .public)")
        return true
    }

    // MARK: - Pinned Links

    var canPinMore: Bool {
        currentWorkspace.pinnedLinks.count < Workspace.maxPinnedLinks
    }

    func pinnedLinkById(_ id: UUID) -> Link? {
        currentWorkspace.pinnedLinks.first(where: { $0.id == id })
    }

    func pinLink(id: UUID) {
        guard canPinMore else { return }
        guard let node = nodeById(id), case .link(let link) = node else { return }
        guard !currentWorkspace.pinnedLinks.contains(where: { $0.id == id }) else { return }

        updateWorkspace(id: currentWorkspace.id) { workspace in
            _ = removeNode(id: id, nodes: &workspace.items)
            workspace.pinnedLinks.append(link)
        }
    }

    func unpinLink(id: UUID) {
        updateWorkspace(id: currentWorkspace.id) { workspace in
            guard let index = workspace.pinnedLinks.firstIndex(where: { $0.id == id }) else { return }
            let link = workspace.pinnedLinks.remove(at: index)
            workspace.items.append(.link(link))
        }
    }

    func updatePinnedLinkFaviconPath(id: UUID, path: String?) {
        updateWorkspace(id: currentWorkspace.id) { workspace in
            guard let index = workspace.pinnedLinks.firstIndex(where: { $0.id == id }) else { return }
            workspace.pinnedLinks[index].faviconPath = path
        }
    }

    func setLinkCustomIcon(id: UUID, icon: CustomIcon?) {
        updateNode(id: id) { node in
            switch node {
            case .link(var link):
                link.customIcon = icon
                node = .link(link)
            case .folder, .note:
                break
            }
        }
    }

    func setNoteCustomIcon(id: UUID, icon: CustomIcon?) {
        updateNode(id: id) { node in
            switch node {
            case .note(var note):
                note.customIcon = icon
                node = .note(note)
            case .folder, .link:
                break
            }
        }
    }

    func setPinnedLinkCustomIcon(id: UUID, icon: CustomIcon?) {
        updateWorkspace(id: currentWorkspace.id) { workspace in
            guard let index = workspace.pinnedLinks.firstIndex(where: { $0.id == id }) else { return }
            workspace.pinnedLinks[index].customIcon = icon
        }
    }

    func location(of nodeId: UUID) -> NodeLocation? {
        findNodeLocation(id: nodeId, nodes: currentWorkspace.items)
    }

    func nodeById(_ id: UUID) -> Node? {
        nodeById(id, nodes: currentWorkspace.items)
    }

    func nodeAcrossWorkspaces(id: UUID) -> Node? {
        for workspace in state.workspaces {
            if let node = nodeById(id, nodes: workspace.items) {
                return node
            }
        }
        return nil
    }

    func workspaceId(forNodeId id: UUID) -> UUID? {
        workspaceIdContaining(nodeId: id)
    }

    func findNode(id: UUID, in nodes: [Node]) -> Node? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if case .folder(let folder) = node,
               let found = findNode(id: id, in: folder.children) {
                return found
            }
        }
        return nil
    }

    func moveNodesToWorkspace(nodeIds: [UUID], toWorkspaceId: UUID) {
        guard toWorkspaceId != currentWorkspace.id else { return }
        guard !nodeIds.isEmpty else { return }

        var nodesToMove: [Node] = []

        updateWorkspace(id: currentWorkspace.id, notify: false) { workspace in
            for nodeId in nodeIds {
                if let removed = removeNode(id: nodeId, nodes: &workspace.items) {
                    nodesToMove.append(removed)
                }
            }
        }

        updateWorkspace(id: toWorkspaceId) { workspace in
            workspace.items.append(contentsOf: nodesToMove)
        }
    }

    @discardableResult
    func groupNodesInNewFolder(nodeIds: [UUID], folderName: String) -> UUID? {
        guard !nodeIds.isEmpty else { return nil }

        // Find locations BEFORE removal to determine correct insertion point
        let locations = nodeIds.compactMap { findNodeLocation(id: $0, nodes: currentWorkspace.items) }

        // Determine common parent — if all selected nodes share the same parent, use it
        let parentIds = Set(locations.map { $0.parentId })
        let commonParentId: UUID? = parentIds.count == 1 ? parentIds.first! : nil

        // Insertion index: earliest position among selected nodes in the common parent
        let insertionIndex: Int? = parentIds.count == 1 ? locations.map { $0.index }.min() : nil

        var nodesToGroup: [Node] = []

        updateWorkspace(id: currentWorkspace.id, notify: false) { workspace in
            for nodeId in nodeIds {
                if let removed = removeNode(id: nodeId, nodes: &workspace.items) {
                    nodesToGroup.append(removed)
                }
            }
        }

        guard !nodesToGroup.isEmpty else { return nil }

        let folder = Folder(id: UUID(), name: folderName, children: nodesToGroup, isExpanded: true)

        updateWorkspace(id: currentWorkspace.id) { workspace in
            insertNode(.folder(folder), parentId: commonParentId, index: insertionIndex, nodes: &workspace.items)
        }

        return folder.id
    }

    private func insertNode(_ node: Node, parentId: UUID?) {
        updateWorkspace(id: currentWorkspace.id) { workspace in
            insertNode(node, parentId: parentId, index: nil, nodes: &workspace.items)
        }
    }

    private func updateWorkspace(id: UUID, notify: Bool = true, _ mutate: (inout Workspace) -> Void) {
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return }
        mutate(&state.workspaces[index])
        persist(notify: notify)
    }

    private func updateNode(id: UUID, notify: Bool = true, _ mutate: (inout Node) -> Void) {
        guard let wsId = workspaceIdContaining(nodeId: id) else { return }
        updateWorkspace(id: wsId, notify: notify) { workspace in
            _ = updateNode(id: id, nodes: &workspace.items, mutate)
        }
    }

    private func persist(notify: Bool = true) {
        store.save(state)
        if notify {
            onChange?()
        }
    }

    private func insertNode(_ node: Node, parentId: UUID?, index: Int?, nodes: inout [Node]) {
        if let parentId {
            for i in nodes.indices {
                switch nodes[i] {
                case .folder(var folder):
                    if folder.id == parentId {
                        if let index {
                            let idx = max(0, min(index, folder.children.count))
                            folder.children.insert(node, at: idx)
                        } else {
                            folder.children.append(node)
                        }
                        nodes[i] = .folder(folder)
                        return
                    }
                    insertNode(node, parentId: parentId, index: index, nodes: &folder.children)
                    nodes[i] = .folder(folder)
                case .link, .note:
                    continue
                }
            }
        } else {
            if let index {
                let idx = max(0, min(index, nodes.count))
                nodes.insert(node, at: idx)
            } else {
                nodes.append(node)
            }
        }
    }

    private func updateNode(id: UUID, nodes: inout [Node], _ mutate: (inout Node) -> Void) -> Bool {
        for index in nodes.indices {
            switch nodes[index] {
            case .link(let link):
                if link.id == id {
                    var node = nodes[index]
                    mutate(&node)
                    nodes[index] = node
                    return true
                }
            case .note(let note):
                if note.id == id {
                    var node = nodes[index]
                    mutate(&node)
                    nodes[index] = node
                    return true
                }
            case .folder(var folder):
                if folder.id == id {
                    var node = nodes[index]
                    mutate(&node)
                    nodes[index] = node
                    return true
                }
                if updateNode(id: id, nodes: &folder.children, mutate) {
                    nodes[index] = .folder(folder)
                    return true
                }
            }
        }
        return false
    }

    private func removeNode(id: UUID, nodes: inout [Node]) -> Node? {
        for index in nodes.indices {
            switch nodes[index] {
            case .link(let link):
                if link.id == id {
                    return nodes.remove(at: index)
                }
            case .note(let note):
                if note.id == id {
                    return nodes.remove(at: index)
                }
            case .folder(var folder):
                if folder.id == id {
                    return nodes.remove(at: index)
                }
                if let removed = removeNode(id: id, nodes: &folder.children) {
                    nodes[index] = .folder(folder)
                    return removed
                }
            }
        }
        return nil
    }

    private func findNodeLocation(id: UUID, nodes: [Node], parentId: UUID? = nil) -> NodeLocation? {
        for (index, node) in nodes.enumerated() {
            switch node {
            case .link(let link):
                if link.id == id {
                    return NodeLocation(parentId: parentId, index: index)
                }
            case .note(let note):
                if note.id == id {
                    return NodeLocation(parentId: parentId, index: index)
                }
            case .folder(let folder):
                if folder.id == id {
                    return NodeLocation(parentId: parentId, index: index)
                }
                if let location = findNodeLocation(id: id, nodes: folder.children, parentId: folder.id) {
                    return location
                }
            }
        }
        return nil
    }

    private func isDescendant(nodeId: UUID, in potentialAncestorId: UUID) -> Bool {
        guard let ancestor = nodeById(potentialAncestorId, nodes: currentWorkspace.items) else { return false }
        return containsNode(nodeId, within: ancestor)
    }

    private func isDescendant(nodeId: UUID, ofAncestor ancestorId: UUID, in nodes: [Node]) -> Bool {
        guard let ancestor = nodeById(ancestorId, nodes: nodes) else { return false }
        return containsNode(nodeId, within: ancestor)
    }

    private func workspaceIdContaining(nodeId: UUID) -> UUID? {
        for workspace in state.workspaces {
            if findNodeLocation(id: nodeId, nodes: workspace.items) != nil {
                return workspace.id
            }
        }
        return nil
    }

    private func nodeById(_ id: UUID, nodes: [Node]) -> Node? {
        for node in nodes {
            switch node {
            case .link(let link):
                if link.id == id { return node }
            case .note(let note):
                if note.id == id { return node }
            case .folder(let folder):
                if folder.id == id { return node }
                if let found = nodeById(id, nodes: folder.children) {
                    return found
                }
            }
        }
        return nil
    }

    private func containsNode(_ id: UUID, within node: Node) -> Bool {
        switch node {
        case .link(let link):
            return link.id == id
        case .note(let note):
            return note.id == id
        case .folder(let folder):
            if folder.id == id { return true }
            return folder.children.contains(where: { containsNode(id, within: $0) })
        }
    }
}
