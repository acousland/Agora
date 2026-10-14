import SwiftUI
import AgoraCore

struct ProfilesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: LibraryProfile?
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Your profiles").font(.system(size: 22, weight: .semibold))
                    Text("A separate space for each part of your life.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.bordered)
            }
            Text("People, conversations, commitments, imports and backups belong to one profile. New profiles start empty.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.profiles) { profile in
                        HStack(spacing: 12) {
                            Image(systemName: profile.id == model.activeProfile.id ? "checkmark.circle.fill" : "person.crop.circle").font(.system(size: 23)).foregroundStyle(profile.id == model.activeProfile.id ? Style.green : Style.accent)
                            Text(profile.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Spacer()
                            Button { editing = profile; name = profile.name } label: { Image(systemName: "pencil") }.buttonStyle(.plain).help("Rename \(profile.name)")
                            if profile.id == model.activeProfile.id { Pill(text: "Current", color: Style.green) }
                            else { Button("Use profile") { model.switchProfile(profile) }.buttonStyle(.bordered).disabled(model.connecting) }
                        }.padding(14).background(Style.card, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Divider()
            HStack(spacing: 10) {
                TextField(editing == nil ? "New profile name" : "Profile name", text: $name).textFieldStyle(.roundedBorder).onSubmit { save() }
                Button(editing == nil ? "Create profile" : "Save name") { save() }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.connecting)
                if editing != nil { Button("Cancel") { editing = nil; name = "" }.buttonStyle(.plain) }
            }
            Text("Switching changes where Outlook saves emails. Pair Outlook for each profile and reconnect AI clients after switching.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(28).frame(width: 560, height: 520).background(Style.canvas)
    }
    private func save() {
        if let editing {
            if model.renameProfile(editing, name: name) { self.editing = nil; name = "" }
        } else { _ = model.createProfile(name: name) }
    }
}
