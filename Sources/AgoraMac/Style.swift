import SwiftUI
import AgoraCore

enum Style {
    static let accent = Color(red: 0.38, green: 0.38, blue: 0.76)
    static let sidebar = Color(red: 0.12, green: 0.15, blue: 0.20)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let green = Color(red: 0.24, green: 0.53, blue: 0.43)
    static let orange = Color(red: 0.72, green: 0.42, blue: 0.19)
    static let red = Color(red: 0.73, green: 0.32, blue: 0.34)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Style.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.05), lineWidth: 1)) }
}

struct Avatar: View {
    var person: Person?
    var size: CGFloat = 36
    var body: some View {
        Text(person?.initials ?? "?").font(.system(size: size * 0.32, weight: .semibold, design: .rounded)).foregroundStyle(Style.accent)
            .frame(width: size, height: size).background(Style.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.32))
    }
}

struct Pill: View {
    var text: String
    var color: Color = Style.accent
    var body: some View { Text(text).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 5).foregroundStyle(color).background(color.opacity(0.09), in: Capsule()) }
}

struct EmptyState: View {
    var icon: String
    var title: String
    var detail: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(Style.accent).frame(width: 64, height: 64).background(Style.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 310)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(Style.accent).padding(.top, 4) }
        }.frame(maxWidth: .infinity).padding(.vertical, 36)
    }
}

func dueLabel(_ value: Commitment) -> String {
    if value.status == "done" { return "Kept" }
    if value.status == "cancelled" { return "Cancelled" }
    guard let day = value.dueDate, let date = Day.date(day) else { return "No deadline" }
    if day == Day.string() { return "Today" }
    if day == Day.string(Calendar.current.date(byAdding: .day, value: 1, to: Date())!) { return "Tomorrow" }
    return date.formatted(.dateTime.day().month(.abbreviated))
}

func interactionIcon(_ kind: String) -> String { switch kind { case "email": "envelope"; case "call": "phone"; case "meeting": "person.2"; case "message": "bubble.left"; default: "note.text" } }

struct PromiseRow: View {
    @EnvironmentObject var model: AppModel
    var item: Commitment
    var compact = false
    var body: some View {
        HStack(spacing: 13) {
            Button { model.markDone(item) } label: { Image(systemName: item.status == "done" ? "checkmark.circle.fill" : "circle").font(.system(size: 20, weight: .light)).foregroundStyle(item.status == "done" ? Style.green : .secondary.opacity(0.45)) }
                .buttonStyle(.plain).help(item.status == "done" ? "Reopen commitment" : "Mark as kept").accessibilityLabel(item.status == "done" ? "Reopen \(item.title)" : "Complete \(item.title)")
            Button {
                model.selectedCommitment = item.id
                if model.section == .people { model.sheet = .commitment(item, item.contactId) }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1).strikethrough(item.status == "done")
                            if item.priority == "high" { Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(Style.orange) }
                        }
                        HStack(spacing: 5) {
                            Text(model.person(item.contactId)?.name ?? "Unknown person")
                            Text("·")
                            Text(item.direction == "i_owe" ? "I promised" : "Waiting on them")
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 10)
                    Pill(text: item.overdue ? "Overdue · \(dueLabel(item))" : dueLabel(item), color: item.overdue ? Style.red : item.status == "done" ? Style.green : item.dueDate == Day.string() ? Style.orange : .secondary)
                    if !compact { Avatar(person: model.person(item.contactId), size: 29) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.padding(.vertical, 14).padding(.horizontal, 14)
            .background(model.selectedCommitment == item.id ? Style.accent.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
    }
}

struct ActivityRow: View {
    @EnvironmentObject var model: AppModel
    var item: Interaction
    var showsTime = false
    var body: some View {
        Button { model.sheet = .source(item) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: interactionIcon(item.kind)).font(.system(size: 13)).foregroundStyle(Style.accent).frame(width: 32, height: 32).background(Style.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.subject).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    HStack(spacing: 5) { Text(model.person(item.contactId)?.name ?? "Unknown person"); Text("·"); Text(item.kind.capitalized); if item.source == "outlook" { Text("· Outlook") } }.font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(showsTime ? Date(timeIntervalSince1970: item.occurredAt).formatted(date: .abbreviated, time: .shortened) : Date(timeIntervalSince1970: item.occurredAt).formatted(.dateTime.day().month(.abbreviated))).font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(.vertical, 13).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
