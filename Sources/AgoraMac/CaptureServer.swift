import Foundation
import Network
import Security
import AgoraCore

/// A single-purpose HTTPS receiver. The MCP helper accesses SQLite directly and needs no listener.
final class CaptureServer: @unchecked Sendable {
    private let store: Store
    private let resources: URL
    private let parameters: NWParameters
    private let queue = DispatchQueue(label: "au.com.acousland.Agora.outlook")
    private var listener: NWListener?
    var onStatus: ((String) -> Void)?
    init(store: Store, resourceURL: URL) throws {
        self.store = store; resources = resourceURL
        let p12 = try Data(contentsOf: store.directory.appendingPathComponent("localhost.p12"))
        let passphrase = try String(contentsOf: store.directory.appendingPathComponent("localhost-passphrase"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        var items: CFArray?
        var options: [String: Any] = [kSecImportExportPassphrase as String: passphrase]
        if #available(macOS 15, *) { options[kSecImportToMemoryOnly as String] = true }
        let status = SecPKCS12Import(p12 as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess, let item = (items as? [[String: Any]])?.first, let value = item[kSecImportItemIdentity as String] else { throw AgoraError.invalid("Could not load local HTTPS certificate. Run setup again.") }
        let identity = value as! SecIdentity
        guard let tlsIdentity = sec_identity_create(identity) else { throw AgoraError.invalid("Could not prepare local HTTPS.") }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, tlsIdentity)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 3848)
        _ = try store.pairingToken()
    }
    func start() throws {
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onStatus?("Listening securely on localhost:3848")
            case .failed(let error): self?.onStatus?("Connection unavailable: \(error.localizedDescription)")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
    }
    func stop() { listener?.cancel(); listener = nil }
    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 15) { connection.cancel() }
        receive(connection, buffer: Data())
    }
    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard buffer.count <= 1_048_576 else { self.respond(connection, status: 413, text: "Request too large"); return }
            guard error == nil else { connection.cancel(); return }
            if let boundary = buffer.range(of: Data("\r\n\r\n".utf8)) {
                guard boundary.lowerBound <= 16384 else { self.respond(connection, status: 431, text: "Headers too large"); return }
                let head = String(decoding: buffer[..<boundary.lowerBound], as: UTF8.self), lines = head.components(separatedBy: "\r\n")
                let parts = (lines.first ?? "").split(separator: " ").map(String.init)
                guard parts.count == 3 else { self.respond(connection, status: 400, text: "Invalid request"); return }
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = line[..<colon].lowercased()
                    guard headers[key] == nil else { self.respond(connection, status: 400, text: "Duplicate header"); return }
                    headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                }
                guard headers["transfer-encoding"] == nil else { self.respond(connection, status: 400, text: "Chunked requests are unsupported"); return }
                let length = Int(headers["content-length"] ?? "0") ?? -1
                guard length >= 0, length <= 1_000_000 else { self.respond(connection, status: 413, text: "Invalid content length"); return }
                let available = buffer.count - boundary.upperBound
                if available >= length {
                    let body = Data(buffer[boundary.upperBound..<(boundary.upperBound + length)])
                    self.handle(connection, method: parts[0], path: parts[1], headers: headers, body: body); return
                }
            }
            if complete { connection.cancel() } else { self.receive(connection, buffer: buffer) }
        }
    }
    private func handle(_ connection: NWConnection, method: String, path: String, headers: [String: String], body: Data) {
        let hosts: Set<String> = ["localhost:3848", "127.0.0.1:3848"]
        let origins: Set<String> = ["https://localhost:3848", "https://127.0.0.1:3848"]
        guard let host = headers["host"], hosts.contains(host.lowercased()), headers["origin"].map(origins.contains) ?? true else { respond(connection, status: 403, text: "Origin rejected"); return }
        if method == "GET" && path == "/health" { respond(connection, status: 200, text: "Agora Outlook connection is ready."); return }
        if path.hasPrefix("/api/") {
            guard let token = try? store.pairingToken(), let auth = headers["authorization"], constantTimeEqual(auth, "Bearer \(token)") else { respond(connection, status: 401, text: "Pair the add-in with your Agora key."); return }
            if path == "/api/ping" && method == "GET" { respond(connection, status: 200, json: ["connected": true]); return }
            guard path == "/api/capture", method == "POST", headers["content-type"]?.hasPrefix("application/json") == true else { respond(connection, status: 404, text: "Unknown endpoint"); return }
            do {
                guard let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw AgoraError.invalid("Invalid email payload.") }
                let result = try Commands.call("capture_email", args: payload, store: store)
                respond(connection, status: 200, json: result)
            } catch { respond(connection, status: 400, json: ["error": error.localizedDescription]) }
            return
        }
        guard method == "GET" else { respond(connection, status: 405, text: "Method unsupported"); return }
        let routes = ["/": "taskpane.html", "/taskpane.html": "taskpane.html", "/taskpane.js": "taskpane.js", "/taskpane.css": "taskpane.css", "/manifest.xml": "manifest.xml", "/icon-16.png": "icon-16.png", "/icon-32.png": "icon-32.png", "/icon-64.png": "icon-64.png", "/icon-80.png": "icon-80.png"]
        guard let file = routes[path], let data = try? Data(contentsOf: resources.appendingPathComponent(file)) else { respond(connection, status: 404, text: "Not found"); return }
        let mime = file.hasSuffix(".js") ? "text/javascript" : file.hasSuffix(".css") ? "text/css" : file.hasSuffix(".xml") ? "application/xml" : file.hasSuffix(".png") ? "image/png" : "text/html"
        respond(connection, status: 200, data: data, mime: mime)
    }
    private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    private func respond(_ connection: NWConnection, status: Int, text: String) { respond(connection, status: status, data: Data(text.utf8), mime: "text/plain; charset=utf-8") }
    private func respond(_ connection: NWConnection, status: Int, json: Any) { respond(connection, status: status, data: (try? JSONSerialization.data(withJSONObject: json)) ?? Data(), mime: "application/json") }
    private func respond(_ connection: NWConnection, status: Int, data: Data, mime: String) {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large", 431: "Request Header Fields Too Large"][status] ?? "Error"
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(mime)\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n\r\n"
        connection.send(content: Data(head.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
    }
}
