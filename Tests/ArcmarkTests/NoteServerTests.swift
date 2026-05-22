import XCTest
@testable import ArcmarkCore

@MainActor
final class NoteServerTests: XCTestCase {
    private func makeStore() -> DataStore {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return DataStore(baseDirectory: temp)
    }

    private func startServer() async throws -> (NoteServer, AppModel) {
        let store = makeStore()
        store.save(DataStore.defaultState())
        let model = AppModel(store: store)
        let server = NoteServer(model: model)
        server.start()

        // Wait briefly for the listener to enter .ready
        for _ in 0..<50 {
            if server.port > 0 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertGreaterThan(server.port, 0, "Server did not bind to a port")
        return (server, model)
    }

    private func request(method: String, path: String, host: String? = nil, body: Data? = nil, port: UInt16) async throws -> (status: Int, body: Data) {
        var url = URLComponents()
        url.scheme = "http"
        url.host = "127.0.0.1"
        url.port = Int(port)
        url.path = path.components(separatedBy: "?").first ?? path
        if let q = path.components(separatedBy: "?").dropFirst().first {
            url.percentEncodedQuery = q
        }
        var request = URLRequest(url: url.url!)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let host {
            request.setValue(host, forHTTPHeaderField: "Host")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        return (httpResponse.statusCode, data)
    }

    func testServerStartsOnEphemeralPort() async throws {
        let (server, _) = try await startServer()
        defer { server.stop() }
        XCTAssertGreaterThan(server.port, 0)
    }

    func testGetReturnsNoteJSON() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        let noteId = model.addNote(title: "Server Test", parentId: nil)

        let (status, body) = try await request(
            method: "GET",
            path: "/api/notes/\(noteId.uuidString)",
            port: server.port
        )
        XCTAssertEqual(status, 200)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["title"] as? String, "Server Test")
        XCTAssertTrue((json?["content"] as? String ?? "").contains("# Untitled"))
    }

    func testGetReturns404WhenNoteDeleted() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        let noteId = model.addNote(title: "Doomed", parentId: nil)
        model.deleteNode(id: noteId)

