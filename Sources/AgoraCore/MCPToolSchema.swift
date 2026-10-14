import Foundation

extension Commands {
    public static func inputSchema(for tool: ToolDefinition) -> [String: Any] {
        func field(_ name: String, _ type: String) -> [String: Any] {
            var value: [String: Any] = ["type": type]
            if type == "array" { value["items"] = ["type": "string"] }
            switch name {
            case "status": value["enum"] = ["open", "done", "cancelled"]
            case "direction": value["enum"] = ["i_owe", "they_owe"]
            case "priority": value["enum"] = ["normal", "high"]
            case "kind": value["enum"] = ["email", "meeting", "call", "message", "note"]
            case "dueDate", "dueBefore": value["pattern"] = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
            case "limit": value["minimum"] = 1; value["maximum"] = 200
            case "offset": value["minimum"] = 0
            case "expectedRevision": value["minimum"] = 1
            default: break
            }
            return value
        }
        var properties = tool.properties.mapValues { ["type": $0] as [String: Any] }
        for (name, type) in tool.properties { properties[name] = field(name, type) }
        if tool.name == "update_contact" || tool.name == "update_commitment" {
            let fields: [String: String] = tool.name == "update_contact"
                ? ["name": "string", "email": "string", "company": "string", "role": "string", "tags": "array", "notes": "string"]
                : ["title": "string", "notes": "string", "dueDate": "string", "direction": "string", "priority": "string", "status": "string"]
            var nested: [String: Any] = [:]
            for (name, type) in fields { nested[name] = field(name, type) }
            if tool.name == "update_commitment" { var due = field("dueDate", "string"); due["type"] = ["string", "null"]; nested["dueDate"] = due }
            properties["fields"] = ["type": "object", "properties": nested, "minProperties": 1, "additionalProperties": false]
        }
        if tool.name == "capture_email" {
            var nested: [String: Any] = [:]
            for name in ["title", "dueDate", "direction", "priority", "notes"] { nested[name] = field(name, "string") }
            properties["commitments"] = ["type": "array", "maxItems": 20, "items": ["type": "object", "properties": nested, "required": ["title"], "additionalProperties": false]]
        }
        return ["type": "object", "properties": properties, "required": tool.required, "additionalProperties": false]
    }
}
