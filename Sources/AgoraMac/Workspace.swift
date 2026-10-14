import SwiftUI
import Combine
import AgoraCore

struct Workspace: View {
    @EnvironmentObject var model: AppModel
    private let refresh = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 216)
            VStack(spacing: 0) {
                header
                Divider().opacity(0.6)
                HStack(spacing: 0) {
                    Group {
                        switch model.section {
                        case .overview: OverviewView()
                        case .people: PeopleView()
                        case .commitments: CommitmentsView()
                        case .timeline: TimelineView()
                        case .connections: ConnectionsView()
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.section == .overview || model.section == .commitments {
                        Divider().opacity(0.55)
                        CommitmentInspector().frame(width: 285)
                    }
                }
                HStack(spacing: 6) {
                    Circle().fill(Style.green).frame(width: 5, height: 5)
                    Text("Local library").font(.system(size: 10))
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(model.people.count) people · \(model.open.count) open commitments").font(.system(size: 10))
                    Spacer()
                    Text("\(model.notice ?? "Saved on this Mac")").font(.system(size: 10)).foregroundStyle(.tertiary)
                }.foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 10).background(Style.card.opacity(0.5))
            }.background(Style.canvas)
        }.tint(Style.accent)
        .onReceive(refresh) { _ in if NSApp.isActive { model.reload() } }
        .sheet(item: $model.sheet) { editor in
            switch editor {
            case .person(let person): PersonEditor(person: person)
            case .merge(let person): MergePeopleEditor(source: person)
            case .commitment(let commitment, let person): CommitmentEditor(commitment: commitment, personId: person)
            case .interaction(let person): InteractionEditor(personId: person)
            case .source(let interaction): SourceView(item: interaction)
            }
        }
        .alert("Agora", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.circle.fill").font(.system(size: 31, weight: .light)).foregroundStyle(Color(red: 0.72, green: 0.71, blue: 0.99))
                VStack(alignment: .leading, spacing: 3) {
                    Text("agora").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.7)
                    Text("A PERSONAL CRM").font(.system(size: 8, weight: .medium)).tracking(2).foregroundStyle(.white.opacity(0.4))
                }
            }.padding(.top, 53).padding(.horizontal, 23).padding(.bottom, 37)
            Text("YOUR SPACE").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.3)).padding(.horizontal, 25).padding(.bottom, 13)
            ForEach(AppModel.Section.allCases, id: \.self) { section in
                Button {
                    model.section = section; model.search = ""
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.icon).font(.system(size: 15, weight: .regular)).frame(width: 20)
                        Text(section.rawValue).font(.system(size: 12, weight: model.section == section ? .semibold : .regular))
                        Spacer()
                        if section == .commitments && !model.owed.isEmpty { Text("\(model.owed.count)").font(.system(size: 10, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 2).background(.white.opacity(0.1), in: Capsule()) }
                    }.foregroundStyle(model.section == section ? .white : .white.opacity(0.55)).padding(.horizontal, 13).padding(.vertical, 13)
                        .background(model.section == section ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 3)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "quote.opening").font(.system(size: 16)).foregroundStyle(.white.opacity(0.22))
                Text("Good relationships\nare built on follow-through.").font(.system(size: 12, weight: .regular)).lineSpacing(5).foregroundStyle(.white.opacity(0.46))
            }.padding(25).padding(.bottom, 20)
            Divider().overlay(.white.opacity(0.06))
            HStack(spacing: 10) {
                Image(systemName: "internaldrive").font(.system(size: 14)).foregroundStyle(.white.opacity(0.45))
                VStack(alignment: .leading, spacing: 4) { Text("Private by design").font(.system(size: 11, weight: .medium)); Text("ON THIS MAC").font(.system(size: 8)).tracking(1.4).foregroundStyle(.white.opacity(0.33)) }
                Spacer()
                Circle().fill(Color(red: 0.45, green: 0.72, blue: 0.57)).frame(width: 5, height: 5)
            }.padding(23)
        }.foregroundStyle(.white).background(Style.sidebar)
    }
    private var header: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.section.rawValue).font(.system(size: 20, weight: .semibold)).tracking(-0.4)
                Text(model.section.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.section != .connections {
                HStack(spacing: 7) { Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary); TextField("Search \(model.section == .overview ? "commitments" : model.section.rawValue.lowercased())", text: $model.search).textFieldStyle(.plain).font(.system(size: 11)) }
                    .padding(10).frame(width: 185).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                Button {
                    switch model.section {
                    case .people: model.sheet = .person(nil)
                    case .timeline: model.sheet = .interaction(model.selectedPerson)
                    default: model.sheet = .commitment(nil, model.selectedPerson)
                    }
                } label: { Label("New", systemImage: "plus").font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 9).foregroundStyle(.white).background(Style.accent, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).help(model.section == .people ? "New person" : model.section == .timeline ? "Log interaction" : "New commitment")
            }
        }.padding(.horizontal, 28).padding(.top, 34).padding(.bottom, 23)
    }
}
