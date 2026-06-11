import Foundation
import Network
import os

/// Minimal loopback-only HTTP server that backs the bundled markdown note editor.
///
/// Binds to 127.0.0.1 on a system-assigned ephemeral port and rejects requests
/// whose Host header doesn't match 127.0.0.1:<port> (DNS rebinding defense).
@MainActor
final class NoteServer {
    private let logger = Logger(subsystem: "com.arcmark.app", category: "noteserver")
    private weak var model: AppModel?
    private let noteStorage: NoteStorage
    private let resourcesURL: URL?

    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    init(model: AppModel, resourcesURL: URL? = NoteServer.resolveBundledResourcesURL()) {
        self.model = model
        self.noteStorage = model.noteStorage
        self.resourcesURL = resourcesURL
        if resourcesURL == nil {
            logger.error("NoteServer could not locate bundled editor resources; note editor will be unavailable")
        }
    }

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
            let newListener = try NWListener(using: parameters)

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.handleConnection(connection)
                }
            }

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let p = newListener.port {
                        MainActor.assumeIsolated {
                            self.port = p.rawValue
                            self.logger.debug("NoteServer ready on 127.0.0.1:\(p.rawValue, privacy: .public)")
                        }
                    }
                case .failed(let error):
                    self.logger.error("NoteServer failed: \(String(describing: error), privacy: .public)")
                default:
                    break
                }
            }

            newListener.start(queue: .main)
            self.listener = newListener
        } catch {
            logger.error("NoteServer start failed: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    func editorURL(noteId: UUID) -> URL? {
        guard port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/?id=\(noteId.uuidString)")
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            MainActor.assumeIsolated {
                var buffer = accumulated
                if let data, !data.isEmpty {
                    buffer.append(data)
                }

                if let request = self.tryParseRequest(buffer: buffer) {
                    self.respond(to: request, on: connection)
                    return
                }

                if isComplete || error != nil {
                    connection.cancel()
                    return
                }

                self.receive(on: connection, accumulated: buffer)
            }
        }
    }

    // MARK: - HTTP parsing

    private struct ParsedRequest {
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: Data
    }

    private func tryParseRequest(buffer: Data) -> ParsedRequest? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        var lines = headerString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst()
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let method = parts[0]
        let target = parts[1]

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        // Treat malformed or negative Content-Length as zero so the body
        // slice below cannot be inverted (which would trap).
        let contentLength = max(0, Int(headers["content-length"] ?? "0") ?? 0)
        let bodyStart = headerEnd.upperBound
        let bodyAvailable = buffer.count - bodyStart
        if bodyAvailable < contentLength {
            return nil
        }

        let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))

        let (path, query) = Self.splitTarget(target)
        return ParsedRequest(method: method, path: path, query: query, headers: headers, body: body)
    }

    private static func splitTarget(_ target: String) -> (String, [String: String]) {
        guard let qIndex = target.firstIndex(of: "?") else {
            return (target, [:])
        }
        let path = String(target[..<qIndex])
        let queryString = String(target[target.index(after: qIndex)...])
        var dict: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            let key = parts.first?.removingPercentEncoding ?? ""
            let value = (parts.count > 1 ? parts[1] : "").removingPercentEncoding ?? ""
            if !key.isEmpty {
                dict[key] = value
            }
        }
        return (path, dict)
    }

    // MARK: - Routing

    private func respond(to request: ParsedRequest, on connection: NWConnection) {
        // Host header check
        let expectedHost = "127.0.0.1:\(port)"
        let host = request.headers["host"] ?? ""
        if host != expectedHost {
            sendStatus(400, message: "Bad Host", on: connection)
            return
        }

        if request.method == "GET" && request.path == "/favicon.ico" {
            sendResponse(status: 204, statusMessage: "No Content", contentType: "image/x-icon", body: Data(), on: connection)
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            serveIndexHTML(on: connection)
        case ("GET", let path) where path.hasPrefix("/editor/"):
            let relative = String(path.dropFirst("/editor/".count))
            serveEditorAsset(relative: relative, on: connection)

        // State / queries
        case ("GET", "/api/state"):
            handleGetState(on: connection)
        case ("GET", "/api/workspaces"):
            handleListWorkspaces(on: connection)
        case ("GET", "/api/workspaces/current"):
            handleCurrentWorkspace(on: connection)
        case ("GET", let path) where path.hasPrefix("/api/workspaces/") && path.hasSuffix("/tree"):
            let middle = path.dropFirst("/api/workspaces/".count).dropLast("/tree".count)
            handleWorkspaceTree(idString: String(middle), on: connection)

        // Workspaces
        case ("POST", "/api/workspaces"):
            handleCreateWorkspace(body: request.body, on: connection)
        case ("PATCH", let path) where path.hasPrefix("/api/workspaces/"):
            let idString = String(path.dropFirst("/api/workspaces/".count))
            handlePatchWorkspace(idString: idString, body: request.body, on: connection)

        // Folders
        case ("POST", "/api/folders"):
            handleCreateFolder(body: request.body, on: connection)
        case ("PATCH", let path) where path.hasPrefix("/api/folders/"):
            let idString = String(path.dropFirst("/api/folders/".count))
            handlePatchFolder(idString: idString, body: request.body, on: connection)

        // Links
        case ("POST", "/api/links"):
            handleCreateLink(body: request.body, on: connection)
        case ("PATCH", let path) where path.hasPrefix("/api/links/"):
            let idString = String(path.dropFirst("/api/links/".count))
            handlePatchLink(idString: idString, body: request.body, on: connection)

        // Notes — create + metadata patch. Content read/write stays on the
        // existing GET/PUT routes below, shared with the bundled editor.
        case ("POST", "/api/notes"):
            handleCreateNote(body: request.body, on: connection)
        case ("PATCH", let path) where path.hasPrefix("/api/notes/"):
            let idString = String(path.dropFirst("/api/notes/".count))
            handlePatchNote(idString: idString, body: request.body, on: connection)
        case ("GET", let path) where path.hasPrefix("/api/notes/"):
            let idString = String(path.dropFirst("/api/notes/".count))
            handleGetNote(idString: idString, on: connection)
        case ("PUT", let path) where path.hasPrefix("/api/notes/"):
            let idString = String(path.dropFirst("/api/notes/".count))
            handlePutNote(idString: idString, body: request.body, on: connection)

        // Generic node ops
        case ("DELETE", let path) where path.hasPrefix("/api/nodes/"):
            let idString = String(path.dropFirst("/api/nodes/".count))
            handleDeleteNode(idString: idString, on: connection)
        case ("POST", let path) where path.hasPrefix("/api/nodes/") && path.hasSuffix("/move"):
            let middle = path.dropFirst("/api/nodes/".count).dropLast("/move".count)
            handleMoveNode(idString: String(middle), body: request.body, on: connection)

        default:
            sendStatus(404, message: "Not Found", on: connection)
        }
    }

    private func noteTitle(id: UUID) -> String? {
        guard let node = model?.nodeAcrossWorkspaces(id: id) else { return nil }
        if case .note(let note) = node { return note.title }
        return nil
    }

    private func handleGetNote(idString: String, on connection: NWConnection) {
        guard let id = UUID(uuidString: idString) else {
            sendStatus(400, message: "Bad Note Id", on: connection)
            return
        }
        guard let title = noteTitle(id: id) else {
            sendStatus(404, message: "Note Not Found", on: connection)
            return
        }
        let content = noteStorage.read(id: id)
        let payload: [String: Any] = [
            "id": id.uuidString,
            "title": title,
            "content": content
        ]
        sendJSON(payload, on: connection)
    }

    private func handlePutNote(idString: String, body: Data, on connection: NWConnection) {
        guard let id = UUID(uuidString: idString) else {
            sendStatus(400, message: "Bad Note Id", on: connection)
            return
        }
        guard noteTitle(id: id) != nil else {
            // The sidebar entry is gone; do not resurrect the .md file.
            sendStatus(404, message: "Note Not Found", on: connection)
            return
        }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let content = json["content"] as? String else {
            sendStatus(400, message: "Bad Body", on: connection)
            return
        }
        do {
            try noteStorage.write(id: id, content: content)
            sendJSON(["ok": true], on: connection)
        } catch {
            sendStatus(500, message: "Write Failed", on: connection)
        }
    }

    // MARK: - Agent API handlers

    private func handleGetState(on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(model.state)
            sendOkRawJSON(top: ["state": data], on: connection)
        } catch {
            sendError(status: 500, code: "encode_failed", message: "Failed to encode state", on: connection)
        }
    }

    private func handleListWorkspaces(on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        let list: [[String: Any]] = model.workspaces.map { ws in
            [
                "id": ws.id.uuidString,
                "name": ws.name,
                "colorId": ws.colorId.rawValue
            ]
        }
        sendOk(["workspaces": list], on: connection)
    }

    private func handleCurrentWorkspace(on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        let state = model.state
        let selectedId = state.selectedWorkspaceId
        let workspace = selectedId.flatMap { id in model.workspaces.first(where: { $0.id == id }) }

        if let workspace {
            let payload: [String: Any] = [
                "selected": true,
                "settingsSelected": state.isSettingsSelected,
                "workspace": [
                    "id": workspace.id.uuidString,
                    "name": workspace.name,
                    "colorId": workspace.colorId.rawValue
                ]
            ]
            sendOk(payload, on: connection)
            return
        }

        let payload: [String: Any] = [
            "selected": false,
            "settingsSelected": state.isSettingsSelected,
            "workspace": NSNull()
        ]
        sendOk(payload, on: connection)
    }

    private func handleWorkspaceTree(idString: String, on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        guard let id = UUID(uuidString: idString) else {
            sendError(status: 400, code: "bad_id", message: "Invalid workspace id", on: connection)
            return
        }
        guard let workspace = model.workspaces.first(where: { $0.id == id }) else {
            sendError(status: 404, code: "workspace_not_found", message: "Workspace not found", on: connection)
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(workspace)
            sendOkRawJSON(top: ["workspace": data], on: connection)
        } catch {
            sendError(status: 500, code: "encode_failed", message: "Failed to encode workspace", on: connection)
        }
    }

    private func handleCreateWorkspace(body: Data, on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        guard let json = parseJSONObject(body) else {
            sendError(status: 400, code: "bad_body", message: "Body must be a JSON object", on: connection)
            return
        }
        guard let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            sendError(status: 400, code: "bad_name", message: "name is required", on: connection)
            return
        }
        let color: WorkspaceColorId
        if let raw = json["colorId"] as? String {
            guard let resolved = Self.resolveColor(raw) else {
                sendError(status: 400, code: "bad_color", message: "Unknown colorId: \(raw)", on: connection)
                return
            }
            color = resolved
        } else {
            color = .defaultColor()
        }
        let id = model.createWorkspace(name: name, colorId: color)
        sendOk(["id": id.uuidString], on: connection)
    }

    private func handlePatchWorkspace(idString: String, body: Data, on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        guard let id = UUID(uuidString: idString) else {
            sendError(status: 400, code: "bad_id", message: "Invalid workspace id", on: connection)
            return
        }
        guard model.workspaces.contains(where: { $0.id == id }) else {
            sendError(status: 404, code: "workspace_not_found", message: "Workspace not found", on: connection)
            return
        }
        guard let json = parseJSONObject(body) else {
            sendError(status: 400, code: "bad_body", message: "Body must be a JSON object", on: connection)
            return
        }
        // Resolve all fields before mutating so a bad colorId can't leave
        // a partial rename applied.
        let trimmedName = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName: String? = (trimmedName?.isEmpty == false) ? trimmedName : nil

        let newColor: WorkspaceColorId?
        if let raw = json["colorId"] as? String {
            guard let resolved = Self.resolveColor(raw) else {
                sendError(status: 400, code: "bad_color", message: "Unknown colorId: \(raw)", on: connection)
                return
            }
            newColor = resolved
        } else {
            newColor = nil
        }

        if let newName {
            model.renameWorkspace(id: id, newName: newName)
        }
        if let newColor {
            model.updateWorkspaceColor(id: id, colorId: newColor)
        }
        sendOk([:], on: connection)
    }

    private func handleCreateFolder(body: Data, on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        guard let json = parseJSONObject(body) else {
            sendError(status: 400, code: "bad_body", message: "Body must be a JSON object", on: connection)
            return
        }
        guard let wsId = Self.parseUUID(json["workspace_id"]) else {
            sendError(status: 400, code: "bad_workspace_id", message: "workspace_id is required", on: connection)
            return
        }
        guard let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            sendError(status: 400, code: "bad_name", message: "name is required", on: connection)
            return
        }
        let parentId = Self.parseOptionalUUID(json["parent_id"])
        if let parentResult = validateParent(workspaceId: wsId, parentId: parentId, expectFolder: true) {
            switch parentResult {
            case .success: break
            case .failure(let code, let message):
                sendError(status: 404, code: code, message: message, on: connection)
                return
            }
        }
        let expanded = (json["expanded"] as? Bool) ?? true
        guard let id = model.addFolder(name: name, workspaceId: wsId, parentId: parentId, isExpanded: expanded) else {
            sendError(status: 404, code: "workspace_not_found", message: "Workspace not found", on: connection)
            return
        }
        sendOk(["id": id.uuidString], on: connection)
    }

    private func handlePatchFolder(idString: String, body: Data, on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        guard let id = UUID(uuidString: idString) else {
            sendError(status: 400, code: "bad_id", message: "Invalid id", on: connection)
            return
        }
        guard let node = model.nodeAcrossWorkspaces(id: id), case .folder = node else {
            sendError(status: 404, code: "folder_not_found", message: "Folder not found", on: connection)
            return
        }
        guard let json = parseJSONObject(body) else {
            sendError(status: 400, code: "bad_body", message: "Body must be a JSON object", on: connection)
            return
        }
        if let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            model.renameNode(id: id, newName: name)
        }
        if let expanded = json["expanded"] as? Bool {
            model.setFolderExpanded(id: id, isExpanded: expanded)
        }
        sendOk([:], on: connection)
    }

    private func handleCreateLink(body: Data, on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        guard let json = parseJSONObject(body) else {
            sendError(status: 400, code: "bad_body", message: "Body must be a JSON object", on: connection)
            return
        }
        guard let wsId = Self.parseUUID(json["workspace_id"]) else {
            sendError(status: 400, code: "bad_workspace_id", message: "workspace_id is required", on: connection)
            return
        }
        guard let url = (json["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
            sendError(status: 400, code: "bad_url", message: "url is required", on: connection)
            return
        }
        let parentId = Self.parseOptionalUUID(json["parent_id"])
        if let result = validateParent(workspaceId: wsId, parentId: parentId, expectFolder: true) {
            switch result {
            case .success: break
            case .failure(let code, let message):
                sendError(status: 404, code: code, message: message, on: connection)
                return
            }
        }
        let providedTitle = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if let providedTitle, !providedTitle.isEmpty {
            title = providedTitle
        } else {
            title = URL(string: url)?.host ?? url
        }
        guard let id = model.addLink(urlString: url, title: title, workspaceId: wsId, parentId: parentId) else {
            sendError(status: 404, code: "workspace_not_found", message: "Workspace not found", on: connection)
            return
        }
        sendOk(["id": id.uuidString], on: connection)
    }

    private func handlePatchLink(idString: String, body: Data, on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        guard let id = UUID(uuidString: idString) else {
            sendError(status: 400, code: "bad_id", message: "Invalid id", on: connection)
            return
        }
        guard let node = model.nodeAcrossWorkspaces(id: id), case .link = node else {
            sendError(status: 404, code: "link_not_found", message: "Link not found", on: connection)
            return
        }
        guard let json = parseJSONObject(body) else {
            sendError(status: 400, code: "bad_body", message: "Body must be a JSON object", on: connection)
            return
        }
        if let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            model.renameNode(id: id, newName: title)
        }
        if let url = (json["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            model.updateLinkUrl(id: id, newUrl: url)
        }
        sendOk([:], on: connection)
    }

    private func handleCreateNote(body: Data, on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        guard let json = parseJSONObject(body) else {
            sendError(status: 400, code: "bad_body", message: "Body must be a JSON object", on: connection)
            return
        }
        guard let wsId = Self.parseUUID(json["workspace_id"]) else {
            sendError(status: 400, code: "bad_workspace_id", message: "workspace_id is required", on: connection)
            return
        }
        guard let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            sendError(status: 400, code: "bad_title", message: "title is required", on: connection)
            return
        }
        let parentId = Self.parseOptionalUUID(json["parent_id"])
        if let result = validateParent(workspaceId: wsId, parentId: parentId, expectFolder: true) {
            switch result {
            case .success: break
            case .failure(let code, let message):
                sendError(status: 404, code: code, message: message, on: connection)
                return
            }
        }
        let content = (json["content"] as? String) ?? ""
        guard let id = model.addNote(title: title, workspaceId: wsId, parentId: parentId, content: content) else {
            sendError(status: 404, code: "workspace_not_found", message: "Workspace not found", on: connection)
            return
        }
        sendOk(["id": id.uuidString], on: connection)
    }

    private func handlePatchNote(idString: String, body: Data, on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        guard let id = UUID(uuidString: idString) else {
            sendError(status: 400, code: "bad_id", message: "Invalid id", on: connection)
            return
        }
        guard let node = model.nodeAcrossWorkspaces(id: id), case .note = node else {
            sendError(status: 404, code: "note_not_found", message: "Note not found", on: connection)
            return
        }
        guard let json = parseJSONObject(body) else {
            sendError(status: 400, code: "bad_body", message: "Body must be a JSON object", on: connection)
            return
        }
        if let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            model.renameNode(id: id, newName: title)
        }
        sendOk([:], on: connection)
    }

    private func handleDeleteNode(idString: String, on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        guard let id = UUID(uuidString: idString) else {
            sendError(status: 400, code: "bad_id", message: "Invalid id", on: connection)
            return
        }
        guard model.nodeAcrossWorkspaces(id: id) != nil else {
            sendError(status: 404, code: "node_not_found", message: "Node not found", on: connection)
            return
        }
        model.deleteNode(id: id)
        sendOk([:], on: connection)
    }

    private func handleMoveNode(idString: String, body: Data, on connection: NWConnection) {
        guard let model else {
            sendError(status: 503, code: "model_unavailable", message: "App model not available", on: connection)
            return
        }
        guard let id = UUID(uuidString: idString) else {
            sendError(status: 400, code: "bad_id", message: "Invalid id", on: connection)
            return
        }
        guard let sourceWsId = model.workspaceId(forNodeId: id) else {
            sendError(status: 404, code: "node_not_found", message: "Node not found", on: connection)
            return
        }
        guard let json = parseJSONObject(body) else {
            sendError(status: 400, code: "bad_body", message: "Body must be a JSON object", on: connection)
            return
        }
        let toWsId = Self.parseOptionalUUID(json["to_workspace_id"])
        let toParentId = Self.parseOptionalUUID(json["to_parent_id"])
        let index = json["index"] as? Int

        if json["to_workspace_id"] == nil, json["to_parent_id"] == nil, json["index"] == nil {
            sendError(status: 400, code: "no_move_params", message: "Provide at least one of to_workspace_id, to_parent_id, or index", on: connection)
            return
        }

        let destWsId = toWsId ?? sourceWsId
        guard model.workspaces.contains(where: { $0.id == destWsId }) else {
            sendError(status: 404, code: "workspace_not_found", message: "Destination workspace not found", on: connection)
            return
        }
        if let toParentId {
            guard let parentNode = model.nodeAcrossWorkspaces(id: toParentId), case .folder = parentNode else {
                sendError(status: 404, code: "parent_not_found", message: "Target parent folder not found", on: connection)
                return
            }
            if model.workspaceId(forNodeId: toParentId) != destWsId {
                sendError(status: 400, code: "parent_wrong_workspace", message: "Target parent is in a different workspace", on: connection)
                return
            }
        }

        if destWsId == sourceWsId {
            model.moveNode(id: id, toParentId: toParentId, index: index ?? Int.max)
        } else {
            model.moveNodeToWorkspace(id: id, workspaceId: destWsId, parentId: toParentId, index: index)
        }
        sendOk([:], on: connection)
    }

    // MARK: - Agent API helpers

    private enum ParentValidation {
        case success
        case failure(code: String, message: String)
    }

    private func validateParent(workspaceId: UUID, parentId: UUID?, expectFolder: Bool) -> ParentValidation? {
        guard let parentId else { return nil }
        guard let model else { return .failure(code: "model_unavailable", message: "App model not available") }
        guard let workspace = model.workspaces.first(where: { $0.id == workspaceId }) else {
            return .failure(code: "workspace_not_found", message: "Workspace not found")
        }
        guard let node = model.findNode(id: parentId, in: workspace.items) else {
            return .failure(code: "parent_not_found", message: "Parent folder not found in workspace")
        }
        if expectFolder, case .folder = node { return .success }
        if expectFolder { return .failure(code: "parent_not_folder", message: "parent_id must reference a folder") }
        return .success
    }

    private func parseJSONObject(_ data: Data) -> [String: Any]? {
        if data.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func parseUUID(_ value: Any?) -> UUID? {
        guard let s = value as? String else { return nil }
        return UUID(uuidString: s)
    }

    private static func parseOptionalUUID(_ value: Any?) -> UUID? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return UUID(uuidString: s)
    }

    private static func resolveColor(_ raw: String) -> WorkspaceColorId? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let direct = WorkspaceColorId(rawValue: trimmed) {
            return direct == .settingsBackground ? nil : direct
        }
        let lower = trimmed.lowercased()
        for case let c in WorkspaceColorId.allCases where c.name.lowercased() == lower {
            return c
        }
        return nil
    }

    private func sendOk(_ payload: [String: Any], on connection: NWConnection) {
        var dict = payload
        dict["ok"] = true
        sendJSON(dict, on: connection)
    }

    private func sendOkRawJSON(top: [String: Data], on connection: NWConnection) {
        // Builds `{"ok":true,"<key>":<rawJson>,...}` so we can splice in
        // pre-encoded JSON (e.g. AppState) without lossy round-tripping.
        var parts: [String] = ["\"ok\":true"]
        for (key, data) in top {
            let escapedKey = key.replacingOccurrences(of: "\"", with: "\\\"")
            let json = String(data: data, encoding: .utf8) ?? "null"
            parts.append("\"\(escapedKey)\":\(json)")
        }
        let body = Data("{\(parts.joined(separator: ","))}".utf8)
        sendResponse(status: 200, statusMessage: "OK", contentType: "application/json; charset=utf-8", body: body, on: connection)
    }

    private func sendError(status: Int, code: String, message: String, on connection: NWConnection) {
        let payload: [String: Any] = [
            "ok": false,
            "error": message,
            "code": code
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{\"ok\":false}".utf8)
        sendResponse(status: status, statusMessage: "Error", contentType: "application/json; charset=utf-8", body: data, on: connection)
    }

    // MARK: - Resource resolution

    /// Locates the directory that holds the bundled `NoteEditor/` assets.
    ///
    /// Deliberately does **not** use `Bundle.module`: Swift Bundler injects a
    /// custom `Bundle.module` accessor that calls `fatalError` when its two
    /// hardcoded search paths (the app root and a developer `.build` path) miss.
    /// Because the resource bundle actually ships under `Contents/Resources`,
    /// every external install of 0.1.12 trapped at launch the moment this
    /// accessor was touched. Here we search the real locations and return `nil`
    /// on miss so a missing bundle degrades to "editor unavailable" (the server
    /// already 404s/500s) instead of killing the app.
    static func resolveBundledResourcesURL() -> URL? {
        let fm = FileManager.default
        let bundleName = "Arcmark_ArcmarkCore.bundle"

        // Bases that might contain the resource bundle (packaged app, flat dev
        // builds) or the assets directly. `Bundle(for:)` covers test/dynamic
        // builds where ArcmarkCore is not statically linked into Bundle.main.
        var bases: [URL] = []
        if let main = Bundle.main.resourceURL { bases.append(main) }
        bases.append(Bundle.main.bundleURL)
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            bases.append(exeDir)
        }
        let codeBundle = Bundle(for: NoteServer.self)
        if let codeResources = codeBundle.resourceURL { bases.append(codeResources) }
        bases.append(codeBundle.bundleURL)

        func hasEditor(_ dir: URL) -> Bool {
            fm.fileExists(atPath: dir.appendingPathComponent("NoteEditor/index.html").path)
        }

        for base in bases {
            // Nested SwiftPM resource bundle (Arcmark_ArcmarkCore.bundle).
            let nested = base.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: nested), let resources = bundle.resourceURL, hasEditor(resources) {
                return resources
            }
            // Resources copied directly under the base directory.
            if hasEditor(base) {
                return base
            }
        }
        return nil
    }

    // MARK: - Static asset serving

    private func serveIndexHTML(on connection: NWConnection) {
        guard let resourcesURL else {
            sendStatus(500, message: "No Resources", on: connection)
            return
        }
        let assetURL = resourcesURL
            .appendingPathComponent("NoteEditor", isDirectory: true)
            .appendingPathComponent("index.html")
        guard let html = try? String(contentsOf: assetURL, encoding: .utf8) else {
            sendStatus(404, message: "Asset Missing", on: connection)
            return
        }
        sendResponse(status: 200, statusMessage: "OK", contentType: "text/html; charset=utf-8", body: Data(html.utf8), on: connection)
    }

    private func serveEditorAsset(relative: String, on connection: NWConnection) {
        // Percent-decode first so that escaped traversal sequences (e.g.
        // `%2e%2e`) are caught by the check below — `Data(contentsOf:)`
        // resolves the URL via its decoded path, which would otherwise
        // collapse them back into `..`.
        guard let decoded = relative.removingPercentEncoding else {
            sendStatus(400, message: "Bad Path", on: connection)
            return
        }
        if decoded.contains("..") || decoded.hasPrefix("/") {
            sendStatus(400, message: "Bad Path", on: connection)
            return
        }

        guard let resourcesURL else {
            sendStatus(500, message: "No Resources", on: connection)
            return
        }

        let editorRoot = resourcesURL.appendingPathComponent("NoteEditor", isDirectory: true)
        let assetURL = editorRoot.appendingPathComponent(decoded)

        // Belt-and-braces: ensure the resolved path stays under the editor
        // root after symlink/`..` resolution.
        let resolvedAsset = assetURL.standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedRoot = editorRoot.standardizedFileURL.resolvingSymlinksInPath().path
        if !resolvedAsset.hasPrefix(resolvedRoot + "/") {
            sendStatus(400, message: "Bad Path", on: connection)
            return
        }

        guard let data = try? Data(contentsOf: assetURL) else {
            sendStatus(404, message: "Asset Missing", on: connection)
            return
        }

        let contentType = Self.mimeType(for: assetURL.pathExtension.lowercased())
        sendResponse(status: 200, statusMessage: "OK", contentType: contentType, body: data, on: connection)
    }

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "ico": return "image/x-icon"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Response helpers

    private func sendStatus(_ status: Int, message: String, on connection: NWConnection) {
        let body = Data("\(status) \(message)".utf8)
        sendResponse(status: status, statusMessage: message, contentType: "text/plain; charset=utf-8", body: body, on: connection)
    }

    private func sendJSON(_ object: Any, on connection: NWConnection) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        sendResponse(status: 200, statusMessage: "OK", contentType: "application/json; charset=utf-8", body: data, on: connection)
    }

    private func sendResponse(status: Int, statusMessage: String, contentType: String, body: Data, on connection: NWConnection) {
        var headers = ""
        headers += "HTTP/1.1 \(status) \(statusMessage)\r\n"
        headers += "Content-Type: \(contentType)\r\n"
        headers += "Content-Length: \(body.count)\r\n"
        headers += "Cache-Control: no-store\r\n"
        headers += "X-Content-Type-Options: nosniff\r\n"
        headers += "Connection: close\r\n"
        headers += "\r\n"

        var packet = Data(headers.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

}
