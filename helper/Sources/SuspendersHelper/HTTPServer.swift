import Foundation
import Network

/// A tiny loopback-only HTTP/1.1 server. Requests from web pages are refused —
/// only the Chrome extension (or local tools like curl) may talk to it.
final class HTTPServer {
    struct Request {
        var method: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: Data
    }

    struct Response {
        var status: Int = 200
        var json: Any = [:]
    }

    typealias Handler = (Request) -> Response

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "suspenders.http")
    private let handler: Handler
    private(set) var port: UInt16

    init(port: UInt16, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { NSLog("Suspenders HTTP failed: \(error)") }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.count > 256 * 1024 || error != nil {
                conn.cancel()
                return
            }
            if let request = HTTPServer.parse(buffer) {
                self.respond(conn, to: request)
            } else if done {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buffer)
            }
        }
    }

    /// Returns nil until the full request (headers + Content-Length body) has arrived.
    static func parse(_ data: Data) -> Request? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= length else { return nil }
        let target = URLComponents(string: String(requestLine[1]))
        var query: [String: String] = [:]
        target?.queryItems?.forEach { query[$0.name] = $0.value ?? "" }
        return Request(method: String(requestLine[0]).uppercased(), path: target?.path ?? "/", query: query,
                       headers: headers, body: data[bodyStart..<(bodyStart + length)])
    }

    private func respond(_ conn: NWConnection, to request: Request) {
        let origin = request.headers["origin"]
        let allowedOrigin = origin.map { $0.hasPrefix("chrome-extension://") } ?? true

        var response: Response
        if !allowedOrigin {
            response = Response(status: 403, json: ["error": "forbidden"])
        } else if request.method == "OPTIONS" {
            response = Response(status: 204, json: NSNull())
        } else {
            response = DispatchQueue.main.sync { handler(request) }
        }

        var body = Data()
        if !(response.json is NSNull), let data = try? JSONSerialization.data(withJSONObject: response.json, options: [.sortedKeys]) {
            body = data
        }
        var head = "HTTP/1.1 \(response.status) \(HTTPServer.reason(response.status))\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n"
        if let origin, allowedOrigin {
            head += "Access-Control-Allow-Origin: \(origin)\r\n"
            head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            head += "Access-Control-Allow-Headers: Content-Type\r\n"
            head += "Access-Control-Allow-Private-Network: true\r\n"
            head += "Vary: Origin\r\n"
        }
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        default: return "Error"
        }
    }
}
