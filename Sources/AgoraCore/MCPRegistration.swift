import Foundation
import Darwin

public enum MCPClient: String, CaseIterable, Sendable {
    case codex, claudeDesktop = "claude-desktop", claudeCode = "claude-code"
    public var name: String {
        switch self { case .codex: return "Codex / ChatGPT"; case .claudeDesktop: return "Claude Desktop"; case .claudeCode: return "Claude Code" }
    }
}

public struct MCPClientStatus: Equatable, Sendable {
    public enum State: Sendable { case configured, notConfigured, needsUpdate, disabled, unavailable, invalid }
    public let state: State
    public let detail: String
    public var isConfigured: Bool { state == .configured }
    public var title: String {
        switch state {
        case .configured: return "Configured"
        case .notConfigured: return "Not configured"
        case .needsUpdate: return "Needs updating"
        case .disabled: return "Disabled"
        case .unavailable: return "Setup unavailable"
        case .invalid: return "Check settings"
        }
    }
}

/// Client setup is explicit. Opening Agora never changes another application's settings.
public struct MCPRegistration: Sendable {
    public let helper: URL
    public let library: URL
    public let home: URL
    public let environment: [String: String]
    public init(helper: URL, library: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.helper = helper; self.library = library; self.home = home; self.environment = environment
    }
    public var entry: [String: Any] { ["command": helper.path, "args": [String](), "env": ["AGORA_DATA_DIR": library.path]] }
    public func configurationJSON() throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["mcpServers": ["agora-local": entry]], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
    public func configurationURL(_ client: MCPClient) -> URL {
        switch client {
        case .codex: return URL(fileURLWithPath: environment["CODEX_HOME"] ?? home.appendingPathComponent(".codex").path).appendingPathComponent("config.toml")
        case .claudeDesktop: return home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .claudeCode:
            if let directory = environment["CLAUDE_CONFIG_DIR"], !directory.isEmpty { return URL(fileURLWithPath: directory).appendingPathComponent(".claude.json") }
            return home.appendingPathComponent(".claude.json")
        }
    }
    public func status(_ client: MCPClient) -> MCPClientStatus {
        do {
            let value: [String: Any]?
            if client == .codex {
                guard let cli = codexCLI else { return .init(state: .unavailable, detail: "Install Codex or ChatGPT desktop to enable setup.") }
                let result = try run(cli, ["mcp", "get", "agora-local", "--json"])
                if result.code != 0 {
                    return result.text.contains("No MCP server named")
                        ? .init(state: .notConfigured, detail: "Set up Agora to make its tools available to this client.")
                        : .init(state: .invalid, detail: "Could not read Codex configuration. Check its settings and try again.")
                }
                guard let data = try JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any], var transport = data["transport"] as? [String: Any] else {
                    return .init(state: .invalid, detail: "Codex returned an unreadable server configuration.")
                }
                if data["enabled"] as? Bool == false { return .init(state: .disabled, detail: "Enable agora-local in Codex / ChatGPT MCP settings.") }
                // The CLI represents an omitted optional environment as JSON null.
                if transport["env"] is NSNull { transport.removeValue(forKey: "env") }
                value = transport
            } else {
                let root = try readJSON(configurationURL(client))
                if let servers = root["mcpServers"], !(servers is [String: Any]) { return .init(state: .invalid, detail: "The client's mcpServers setting must be a JSON object.") }
                let entry = (root["mcpServers"] as? [String: Any])?["agora-local"]
                if let entry, !(entry is [String: Any]) { return .init(state: .invalid, detail: "The agora-local setting must be a JSON object.") }
                value = entry as? [String: Any]
            }
            guard let value else { return .init(state: .notConfigured, detail: "Set up Agora to make its tools available to this client.") }
            if let args = value["args"], !(args is [String]) { return .init(state: .invalid, detail: "The helper's arguments must be a list of strings.") }
            if let env = value["env"], !(env is [String: String]) { return .init(state: .invalid, detail: "The helper's environment settings must contain string values.") }
            do { try validateInstalledHelper() }
            catch { return .init(state: .needsUpdate, detail: "Install Agora in Applications and configure this client again.") }
            guard value["command"] as? String == helper.path, (value["args"] as? [String] ?? []).isEmpty,
                  value["type"] == nil || value["type"] as? String == "stdio" else {
                return .init(state: .needsUpdate, detail: "The saved settings do not point to this Agora helper. Run setup again.")
            }
            let env = value["env"] as? [String: String] ?? [:]
            let defaultLibrary = home.appendingPathComponent("Library/Application Support/Agora").path
            let sameLibrary = env["AGORA_DATA_DIR"] == library.path || ((env["AGORA_DATA_DIR"] ?? "").isEmpty && library.path == defaultLibrary)
            guard sameLibrary else { return .init(state: .needsUpdate, detail: "This client points to a different library. Run setup to connect this library.") }
            return .init(state: .configured, detail: "The installed helper and library match the saved settings.")
        } catch { return .init(state: .invalid, detail: "Could not read the client configuration. Check its file and try again.") }
    }
    public func install(_ client: MCPClient) throws {
        try validateInstalledHelper()
        let url = configurationURL(client)
        if client == .codex {
            guard let cli = codexCLI else { throw AgoraError.invalid("Install the Codex CLI, then try again. You can also copy the configuration from the connection guide.") }
            // The supported CLI edits TOML without replacing unrelated settings or servers.
            _ = try backup(url)
            let result = try run(cli, ["mcp", "add", "agora-local", "--env", "AGORA_DATA_DIR=\(library.path)", "--", helper.path])
            guard result.code == 0 else { throw AgoraError.invalid("Codex could not save its MCP configuration. Check the configuration in Codex and try again.") }
        } else {
            let original = try FileManager.default.fileExists(atPath: url.path) ? Data(contentsOf: url) : nil
            var root = try readJSON(url)
            if let servers = root["mcpServers"], !(servers is [String: Any]) { throw AgoraError.invalid("The client's mcpServers setting is not an object. Fix it before setting up Agora.") }
            var servers = root["mcpServers"] as? [String: Any] ?? [:]
            var value = entry
            if client == .claudeCode { value["type"] = "stdio" }
            servers["agora-local"] = value; root["mcpServers"] = servers
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            let previous = try backup(url)
            // Refuse to overwrite settings changed by a running client while preparing the write.
            guard previous == original, (try? Data(contentsOf: url)) == original else { throw AgoraError.invalid("Client settings changed during setup. Try again.") }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
    public func validateInstalledHelper() throws {
        let app = helper.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let parent = app.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let locations = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")].map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        guard app.pathExtension == "app", helper.lastPathComponent == "AgoraMCP", locations.contains(parent), FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw AgoraError.invalid("Move Agora.app into Applications or your home Applications folder, open that copy, then set up the client. This keeps the connection working after updates.")
        }
    }
    private func readJSON(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw AgoraError.invalid("The client configuration must contain a JSON object.") }
        return root
    }
    @discardableResult private func backup(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let backupURL = url.appendingPathExtension("agora-backup-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: backupURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw AgoraError.storage("Could not back up the client's configuration.") }
        return data
    }
    private var codexCLI: URL? {
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", home.appendingPathComponent(".local/bin/codex").path,
            "/Applications/Codex.app/Contents/Resources/codex", home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex").path,
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex", home.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex").path]
        let paths = (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }.map { String($0) + "/codex" }
        return (candidates + paths).first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    private func run(_ executable: URL, _ arguments: [String]) throws -> (code: Int32, text: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agora-client-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw AgoraError.storage("Could not prepare client setup.") }
        defer { try? FileManager.default.removeItem(at: url) }
        let output = try FileHandle(forWritingTo: url); defer { try? output.close() }
        let task = Process(), done = DispatchSemaphore(value: 0)
        task.executableURL = executable; task.arguments = arguments; task.environment = environment; task.currentDirectoryURL = home
        task.standardInput = FileHandle.nullDevice; task.standardOutput = output; task.standardError = output
        task.terminationHandler = { _ in done.signal() }
        try task.run()
        if done.wait(timeout: .now() + 15) == .timedOut {
            task.terminate()
            if done.wait(timeout: .now() + 2) == .timedOut { kill(task.processIdentifier, SIGKILL); task.waitUntilExit() }
            throw AgoraError.invalid("Client setup timed out. Close the client and try again.")
        }
        return (task.terminationStatus, String(decoding: try Data(contentsOf: url), as: UTF8.self))
    }
}
