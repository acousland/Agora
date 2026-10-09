import XCTest
@testable import AgoraCore

final class StoreTests: XCTestCase {
    var directory: URL!
    var store: Store!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("agora-tests-\(UUID().uuidString)")
        store = try Store(directory: directory)
    }
    override func tearDownWithError() throws { store = nil; try FileManager.default.removeItem(at: directory) }
    func testPersistenceAndSharedWriters() throws {
        let person = try store.createContact(name: "Maya", email: "Maya@Example.com", tags: ["Friend"])
        let second = try Store(directory: directory)
        XCTAssertEqual(try second.contact(person.id).email, "maya@example.com")
        let promise = try second.createCommitment(contactId: person.id, title: "Send the book", dueDate: "2020-01-01")
        XCTAssertTrue(try store.commitment(promise.id).overdue)
        var update = promise; update.status = "done"
        let done = try store.updateCommitment(update)
        XCTAssertNotNil(done.completedAt); XCTAssertEqual(done.revision, 2)
        XCTAssertFalse(try second.commitment(promise.id).overdue)
        XCTAssertThrowsError(try second.updateCommitment(update)) { XCTAssertEqual($0.localizedDescription, AgoraError.stale.localizedDescription) }
        var reopened = done; reopened.status = "open"
        XCTAssertNil(try store.updateCommitment(reopened).completedAt)
    }
    func testDuplicateEmailAndProfileRevision() throws {
        var person = try store.createContact(name: "Maya", email: "maya@example.com")
        XCTAssertThrowsError(try store.createContact(name: "Duplicate", email: "MAYA@example.com"))
        let stale = person; person.notes = "Likes coffee"
        XCTAssertEqual(try store.updateContact(person).revision, 2)
        XCTAssertThrowsError(try store.updateContact(stale))
        XCTAssertEqual(try store.contacts().count, 1)
    }
    func payload() -> [String: Any] { ["contactName": "Maya", "contactEmail": "maya@example.com", "subject": "Our plans", "body": "I will send the book", "externalId": "message-1", "commitments": [["title": "Send the book", "dueDate": "2026-10-12"]]] }
    func testAtomicOutlookCaptureAndDuplicateProtection() throws {
        let first = try store.captureEmail(payload()), second = try store.captureEmail(payload())
        XCTAssertEqual(first["interactionId"] as? String, second["interactionId"] as? String)
        XCTAssertEqual(second["alreadySaved"] as? Bool, true)
        XCTAssertEqual(try store.contacts().count, 1); XCTAssertEqual(try store.interactions().count, 1); XCTAssertEqual(try store.commitments().count, 1)
        let promise = try XCTUnwrap(store.commitments().first)
        XCTAssertEqual(promise.interactionId, first["interactionId"] as? String)
        var more = payload(); more["commitments"] = [["title": "Call the publisher", "direction": "they_owe"]]
        _ = try store.captureEmail(more)
        XCTAssertEqual(try store.commitments().count, 2)
    }
    func testBadCaptureRollsBackEveryRecord() throws {
        var bad = payload(); bad["commitments"] = [["title": "Valid promise"], ["title": "Invalid deadline", "dueDate": "2026-02-30"]]
        XCTAssertThrowsError(try store.captureEmail(bad))
        XCTAssertTrue(try store.contacts().isEmpty); XCTAssertTrue(try store.interactions().isEmpty); XCTAssertTrue(try store.commitments().isEmpty)
        bad["commitments"] = [["title": "Invalid type", "dueDate": 5]]
        XCTAssertThrowsError(try store.captureEmail(bad))
        XCTAssertTrue(try store.contacts().isEmpty)
    }
    func testSourceMustBelongToPersonAndDatesValidated() throws {
        let a = try store.createContact(name: "A"), b = try store.createContact(name: "B")
        let source = try store.logInteraction(contactId: a.id, kind: "call", subject: "Hello")
        XCTAssertThrowsError(try store.createCommitment(contactId: b.id, title: "Wrong person", interactionId: source.id))
        XCTAssertThrowsError(try store.createCommitment(contactId: a.id, title: "Wrong date", dueDate: "2026-13-01"))
        XCTAssertThrowsError(try store.createCommitment(contactId: "missing", title: "No one"))
        XCTAssertThrowsError(try store.logInteraction(contactId: a.id, kind: "unknown", subject: "Hello"))
        XCTAssertThrowsError(try store.deleteContact(a.id))
    }
    func testImportExportAndLiveDatabaseBackup() throws {
        _ = try store.captureEmail(payload())
        let snapshot = try store.snapshot()
        let importedDirectory = directory.appendingPathComponent("imported")
        let imported = try Store(directory: importedDirectory)
        try imported.importLibrary(snapshot)
        XCTAssertEqual(try imported.contacts(), snapshot.contacts)
        XCTAssertEqual(try imported.commitments(), snapshot.commitments)
        XCTAssertThrowsError(try imported.importLibrary(snapshot))
        XCTAssertEqual(try imported.commitments().count, 1)
        let backupDirectory = directory.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        try store.backup(to: backupDirectory.appendingPathComponent("agora.sqlite"))
        let backup = try Store(directory: backupDirectory)
        XCTAssertEqual(try backup.interactions(), snapshot.interactions)
    }
    func testMCPPatchesAndFilters() throws {
        let person = try store.createContact(name: "Maya", email: "maya@example.com")
        let promise = try store.createCommitment(contactId: person.id, title: "Send the book", dueDate: "2020-01-01")
        let page = try XCTUnwrap(Commands.call("list_commitments", args: ["overdueOnly": true, "limit": 1], store: store) as? [String: Any])
        XCTAssertEqual(page["total"] as? Int, 1)
        _ = try Commands.call("update_commitment", args: ["id": promise.id, "expectedRevision": 1, "fields": ["dueDate": NSNull(), "status": "done"]], store: store)
        XCTAssertNil(try store.commitment(promise.id).dueDate); XCTAssertEqual(try store.commitment(promise.id).status, "done")
        XCTAssertThrowsError(try Commands.call("update_commitment", args: ["id": promise.id, "expectedRevision": 2, "fields": ["contactId": "missing"]], store: store))
        XCTAssertThrowsError(try Commands.call("list_contacts", args: ["limit": true], store: store))
        XCTAssertThrowsError(try Commands.call("list_contacts", args: ["limit": 0], store: store))
        XCTAssertThrowsError(try Commands.call("create_contact", args: ["name": "Maya", "tags": [1]], store: store))
    }
    func testTokenStablePrivateAndRotatable() throws {
        let token = try store.pairingToken()
        XCTAssertEqual(token.count, 64); XCTAssertEqual(try store.pairingToken(), token)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("outlook-token").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertNotEqual(try store.rotatePairingToken(), token)
    }
}
