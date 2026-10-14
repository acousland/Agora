import Foundation

public struct Person: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var email: String
    public var company: String
    public var role: String
    public var tags: [String]
    public var notes: String
    public var createdAt: Double
    public var updatedAt: Double
    public var revision: Int
    public var alternateEmails: [String]? = nil
    public var emailAddresses: [String] { ([email] + (alternateEmails ?? [])).filter { !$0.isEmpty } }
    public var initials: String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
}

public struct Interaction: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var contactId: String
    public var kind: String
    public var subject: String
    public var body: String
    public var occurredAt: Double
    public var source: String
    public var externalId: String?
    public var duplicateExternalId: String? = nil
}

public struct Commitment: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var contactId: String
    public var interactionId: String?
    public var title: String
    public var notes: String
    public var dueDate: String?
    public var status: String
    public var priority: String
    public var direction: String
    public var createdAt: Double
    public var updatedAt: Double
    public var completedAt: Double?
    public var revision: Int
    public init(id: String, contactId: String, interactionId: String?, title: String, notes: String, dueDate: String?, status: String, priority: String, direction: String, createdAt: Double, updatedAt: Double, completedAt: Double?, revision: Int) {
        self.id = id; self.contactId = contactId; self.interactionId = interactionId; self.title = title; self.notes = notes; self.dueDate = dueDate; self.status = status; self.priority = priority; self.direction = direction; self.createdAt = createdAt; self.updatedAt = updatedAt; self.completedAt = completedAt; self.revision = revision
    }
    public var overdue: Bool { status == "open" && dueDate.map { $0 < Day.string() } == true }
}

public struct LibraryExport: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var contacts: [Person]
    public var interactions: [Interaction]
    public var commitments: [Commitment]
}

public enum Day {
    public static func string(_ date: Date = Date()) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    public static func date(_ value: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard value.count == 10, let date = formatter.date(from: value), string(date) == value else { return nil }
        return date
    }
}

public enum AgoraError: LocalizedError {
    case invalid(String), storage(String), notFound, stale
    public var errorDescription: String? {
        switch self {
        case .invalid(let message), .storage(let message): return message
        case .notFound: return "This record no longer exists. Refresh and try again."
        case .stale: return "This record changed elsewhere. Refresh before saving your changes."
        }
    }
}
