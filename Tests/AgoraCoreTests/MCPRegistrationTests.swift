import XCTest
@testable import AgoraCore

final class MCPRegistrationTests: XCTestCase {
    private var home: URL!
    private var setup: MCPRegistration!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("agora-client-tests-\(UUID().uuidString)")
        let helper = home.appendingPathComponent("Applications/Agora.app/Contents/MacOS/AgoraMCP")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: helper.path, contents: Data("#!/bin/sh\nexit 0\n".utf8), attributes: [.posixPermissions: 0o755]))
        setup = MCPRegistration(helper: helper, library: home.appendingPathComponent("Private Library"), home: home, environment: ["HOME": home.path, "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "CODEX_HOME": home.appendingPathComponent(".codex").path])
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }
    func testClaudeMergePreservesSettingsAndCreatesPrivateBackup() throws {
        for client in [MCPClient.claudeDesktop, .claudeCode] {
            let url = setup.configurationURL(client)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = Data("{\"theme\":\"dark\",\"mcpServers\":{\"other\":{\"command\":\"/other\"}}}".utf8)
            try original.write(to: url)
            try setup.install(client)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertEqual(root["theme"] as? String, "dark")
            let servers = try XCTUnwrap(root["mcpServers"] as? [String: [String: Any]])
            XCTAssertEqual(servers["other"]?["command"] as? String, "/other")
            XCTAssertEqual(servers["agora-local"]?["command"] as? String, setup.helper.path)
            XCTAssertEqual((servers["agora-local"]?["env"] as? [String: String])?["AGORA_DATA_DIR"], setup.library.path)
            let backups = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(url.lastPathComponent + ".agora-backup-") }
            XCTAssertEqual(backups.count, 1); XCTAssertEqual(try Data(contentsOf: backups[0]), original)
            for file in [url, backups[0]] { XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600) }
            try setup.install(client)
            XCTAssertTrue(setup.status(client).hasPrefix("Configured"))
        }
    }
    func testMalformedSettingsRemainUntouched() throws {
        let url = setup.configurationURL(.claudeCode)
        for source in ["{invalid", "[]", "{\"mcpServers\":[]}"] {
            let original = Data(source.utf8); try original.write(to: url)
            XCTAssertThrowsError(try setup.install(.claudeCode))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }
    func testTransientHelperIsRejectedAndCustomLibraryIsCopied() throws {
        let transient = MCPRegistration(helper: home.appendingPathComponent("build/AgoraMCP"), library: setup.library, home: home)
        XCTAssertThrowsError(try transient.install(.claudeCode))
        XCTAssertFalse(FileManager.default.fileExists(atPath: setup.configurationURL(.claudeCode).path))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(setup.configurationJSON().utf8)) as? [String: [String: [String: Any]]])
        XCTAssertEqual(config["mcpServers"]?["agora-local"]?["env"] as? [String: String], ["AGORA_DATA_DIR": setup.library.path])
    }
    func testCodexCLIWithIsolatedHomePreservesOtherTOML() throws {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/codex") || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/codex") else { throw XCTSkip("Codex CLI is not installed") }
        let url = setup.configurationURL(.codex)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# Existing settings\n[mcp_servers.other]\ncommand = \"/other\"\n".utf8).write(to: url)
        try setup.install(.codex)
        try setup.install(.codex)
        let config = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(config.contains("[mcp_servers.other]")); XCTAssertTrue(config.contains("command = \"/other\"")); XCTAssertTrue(config.contains("AGORA_DATA_DIR"))
        XCTAssertEqual(config.components(separatedBy: "[mcp_servers.agora-local]").count, 2)
        let status = setup.status(.codex)
        XCTAssertTrue(status.hasPrefix("Configured"), status)
    }
}
