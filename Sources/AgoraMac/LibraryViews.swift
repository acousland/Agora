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
    @State private var deleting: Person?
    private var filtered: [Person] { model.people.filter { model.matches($0.name, $0.emailAddresses.joined(separator: " "), $0.company, $0.tags.joined(separator: " ")) } }
    private var selected: Person? { filtered.first { $0.id == model.selectedPerson } ?? filtered.first }
    var body: some View {
        content.alert("Delete this person?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { person in
            Button("Delete person", role: .destructive) { delete(person) }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { person in
            let interactions = model.interactions.filter { $0.contactId == person.id }.count
            let commitments = model.commitments.filter { $0.contactId == person.id }.count
            Text("Delete \(person.name) and all linked history?\n\nInteractions: \(interactions)\nCommitments: \(commitments)\n\nA database backup will be saved in your library's Backups folder first.")
        }
    }
    @ViewBuilder private var content: some View {
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
                            }.buttonStyle(.plain).contextMenu { managementActions(person) }
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
                                    if let addresses = person.alternateEmails, !addresses.isEmpty { Text("Also: " + addresses.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled) }
                                    if !person.tags.isEmpty { HStack { ForEach(person.tags, id: \.self) { Pill(text: $0) } } }
                                }
                                Spacer()
                                Button("Edit") { model.sheet = .person(person) }.buttonStyle(.bordered).controlSize(.small)
                                Menu("More") { managementActions(person) }.menuStyle(.borderlessButton).fixedSize().help("Merge or delete this person")
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
    @ViewBuilder private func managementActions(_ person: Person) -> some View {
        Button("Merge with another person…", systemImage: "arrow.triangle.merge") { model.sheet = .merge(person) }.disabled(model.people.count < 2)
        Divider()
        Button("Delete person…", systemImage: "trash", role: .destructive) { deleting = person }
    }
    private func delete(_ person: Person) {
        let interactionCount = model.interactions.filter { $0.contactId == person.id }.count
        let commitmentCount = model.commitments.filter { $0.contactId == person.id }.count
        model.perform { store in
            try store.deleteContact(person.id, includingHistory: true, expectedRevision: person.revision, expectedInteractionCount: interactionCount, expectedCommitmentCount: commitmentCount)
            model.selectedPerson = nil; model.notice = "Person deleted. A backup was saved in your library's Backups folder."
        }
        deleting = nil
    }
}

struct TimelineView: View {
    @EnvironmentObject var model: AppModel
    @State private var kind = "All"
    @AppStorage("timelineGrouping") private var grouping = "date"
    private var filtered: [Interaction] { model.interactions.filter { model.matches($0.subject, $0.body, model.person($0.contactId)?.name ?? "") && (kind == "All" || $0.kind == kind.lowercased()) } }
    private var gaps: [String: TimeInterval] { Timeline.gapsByInteraction(model.interactions) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 20) {
                    Picker("Type", selection: $kind) { ForEach(["All", "Email", "Meeting", "Call", "Message", "Note"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 480)
                    Spacer(minLength: 0)
                    HStack(spacing: 8) { Text("Group by").font(.system(size: 11)).foregroundStyle(.secondary); Picker("Group by", selection: $grouping) { Text("Date").tag("date"); Text("Person").tag("person") }.labelsHidden().pickerStyle(.segmented).frame(width: 155) }
                }
                Text("Gaps show the time since each person's previous interaction, including interactions hidden by filters.").font(.system(size: 11)).foregroundStyle(.secondary)
                Card {
                    if filtered.isEmpty { EmptyState(icon: "bubble.left.and.bubble.right", title: "Every conversation counts", detail: "Log an interaction here, or save an email from Outlook.", actionTitle: "Log interaction") { model.sheet = .interaction(nil) } }
                    else {
                        VStack(alignment: .leading, spacing: 20) {
                            let grouped = Dictionary(grouping: filtered) { grouping == "person" ? $0.contactId : Day.string(Date(timeIntervalSince1970: $0.occurredAt)) }
                            let keys = grouping == "person" ? grouped.keys.sorted { (model.person($0)?.name ?? "").localizedCaseInsensitiveCompare(model.person($1)?.name ?? "") == .orderedAscending } : grouped.keys.sorted(by: >)
                            let intervals = gaps
                            ForEach(keys, id: \.self) { key in
                                VStack(alignment: .leading, spacing: 6) {
                                    if grouping == "person" {
                                        let count = grouped[key]?.count ?? 0
                                        HStack(spacing: 10) { Avatar(person: model.person(key), size: 30); Text(model.person(key)?.name ?? "Unknown person").font(.system(size: 14, weight: .semibold)); Spacer(); Text(count == 1 ? "1 interaction" : "\(count) interactions").font(.system(size: 10)).foregroundStyle(.secondary) }.padding(.bottom, 8)
                                    } else {
                                        Text(Day.date(key)?.formatted(.dateTime.weekday(.wide).day().month(.wide).year()) ?? key).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 8)
                                    }
                                    ForEach(grouped[key] ?? []) { item in
                                        VStack(alignment: .leading, spacing: 0) {
                                            ActivityRow(item: item, showsTime: true)
                                            Label(Timeline.gapDescription(intervals[item.id]), systemImage: "clock.arrow.circlepath").font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 44).padding(.bottom, 12)
                                        }
                                    }
                                }
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }
            }.padding(28)
        }
    }
}
