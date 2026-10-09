import SwiftUI
import AgoraCore

struct CommitmentsView: View {
    @EnvironmentObject var model: AppModel
    @State private var filter = "I promised"
    private var items: [Commitment] {
        model.commitments.filter { item in
            model.matches(item.title, model.person(item.contactId)?.name ?? "", item.notes) &&
            (filter == "All" || (filter == "I promised" && item.status == "open" && item.direction == "i_owe") || (filter == "Waiting on" && item.status == "open" && item.direction == "they_owe") || (filter == "Kept" && item.status == "done"))
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Picker("Show", selection: $filter) { ForEach(["I promised", "Waiting on", "Kept", "All"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 400); Spacer() }
                Card {
                    if items.isEmpty { EmptyState(icon: "checkmark.circle", title: "Nothing here yet", detail: model.search.isEmpty ? "Promises, introductions and little things you said you'd do. Give them a place to live.": "Try another name or phrase.", actionTitle: "New commitment") { model.sheet = .commitment(nil, nil) } }
                    else { VStack(spacing: 0) { ForEach(items) { item in PromiseRow(item: item); if item.id != items.last?.id { Divider().padding(.leading, 46).opacity(0.5) } } }.padding(.horizontal, -10) }
                }
            }.padding(28)
        }
    }
}

struct PeopleView: View {
    @EnvironmentObject var model: AppModel
    private var filtered: [Person] { model.people.filter { model.matches($0.name, $0.email, $0.company, $0.tags.joined(separator: " ")) } }
    private var selected: Person? { model.people.first { $0.id == model.selectedPerson } ?? filtered.first }
    var body: some View {
        if model.people.isEmpty {
            EmptyState(icon: "person.2", title: "Your people, all together", detail: "A place for friends, collaborators, and everyone you want to show up for.", actionTitle: "Add your first person") { model.sheet = .person(nil) }
        } else {
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("\(filtered.count) PEOPLE").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary); Spacer(); Button { model.sheet = .person(nil) } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("Add person") }.padding(.bottom, 12)
                        ForEach(filtered) { person in
                            Button { model.selectedPerson = person.id } label: {
                                HStack(spacing: 12) {
                                    Avatar(person: person, size: 39)
                                    VStack(alignment: .leading, spacing: 5) { Text(person.name).font(.system(size: 12, weight: .medium)); Text(person.company.isEmpty ? person.email : person.company).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                                    Spacer()
                                }.padding(12).background(selected?.id == person.id ? Style.accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if filtered.isEmpty { Text("No matching people").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 20) }
                    }.padding(22)
                }.frame(width: 280)
                Divider().opacity(0.5)
                if let person = selected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 25) {
                            HStack(alignment: .top, spacing: 18) {
                                Avatar(person: person, size: 68)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(person.name).font(.system(size: 28, weight: .semibold)).tracking(-0.7)
                                    Text([person.role, person.company].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(.secondary)
                                    if !person.email.isEmpty { Text(person.email).font(.system(size: 11)).foregroundStyle(Style.accent).textSelection(.enabled) }
                                    if !person.tags.isEmpty { HStack { ForEach(person.tags, id: \.self) { Pill(text: $0) } } }
                                }
                                Spacer()
                                Button("Edit") { model.sheet = .person(person) }.buttonStyle(.bordered).controlSize(.small)
                            }
                            HStack { Button("Make a commitment", systemImage: "plus") { model.sheet = .commitment(nil, person.id) }.buttonStyle(.borderedProminent); Button("Log interaction", systemImage: "bubble.left") { model.sheet = .interaction(person.id) }.buttonStyle(.bordered) }.controlSize(.small)
                            if !person.notes.isEmpty { Card { VStack(alignment: .leading, spacing: 12) { Text("Worth remembering").font(.system(size: 13, weight: .semibold)); Text(person.notes).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5).textSelection(.enabled) } } }
                            Card {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Commitments").font(.system(size: 14, weight: .semibold))
                                    let promises = model.commitments.filter { $0.contactId == person.id }
                                    if promises.isEmpty { Text("No promises recorded yet.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 12) }
                                    else { ForEach(promises) { PromiseRow(item: $0, compact: true) } }
                                }
                            }
                            Card {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Conversation history").font(.system(size: 14, weight: .semibold))
                                    let history = model.interactions.filter { $0.contactId == person.id }
                                    if history.isEmpty { Text("Log a conversation to start the story.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 12) }
                                    else { ForEach(history) { ActivityRow(item: $0) } }
                                }
                            }
                        }.padding(32)
                    }
                } else { Spacer() }
            }
        }
    }
}

struct TimelineView: View {
    @EnvironmentObject var model: AppModel
    @State private var kind = "All"
    private var filtered: [Interaction] { model.interactions.filter { model.matches($0.subject, $0.body, model.person($0.contactId)?.name ?? "") && (kind == "All" || $0.kind == kind.lowercased()) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Picker("Type", selection: $kind) { ForEach(["All", "Email", "Meeting", "Call", "Message", "Note"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 530); Spacer() }
                Card {
                    if filtered.isEmpty { EmptyState(icon: "bubble.left.and.bubble.right", title: "Every conversation counts", detail: "Log an interaction here, or save an email from Outlook.", actionTitle: "Log interaction") { model.sheet = .interaction(nil) } }
                    else {
                        VStack(alignment: .leading, spacing: 20) {
                            let grouped = Dictionary(grouping: filtered) { Day.string(Date(timeIntervalSince1970: $0.occurredAt)) }
                            ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                                VStack(alignment: .leading, spacing: 6) { Text(Day.date(day)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? day).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 8); ForEach(grouped[day] ?? []) { ActivityRow(item: $0) } }
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }
            }.padding(28)
        }
    }
}
