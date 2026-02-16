import XCTest
@testable import ArcmarkCore

final class ModelTests: XCTestCase {
    private func makeStore() -> DataStore {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return DataStore(baseDirectory: temp)
    }

    func testJSONRoundTrip() throws {
        let link = Link(id: UUID(), title: "Example", url: "https://example.com", faviconPath: nil)
        let folder = Folder(id: UUID(), name: "Folder", children: [.link(link)], isExpanded: true)
        let workspace = Workspace(id: UUID(), name: "Inbox", colorId: .ember, items: [.folder(folder)])
        let state = AppState(schemaVersion: 1, workspaces: [workspace], selectedWorkspaceId: workspace.id, isSettingsSelected: false)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppState.self, from: data)
        XCTAssertEqual(state, decoded)
    }

    func testMoveNodeReorderAndNest() {
        let store = makeStore()
        store.save(DataStore.defaultState())
        let model = AppModel(store: store)

        model.addFolder(name: "Folder", parentId: nil)
        model.addLink(urlString: "https://a.com", title: "A", parentId: nil)
        model.addLink(urlString: "https://b.com", title: "B", parentId: nil)

        guard
            let folderId = model.currentWorkspace.items.compactMap({
                if case .folder(let folder) = $0 { return folder.id }
                return nil
            }).first,
            let linkAId = model.currentWorkspace.items.compactMap({
                if case .link(let link) = $0, link.title == "A" { return link.id }
                return nil
            }).first
        else {
            XCTFail("Expected nodes to exist")
            return
        }

        model.moveNode(id: linkAId, toParentId: folderId, index: 0)
        let location = model.location(of: linkAId)
        XCTAssertEqual(location?.parentId, folderId)

        if let folderNode = model.nodeById(folderId), case .folder(let folder) = folderNode {
            XCTAssertEqual(folder.children.count, 1)
        } else {
            XCTFail("Expected folder to contain moved link")
        }

        if let linkBId = model.currentWorkspace.items.compactMap({
            if case .link(let link) = $0, link.title == "B" { return link.id }
            return nil
        }).first {
            model.moveNode(id: linkBId, toParentId: nil, index: 0)
            let locationB = model.location(of: linkBId)
            XCTAssertEqual(locationB?.parentId, nil)
            XCTAssertEqual(locationB?.index, 0)
        }
    }

    func testWorkspaceScopedFiltering() {
        let link1 = Link(id: UUID(), title: "Docs", url: "https://docs.com", faviconPath: nil)
        let link2 = Link(id: UUID(), title: "Blog", url: "https://blog.com", faviconPath: nil)
        let folder = Folder(id: UUID(), name: "Reading", children: [.link(link2)], isExpanded: false)
        let nodes: [Node] = [.link(link1), .folder(folder)]

        let results = NodeFiltering.filter(nodes: nodes, query: "blog")
        XCTAssertEqual(results.count, 1)
        if case .folder(let filteredFolder) = results[0] {
            XCTAssertEqual(filteredFolder.children.count, 1)
        } else {
            XCTFail("Expected folder to remain for matching child")
        }
    }

    func testWorkspaceReordering() {
        let store = makeStore()
        store.save(DataStore.defaultState())
        let model = AppModel(store: store)

        // Create three workspaces
        let id1 = model.createWorkspace(name: "First", colorId: .ember)
        let id2 = model.createWorkspace(name: "Second", colorId: .ruby)
        let id3 = model.createWorkspace(name: "Third", colorId: .moss)

        // Initial order should be: Inbox (default), First, Second, Third
        XCTAssertEqual(model.workspaces.count, 4)
        XCTAssertEqual(model.workspaces[0].name, "Inbox")
        XCTAssertEqual(model.workspaces[1].name, "First")
        XCTAssertEqual(model.workspaces[2].name, "Second")
        XCTAssertEqual(model.workspaces[3].name, "Third")

        // Move "Second" to the right (swap with "Third")
        model.moveWorkspace(id: id2, direction: .right)
        XCTAssertEqual(model.workspaces[2].name, "Third")
        XCTAssertEqual(model.workspaces[3].name, "Second")

        // Move "Second" to the left (swap back with "Third")
        model.moveWorkspace(id: id2, direction: .left)
        XCTAssertEqual(model.workspaces[2].name, "Second")
        XCTAssertEqual(model.workspaces[3].name, "Third")

        // Move "First" to the left (swap with "Inbox")
        model.moveWorkspace(id: id1, direction: .left)
        XCTAssertEqual(model.workspaces[0].name, "First")
        XCTAssertEqual(model.workspaces[1].name, "Inbox")

        // Try to move "First" to the left again (should not move, already at start)
        model.moveWorkspace(id: id1, direction: .left)
        XCTAssertEqual(model.workspaces[0].name, "First")
        XCTAssertEqual(model.workspaces[1].name, "Inbox")

        // Try to move "Third" to the right (should not move, already at end)
        model.moveWorkspace(id: id3, direction: .right)
        XCTAssertEqual(model.workspaces[2].name, "Second")
        XCTAssertEqual(model.workspaces[3].name, "Third")
    }

    // MARK: - Pinned Links Tests

    func testPinLink() {
        let store = makeStore()
        store.save(DataStore.defaultState())
        let model = AppModel(store: store)

        let linkId = model.addLink(urlString: "https://a.com", title: "A", parentId: nil)
        XCTAssertEqual(model.currentWorkspace.items.count, 1)
        XCTAssertEqual(model.currentWorkspace.pinnedLinks.count, 0)

        model.pinLink(id: linkId)
        XCTAssertEqual(model.currentWorkspace.items.count, 0)
        XCTAssertEqual(model.currentWorkspace.pinnedLinks.count, 1)
        XCTAssertEqual(model.currentWorkspace.pinnedLinks[0].id, linkId)
        XCTAssertEqual(model.currentWorkspace.pinnedLinks[0].title, "A")
    }

    func testUnpinLink() {
        let store = makeStore()
        store.save(DataStore.defaultState())
        let model = AppModel(store: store)

        let linkId = model.addLink(urlString: "https://a.com", title: "A", parentId: nil)
        model.pinLink(id: linkId)
        XCTAssertEqual(model.currentWorkspace.pinnedLinks.count, 1)
        XCTAssertEqual(model.currentWorkspace.items.count, 0)

        model.unpinLink(id: linkId)
        XCTAssertEqual(model.currentWorkspace.pinnedLinks.count, 0)
        XCTAssertEqual(model.currentWorkspace.items.count, 1)
        if case .link(let link) = model.currentWorkspace.items.last {
            XCTAssertEqual(link.id, linkId)
            XCTAssertEqual(link.title, "A")
        } else {
            XCTFail("Expected link at root level after unpin")
        }
    }

    func testPinLinkMaximum() {
        let store = makeStore()
        store.save(DataStore.defaultState())
        let model = AppModel(store: store)

        var linkIds: [UUID] = []
        for i in 0..<10 {
            let id = model.addLink(urlString: "https://\(i).com", title: "Link \(i)", parentId: nil)
            linkIds.append(id)
        }

        // Pin 9 links (the maximum)
        for i in 0..<9 {
            model.pinLink(id: linkIds[i])
        }
        XCTAssertEqual(model.currentWorkspace.pinnedLinks.count, 9)
        XCTAssertEqual(model.currentWorkspace.items.count, 1)
        XCTAssertFalse(model.canPinMore)

        // Attempt to pin the 10th - should be rejected
        model.pinLink(id: linkIds[9])
        XCTAssertEqual(model.currentWorkspace.pinnedLinks.count, 9)
        XCTAssertEqual(model.currentWorkspace.items.count, 1)
    }

    func testPinLinkFromNestedFolder() {
        let store = makeStore()
        store.save(DataStore.defaultState())
        let model = AppModel(store: store)

        let folderId = model.addFolder(name: "Folder", parentId: nil)
        let linkId = model.addLink(urlString: "https://nested.com", title: "Nested", parentId: folderId)

        if let folderNode = model.nodeById(folderId), case .folder(let folder) = folderNode {
            XCTAssertEqual(folder.children.count, 1)
        }

        model.pinLink(id: linkId)
        XCTAssertEqual(model.currentWorkspace.pinnedLinks.count, 1)
        XCTAssertEqual(model.currentWorkspace.pinnedLinks[0].title, "Nested")

        // Verify link was removed from the folder
        if let folderNode = model.nodeById(folderId), case .folder(let folder) = folderNode {
            XCTAssertEqual(folder.children.count, 0)
        } else {
            XCTFail("Expected folder to still exist")
        }
    }

    func testCannotPinFolder() {
        let store = makeStore()
        store.save(DataStore.defaultState())
        let model = AppModel(store: store)

        let folderId = model.addFolder(name: "Folder", parentId: nil)
        model.pinLink(id: folderId)
        XCTAssertEqual(model.currentWorkspace.pinnedLinks.count, 0)
        XCTAssertEqual(model.currentWorkspace.items.count, 1)
    }

    func testJSONRoundTripWithPinnedLinks() throws {
        let link = Link(id: UUID(), title: "Pinned", url: "https://pinned.com", faviconPath: nil)
        let treeLink = Link(id: UUID(), title: "Tree", url: "https://tree.com", faviconPath: nil)
        let workspace = Workspace(
            id: UUID(),
            name: "Test",
            colorId: .ember,
            items: [.link(treeLink)],
            pinnedLinks: [link]
        )
        let state = AppState(schemaVersion: 1, workspaces: [workspace], selectedWorkspaceId: workspace.id, isSettingsSelected: false)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AppState.self, from: data)

        XCTAssertEqual(decoded.workspaces[0].pinnedLinks.count, 1)
        XCTAssertEqual(decoded.workspaces[0].pinnedLinks[0].title, "Pinned")
        XCTAssertEqual(decoded.workspaces[0].items.count, 1)
        XCTAssertEqual(state, decoded)
    }

    func testBackwardCompatibilityNoPinnedLinks() throws {
        // Simulate old JSON format without pinnedLinks field
        let json = """
        {
            "schemaVersion": 1,
            "workspaces": [{
                "id": "00000000-0000-0000-0000-000000000001",
                "name": "Old Workspace",
                "colorId": "ember",
                "items": []
            }],
            "selectedWorkspaceId": "00000000-0000-0000-0000-000000000001",
            "isSettingsSelected": false
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppState.self, from: data)

        XCTAssertEqual(decoded.workspaces[0].pinnedLinks.count, 0)
        XCTAssertEqual(decoded.workspaces[0].name, "Old Workspace")
    }
}
