import Foundation

public enum Timeline {
    /// Each gap is measured against the same person's complete history, before UI filtering.
    public static func gapsByInteraction(_ interactions: [Interaction]) -> [String: TimeInterval] {
        var previous: [String: Double] = [:], gaps: [String: TimeInterval] = [:]
        for item in interactions.sorted(by: { ($0.occurredAt, $0.id) < ($1.occurredAt, $1.id) }) {
            if let earlier = previous[item.contactId] { gaps[item.id] = max(0, item.occurredAt - earlier) }
            previous[item.contactId] = item.occurredAt
        }
        return gaps
    }
    public static func gapDescription(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "First recorded interaction with this person" }
        if seconds == 0 { return "Same time as the previous interaction" }
        if seconds < 60 { return "Less than a minute since the previous interaction" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]; formatter.maximumUnitCount = 2; formatter.unitsStyle = .full
        return "\(formatter.string(from: seconds) ?? "A short time") since the previous interaction"
    }
}
