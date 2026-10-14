import Foundation

public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let properties: [String: String]
    public let required: [String]
}

public enum Commands {
    public static let tools: [ToolDefinition] = [
        .init(name: "get_overview", description: "Summarise your local CRM: overdue promises, due-today commitments, waiting-on-others and recent interactions. Dates use the Mac's local timezone.", properties: [:], required: []),
        .init(name: "list_contacts", description: "Find people by name, email, company or tag. Paginated; limit defaults to 50, maximum 200.", properties: ["search": "string", "limit": "integer", "offset": "integer"], required: []),
        .init(name: "get_contact", description: "Read a person's profile, interactions and commitments before making changes.", properties: ["id": "string"], required: ["id"]),
        .init(name: "create_contact", description: "Create a person in the local CRM. Nonempty email addresses must be unique.", properties: ["name": "string", "email": "string", "company": "string", "role": "string", "tags": "array", "notes": "string"], required: ["name"]),
        .init(name: "update_contact", description: "Patch a profile. fields may contain name, email, company, role, tags or notes. Get the latest revision first; stale updates are rejected.", properties: ["id": "string", "expectedRevision": "integer", "fields": "object"], required: ["id", "expectedRevision", "fields"]),
        .init(name: "log_interaction", description: "Record an email, meeting, call, message or note with a person. occurredAt is an optional Unix timestamp in seconds.", properties: ["contactId": "string", "kind": "string", "subject": "string", "body": "string", "occurredAt": "number"], required: ["contactId", "kind", "subject"]),
        .init(name: "list_commitments", description: "List promises, filtered by contactId, status (open/done/cancelled), direction (i_owe/they_owe), overdueOnly, or dueBefore (YYYY-MM-DD inclusive). Paginated.", properties: ["contactId": "string", "status": "string", "direction": "string", "overdueOnly": "boolean", "dueBefore": "string", "search": "string", "limit": "integer", "offset": "integer"], required: []),
        .init(name: "create_commitment", description: "Register a promise you made or a promise someone made to you. direction defaults to i_owe, priority to normal. dueDate is an optional local YYYY-MM-DD date. Link interactionId to preserve its source.", properties: ["contactId": "string", "title": "string", "dueDate": "string", "direction": "string", "priority": "string", "notes": "string", "interactionId": "string"], required: ["contactId", "title"]),
        .init(name: "update_commitment", description: "Patch title, notes, dueDate, direction, priority or status. Set status to done to keep a promise, open to reopen, cancelled to cancel. A null dueDate removes the deadline. Requires the latest expectedRevision.", properties: ["id": "string", "expectedRevision": "integer", "fields": "object"], required: ["id", "expectedRevision", "fields"]),
        .init(name: "capture_email", description: "Atomically save an Outlook email and its promises. Finds or creates the contact by email. Duplicate message IDs and repeated titles are idempotent. commitments contains objects with title and optional dueDate, direction, priority, notes.", properties: ["contactName": "string", "contactEmail": "string", "subject": "string", "body": "string", "externalId": "string", "occurredAt": "number", "commitments": "array"], required: ["contactName", "contactEmail", "subject", "externalId"])
    ]
    public static func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
    private static func string(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = args[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgoraError.invalid("\(key) is required.") }
        return value
    }
    private static func page<T: Encodable>(_ items: [T], _ args: [String: Any], key: String) throws -> [String: Any] {
        let limit = args["limit"] as? Int ?? 50, offset = args["offset"] as? Int ?? 0
        guard (1...200).contains(limit), offset >= 0 else { throw AgoraError.invalid("limit must be 1–200 and offset nonnegative.") }
        let values = Array(items.dropFirst(offset).prefix(limit))
        return [key: try object(values), "total": items.count, "nextOffset": offset + values.count < items.count ? offset + values.count as Any : NSNull()]
    }
    private static func patch<T: Codable>(_ current: T, _ args: [String: Any], allowed: Set<String>) throws -> T {
        guard let revision = args["expectedRevision"] as? Int, let fields = args["fields"] as? [String: Any], !fields.isEmpty else { throw AgoraError.invalid("Supply expectedRevision and nonempty fields.") }
        guard Set(fields.keys).isSubset(of: allowed) else { throw AgoraError.invalid("One or more fields cannot be edited.") }
        var data = try object(current) as! [String: Any]
        guard data["revision"] as? Int == revision else { throw AgoraError.stale }
        for (key, value) in fields { data[key] = value }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: data))
    }
    public static func call(_ name: String, args: [String: Any], store: Store) throws -> Any {
        guard let definition = tools.first(where: { $0.name == name }) else { throw AgoraError.invalid("Unknown tool: \(name)") }
        guard Set(args.keys).isSubset(of: Set(definition.properties.keys)) else { throw AgoraError.invalid("Unknown argument.") }
        for (key, value) in args {
            let type = definition.properties[key]!
            let number = value as? NSNumber
            let isBoolean = number.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            let valid: Bool
            switch type {
            case "string": valid = value is String
            case "object": valid = value is [String: Any]
            case "array": valid = value is [Any]
            case "boolean": valid = isBoolean
            case "integer": valid = number != nil && !isBoolean && number!.doubleValue.isFinite && number!.doubleValue.rounded() == number!.doubleValue
            case "number": valid = number != nil && !isBoolean && number!.doubleValue.isFinite
            default: valid = false
            }
            guard valid else { throw AgoraError.invalid("\(key) must be a \(type).") }
        }
        for key in definition.required where args[key] == nil { throw AgoraError.invalid("\(key) is required.") }
        switch name {
        case "get_overview":
            let library = try store.snapshot(), open = library.commitments.filter { $0.status == "open" }
            return ["contacts": library.contacts.count, "open": open.count, "overdue": try object(open.filter(\.overdue)), "dueToday": try object(open.filter { $0.dueDate == Day.string() }), "waiting": try object(open.filter { $0.direction == "they_owe" }), "recentInteractions": try object(Array(library.interactions.prefix(10)))] as [String: Any]
        case "list_contacts":
            let query = (args["search"] as? String ?? "").lowercased()
            return try page(store.contacts().filter { query.isEmpty || [$0.name, $0.emailAddresses.joined(separator: " "), $0.company, $0.tags.joined(separator: " ")].joined(separator: " ").lowercased().contains(query) }, args, key: "contacts")
        case "get_contact":
            let id = try string(args, "id"), library = try store.snapshot()
            return ["contact": try object(store.contact(id)), "interactions": try object(library.interactions.filter { $0.contactId == id }), "commitments": try object(library.commitments.filter { $0.contactId == id })]
        case "create_contact":
            if let tags = args["tags"] as? [Any], !(tags.allSatisfy { $0 is String }) { throw AgoraError.invalid("tags must contain strings.") }
            return try object(store.createContact(name: string(args, "name"), email: args["email"] as? String ?? "", company: args["company"] as? String ?? "", role: args["role"] as? String ?? "", tags: args["tags"] as? [String] ?? [], notes: args["notes"] as? String ?? ""))
        case "update_contact":
            return try object(store.updateContact(patch(store.contact(string(args, "id")), args, allowed: ["name", "email", "company", "role", "tags", "notes"])))
        case "log_interaction":
            return try object(store.logInteraction(contactId: string(args, "contactId"), kind: string(args, "kind"), subject: string(args, "subject"), body: args["body"] as? String ?? "", occurredAt: args["occurredAt"] as? Double ?? Date().timeIntervalSince1970))
        case "list_commitments":
            if let status = args["status"] as? String, !["open", "done", "cancelled"].contains(status) { throw AgoraError.invalid("Unknown status.") }
            if let direction = args["direction"] as? String, !["i_owe", "they_owe"].contains(direction) { throw AgoraError.invalid("Unknown direction.") }
            if let day = args["dueBefore"] as? String, Day.date(day) == nil { throw AgoraError.invalid("dueBefore must be YYYY-MM-DD.") }
            let query = (args["search"] as? String ?? "").lowercased()
            let values = try store.commitments().filter { item in
                (args["contactId"] == nil || item.contactId == args["contactId"] as? String) &&
                (args["status"] == nil || item.status == args["status"] as? String) &&
                (args["direction"] == nil || item.direction == args["direction"] as? String) &&
                (args["overdueOnly"] as? Bool != true || item.overdue) &&
                (args["dueBefore"] == nil || item.dueDate.map { $0 <= args["dueBefore"] as! String } == true) &&
                (query.isEmpty || (item.title + " " + item.notes).lowercased().contains(query))
            }
            return try page(values, args, key: "commitments")
        case "create_commitment":
            return try object(store.createCommitment(contactId: string(args, "contactId"), title: string(args, "title"), dueDate: args["dueDate"] as? String, direction: args["direction"] as? String ?? "i_owe", priority: args["priority"] as? String ?? "normal", notes: args["notes"] as? String ?? "", interactionId: args["interactionId"] as? String))
        case "update_commitment":
            return try object(store.updateCommitment(patch(store.commitment(string(args, "id")), args, allowed: ["title", "notes", "dueDate", "direction", "priority", "status"])))
        case "capture_email": return try store.captureEmail(args)
        default: throw AgoraError.invalid("Unknown tool.")
        }
    }
}

import CoreFoundation
