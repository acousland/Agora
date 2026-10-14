import XCTest
@testable import AgoraCore

final class PeopleAndTimelineTests: XCTestCase {
    private var directory: URL!
    private var store: Store!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("agora-people-tests-\(UUID().uuidString)")
        store = try Store(directory: directory)
    }
    override func tearDownWithError() throws { store = nil; try FileManager.default.removeItem(at: directory) }
    func testMergePreservesProfilesHistoriesLinksAndEmailIdentity() throws {
        let source = try store.createContact(name: "Maya Old", email: "old@example.com", company: "Old Co", role: "Designer", tags: ["Friend"], notes: "Old notes")
        let target = try store.createContact(name: "Maya", email: "new@example.com", company: "New Co", tags: ["Work"], notes: "New notes")
        let interaction = try store.logInteraction(contactId: source.id, kind: "call", subject: "A promise")
        let promise = try store.createCommitment(contactId: source.id, title: "Send the book", interactionId: interaction.id)
        let merged = try store.mergeContact(source.id, into: target.id, expectedSourceRevision: 1, expectedTargetRevision: 1)
        XCTAssertEqual(merged.id, target.id); XCTAssertEqual(merged.name, "Maya"); XCTAssertEqual(merged.email, "new@example.com")
        XCTAssertEqual(merged.alternateEmails, ["old@example.com"]); XCTAssertEqual(merged.company, "New Co"); XCTAssertEqual(merged.role, "Designer")
        XCTAssertEqual(Set(merged.tags), ["Friend", "Work"]); XCTAssertTrue(merged.notes.contains("Old notes")); XCTAssertTrue(merged.notes.contains("Old Co")); XCTAssertTrue(merged.notes.contains("New notes"))
        XCTAssertEqual(merged.revision, 2); XCTAssertThrowsError(try store.contact(source.id))
        XCTAssertEqual(try store.interactions().first?.contactId, target.id)
        let moved = try store.commitment(promise.id)
        XCTAssertEqual(moved.contactId, target.id); XCTAssertEqual(moved.interactionId, interaction.id); XCTAssertEqual(moved.revision, 2)
        XCTAssertThrowsError(try store.updateCommitment(promise))
        XCTAssertThrowsError(try store.createContact(name: "Duplicate", email: "OLD@EXAMPLE.COM"))
        let capture = try store.captureEmail(["contactName": "Maya Old", "contactEmail": "old@example.com", "subject": "After merging", "externalId": "new-email"])
        XCTAssertEqual(capture["contactId"] as? String, target.id); XCTAssertEqual(try store.contacts().count, 1)
        let page = try XCTUnwrap(Commands.call("list_contacts", args: ["search": "old@example.com"], store: store) as? [String: Any])
        XCTAssertEqual(page["total"] as? Int, 1)
        var edited = merged; edited.notes = "Updated notes"
        XCTAssertEqual(try store.updateContact(edited).alternateEmails, ["old@example.com"])
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Backups"), includingPropertiesForKeys: nil).first)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let restore = directory.appendingPathComponent("restore")
        try FileManager.default.createDirectory(at: restore, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: backup, to: restore.appendingPathComponent("agora.sqlite"))
        let restored = try Store(directory: restore)
        XCTAssertEqual(try restored.contacts().count, 2); XCTAssertEqual(try restored.commitment(promise.id).contactId, source.id)
    }
    func testMergeKeepsDuplicateEmailCopiesAndCaptureStaysIdempotent() throws {
        let a: [String: Any] = ["contactName": "A", "contactEmail": "a@example.com", "subject": "Shared message", "externalId": "same-message", "commitments": [["title": "A promise"]]]
        let b: [String: Any] = ["contactName": "B", "contactEmail": "b@example.com", "subject": "Shared message copy", "externalId": "same-message", "commitments": [["title": "B promise"]]]
        let first = try store.captureEmail(a), second = try store.captureEmail(b)
        let source = try XCTUnwrap(first["contactId"] as? String), target = try XCTUnwrap(second["contactId"] as? String)
        _ = try store.mergeContact(source, into: target, expectedSourceRevision: 1, expectedTargetRevision: 1)
        XCTAssertEqual(try store.interactions().count, 2); XCTAssertEqual(try store.commitments().count, 2)
        XCTAssertTrue(try store.interactions().allSatisfy { $0.contactId == target })
        XCTAssertEqual(try store.interactions().filter { $0.duplicateExternalId == "same-message" }.count, 1)
        let repeatCapture = try store.captureEmail(a)
        XCTAssertEqual(repeatCapture["alreadySaved"] as? Bool, true)
        XCTAssertEqual(repeatCapture["commitmentIds"] as? [String], first["commitmentIds"] as? [String])
        XCTAssertEqual(try store.commitments().count, 2)
    }
    func testStaleOrInvalidMergeLeavesBothPeopleUntouched() throws {
        let source = try store.createContact(name: "Source", tags: (0..<20).map { "Source \($0)" })
        let target = try store.createContact(name: "Target", tags: (0..<20).map { "Target \($0)" })
        XCTAssertThrowsError(try store.mergeContact(source.id, into: source.id, expectedSourceRevision: 1, expectedTargetRevision: 1))
        XCTAssertThrowsError(try store.mergeContact(source.id, into: target.id, expectedSourceRevision: 2, expectedTargetRevision: 1)) { XCTAssertEqual($0.localizedDescription, AgoraError.stale.localizedDescription) }
        XCTAssertThrowsError(try store.mergeContact(source.id, into: target.id, expectedSourceRevision: 1, expectedTargetRevision: 1))
        XCTAssertEqual(try store.contact(source.id), source); XCTAssertEqual(try store.contact(target.id), target)
    }
    func testDeleteRequiresExplicitHistoryAndRejectsNewChanges() throws {
        let person = try store.createContact(name: "Delete me"), other = try store.createContact(name: "Keep me")
        let note = try store.logInteraction(contactId: person.id, kind: "note", subject: "History")
        _ = try store.createCommitment(contactId: person.id, title: "Promise", interactionId: note.id)
        XCTAssertThrowsError(try store.deleteContact(person.id))
        XCTAssertThrowsError(try store.deleteContact(person.id, includingHistory: true, expectedRevision: 1, expectedInteractionCount: 0, expectedCommitmentCount: 1))
        XCTAssertEqual(try store.interactions().count, 1); XCTAssertEqual(try store.commitments().count, 1)
        try store.deleteContact(person.id, includingHistory: true, expectedRevision: 1, expectedInteractionCount: 1, expectedCommitmentCount: 1)
        XCTAssertEqual(try store.contacts().map(\.id), [other.id]); XCTAssertTrue(try store.interactions().isEmpty); XCTAssertTrue(try store.commitments().isEmpty)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Backups").path).isEmpty)
    }
    func testAliasExportImportAndLegacyDecoding() throws {
        let a = try store.createContact(name: "A", email: "a@example.com"), b = try store.createContact(name: "B", email: "b@example.com")
        _ = try store.mergeContact(a.id, into: b.id, expectedSourceRevision: 1, expectedTargetRevision: 1)
        let snapshot = try store.snapshot()
        let imported = try Store(directory: directory.appendingPathComponent("imported")); try imported.importLibrary(snapshot)
        XCTAssertEqual(try imported.contacts(), snapshot.contacts)
        XCTAssertThrowsError(try imported.createContact(name: "Duplicate", email: "a@example.com"))
        var legacy = try XCTUnwrap(Commands.object(snapshot.contacts[0]) as? [String: Any]); legacy.removeValue(forKey: "alternateEmails")
        XCTAssertNil(try JSONDecoder().decode(Person.self, from: JSONSerialization.data(withJSONObject: legacy)).alternateEmails)
    }
    func testTimelineGapsArePerPersonAndIndependentOfOrdering() throws {
        let a = try store.createContact(name: "A"), b = try store.createContact(name: "B")
        let first = try store.logInteraction(contactId: a.id, kind: "note", subject: "First", occurredAt: 1000)
        let unrelated = try store.logInteraction(contactId: b.id, kind: "note", subject: "Other person", occurredAt: 2000)
        let next = try store.logInteraction(contactId: a.id, kind: "call", subject: "Next", occurredAt: 8200)
        let latest = try store.logInteraction(contactId: a.id, kind: "email", subject: "Latest", occurredAt: 94600)
        let gaps = Timeline.gapsByInteraction([latest, unrelated, first, next])
        XCTAssertNil(gaps[first.id]); XCTAssertNil(gaps[unrelated.id]); XCTAssertEqual(gaps[next.id], 7200); XCTAssertEqual(gaps[latest.id], 86400)
        XCTAssertTrue(Timeline.gapDescription(nil).contains("First")); XCTAssertTrue(Timeline.gapDescription(0).contains("Same time")); XCTAssertTrue(Timeline.gapDescription(30).contains("Less than a minute")); XCTAssertTrue(Timeline.gapDescription(7200).contains("2 hours"))
    }
}