        let (status, _) = try await request(
            method: "GET",
            path: "/api/notes/\(noteId.uuidString)",
            port: server.port
        )
        XCTAssertEqual(status, 404)
    }

    func testPutReturns404WhenNoteDeleted() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        let noteId = model.addNote(title: "Doomed", parentId: nil)
        model.deleteNode(id: noteId)

        let body = try JSONSerialization.data(withJSONObject: ["content": "should not write"])
        let (status, _) = try await request(
            method: "PUT",
            path: "/api/notes/\(noteId.uuidString)",
            body: body,
            port: server.port
        )
        XCTAssertEqual(status, 404)
        XCTAssertEqual(model.noteStorage.read(id: noteId), "")
    }

    func testPutWritesContent() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        let noteId = model.addNote(title: "Writable", parentId: nil)

        let body = try JSONSerialization.data(withJSONObject: ["content": "## Updated"])
        let (status, _) = try await request(
            method: "PUT",
            path: "/api/notes/\(noteId.uuidString)",
            body: body,
            port: server.port
        )
        XCTAssertEqual(status, 200)
        XCTAssertEqual(model.noteStorage.read(id: noteId), "## Updated")
    }

    // MARK: - Agent API round-trips

    private func apiRequest(
        _ method: String,
        _ path: String,
        body: [String: Any]? = nil,
        port: UInt16
    ) async throws -> (status: Int, json: [String: Any]) {
        let data = body.map { try? JSONSerialization.data(withJSONObject: $0) } ?? nil
        let (status, raw) = try await request(method: method, path: path, body: data ?? nil, port: port)
        let parsed = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] ?? [:]
        return (status, parsed)
    }

    func testWorkspaceRoundTrip() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }

        let (createStatus, createJson) = try await apiRequest(
            "POST", "/api/workspaces",
            body: ["name": "Reading", "colorId": "leaf"],
            port: server.port
        )
        XCTAssertEqual(createStatus, 200)
        XCTAssertEqual(createJson["ok"] as? Bool, true)
        let id = try XCTUnwrap(createJson["id"] as? String)
        let uuid = try XCTUnwrap(UUID(uuidString: id))
        XCTAssertTrue(model.workspaces.contains(where: { $0.id == uuid }))

        let (renameStatus, _) = try await apiRequest(
            "PATCH", "/api/workspaces/\(id)",
            body: ["name": "Reading List"],
            port: server.port
        )
        XCTAssertEqual(renameStatus, 200)
        XCTAssertEqual(model.workspaces.first(where: { $0.id == uuid })?.name, "Reading List")
    }

    func testFolderRoundTrip() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        let wsId = try XCTUnwrap(model.workspaces.first?.id).uuidString

        let (createStatus, createJson) = try await apiRequest(
            "POST", "/api/folders",
            body: ["workspace_id": wsId, "name": "Inbox"],
            port: server.port
        )
        XCTAssertEqual(createStatus, 200)
        let id = try XCTUnwrap(createJson["id"] as? String)
        let uuid = try XCTUnwrap(UUID(uuidString: id))

        let node = try XCTUnwrap(model.nodeAcrossWorkspaces(id: uuid))
        guard case .folder(let folder) = node else { return XCTFail("Expected folder") }
        XCTAssertEqual(folder.name, "Inbox")

        let (renameStatus, _) = try await apiRequest(
            "PATCH", "/api/folders/\(id)",
            body: ["name": "Triage", "expanded": false],
            port: server.port
        )
        XCTAssertEqual(renameStatus, 200)
        if case .folder(let updated) = try XCTUnwrap(model.nodeAcrossWorkspaces(id: uuid)) {
            XCTAssertEqual(updated.name, "Triage")
            XCTAssertFalse(updated.isExpanded)
        } else {
            XCTFail("Expected folder after rename")
        }
    }

    func testLinkRoundTrip() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        let wsId = try XCTUnwrap(model.workspaces.first?.id).uuidString

        let (status, createJson) = try await apiRequest(
            "POST", "/api/links",
            body: ["workspace_id": wsId, "url": "https://anthropic.com", "title": "Anthropic"],
            port: server.port
        )
        XCTAssertEqual(status, 200)
        let id = try XCTUnwrap(createJson["id"] as? String)
        let uuid = try XCTUnwrap(UUID(uuidString: id))
        guard case .link(let link) = try XCTUnwrap(model.nodeAcrossWorkspaces(id: uuid)) else {
            return XCTFail("Expected link")
        }
        XCTAssertEqual(link.url, "https://anthropic.com")
        XCTAssertEqual(link.title, "Anthropic")

        let (patchStatus, _) = try await apiRequest(
            "PATCH", "/api/links/\(id)",
            body: ["title": "Anthropic AI", "url": "https://www.anthropic.com"],
            port: server.port
        )
        XCTAssertEqual(patchStatus, 200)
        if case .link(let updated) = try XCTUnwrap(model.nodeAcrossWorkspaces(id: uuid)) {
            XCTAssertEqual(updated.title, "Anthropic AI")
            XCTAssertEqual(updated.url, "https://www.anthropic.com")
        } else {
            XCTFail("Expected link after patch")
        }
    }

    func testNoteRoundTrip() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        let wsId = try XCTUnwrap(model.workspaces.first?.id).uuidString

        let (status, createJson) = try await apiRequest(
            "POST", "/api/notes",
            body: ["workspace_id": wsId, "title": "Plan", "content": "# Hello"],
            port: server.port
        )
        XCTAssertEqual(status, 200)
        let id = try XCTUnwrap(createJson["id"] as? String)
        let uuid = try XCTUnwrap(UUID(uuidString: id))
        XCTAssertEqual(model.noteStorage.read(id: uuid), "# Hello")

        let (renameStatus, _) = try await apiRequest(
            "PATCH", "/api/notes/\(id)",
            body: ["title": "Renamed"],
            port: server.port
        )
        XCTAssertEqual(renameStatus, 200)
        if case .note(let note) = try XCTUnwrap(model.nodeAcrossWorkspaces(id: uuid)) {
            XCTAssertEqual(note.title, "Renamed")
        } else {
            XCTFail("Expected note after patch")
        }
    }

    func testMoveAcrossWorkspaces() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        let sourceWsId = try XCTUnwrap(model.workspaces.first?.id)
        let destWsId = model.createWorkspace(name: "Other", colorId: .moss)

        // Note: createWorkspace also flips selectedWorkspaceId. Re-select source
        // so addLink without explicit workspaceId would still go there if used,
        // but we use the explicit workspaceId variant via the API for safety.
        model.selectWorkspace(id: sourceWsId)

        let (_, createJson) = try await apiRequest(
            "POST", "/api/links",
            body: ["workspace_id": sourceWsId.uuidString, "url": "https://example.com"],
            port: server.port
        )
        let linkId = try XCTUnwrap(createJson["id"] as? String)
        let linkUUID = try XCTUnwrap(UUID(uuidString: linkId))

        let (moveStatus, moveJson) = try await apiRequest(
            "POST", "/api/nodes/\(linkId)/move",
            body: ["to_workspace_id": destWsId.uuidString],
            port: server.port
        )
        XCTAssertEqual(moveStatus, 200)
        XCTAssertEqual(moveJson["ok"] as? Bool, true)

        XCTAssertEqual(model.workspaceId(forNodeId: linkUUID), destWsId)
    }

    func testDeleteNode() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        let wsId = try XCTUnwrap(model.workspaces.first?.id).uuidString

        let (_, createJson) = try await apiRequest(
            "POST", "/api/notes",
            body: ["workspace_id": wsId, "title": "Doomed", "content": "bye"],
            port: server.port
        )
        let id = try XCTUnwrap(createJson["id"] as? String)
        let uuid = try XCTUnwrap(UUID(uuidString: id))
        XCTAssertNotNil(model.nodeAcrossWorkspaces(id: uuid))

        let (status, _) = try await apiRequest(
            "DELETE", "/api/nodes/\(id)",
            port: server.port
        )
        XCTAssertEqual(status, 200)
        XCTAssertNil(model.nodeAcrossWorkspaces(id: uuid))
        // The note .md file is cleaned up by deleteNode.
        XCTAssertEqual(model.noteStorage.read(id: uuid), "")
    }

    func testStateAndTreeEndpoints() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        let wsId = try XCTUnwrap(model.workspaces.first?.id).uuidString

        let (stateStatus, stateJson) = try await apiRequest("GET", "/api/state", port: server.port)
        XCTAssertEqual(stateStatus, 200)
        XCTAssertEqual(stateJson["ok"] as? Bool, true)
        XCTAssertNotNil(stateJson["state"])

        let (treeStatus, treeJson) = try await apiRequest("GET", "/api/workspaces/\(wsId)/tree", port: server.port)
        XCTAssertEqual(treeStatus, 200)
        XCTAssertNotNil(treeJson["workspace"])
    }

    func testCurrentWorkspaceReturnsSelected() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        let wsId = try XCTUnwrap(model.workspaces.first?.id)
        model.selectWorkspace(id: wsId)

        let (status, json) = try await apiRequest("GET", "/api/workspaces/current", port: server.port)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(json["selected"] as? Bool, true)
        XCTAssertEqual(json["settingsSelected"] as? Bool, false)
        let workspace = try XCTUnwrap(json["workspace"] as? [String: Any])
        XCTAssertEqual(workspace["id"] as? String, wsId.uuidString)
    }

    func testCurrentWorkspaceReportsSettings() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        model.selectSettings()

        let (status, json) = try await apiRequest("GET", "/api/workspaces/current", port: server.port)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(json["selected"] as? Bool, false)
        XCTAssertEqual(json["settingsSelected"] as? Bool, true)
        XCTAssertTrue(json["workspace"] is NSNull)
    }

    func testCreateWorkspaceRejectsUnknownColor() async throws {
        // Bind `model` so NoteServer's weak reference stays alive.
        let (server, model) = try await startServer()
        defer { server.stop() }
        _ = model
        let (status, json) = try await apiRequest(
            "POST", "/api/workspaces",
            body: ["name": "X", "colorId": "puce"],
            port: server.port
        )
        XCTAssertEqual(status, 400)
        XCTAssertEqual(json["code"] as? String, "bad_color")
    }

    func testNoDeleteWorkspaceRoute() async throws {
        let (server, model) = try await startServer()
        defer { server.stop() }
        let wsId = try XCTUnwrap(model.workspaces.first?.id).uuidString
        let (status, _) = try await apiRequest(
            "DELETE", "/api/workspaces/\(wsId)",
            port: server.port
        )
        XCTAssertEqual(status, 404)
    }
}
