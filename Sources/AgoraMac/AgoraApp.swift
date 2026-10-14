import SwiftUI
import Sparkle
import AgoraCore

@MainActor final class AppModel: ObservableObject {
    @Published var people: [Person] = []
    @Published var interactions: [Interaction] = []
    @Published var commitments: [Commitment] = []
    @Published var section: Section = .overview
    @Published var search = ""
    @Published var selectedPerson: String?
    @Published var selectedCommitment: String?
    @Published var sheet: Editor?
    @Published var error: String?
    @Published var notice: String?
    @Published var outlookStatus = "Not configured"
    @Published var profiles: [LibraryProfile] = []
    @Published var activeProfile = LibraryProfile(id: "default", name: "Work")
    @Published var connecting = false
    var profileManager: ProfileManager?
    var store: Store?
    var captureServer: CaptureServer?

    enum Section: String, CaseIterable {
        case overview = "Overview", people = "People", commitments = "Commitments", timeline = "Timeline", connections = "Connections"
        var icon: String { switch self { case .overview: "square.grid.2x2"; case .people: "person.2"; case .commitments: "checkmark.circle"; case .timeline: "clock.arrow.circlepath"; case .connections: "point.3.connected.trianglepath.dotted" } }
        var subtitle: String { switch self { case .overview: "A little attention goes a long way."; case .people: "The people behind your promises."; case .commitments: "Keep track. Follow through."; case .timeline: "Your conversations, remembered."; case .connections: "Your relationships, connected." } }
    }
    enum Editor: Identifiable {
        case person(Person?), merge(Person), commitment(Commitment?, String?), interaction(String?), source(Interaction), profiles
        var id: String { switch self { case .person(let p): "person-\(p?.id ?? "new")"; case .merge(let p): "merge-\(p.id)"; case .commitment(let c, _): "promise-\(c?.id ?? "new")"; case .interaction: "interaction"; case .source(let i): "source-\(i.id)"; case .profiles: "profiles" } }
    }
    init() {
        do {
            let demo = ProcessInfo.processInfo.arguments.contains("--demo")
            if demo {
                let path = ProcessInfo.processInfo.environment["AGORA_DATA_DIR"] ?? ""
                let privateLibrary = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Agora")
                guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath() != privateLibrary.standardizedFileURL.resolvingSymlinksInPath() else {
                    throw AgoraError.invalid("Demo mode requires AGORA_DATA_DIR to point to a separate, nonempty library path.")
                }
            }
            let manager = try ProfileManager(); profileManager = manager
            let selection = try manager.snapshot(); profiles = selection.profiles; activeProfile = selection.active
            let store = try Store(directory: manager.directory(for: selection.active)); self.store = store
            if demo {
                if try store.contacts().isEmpty { try Self.seedDemo(store) }
            }
        } catch { store = nil; self.error = error.localizedDescription }
        reload(); startOutlook()
    }
    func perform(_ action: (Store) throws -> Void) {
        guard let store else { error = "The library could not be opened. Quit and reopen Agora."; return }
        do {
            if let profileManager { try profileManager.withActiveProfile(expectedID: activeProfile.id) { _ in try action(store) } }
            else { try action(store) }
            reload()
        } catch { self.error = error.localizedDescription }
    }
    func reload() {
        do {
            if let profileManager {
                let selection = try profileManager.snapshot()
                if selection.activeID != activeProfile.id {
                    let replacement = try Store(directory: profileManager.directory(for: selection.active))
                    applyProfile(selection, store: replacement)
                } else { profiles = selection.profiles; activeProfile = selection.active }
            }
            guard let store else { return }
            let library = try store.snapshot(); people = library.contacts; interactions = library.interactions; commitments = library.commitments
        }
        catch { self.error = error.localizedDescription }
    }
    func switchProfile(_ profile: LibraryProfile) {
        guard let profileManager, !connecting else { return }
        do {
            guard sheet == nil || sheet?.id == "profiles" else { throw AgoraError.invalid("Save or cancel your current changes before switching profiles.") }
            let replacement = try Store(directory: profileManager.directory(for: profile))
            applyProfile(try profileManager.select(id: profile.id), store: replacement)
            reload()
        } catch { self.error = error.localizedDescription }
    }
    private func applyProfile(_ selection: ProfileSnapshot, store: Store) {
        self.store = store; profiles = selection.profiles; activeProfile = selection.active
        sheet = nil; search = ""; selectedPerson = nil; selectedCommitment = nil
        people = []; interactions = []; commitments = []; error = nil
        notice = "\(activeProfile.name) profile · Reconnect AI clients after switching"
        if let captureServer { captureServer.selectProfile(store: store, profile: activeProfile) }
        else { startOutlook() }
    }
    @discardableResult func createProfile(name: String) -> Bool {
        guard let profileManager else { return false }
        do { let profile = try profileManager.create(name: name); switchProfile(profile); return error == nil }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func renameProfile(_ profile: LibraryProfile, name: String) -> Bool {
        guard let profileManager else { return false }
        do { try profileManager.rename(id: profile.id, name: name); reload(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func person(_ id: String) -> Person? { people.first { $0.id == id } }
    var open: [Commitment] { commitments.filter { $0.status == "open" } }
    var owed: [Commitment] { open.filter { $0.direction == "i_owe" } }
    var overdue: [Commitment] { owed.filter(\.overdue) }
    var today: [Commitment] { owed.filter { $0.dueDate == Day.string() } }
    var waiting: [Commitment] { open.filter { $0.direction == "they_owe" } }
    var focus: [Commitment] { owed.sorted { ($0.dueDate ?? "9999", $0.priority == "high" ? 0 : 1) < ($1.dueDate ?? "9999", $1.priority == "high" ? 0 : 1) } }
    func matches(_ strings: String...) -> Bool { search.isEmpty || strings.joined(separator: " ").localizedCaseInsensitiveContains(search) }
    func markDone(_ commitment: Commitment) { perform { store in var value = commitment; value.status = commitment.status == "done" ? "open" : "done"; _ = try store.updateCommitment(value) } }
    func startOutlook() {
        guard let store else { return }
        captureServer?.stop(); captureServer = nil
        let connectionDirectory = profileManager?.root ?? store.directory
        guard FileManager.default.fileExists(atPath: connectionDirectory.appendingPathComponent("localhost.p12").path) else { outlookStatus = "Set up local HTTPS to connect"; return }
        do {
            var port: UInt16 = 3848
            if let value = ProcessInfo.processInfo.environment["AGORA_TEST_OUTLOOK_PORT"] {
                let privateLibrary = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Agora").resolvingSymlinksInPath()
                guard ProcessInfo.processInfo.environment["AGORA_DATA_DIR"]?.isEmpty == false,
                      connectionDirectory.resolvingSymlinksInPath() != privateLibrary,
                      let testPort = UInt16(value), testPort > 1023 else { throw AgoraError.invalid("The test port requires a separate test library.") }
                port = testPort
            }
            let server = try CaptureServer(store: store, resourceURL: Bundle.module.url(forResource: "Outlook", withExtension: nil)!, connectionDirectory: connectionDirectory, profileManager: profileManager, profile: activeProfile, port: port)
            server.onStatus = { [weak self, weak server] message in Task { @MainActor in if self?.captureServer === server { self?.outlookStatus = message } } }
            captureServer = server; try server.start()
        } catch { outlookStatus = error.localizedDescription; FileHandle.standardError.write(Data("Agora Outlook: \(outlookStatus)\n".utf8)) }
    }
    static func seedDemo(_ store: Store) throws {
        let people = [
            try store.createContact(name: "Sofia Chen", email: "sofia@example.com", company: "Northstar Studio", role: "Design Director", tags: ["Work", "Design"], notes: "Met at the Melbourne design meetup. Building a new studio together with her cofounder. Ask about the Tokyo trip."),
            try store.createContact(name: "James Wilson", email: "james@example.com", company: "Fieldwork", role: "Founder", tags: ["Work"]),
            try store.createContact(name: "Amelia Brooks", email: "amelia@example.com", company: "Common Ground", role: "Architect", tags: ["Friends"]),
            try store.createContact(name: "Oliver Park", email: "oliver@example.com", company: "Arc Ventures", role: "Partner", tags: ["Work", "Investing"])
        ]
        let date = { (days: Int) in Day.string(Calendar.current.date(byAdding: .day, value: days, to: Date())!) }
        let source = try store.logInteraction(contactId: people[0].id, kind: "email", subject: "A few thoughts on the studio", body: "Thanks for the conversation yesterday. I promised to send you the studio proposal by Friday. Looking forward to making this happen.", occurredAt: Date().addingTimeInterval(-3600).timeIntervalSince1970)
        try store.createCommitment(contactId: people[0].id, title: "Send the studio proposal", dueDate: date(0), priority: "high", notes: "Include the scope, milestones and a first-pass budget. We discussed a November start.", interactionId: source.id)
        try store.createCommitment(contactId: people[1].id, title: "Make an introduction to Daniel", dueDate: date(-1), notes: "Daniel's experience with early-stage teams could be useful.")
        try store.createCommitment(contactId: people[2].id, title: "Share the renovation references", dueDate: date(2))
        try store.createCommitment(contactId: people[3].id, title: "Catch up over coffee", dueDate: date(5))
        try store.createCommitment(contactId: people[1].id, title: "Feedback on the project brief", dueDate: date(3), direction: "they_owe")
        try store.logInteraction(contactId: people[1].id, kind: "call", subject: "A good conversation about what's next", body: "Discussed the new project and offered to introduce Daniel.", occurredAt: Date().addingTimeInterval(-80000).timeIntervalSince1970)
        try store.logInteraction(contactId: people[2].id, kind: "meeting", subject: "Lunch at Common Ground", body: "Caught up about the renovation and her new practice.", occurredAt: Date().addingTimeInterval(-170000).timeIntervalSince1970)
    }
}

@main struct AgoraApp: App {
    @NSApplicationDelegateAdaptor(AgoraAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var model = AppModel()
    @StateObject private var updates = Updates()
    init() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            let previewModel = AppModel()
            if let sectionIndex = CommandLine.arguments.firstIndex(of: "--render-section"), CommandLine.arguments.count > sectionIndex + 1,
               let section = AppModel.Section(rawValue: CommandLine.arguments[sectionIndex + 1]) { previewModel.section = section }
            if CommandLine.arguments.contains("--render-source") { previewModel.selectedCommitment = previewModel.commitments.first { $0.interactionId != nil }?.id }
            if let profileIndex = CommandLine.arguments.firstIndex(of: "--preview-profile"), CommandLine.arguments.count > profileIndex + 1,
               let profile = previewModel.profiles.first(where: { $0.name == CommandLine.arguments[profileIndex + 1] }) { previewModel.switchProfile(profile) }
            let mergePreview = CommandLine.arguments.contains("--render-merge") && previewModel.people.count > 1
            let profilesPreview = CommandLine.arguments.contains("--render-profiles")
            let width: CGFloat = profilesPreview ? 560 : mergePreview ? 520 : 1320
            let height: CGFloat = profilesPreview ? 520 : mergePreview ? 500 : previewModel.section == .connections ? 1850 : 850
            let content = profilesPreview ? AnyView(ProfilesView()) : mergePreview ? AnyView(MergePeopleEditor(source: previewModel.people[0], targetId: previewModel.people[1].id)) : AnyView(Workspace())
            let view = content.environmentObject(previewModel).environmentObject(Updates()).frame(width: width, height: height).environment(\.colorScheme, .light)
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
            hosting.layoutSubtreeIfNeeded()
            // Let asynchronous configuration checks populate the native preview.
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            hosting.layoutSubtreeIfNeeded()
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            }
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup("Agora", id: "main") {
            Workspace().environmentObject(model).environmentObject(updates).frame(minWidth: 1020, minHeight: 680)
                .onAppear {
                    model.reload()
                    NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
                    appDelegate.reopen = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                    appDelegate.checkWindowReopenIfRequested(profileID: model.activeProfile.id)
                }
        }
        .defaultSize(width: 1320, height: 850).windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Show Agora") { appDelegate.showMainWindow() }.keyboardShortcut("0")
                Button("Manage Profiles…") { appDelegate.showMainWindow(); model.sheet = .profiles }.disabled(model.sheet != nil || model.connecting)
                Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheck)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Person…") { model.sheet = .person(nil) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Commitment…") { model.sheet = .commitment(nil, model.selectedPerson) }.keyboardShortcut("n")
                Button("Log Interaction…") { model.sheet = .interaction(model.selectedPerson) }.keyboardShortcut("l")
            }
            CommandGroup(after: .toolbar) { Button("Refresh") { model.reload() }.keyboardShortcut("r") }
        }
    }
}
