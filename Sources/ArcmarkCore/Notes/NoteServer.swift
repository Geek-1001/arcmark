import Foundation
import Network
import os

/// Minimal loopback-only HTTP server that backs the bundled markdown note editor.
///
/// Binds to 127.0.0.1 on a system-assigned ephemeral port, authenticates every
/// request with a 256-bit random token, and rejects requests whose Host header
/// doesn't match 127.0.0.1:<port> (DNS rebinding defense).
@MainActor
final class NoteServer {
    private let logger = Logger(subsystem: "com.arcmark.app", category: "noteserver")
    private weak var model: AppModel?
    private let noteStorage: NoteStorage
    private let resourcesURL: URL?

    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    let token: String

    init(model: AppModel, resourcesURL: URL? = Bundle.module.resourceURL) {
        self.model = model
        self.noteStorage = model.noteStorage
        self.resourcesURL = resourcesURL
        self.token = Self.generateToken()
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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
        return URL(string: "http://127.0.0.1:\(port)/?id=\(noteId.uuidString)&token=\(token)")
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

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
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

        // Browsers fetch /favicon.ico automatically with no token; serve a
        // 204 so we don't log noisy 401s.
        if request.method == "GET" && request.path == "/favicon.ico" {
            sendResponse(status: 204, statusMessage: "No Content", contentType: "image/x-icon", body: Data(), on: connection)
            return
        }

        // Token check (applies to all routes — including static assets)
        let providedToken = request.query["token"] ?? request.headers["x-arcmark-token"] ?? ""
        if !constantTimeEqual(providedToken, token) {
            sendStatus(401, message: "Unauthorized", on: connection)
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            serveIndexHTML(on: connection)
        case ("GET", "/favicon.ico"):
            sendResponse(status: 204, statusMessage: "No Content", contentType: "image/x-icon", body: Data(), on: connection)
        case ("GET", let path) where path.hasPrefix("/editor/"):
            let relative = String(path.dropFirst("/editor/".count))
            serveEditorAsset(relative: relative, on: connection)
        case ("GET", let path) where path.hasPrefix("/api/notes/"):
            let idString = String(path.dropFirst("/api/notes/".count))
            handleGetNote(idString: idString, on: connection)
        case ("PUT", let path) where path.hasPrefix("/api/notes/"):
            let idString = String(path.dropFirst("/api/notes/".count))
            handlePutNote(idString: idString, body: request.body, on: connection)
        default:
            sendStatus(404, message: "Not Found", on: connection)
        }
    }

    private func handleGetNote(idString: String, on connection: NWConnection) {
        guard let id = UUID(uuidString: idString) else {
            sendStatus(400, message: "Bad Note Id", on: connection)
            return
        }
        let title = model?.nodeById(id).flatMap { node -> String? in
            if case .note(let note) = node { return note.title }
            return nil
        } ?? ""
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

    // MARK: - Static asset serving

    private func serveIndexHTML(on connection: NWConnection) {
        guard let resourcesURL else {
            sendStatus(500, message: "No Resources", on: connection)
            return
        }
        let assetURL = resourcesURL
            .appendingPathComponent("NoteEditor", isDirectory: true)
            .appendingPathComponent("index.html")
        guard var html = try? String(contentsOf: assetURL, encoding: .utf8) else {
            sendStatus(404, message: "Asset Missing", on: connection)
            return
        }
        html = html.replacingOccurrences(of: "{{TOKEN}}", with: token)
        sendResponse(status: 200, statusMessage: "OK", contentType: "text/html; charset=utf-8", body: Data(html.utf8), on: connection)
    }

    private func serveEditorAsset(relative: String, on connection: NWConnection) {
        // Reject path traversal
        if relative.contains("..") || relative.hasPrefix("/") {
            sendStatus(400, message: "Bad Path", on: connection)
            return
        }

        guard let resourcesURL else {
            sendStatus(500, message: "No Resources", on: connection)
            return
        }

        let assetURL = resourcesURL
            .appendingPathComponent("NoteEditor", isDirectory: true)
            .appendingPathComponent(relative)

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

    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8)
        let rhs = Array(b.utf8)
        if lhs.count != rhs.count { return false }
        var result: UInt8 = 0
        for i in 0..<lhs.count {
            result |= lhs[i] ^ rhs[i]
        }
        return result == 0
    }
}
