import SwiftUI
import AgoraCore
import UniformTypeIdentifiers

struct ConnectionsView: View {
    @EnvironmentObject var model: AppModel
    @State private var configuring = false
    @State private var copied = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("A few thoughtful connections.").font(.system(size: 29, weight: .semibold)).tracking(-0.8)
                Text("Capture conversations in Outlook. Give your AI assistant the context to help you follow through.").font(.system(size: 12)).foregroundStyle(.secondary)
                Card {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 14) { Image(systemName: "envelope.badge.shield.half.filled").font(.system(size: 25)).foregroundStyle(Style.accent); VStack(alignment: .leading, spacing: 5) { Text("Outlook for Mac").font(.system(size: 16, weight: .semibold)); Text(model.outlookStatus).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Pill(text: model.outlookStatus.hasPrefix("Listening") ? "Ready" : "Setup needed", color: model.outlookStatus.hasPrefix("Listening") ? Style.green : Style.orange) }
                        Text("Save the email you're reading, choose the person, and record any promises alongside it. Agora must be open to receive emails.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                        Divider().opacity(0.5)
                        step("1", "Set up secure localhost", "Create a certificate for localhost and trust it in your login Keychain. macOS may ask you to confirm.")
                        Button(configuring ? "Setting up…" : "Set up local HTTPS") { setupHTTPS() }.buttonStyle(.bordered).disabled(configuring)
                        step("2", "Add Agora to Outlook", "Open Microsoft's add-in installer. Under My add-ins → Add a custom add-in → Add from File, select Agora's manifest.")
                        HStack { Button("Save manifest…") { saveManifest() }.buttonStyle(.bordered); Link("Open Outlook add-in installer ↗", destination: URL(string: "https://aka.ms/olksideload")!).font(.system(size: 11)) }
                        step("3", "Pair once", "Open an email, choose Apps → Agora, then paste your pairing key into the add-in.")
                        HStack { Button(copied == "pairing" ? "Key copied" : "Copy pairing key") { if let token = try? model.store?.pairingToken() { copy(token, kind: "pairing") } }.buttonStyle(.bordered); Button("Rotate key") { model.perform { _ = try $0.rotatePairingToken() }; copied = "" }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).help("Disconnect the current Outlook pairing. Copy the new key and pair again.") }
                        Text("Custom add-ins require a supported Microsoft 365 / Exchange mailbox and may depend on your organisation's add-in policy.").font(.system(size: 10)).foregroundStyle(.tertiary).lineSpacing(3)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack(spacing: 14) { Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 25)).foregroundStyle(Style.accent); VStack(alignment: .leading, spacing: 5) { Text("Local MCP server").font(.system(size: 16, weight: .semibold)); Text("Works with the app open or closed").font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Pill(text: "STDIO", color: Style.green) }
                        Text("Your AI client launches AgoraMCP and reads the same local library. It can find people, log interactions, and register or complete commitments. Your client controls which records it sends to its model.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                        Text(helperPath).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        HStack { Button(copied == "mcp" ? "Configuration copied" : "Copy MCP configuration") { copy(mcpConfig, kind: "mcp") }.buttonStyle(.bordered); Button("Copy helper path") { copy(helperPath, kind: "path") }.buttonStyle(.bordered); Link("Connection guide ↗", destination: URL(string: "https://github.com/acousland/Agora/blob/main/docs/MCP.md")!).font(.system(size: 11)) }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 17) {
                        Label("Your library", systemImage: "internaldrive").font(.system(size: 16, weight: .semibold))
                        Text("Your contacts, conversations and commitments live in SQLite on this Mac. Export a portable JSON archive or create a consistent database backup.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                        HStack { Button("Export JSON…") { exportLibrary() }; Button("Import JSON…") { importLibrary() }; Button("Back up database…") { backup() }; Button("Show in Finder") { if let store = model.store { NSWorkspace.shared.open(store.directory) } } }.buttonStyle(.bordered).controlSize(.small)
                        Text("Agora \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") · No account required").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }.padding(32).frame(maxWidth: 920, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    private var helperPath: String { Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/AgoraMCP").path : URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("AgoraMCP").path }
    private var mcpConfig: String {
        let configuration: [String: Any] = ["mcpServers": ["agora-local": ["command": helperPath, "args": []]]]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self)
    }
    private func copy(_ text: String, kind: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); copied = kind }
    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) { Text(number).font(.system(size: 10, weight: .semibold)).foregroundStyle(Style.accent).frame(width: 23, height: 23).background(Style.accent.opacity(0.08), in: Circle()); VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 12, weight: .medium)); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3) } }
    }
    private func saveManifest() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Agora-Outlook.xml"; panel.allowedContentTypes = [.xml]
        guard panel.runModal() == .OK, let url = panel.url, let source = Bundle.module.url(forResource: "Outlook", withExtension: nil)?.appendingPathComponent("manifest.xml") else { return }
        model.perform { _ in try Data(contentsOf: source).write(to: url, options: .atomic) }
    }
    private func exportLibrary() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Agora-\(Day.string()).json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.perform { store in let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(store.snapshot()).write(to: url, options: .atomic); model.notice = "Library exported" }
    }
    private func importLibrary() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.perform { store in let data = try Data(contentsOf: url); guard data.count <= 100_000_000 else { throw AgoraError.invalid("Import files must be below 100 MB.") }; try store.importLibrary(JSONDecoder().decode(LibraryExport.self, from: data)); model.notice = "Library imported" }
    }
    private func backup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Agora-\(Day.string())-backup.sqlite"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.perform { store in try store.backup(to: url); model.notice = "Database backed up" }
    }
    private func setupHTTPS() {
        guard let store = model.store, let script = Bundle.main.url(forResource: "setup-outlook", withExtension: "sh") else { model.error = "Run scripts/build-app.sh, then open the built app to set up Outlook."; return }
        configuring = true
        Task {
            let result = await Task.detached { () -> (Int32, String) in
                let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/bash"); task.arguments = [script.path, store.directory.path]
                let output = Pipe(); task.standardOutput = output; task.standardError = output
                do { try task.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit(); return (task.terminationStatus, String(decoding: data, as: UTF8.self)) }
                catch { return (1, error.localizedDescription) }
            }.value
            configuring = false
            if result.0 == 0 { model.startOutlook(); model.notice = "Outlook HTTPS configured" }
            else { model.error = result.1 }
        }
    }
}
