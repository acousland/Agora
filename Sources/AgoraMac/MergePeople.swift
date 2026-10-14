import SwiftUI
import AgoraCore

struct MergePeopleEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let source: Person
    @State private var targetId = ""
    @State private var error: String?
    init(source: Person, targetId: String = "") { self.source = source; _targetId = State(initialValue: targetId) }
    private var target: Person? { model.people.first { $0.id == targetId } }
    var body: some View {
        EditorShell(title: "Bring their history together.", subtitle: "Merge \(source.name) into the person you choose below.", saveTitle: "Merge people", canSave: target != nil, save: merge) {
            Form {
                SwiftUI.Section("Person to keep") {
                    Picker("Keep", selection: $targetId) {
                        Text("Choose a person").tag("")
                        ForEach(model.people.filter { $0.id != source.id }) { person in Text(person.name + (person.email.isEmpty ? "" : " · " + person.email)).tag(person.id) }
                    }
                    if let target {
                        Text("\(target.name) will keep their name and primary details. Empty details are filled from \(source.name). Other email addresses, tags and notes are retained.").font(.system(size: 12)).foregroundStyle(.secondary)
                        let ids: Set<String> = [source.id, target.id]
                        Text("\(model.interactions.filter { ids.contains($0.contactId) }.count) interactions and \(model.commitments.filter { ids.contains($0.contactId) }.count) commitments will belong to \(target.name).").font(.system(size: 12, weight: .medium))
                    }
                }
                SwiftUI.Section {
                    Text("\(source.name)'s separate person record will be removed. All conversations and commitments are kept, including their source links. A database backup is saved in your library's Backups folder first.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.system(size: 12)).foregroundStyle(Style.red) }
            }.formStyle(.grouped).frame(height: 310)
        }
    }
    private func merge() {
        guard let store = model.store, let target else { return }
        do {
            let person = try store.mergeContact(source.id, into: target.id, expectedSourceRevision: source.revision, expectedTargetRevision: target.revision)
            model.selectedPerson = person.id; model.reload(); model.notice = "People merged. A backup was saved in your library's Backups folder."; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
