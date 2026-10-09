import Foundation
import Logging
import MCP

// SDK 0.12.1 models experimental client capabilities as string values. Modern
// clients may send arbitrary JSON. Agora implements none of those extensions.
actor LocalTransport: Transport {
    private let base: StdioTransport
    nonisolated let logger: Logger
    init() { let transport = StdioTransport(); base = transport; logger = transport.logger }
    func connect() async throws { try await base.connect() }
    func disconnect() async { await base.disconnect() }
    func send(_ data: Data) async throws { try await base.send(data) }
    func receive() -> AsyncThrowingStream<Data, Error> {
        let base = base
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var initialized = false
                    for try await data in await base.receive() {
                        if !initialized, var message = try? JSONSerialization.jsonObject(with: data) as? [String: Any], message["method"] as? String == "initialize" {
                            initialized = true
                            if var params = message["params"] as? [String: Any], var capabilities = params["capabilities"] as? [String: Any] {
                                capabilities.removeValue(forKey: "experimental")
                                params["capabilities"] = capabilities; message["params"] = params
                                continuation.yield(try JSONSerialization.data(withJSONObject: message)); continue
                            }
                        }
                        continuation.yield(data)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
