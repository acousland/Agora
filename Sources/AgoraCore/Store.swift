import Foundation
import CSQLite

public final class Store: @unchecked Sendable {
    public let directory: URL
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public static var defaultDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["AGORA_DATA_DIR"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Agora", isDirectory: true)
    }

    public init(directory: URL = Store.defaultDirectory) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let database = directory.appendingPathComponent("agora.sqlite")
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; self.db = nil
            throw AgoraError.storage("Could not open the Agora database.")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: database.path)
        sqlite3_busy_timeout(db, 5000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        let version = try rows("PRAGMA user_version").first?.first.flatMap(Int.init) ?? 0
        guard version <= 1 else { throw AgoraError.storage("This library was created by a newer Agora version. Update the app before opening it.") }
        try transaction {
            try execute("CREATE TABLE IF NOT EXISTS contacts (id TEXT PRIMARY KEY, email TEXT COLLATE NOCASE, data BLOB NOT NULL)")
            try execute("CREATE UNIQUE INDEX IF NOT EXISTS contact_email ON contacts(email) WHERE email != ''")
            try execute("CREATE TABLE IF NOT EXISTS interactions (id TEXT PRIMARY KEY, contact_id TEXT NOT NULL REFERENCES contacts(id) ON DELETE RESTRICT, external_id TEXT, data BLOB NOT NULL)")
            try execute("CREATE UNIQUE INDEX IF NOT EXISTS interaction_external ON interactions(contact_id, external_id) WHERE external_id IS NOT NULL")
            try execute("CREATE TABLE IF NOT EXISTS commitments (id TEXT PRIMARY KEY, contact_id TEXT NOT NULL REFERENCES contacts(id) ON DELETE RESTRICT, interaction_id TEXT REFERENCES interactions(id) ON DELETE RESTRICT, data BLOB NOT NULL)")
            try execute("CREATE INDEX IF NOT EXISTS commitments_contact ON commitments(contact_id)")
            try execute("CREATE INDEX IF NOT EXISTS interactions_contact ON interactions(contact_id)")
            try execute("PRAGMA user_version=1")
        }
    }
    deinit { if let db { sqlite3_close(db) } }

    private func synchronized<T>(_ action: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try action() }
    private func failure() -> AgoraError { .storage(String(cString: sqlite3_errmsg(db))) }
    private func statement(_ sql: String, _ args: [String?]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw failure() }
        for (index, value) in args.enumerated() {
            if let value { sqlite3_bind_text(stmt, Int32(index + 1), value, -1, transient) }
            else { sqlite3_bind_null(stmt, Int32(index + 1)) }
        }
        return stmt
    }
    private func execute(_ sql: String, _ args: [String?] = []) throws {
        let stmt = try statement(sql, args); defer { sqlite3_finalize(stmt) }
        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw failure() }
    }
    private func rows(_ sql: String, _ args: [String?] = []) throws -> [[String]] {
        let stmt = try statement(sql, args); defer { sqlite3_finalize(stmt) }
        var result: [[String]] = []
        while true {
            let status = sqlite3_step(stmt)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw failure() }
            result.append((0..<sqlite3_column_count(stmt)).map { index in
                guard let value = sqlite3_column_text(stmt, index) else { return "" }
                return String(cString: value)
            })
        }
        return result
    }
    private func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
    private func all<T: Decodable>(_ table: String, as: T.Type) throws -> [T] {
        try rows("SELECT data FROM \(table)").map { try decoder.decode(T.self, from: Data($0[0].utf8)) }
    }
    private func transaction<T>(_ action: () throws -> T) throws -> T {
        try synchronized {
            try execute("BEGIN IMMEDIATE")
            do { let value = try action(); try execute("COMMIT"); return value }
            catch { try? execute("ROLLBACK"); throw error }
        }
    }
    private func clean(_ value: String, field: String, required: Bool = false, limit: Int = 10000) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !required || !result.isEmpty else { throw AgoraError.invalid("\(field) is required.") }
        guard result.count <= limit else { throw AgoraError.invalid("\(field) exceeds \(limit) characters.") }
        return result
    }
    private func email(_ value: String) throws -> String {
        let value = try clean(value, field: "Email", limit: 320).lowercased()
        guard value.isEmpty || (value.split(separator: "@").count == 2 && !value.contains(where: \.isWhitespace) && !value.hasSuffix("@")) else { throw AgoraError.invalid("Enter a valid email address.") }
        return value
    }
    public func contacts() throws -> [Person] { try synchronized { try all("contacts", as: Person.self).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } } }
    public func interactions() throws -> [Interaction] { try synchronized { try all("interactions", as: Interaction.self).sorted { $0.occurredAt > $1.occurredAt } } }
    public func commitments() throws -> [Commitment] {
        try synchronized { try all("commitments", as: Commitment.self).sorted { ($0.dueDate ?? "9999", $0.createdAt) < ($1.dueDate ?? "9999", $1.createdAt) } }
    }
    public func contact(_ id: String) throws -> Person {
        try synchronized {
            guard let data = try rows("SELECT data FROM contacts WHERE id=?", [id]).first?.first else { throw AgoraError.notFound }
            return try decoder.decode(Person.self, from: Data(data.utf8))
        }
    }
    public func commitment(_ id: String) throws -> Commitment {
        try synchronized {
            guard let data = try rows("SELECT data FROM commitments WHERE id=?", [id]).first?.first else { throw AgoraError.notFound }
            return try decoder.decode(Commitment.self, from: Data(data.utf8))
        }
    }
    @discardableResult public func createContact(name: String, email address: String = "", company: String = "", role: String = "", tags: [String] = [], notes: String = "") throws -> Person {
        try transaction {
            let now = Date().timeIntervalSince1970
            guard tags.count <= 30 else { throw AgoraError.invalid("Use at most 30 tags.") }
            let person = Person(id: UUID().uuidString, name: try clean(name, field: "Name", required: true, limit: 200), email: try email(address), company: try clean(company, field: "Company", limit: 200), role: try clean(role, field: "Role", limit: 200), tags: try tags.map { try clean($0, field: "Tag", required: true, limit: 50) }, notes: try clean(notes, field: "Notes"), createdAt: now, updatedAt: now, revision: 1)
            try execute("INSERT INTO contacts VALUES (?, ?, ?)", [person.id, person.email, try json(person)])
            return person
        }
    }
    // Transaction-safe internal variants allow Outlook capture to commit all records together.
    private func insertContact(name: String, address: String) throws -> Person {
        let now = Date().timeIntervalSince1970
        let person = Person(id: UUID().uuidString, name: try clean(name, field: "Name", required: true, limit: 200), email: try email(address), company: "", role: "", tags: [], notes: "", createdAt: now, updatedAt: now, revision: 1)
        try execute("INSERT INTO contacts VALUES (?, ?, ?)", [person.id, person.email, try json(person)])
        return person
    }
    public func updateContact(_ person: Person) throws -> Person {
        try transaction {
            let current = try contact(person.id)
            guard current.revision == person.revision else { throw AgoraError.stale }
            guard person.revision < Int.max else { throw AgoraError.invalid("This record's revision limit has been reached.") }
            var value = person
            value.name = try clean(value.name, field: "Name", required: true, limit: 200); value.email = try email(value.email)
            value.company = try clean(value.company, field: "Company", limit: 200); value.role = try clean(value.role, field: "Role", limit: 200)
            guard value.tags.count <= 30 else { throw AgoraError.invalid("Use at most 30 tags.") }
            value.tags = try value.tags.map { try clean($0, field: "Tag", required: true, limit: 50) }
            value.notes = try clean(value.notes, field: "Notes"); value.createdAt = current.createdAt
            value.updatedAt = Date().timeIntervalSince1970; value.revision += 1
            try execute("UPDATE contacts SET email=?, data=? WHERE id=?", [value.email, try json(value), value.id])
            return value
        }
    }
    public func deleteContact(_ id: String) throws {
        try transaction {
            _ = try contact(id)
            guard try rows("SELECT id FROM commitments WHERE contact_id=? UNION SELECT id FROM interactions WHERE contact_id=?", [id, id]).isEmpty else { throw AgoraError.invalid("This person has interactions or commitments. Keep their record to preserve your history.") }
            try execute("DELETE FROM contacts WHERE id=?", [id])
        }
    }
    @discardableResult public func logInteraction(contactId: String, kind: String, subject: String, body: String = "", occurredAt: Double = Date().timeIntervalSince1970) throws -> Interaction {
        try transaction { try insertInteraction(contactId: contactId, kind: kind, subject: subject, body: body, occurredAt: occurredAt, source: "manual", externalId: nil) }
    }
    private func insertInteraction(contactId: String, kind: String, subject: String, body: String, occurredAt: Double, source: String, externalId: String?) throws -> Interaction {
        _ = try contact(contactId)
        guard ["email", "meeting", "call", "message", "note"].contains(kind) else { throw AgoraError.invalid("Unknown interaction type.") }
        guard occurredAt.isFinite, occurredAt >= 0, occurredAt <= Date().addingTimeInterval(86400).timeIntervalSince1970 else { throw AgoraError.invalid("Interaction date must be a valid past or current date.") }
        let item = Interaction(id: UUID().uuidString, contactId: contactId, kind: kind, subject: try clean(subject, field: "Subject", required: true, limit: 500), body: try clean(body, field: "Body", limit: 200000), occurredAt: occurredAt, source: source, externalId: externalId)
        try execute("INSERT INTO interactions VALUES (?, ?, ?, ?)", [item.id, contactId, externalId, try json(item)])
        return item
    }
    private func validate(_ value: Commitment) throws -> Commitment {
        var value = value
        _ = try contact(value.contactId)
        value.title = try clean(value.title, field: "Commitment", required: true, limit: 500)
        value.notes = try clean(value.notes, field: "Notes")
        guard ["open", "done", "cancelled"].contains(value.status), ["normal", "high"].contains(value.priority), ["i_owe", "they_owe"].contains(value.direction) else { throw AgoraError.invalid("Invalid commitment status, priority or direction.") }
        if let due = value.dueDate, Day.date(due) == nil { throw AgoraError.invalid("Due date must be a real date in YYYY-MM-DD format.") }
        if let source = value.interactionId {
            guard !(try rows("SELECT id FROM interactions WHERE id=? AND contact_id=?", [source, value.contactId])).isEmpty else { throw AgoraError.invalid("The source interaction must belong to this person.") }
        }
        return value
    }
    @discardableResult public func createCommitment(contactId: String, title: String, dueDate: String? = nil, direction: String = "i_owe", priority: String = "normal", notes: String = "", interactionId: String? = nil) throws -> Commitment {
        try transaction { try insertCommitment(contactId: contactId, title: title, dueDate: dueDate, direction: direction, priority: priority, notes: notes, interactionId: interactionId) }
    }
    private func insertCommitment(contactId: String, title: String, dueDate: String?, direction: String, priority: String, notes: String, interactionId: String?) throws -> Commitment {
        let now = Date().timeIntervalSince1970
        let value = try validate(Commitment(id: UUID().uuidString, contactId: contactId, interactionId: interactionId, title: title, notes: notes, dueDate: dueDate, status: "open", priority: priority, direction: direction, createdAt: now, updatedAt: now, completedAt: nil, revision: 1))
        try execute("INSERT INTO commitments VALUES (?, ?, ?, ?)", [value.id, contactId, interactionId, try json(value)])
        return value
    }
    public func updateCommitment(_ value: Commitment) throws -> Commitment {
        try transaction {
            let current = try commitment(value.id)
            guard current.revision == value.revision else { throw AgoraError.stale }
            guard value.revision < Int.max else { throw AgoraError.invalid("This record's revision limit has been reached.") }
            var value = try validate(value)
            value.createdAt = current.createdAt; value.updatedAt = Date().timeIntervalSince1970; value.revision += 1
            value.completedAt = value.status == "done" ? (current.completedAt ?? value.updatedAt) : nil
            try execute("UPDATE commitments SET contact_id=?, interaction_id=?, data=? WHERE id=?", [value.contactId, value.interactionId, try json(value), value.id])
            return value
        }
    }
    public func snapshot() throws -> LibraryExport {
        try transaction { LibraryExport(contacts: try contacts(), interactions: try interactions(), commitments: try commitments()) }
    }
    public func importLibrary(_ library: LibraryExport) throws {
        guard library.schemaVersion == 1 else { throw AgoraError.invalid("Unsupported export version.") }
        guard library.contacts.count + library.interactions.count + library.commitments.count <= 100000 else { throw AgoraError.invalid("This export exceeds 100,000 records.") }
        try transaction {
            for var person in library.contacts {
                guard !person.id.isEmpty, person.revision > 0, person.revision < Int.max, person.createdAt.isFinite, person.updatedAt.isFinite else { throw AgoraError.invalid("Invalid imported contact.") }
                person.name = try clean(person.name, field: "Name", required: true, limit: 200); person.email = try email(person.email)
                person.company = try clean(person.company, field: "Company", limit: 200); person.role = try clean(person.role, field: "Role", limit: 200)
                guard person.tags.count <= 30 else { throw AgoraError.invalid("Too many tags.") }
                person.tags = try person.tags.map { try clean($0, field: "Tag", required: true, limit: 50) }
                person.notes = try clean(person.notes, field: "Notes")
                try execute("INSERT INTO contacts VALUES (?, ?, ?)", [person.id, person.email, try json(person)])
            }
            for item in library.interactions {
                _ = try contact(item.contactId)
                guard !item.id.isEmpty, item.occurredAt.isFinite, ["email", "meeting", "call", "message", "note"].contains(item.kind) else { throw AgoraError.invalid("Invalid imported interaction.") }
                _ = try clean(item.subject, field: "Subject", required: true, limit: 500); _ = try clean(item.body, field: "Body", limit: 200000)
                try execute("INSERT INTO interactions VALUES (?, ?, ?, ?)", [item.id, item.contactId, item.externalId, try json(item)])
            }
            for item in library.commitments {
                let item = try validate(item)
                guard !item.id.isEmpty, item.revision > 0, item.revision < Int.max, item.createdAt.isFinite, item.updatedAt.isFinite else { throw AgoraError.invalid("Invalid imported commitment.") }
                try execute("INSERT INTO commitments VALUES (?, ?, ?, ?)", [item.id, item.contactId, item.interactionId, try json(item)])
            }
        }
    }
    public func captureEmail(_ payload: [String: Any]) throws -> [String: Any] {
        try transaction {
            guard let address = payload["contactEmail"] as? String, let name = payload["contactName"] as? String,
                  let subject = payload["subject"] as? String, let external = payload["externalId"] as? String, !external.isEmpty else { throw AgoraError.invalid("An email needs a contact, subject and message ID.") }
            let normalized = try email(address)
            guard !normalized.isEmpty else { throw AgoraError.invalid("The email contact needs an address.") }
            _ = try clean(external, field: "Message ID", required: true, limit: 4096)
            let person: Person
            if let existing = try rows("SELECT data FROM contacts WHERE email=?", [normalized]).first?.first { person = try decoder.decode(Person.self, from: Data(existing.utf8)) }
            else { person = try insertContact(name: name, address: normalized) }
            let interaction: Interaction
            var duplicate = false
            if let existing = try rows("SELECT data FROM interactions WHERE contact_id=? AND external_id=?", [person.id, external]).first?.first {
                interaction = try decoder.decode(Interaction.self, from: Data(existing.utf8)); duplicate = true
            } else {
                interaction = try insertInteraction(contactId: person.id, kind: "email", subject: subject, body: payload["body"] as? String ?? "", occurredAt: payload["occurredAt"] as? Double ?? Date().timeIntervalSince1970, source: "outlook", externalId: external)
            }
            if let raw = payload["commitments"], !(raw is [[String: Any]]) { throw AgoraError.invalid("commitments must contain objects.") }
            let drafts = payload["commitments"] as? [[String: Any]] ?? []
            guard drafts.count <= 20 else { throw AgoraError.invalid("Capture at most 20 commitments at once.") }
            var ids: [String] = []
            for draft in drafts {
                guard Set(draft.keys).isSubset(of: ["title", "dueDate", "direction", "priority", "notes"]), draft.values.allSatisfy({ $0 is String }) else { throw AgoraError.invalid("Commitment fields must be title and optional dueDate, direction, priority and notes strings.") }
                guard let title = draft["title"] as? String else { throw AgoraError.invalid("Each commitment needs a title.") }
                let cleaned = try clean(title, field: "Commitment", required: true, limit: 500)
                if let existing = try commitments().first(where: { $0.interactionId == interaction.id && $0.title == cleaned }) { ids.append(existing.id); continue }
                let value = try insertCommitment(contactId: person.id, title: cleaned, dueDate: draft["dueDate"] as? String, direction: draft["direction"] as? String ?? "i_owe", priority: draft["priority"] as? String ?? "normal", notes: draft["notes"] as? String ?? "", interactionId: interaction.id)
                ids.append(value.id)
            }
            return ["contactId": person.id, "interactionId": interaction.id, "commitmentIds": ids, "alreadySaved": duplicate]
        }
    }
    public func pairingToken() throws -> String {
        try synchronized {
            let url = directory.appendingPathComponent("outlook-token")
            if let token = try? String(contentsOf: url, encoding: .utf8), token.count == 64 { return token }
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AgoraError.storage("Could not generate a secure pairing key.") }
            let token = bytes.map { String(format: "%02x", $0) }.joined()
            try token.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return token
        }
    }
    public func rotatePairingToken() throws -> String {
        try synchronized {
            let url = directory.appendingPathComponent("outlook-token")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return try pairingToken()
        }
    }
    public func backup(to url: URL) throws {
        try synchronized {
            guard !FileManager.default.fileExists(atPath: url.path) else { throw AgoraError.invalid("Choose a new backup filename.") }
            var destination: OpaquePointer?
            guard sqlite3_open(url.path, &destination) == SQLITE_OK else { if let destination { sqlite3_close(destination) }; throw AgoraError.storage("Could not create backup.") }
            defer { sqlite3_close(destination) }
            guard let backup = sqlite3_backup_init(destination, "main", db, "main") else { throw AgoraError.storage("Could not start backup.") }
            let result = sqlite3_backup_step(backup, -1); let finish = sqlite3_backup_finish(backup)
            guard result == SQLITE_DONE, finish == SQLITE_OK else { try? FileManager.default.removeItem(at: url); throw AgoraError.storage("Backup could not finish. Try again.") }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

import Security
