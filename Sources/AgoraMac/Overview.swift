import SwiftUI
import AgoraCore

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                        Text("Your word, kept.").font(.system(size: 32, weight: .semibold)).tracking(-1.1)
                        Text(model.overdue.isEmpty ? "Make room for the people who matter." : "A few promises could use your attention.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "sun.max").font(.system(size: 35, weight: .ultraLight)).foregroundStyle(Style.orange.opacity(0.65)).padding(.top, 22)
                }.padding(.top, 5)
                HStack(spacing: 12) {
                    stat("DUE TODAY", value: model.today.count, icon: "sun.max", color: Style.orange)
                    stat("OVERDUE", value: model.overdue.count, icon: "clock", color: Style.red)
                    stat("WAITING ON", value: model.waiting.count, icon: "arrow.turn.down.right", color: Style.accent)
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Label("On your radar", systemImage: "scope").font(.system(size: 14, weight: .semibold)); Spacer(); Text("\(model.owed.count) open").font(.system(size: 10)).foregroundStyle(.secondary) }
                        Text("The promises you made, in the order they need you.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 7)
                        let focus = model.focus.filter { model.matches($0.title, model.person($0.contactId)?.name ?? "") }
                        if focus.isEmpty {
                            EmptyState(icon: "checkmark.seal", title: model.search.isEmpty ? "A fresh start" : "No matching commitments", detail: model.people.isEmpty ? "Add someone to your circle, then capture your first promise." : "Register a promise and give it a place to land.", actionTitle: model.people.isEmpty ? "Add your first person" : "Make a commitment") {
                                model.sheet = model.people.isEmpty ? .person(nil) : .commitment(nil, nil)
                            }
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(focus.prefix(5))) { item in PromiseRow(item: item); if item.id != focus.prefix(5).last?.id { Divider().padding(.leading, 46).opacity(0.45) } }
                            }.padding(.horizontal, -12)
                            if focus.count > 5 { Button("View all commitments →") { model.section = .commitments }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Style.accent).padding(.top, 8) }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text("Recent conversations").font(.system(size: 14, weight: .semibold)); Spacer(); Button("View timeline →") { model.section = .timeline }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary) }.padding(.bottom, 8)
                        if model.interactions.isEmpty { Text("Your first conversation starts the story.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 17) }
                        else { ForEach(Array(model.interactions.prefix(3))) { ActivityRow(item: $0) } }
                    }
                }
            }.padding(28)
        }
    }
    private func stat(_ title: String, value: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text(title).font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(.secondary); Spacer(); Image(systemName: icon).font(.system(size: 13)).foregroundStyle(color) }
            HStack(alignment: .firstTextBaseline, spacing: 7) { Text("\(value)").font(.system(size: 29, weight: .medium, design: .rounded)); Text(value == 1 ? "promise" : "promises").font(.system(size: 10)).foregroundStyle(.tertiary) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Style.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.05)))
    }
}

struct CommitmentInspector: View {
    @EnvironmentObject var model: AppModel
    private var item: Commitment? { model.commitments.first { $0.id == model.selectedCommitment } ?? model.focus.first }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text("A LITTLE CONTEXT").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary); Spacer(); Image(systemName: "sidebar.right").foregroundStyle(.tertiary).font(.system(size: 12)) }
                if let item, let person = model.person(item.contactId) {
                    VStack(alignment: .leading, spacing: 14) {
                        Avatar(person: person, size: 58)
                        VStack(alignment: .leading, spacing: 5) { Text(person.name).font(.system(size: 20, weight: .semibold)).tracking(-0.5); Text([person.role, person.company].filter { !$0.isEmpty }.joined(separator: " at ")).font(.system(size: 11)).foregroundStyle(.secondary) }
                        Button("View relationship →") { model.selectedPerson = person.id; model.section = .people }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Style.accent)
                    }
                    Divider().opacity(0.55)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.direction == "i_owe" ? "YOU PROMISED" : "THEY PROMISED").font(.system(size: 8, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                        Text(item.title).font(.system(size: 17, weight: .medium)).lineSpacing(4)
                        HStack { Image(systemName: "calendar").font(.system(size: 12)); Text(item.dueDate.flatMap(Day.date)?.formatted(date: .abbreviated, time: .omitted) ?? "No deadline").font(.system(size: 11)); Spacer(); if item.overdue { Pill(text: "Overdue", color: Style.red) } }.foregroundStyle(.secondary)
                        if !item.notes.isEmpty { Text(item.notes).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5).padding(.top, 5) }
                        HStack {
                            Button(item.status == "done" ? "Reopen" : "Mark as kept") { model.markDone(item) }.buttonStyle(.borderedProminent).tint(Style.accent).controlSize(.small)
                            Button("Edit") { model.sheet = .commitment(item, item.contactId) }.buttonStyle(.bordered).controlSize(.small)
                        }.padding(.top, 8)
                    }
                    if let sourceId = item.interactionId, let source = model.interactions.first(where: { $0.id == sourceId }) {
                        Divider().opacity(0.55)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("WHERE IT STARTED").font(.system(size: 8, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                            Button { model.sheet = .source(source) } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    Label(source.kind.capitalized, systemImage: interactionIcon(source.kind)).font(.system(size: 10)).foregroundStyle(Style.accent)
                                    Text(source.subject).font(.system(size: 12, weight: .medium))
                                    Text(source.body).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(4).lineSpacing(4)
                                    Text("Open conversation ↗").font(.system(size: 10)).foregroundStyle(Style.accent)
                                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Style.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                    if !person.notes.isEmpty {
                        Divider().opacity(0.55)
                        VStack(alignment: .leading, spacing: 10) { Text("WORTH REMEMBERING").font(.system(size: 8, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary); Text(person.notes).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5) }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "leaf").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Style.green).padding(.top, 40)
                        Text("A thoughtful\nplace to start.").font(.system(size: 24, weight: .medium)).tracking(-0.5)
                        Text("Every promise has a person behind it. Capture the small things, and let Agora help you remember.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(6)
                        Button("Add a person →") { model.sheet = .person(nil) }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Style.accent)
                    }
                }
            }.padding(25).padding(.top, 6)
        }.background(Style.card.opacity(0.5))
    }
}
