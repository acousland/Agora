import XCTest
@testable import AgoraCore

final class ProfileTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("agora-profile-tests-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testExistingLibraryBecomesWorkWithoutMovingRecords() throws {
        let original = try Store(directory: root)
        let person = try original.createContact(name: "Existing work person", email: "same@example.com")
        let source = try original.logInteraction(contactId: person.id, kind: "email", subject: "Existing conversation")
        let promise = try original.createCommitment(contactId: person.id, title: "Existing promise", interactionId: source.id)
        let token = try original.pairingToken()
        let manager = try ProfileManager(root: root)
        let selection = try manager.snapshot()
        XCTAssertEqual(selection.active.name, "Work")
        XCTAssertEqual(try manager.directory(for: selection.active), root.resolvingSymlinksInPath())
        let work = try Store(directory: manager.directory(for: selection.active))
        XCTAssertEqual(try work.contact(person.id), person)
        XCTAssertEqual(try work.commitment(promise.id).interactionId, source.id)
        XCTAssertEqual(try work.pairingToken(), token)
        let university = try XCTUnwrap(selection.profiles.first { $0.name == "University" })
        let empty = try Store(directory: manager.directory(for: university))
        XCTAssertTrue(try empty.contacts().isEmpty)
        XCTAssertTrue(try empty.interactions().isEmpty)
        XCTAssertTrue(try empty.commitments().isEmpty)
        XCTAssertNotEqual(try empty.pairingToken(), token)
    }
    func testCreateRenameSelectAndReopenPersist() throws {
        let manager = try ProfileManager(root: root)
        let profile = try manager.create(name: "  Personal  ")
        XCTAssertEqual(profile.name, "Personal")
        try manager.select(id: profile.id)
        try manager.rename(id: profile.id, name: "Friends")
        let reopened = try ProfileManager(root: root)
        XCTAssertEqual(try reopened.snapshot().active, LibraryProfile(id: profile.id, name: "Friends"))
        XCTAssertEqual(try reopened.directory(for: profile), try manager.directory(for: profile))
        XCTAssertThrowsError(try manager.create(name: " work "))
        XCTAssertThrowsError(try manager.rename(id: profile.id, name: "UNIVERSITY"))
        for name in ["", " \n ", String(repeating: "a", count: 61), "Bad\nname"] { XCTAssertThrowsError(try manager.create(name: name)) }
        XCTAssertThrowsError(try manager.select(id: "missing"))
        let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("profiles.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testEmailCaptureSearchAndBackupAreIsolated() throws {
        let manager = try ProfileManager(root: root), selection = try manager.snapshot()
        let work = try Store(directory: manager.directory(for: selection.active))
        let university = try Store(directory: manager.directory(for: selection.profiles[1]))
        let payload: [String: Any] = ["contactName": "Shared person", "contactEmail": "same@example.com", "subject": "A conversation", "externalId": "same-message", "commitments": [["title": "Follow up"]]]
        let first = try work.captureEmail(payload)
        let second = try university.captureEmail(payload)
        XCTAssertNotEqual(first["interactionId"] as? String, second["interactionId"] as? String)
        XCTAssertFalse(second["alreadySaved"] as? Bool ?? true)
        let person = try work.contacts()[0]
        XCTAssertThrowsError(try university.contact(person.id))
        XCTAssertThrowsError(try university.createCommitment(contactId: person.id, title: "Wrong world"))
        let backup = root.appendingPathComponent("university-backup.sqlite")
        try university.backup(to: backup)
        let restoredDirectory = root.appendingPathComponent("Restored")
        try FileManager.default.createDirectory(at: restoredDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: backup, to: restoredDirectory.appendingPathComponent("agora.sqlite"))
        let restored = try Store(directory: restoredDirectory)
        XCTAssertEqual(try restored.contacts()[0].id, try university.contacts()[0].id)
        XCTAssertNotEqual(try restored.contacts()[0].id, person.id)
        XCTAssertEqual(try work.contacts().count, 1)
        XCTAssertEqual(try university.commitments().count, 1)
    }
    func testStaleMCPSessionCannotReadOrWriteAnotherProfile() throws {
        let manager = try ProfileManager(root: root)
        let work = try ProfileSession(environment: ["AGORA_PROFILE_ROOT": root.path])
        _ = try work.call("create_contact", args: ["name": "Work person"])
        let university = try manager.snapshot().profiles[1]
        try manager.select(id: university.id)
        for name in ["get_overview", "create_contact"] {
            XCTAssertThrowsError(try work.call(name, args: name == "create_contact" ? ["name": "Wrong world"] : [:])) {
                XCTAssertEqual($0.localizedDescription, AgoraError.profileChanged.localizedDescription)
            }
        }
        let current = try ProfileSession(environment: ["AGORA_PROFILE_ROOT": root.path])
        XCTAssertEqual(current.profile, university)
        XCTAssertTrue(try current.store.contacts().isEmpty)
        _ = try current.call("create_contact", args: ["name": "University person"])
        XCTAssertEqual(try work.store.contacts().map(\.name), ["Work person"])
        try manager.select(id: "default")
        XCTAssertThrowsError(try current.call("get_overview", args: [:]))
        XCTAssertEqual((try work.call("get_overview", args: [:]) as? [String: Any])?["contacts"] as? Int, 1)
    }
    func testFixedLibraryModeAndAmbiguousEnvironment() throws {
        let fixed = try ProfileSession(environment: ["AGORA_DATA_DIR": root.path])
        XCTAssertNil(fixed.manager)
        _ = try fixed.call("create_contact", args: ["name": "Fixed library"])
        let manager = try ProfileManager(root: root)
        try manager.select(id: manager.snapshot().profiles[1].id)
        XCTAssertEqual((try fixed.call("get_overview", args: [:]) as? [String: Any])?["contacts"] as? Int, 1)
        XCTAssertThrowsError(try ProfileSession(environment: ["AGORA_PROFILE_ROOT": root.path, "AGORA_DATA_DIR": root.path]))
    }
    func testCorruptOrEscapingProfileSettingsFailClosed() throws {
        let manager = try ProfileManager(root: root)
        let original = try manager.snapshot()
        let path = root.appendingPathComponent("profiles.json")
        var value = original; value.activeID = "unknown"
        try JSONEncoder().encode(value).write(to: path)
        XCTAssertThrowsError(try manager.snapshot())
        XCTAssertThrowsError(try ProfileManager(root: root))
        value = original; value.profiles[1] = LibraryProfile(id: "../escape", name: "Outside")
        try JSONEncoder().encode(value).write(to: path)
        XCTAssertThrowsError(try manager.snapshot())
        value = original; value.profiles.append(LibraryProfile(id: original.profiles[1].id.lowercased(), name: "Alias of another profile"))
        try JSONEncoder().encode(value).write(to: path)
        XCTAssertThrowsError(try manager.snapshot())
        try JSONEncoder().encode(original).write(to: path)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("agora-profile-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Profiles"), withDestinationURL: outside)
        XCTAssertThrowsError(try manager.directory(for: original.profiles[1]))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
    func testConcurrentRegistryChangesKeepEveryProfile() throws {
        _ = try ProfileManager(root: root)
        let directory = root!
        let results = ProfileCreationResults()
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            do { _ = try ProfileManager(root: directory).create(name: "Profile \(index)") }
            catch { results.record(error) }
        }
        XCTAssertEqual(results.count, 0)
        let snapshot = try ProfileManager(root: root).snapshot()
        XCTAssertEqual(snapshot.profiles.count, 14)
        XCTAssertEqual(Set(snapshot.profiles.map(\.id)).count, 14)
    }
}

private final class ProfileCreationResults: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []
    func record(_ error: Error) { lock.lock(); defer { lock.unlock() }; errors.append(error) }
    var count: Int { lock.lock(); defer { lock.unlock() }; return errors.count }
}
