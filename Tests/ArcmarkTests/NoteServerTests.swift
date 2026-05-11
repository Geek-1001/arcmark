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
}
