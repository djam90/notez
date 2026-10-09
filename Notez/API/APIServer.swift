#if os(macOS)
import Foundation
import Network
import Observation
import Security
import SwiftData

/// Local HTTP server so AI tools can manage notes while the app is running:
/// REST under `/api`, MCP (Streamable HTTP) at `/mcp`.
///
/// Off by default. Loopback only, and every request needs the bearer token
/// shown in Settings, so other machines, and web pages (which can reach
/// localhost but can't learn the token), get nothing.
@Observable
final class APIServer {
    enum Status: Equatable {
        case stopped, running, failed(String)
    }

    // N-O-T-E on a phone keypad. Debug uses the next port so Notez Dev and the
    // installed app can both serve at once.
    #if DEBUG
    static let defaultPort = 6684
    #else
    static let defaultPort = 6683
    #endif

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            restart()
        }
    }

    var port: Int {
        didSet {
            // The port field re-commits its value on blur.
            guard port != oldValue else { return }
            UserDefaults.standard.set(port, forKey: Keys.port)
            restart()
        }
    }

    private(set) var token: String
    private(set) var status = Status.stopped

    var baseURL: String { "http://127.0.0.1:\(port)" }

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private let api: NotesAPI
    @ObservationIgnored private let mcp: MCPHandler

    private enum Keys {
        static let enabled = "api.enabled"
        static let port = "api.port"
        static let token = "api.token"
    }

    private static let maxBodySize = 20 << 20

    init(context: ModelContext) {
        api = NotesAPI(context: context)
        mcp = MCPHandler(api: api)
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.enabled)
        port = defaults.object(forKey: Keys.port) as? Int ?? Self.defaultPort
        token = defaults.string(forKey: Keys.token) ?? Self.newToken()
        defaults.set(token, forKey: Keys.token)
        restart()
    }

    func regenerateToken() {
        token = Self.newToken()
        UserDefaults.standard.set(token, forKey: Keys.token)
    }

    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Listener

    private func restart() {
        status = .stopped
        guard let old = listener else { return start() }
        listener = nil
        // The port stays bound until the old listener has fully cancelled.
        old.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { MainActor.assumeIsolated { self?.start() } }
        }
        old.cancel()
    }

    private func start() {
        guard isEnabled, listener == nil else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)), port > 0 else {
            status = .failed("Invalid port")
            return
        }
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: params, on: nwPort)
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                MainActor.assumeIsolated {
                    guard let self, let listener, self.listener === listener else { return }
                    switch state {
                    case .ready: self.status = .running
                    case .failed(.posix(.EADDRINUSE)): self.status = .failed("Port \(self.port) is in use by another app")
                    case .failed(let error): self.status = .failed(error.localizedDescription)
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return connection.cancel() }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch HTTPRequest.parse(buffer, maxBodySize: Self.maxBodySize) {
                case .complete(let request):
                    self.send(self.respond(to: request), on: connection)
                case .invalid(let status):
                    self.send(.error(status, "Bad request"), on: connection)
                case .incomplete where error == nil && !isComplete:
                    self.receive(on: connection, buffer: buffer)
                case .incomplete:
                    connection.cancel()
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Routing

    private func respond(to request: HTTPRequest) -> HTTPResponse {
        // Browsers send Origin; only accept local pages (DNS rebinding guard, required by MCP).
        if let origin = request.headers["origin"], let host = URL(string: origin)?.host(),
           !["localhost", "127.0.0.1", "::1"].contains(host) {
            return .error(403, "Origin not allowed")
        }
        guard authorized(request) else {
            return HTTPResponse(status: 401, json: ["error": "Missing or wrong bearer token"],
                                headers: ["WWW-Authenticate": "Bearer"])
        }

        // "/api/notes/<id>" routes as "/api/notes/:id".
        var parts = request.path.split(separator: "/").map(String.init)
        let id = parts.count == 3 ? parts[2] : ""
        if parts.count == 3 { parts[2] = ":id" }
        let route = "/" + parts.joined(separator: "/")
        do {
            switch (request.method, route) {
            case ("POST", "/mcp"):
                guard let body = mcp.handle(request.body) else { return HTTPResponse(status: 202) }
                return HTTPResponse(status: 200, body: body, contentType: "application/json")
            case (_, "/mcp"):
                // No server-initiated SSE stream or sessions to end.
                return .error(405, "Method not allowed")

            case ("GET", "/api/notes"):
                return .ok(try api.list(request.query))
            case ("POST", "/api/notes"):
                return HTTPResponse(status: 201, json: try api.create(try request.jsonBody()))
            case ("GET", "/api/notes/:id"):
                return .ok(try api.get(["id": id]))
            case ("PATCH", "/api/notes/:id"):
                return .ok(try api.update(try request.jsonBody().merging(["id": id]) { $1 }))
            case ("DELETE", "/api/notes/:id"):
                return .ok(try api.delete(["id": id]))
            case ("GET", "/api/projects"):
                return .ok(try api.listProjects([:]))
            case ("POST", "/api/projects"):
                return HTTPResponse(status: 201, json: try api.createProject(try request.jsonBody()))
            case ("GET", "/api/search"):
                var args: [String: Any] = request.query
                args["query"] = request.query["q"] ?? ""
                return .ok(try api.search(args))
            case ("GET", "/api/assets/:id"):
                let asset = try api.asset(id)
                return HTTPResponse(status: 200, body: asset.data, contentType: asset.mimeType)
            default:
                return .error(404, "No route for \(request.method) \(request.path)")
            }
        } catch let error as APIError {
            return .error(error.status, error.message)
        } catch {
            return .error(500, "\(error)")
        }
    }

    private func authorized(_ request: HTTPRequest) -> Bool {
        guard let header = request.headers["authorization"], header.hasPrefix("Bearer ") else { return false }
        let given = Array(header.dropFirst("Bearer ".count).utf8)
        let expected = Array(token.utf8)
        // Constant time, so the token can't be guessed byte by byte from response timing.
        guard given.count == expected.count else { return false }
        return zip(given, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

// MARK: - Minimal HTTP/1.1

private struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    enum ParseResult {
        case incomplete
        case invalid(Int)
        case complete(HTTPRequest)
    }

    static func parse(_ data: Data, maxBodySize: Int) -> ParseResult {
        guard let headerEnd = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 64 << 10 ? .invalid(431) : .incomplete
        }
        let head = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, let components = URLComponents(string: String(requestLine[1])) else {
            return .invalid(400)
        }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if headers["transfer-encoding"] != nil { return .invalid(501) }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= maxBodySize else { return .invalid(413) }
        let bodyStart = headerEnd.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return .complete(HTTPRequest(
            method: String(requestLine[0]),
            path: components.path,
            query: query,
            headers: headers,
            body: data[bodyStart..<(bodyStart + length)]
        ))
    }

    func jsonBody() throws -> [String: Any] {
        if body.isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw APIError.badRequest("Body must be a JSON object")
        }
        return object
    }
}

private struct HTTPResponse {
    var status: Int
    var body = Data()
    var contentType = "application/json"
    var headers: [String: String] = [:]

    init(status: Int, body: Data = Data(), contentType: String = "application/json", headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.contentType = contentType
        self.headers = headers
    }

    init(status: Int, json: Any, headers: [String: String] = [:]) {
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [.withoutEscapingSlashes])) ?? Data()
        self.init(status: status, body: data, headers: headers)
    }

    static func ok(_ json: Any) -> HTTPResponse { HTTPResponse(status: 200, json: json) }
    static func error(_ status: Int, _ message: String) -> HTTPResponse { HTTPResponse(status: status, json: ["error": message]) }

    func serialized() -> Data {
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        var all = headers
        all["Content-Length"] = String(body.count)
        all["Connection"] = "close"
        if !body.isEmpty { all["Content-Type"] = contentType }
        for (name, value) in all { head += "\(name): \(value)\r\n" }
        return Data((head + "\r\n").utf8) + body
    }
}
#endif
