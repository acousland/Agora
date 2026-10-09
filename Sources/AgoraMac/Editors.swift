import SwiftUI
import AgoraCore

struct EditorShell<Content: View>: View {
    var title: String
    var subtitle: String
    var saveTitle = "Save"
    var canSave = true
    var save: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 23, weight: .semibold)).tracking(-0.5); Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
            Divider()
            content
            Divider()
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(saveTitle, action: save).buttonStyle(.borderedProminent).tint(Style.accent).disabled(!canSave).keyboardShortcut(.defaultAction) }.padding(20)
        }.frame(width: 520).background(Style.canvas)
    }
}

struct PersonEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var person: Person?
    @State private var name = ""
    @State private var email = ""
    @State private var company = ""
    @State private var role = ""
    @State private var tags = ""
    @State private var notes = ""
    @State private var error: String?
    var body: some View {
        EditorShell(title: person == nil ? "Someone worth knowing." : "A little more about them.", subtitle: "Keep the details that make a relationship personal.", canSave: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, save: save) {
            Form {
                SwiftUI.Section { TextField("Name", text: $name); TextField("Email", text: $email); TextField("Company", text: $company); TextField("Role", text: $role); TextField("Tags, separated by commas", text: $tags) }
                SwiftUI.Section("Worth remembering") { TextEditor(text: $notes).font(.system(size: 12)).frame(height: 100) }
                if let error { Text(error).foregroundStyle(Style.red).font(.system(size: 12)) }
            }.formStyle(.grouped).frame(height: 400)
        }.onAppear { if let person { name = person.name; email = person.email; company = person.company; role = person.role; tags = person.tags.joined(separator: ", "); notes = person.notes } }
    }
    private func save() {
        guard let store = model.store else { return }
        do {
            let tagValues = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let result: Person
            if var person { person.name = name; person.email = email; person.company = company; person.role = role; person.tags = tagValues; person.notes = notes; result = try store.updateContact(person) }
            else { result = try store.createContact(name: name, email: email, company: company, role: role, tags: tagValues, notes: notes) }
            model.selectedPerson = result.id; model.reload(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct CommitmentEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var commitment: Commitment?
    var personId: String?
    @State private var contactId = ""
    @State private var title = ""
    @State private var notes = ""
    @State private var direction = "i_owe"
    @State private var priority = "normal"
    @State private var hasDeadline = true
    @State private var deadline = Date()
    @State private var status = "open"
    @State private var error: String?
    private var isEditing: Bool { commitment.map { !$0.id.isEmpty } ?? false }
    var body: some View {
        EditorShell(title: isEditing ? "Keep the promise up to date." : "Put your promise in writing.", subtitle: "What did you say you'd do, and for whom?", saveTitle: isEditing ? "Save changes" : "Register commitment", canSave: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !contactId.isEmpty, save: save) {
            Form {
                if model.people.isEmpty {
                    SwiftUI.Section { Text("Add a person before recording your first commitment.").font(.system(size: 12)); Button("Add a person") { model.sheet = .person(nil) } }
                } else {
                    SwiftUI.Section {
                        Picker("Person", selection: $contactId) { Text("Choose someone").tag(""); ForEach(model.people) { Text($0.name).tag($0.id) } }.disabled(commitment != nil)
                        TextField("What was promised?", text: $title)
                        Picker("Direction", selection: $direction) { Text("I promised them").tag("i_owe"); Text("They promised me").tag("they_owe") }
                        Picker("Priority", selection: $priority) { Text("Normal").tag("normal"); Text("High").tag("high") }
                        Toggle("Has a deadline", isOn: $hasDeadline)
                        if hasDeadline { DatePicker("Due", selection: $deadline, displayedComponents: .date) }
                        if isEditing { Picker("Status", selection: $status) { Text("Open").tag("open"); Text("Kept").tag("done"); Text("Cancelled").tag("cancelled") } }
                    }
                    SwiftUI.Section("A little context") { TextEditor(text: $notes).font(.system(size: 12)).frame(height: 80) }
                }
                if let error { Text(error).foregroundStyle(Style.red).font(.system(size: 12)) }
            }.formStyle(.grouped).frame(height: isEditing ? 455 : 415)
        }.onAppear {
            contactId = commitment?.contactId ?? personId ?? model.people.first?.id ?? ""
            if let commitment { title = commitment.title; notes = commitment.notes; direction = commitment.direction; priority = commitment.priority; status = commitment.status; hasDeadline = commitment.dueDate != nil; deadline = commitment.dueDate.flatMap(Day.date) ?? Date() }
        }
    }
    private func save() {
        guard let store = model.store else { return }
        do {
            let result: Commitment
            if var commitment, !commitment.id.isEmpty { commitment.title = title; commitment.notes = notes; commitment.direction = direction; commitment.priority = priority; commitment.dueDate = hasDeadline ? Day.string(deadline) : nil; commitment.status = status; result = try store.updateCommitment(commitment) }
            else { result = try store.createCommitment(contactId: contactId, title: title, dueDate: hasDeadline ? Day.string(deadline) : nil, direction: direction, priority: priority, notes: notes, interactionId: commitment?.interactionId) }
            model.selectedCommitment = result.id; model.reload(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct InteractionEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var personId: String?
    @State private var contactId = ""
    @State private var kind = "meeting"
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var occurred = Date()
    @State private var error: String?
    var body: some View {
        EditorShell(title: "Remember the conversation.", subtitle: "An email, a coffee, a quick call. It all adds up.", saveTitle: "Log interaction", canSave: !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !contactId.isEmpty, save: save) {
            Form {
                if model.people.isEmpty { Text("Add a person first."); Button("Add a person") { model.sheet = .person(nil) } }
                SwiftUI.Section {
                    Picker("Person", selection: $contactId) { Text("Choose someone").tag(""); ForEach(model.people) { Text($0.name).tag($0.id) } }
                    Picker("Type", selection: $kind) { ForEach(["meeting", "email", "call", "message", "note"], id: \.self) { Text($0.capitalized).tag($0) } }
                    TextField("Subject", text: $subject)
                    DatePicker("When", selection: $occurred, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                SwiftUI.Section("Conversation notes") { TextEditor(text: $bodyText).font(.system(size: 12)).frame(height: 110) }
                if let error { Text(error).foregroundStyle(Style.red).font(.system(size: 12)) }
            }.formStyle(.grouped).frame(height: 390)
        }.onAppear { contactId = personId ?? model.people.first?.id ?? "" }
    }
    private func save() {
        guard let store = model.store else { return }
        do { _ = try store.logInteraction(contactId: contactId, kind: kind, subject: subject, body: bodyText, occurredAt: occurred.timeIntervalSince1970); model.reload(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct SourceView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var item: Interaction
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Label(item.kind.capitalized, systemImage: interactionIcon(item.kind)).font(.system(size: 12)).foregroundStyle(Style.accent); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text(item.subject).font(.system(size: 23, weight: .semibold)).textSelection(.enabled)
            HStack { Avatar(person: model.person(item.contactId), size: 30); VStack(alignment: .leading, spacing: 4) { Text(model.person(item.contactId)?.name ?? "Unknown person").font(.system(size: 12, weight: .medium)); Text(Date(timeIntervalSince1970: item.occurredAt).formatted(date: .long, time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer(); Pill(text: item.source == "outlook" ? "From Outlook" : "Logged manually") }
            Divider()
            ScrollView { Text(item.body.isEmpty ? "No notes recorded." : item.body).font(.system(size: 13)).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(minHeight: 200, maxHeight: 400)
            HStack { Spacer(); Button("Record a promise from this") {
                let now = Date().timeIntervalSince1970
                let draft = Commitment(id: "", contactId: item.contactId, interactionId: item.id, title: "", notes: "", dueDate: nil, status: "open", priority: "normal", direction: "i_owe", createdAt: now, updatedAt: now, completedAt: nil, revision: 0)
                model.sheet = .commitment(draft, item.contactId)
            }.buttonStyle(.borderedProminent).tint(Style.accent) }
        }.padding(28).frame(width: 590)
    }
}
