import Foundation
import AgoraCore
import MCP

@main struct AgoraMCPEntry {
    static func main() async {
        do {
            if CommandLine.arguments.count > 1 {
                guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--configure-client", let client = MCPClient(rawValue: CommandLine.arguments[2]) else {
                    throw AgoraError.invalid("Usage: AgoraMCP [--configure-client codex|claude-desktop|claude-code]")
                }
                let session = try ProfileSession()
                let setup = MCPRegistration(helper: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL, library: session.store.directory, profileRoot: session.manager?.root)
                try setup.install(client)
                FileHandle.standardError.write(Data("Agora configured for \(client.name). Quit and reopen the client.\n".utf8))
                return
            }
            let session = try ProfileSession()
            let infoURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
            let info = (try? Data(contentsOf: infoURL)).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
            let context = session.profile.map { " This session uses the \($0.name) profile (\($0.id)). Profiles have separate libraries. If the profile changes in Agora, stop and reconnect the client; do not continue an old conversation in a different profile." } ?? " This connection uses a fixed library."
            let server = Server(name: "Agora", version: info?["CFBundleShortVersionString"] as? String ?? "development", instructions: "Agora is your private, local personal CRM. Use get_overview for promises needing attention; list_contacts then get_contact for context. Record commitments explicitly: i_owe means you promised, they_owe means the other person promised. Never invent promises or dates. Link commitments to their source interaction when available. Read current revisions before updating. Writes are visible in the native app automatically. Agora stores data on this Mac; the connected AI client may send retrieved records to its model provider." + context, capabilities: .init(tools: .init(listChanged: false)))
            await server.withMethodHandler(ListTools.self) { _ in
                try .init(tools: Commands.tools.map { definition in
                    let schema = try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: Commands.inputSchema(for: definition)))
                    let readOnly = ["get_overview", "list_contacts", "get_contact", "list_commitments"].contains(definition.name)
                    return Tool(name: definition.name, description: definition.description, inputSchema: schema, annotations: .init(readOnlyHint: readOnly, destructiveHint: definition.name.hasPrefix("update_"), idempotentHint: readOnly || definition.name == "capture_email", openWorldHint: false))
                })
            }
            await server.withMethodHandler(CallTool.self) { params in
                do {
                    let encoded = try JSONEncoder().encode(params.arguments ?? [:])
                    let args = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
                    let result = try session.call(params.name, args: args)
                    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .fragmentsAllowed])
                    return .init(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)])
                } catch { return .init(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true) }
            }
            try await server.start(transport: LocalTransport())
            await server.waitUntilCompleted()
        } catch {
            FileHandle.standardError.write(Data("Agora MCP: \(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
}
