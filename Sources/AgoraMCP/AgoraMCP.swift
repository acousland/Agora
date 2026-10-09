import Foundation
import AgoraCore
import MCP

@main struct AgoraMCPEntry {
    static func main() async {
        do {
            let store = try Store()
            let server = Server(name: "Agora", version: "1.0.0", instructions: "Agora is your private, local personal CRM. Use get_overview for promises needing attention; list_contacts then get_contact for context. Record commitments explicitly: i_owe means you promised, they_owe means the other person promised. Never invent promises or dates. Link commitments to their source interaction when available. Read current revisions before updating. Writes are visible in the native app automatically. All data stays on this Mac; the connected AI client can read the records you request.", capabilities: .init(tools: .init(listChanged: false)))
            await server.withMethodHandler(ListTools.self) { _ in
                .init(tools: Commands.tools.map { definition in
                    let properties = definition.properties.mapValues { type -> Value in
                        var schema: [String: Value] = ["type": .string(type)]
                        if type == "array" { schema["items"] = definition.name == "capture_email" ? .object(["type": .string("object"), "properties": .object(["title": .object(["type": .string("string")]), "dueDate": .object(["type": .string("string")]), "direction": .object(["type": .string("string"), "enum": .array([.string("i_owe"), .string("they_owe")])]), "priority": .object(["type": .string("string"), "enum": .array([.string("normal"), .string("high")])]), "notes": .object(["type": .string("string")])]), "required": .array([.string("title")]), "additionalProperties": .bool(false)]) : .object(["type": .string("string")]) }
                        return .object(schema)
                    }
                    return Tool(name: definition.name, description: definition.description, inputSchema: .object(["type": .string("object"), "properties": .object(properties), "required": .array(definition.required.map(Value.string)), "additionalProperties": .bool(false)]))
                })
            }
            await server.withMethodHandler(CallTool.self) { params in
                do {
                    let encoded = try JSONEncoder().encode(params.arguments ?? [:])
                    let args = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
                    let result = try Commands.call(params.name, args: args, store: store)
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
