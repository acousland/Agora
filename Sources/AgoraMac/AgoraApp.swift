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
    var store: Store?
    var captureServer: CaptureServer?

    enum Section: String, CaseIterable {
        case overview = "Overview", people = "People", commitments = "Commitments", timeline = "Timeline", connections = "Connections"
        var icon: String { switch self { case .overview: "square.grid.2x2"; case .people: "person.2"; case .commitments: "checkmark.circle"; case .timeline: "clock.arrow.circlepath"; case .connections: "point.3.connected.trianglepath.dotted" } }
        var subtitle: String { switch self { case .overview: "A little attention goes a long way."; case .people: "The people behind your promises."; case .commitments: "Keep track. Follow through."; case .timeline: "Your conversations, remembered."; case .connections: "Your relationships, connected." } }
    }
    enum Editor: Identifiable {
        case person(Person?), commitment(Commitment?, String?), interaction(String?), source(Interaction)
        var id: String { switch self { case .person(let p): "person-\(p?.id ?? "new")"; case .commitment(let c, _): "promise-\(c?.id ?? "new")"; case .interaction: "interaction"; case .source(let i): "source-\(i.id)" } }
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
            let store = try Store(); self.store = store
            if demo {
                if try store.contacts().isEmpty { try Self.seedDemo(store) }
            }
        } catch { store = nil; self.error = error.localizedDescription }
        reload(); startOutlook()
    }
    func perform(_ action: (Store) throws -> Void) {
        guard let store else { error = "The library could not be opened. Quit and reopen Agora."; return }
        do { try action(store); reload() } catch { self.error = error.localizedDescription }
    }
    func reload() {
        guard let store else { return }
        do { let library = try store.snapshot(); people = library.contacts; interactions = library.interactions; commitments = library.commitments }
        catch { self.error = error.localizedDescription }
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
        guard FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("localhost.p12").path) else { outlookStatus = "Set up local HTTPS to connect"; return }
        do {
            let server = try CaptureServer(store: store, resourceURL: Bundle.module.url(forResource: "Outlook", withExtension: nil)!)
            server.onStatus = { [weak self] message in Task { @MainActor in self?.outlookStatus = message } }
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
    @StateObject private var model = AppModel()
    @StateObject private var updates = Updates()
    init() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            let previewModel = AppModel()
            if let sectionIndex = CommandLine.arguments.firstIndex(of: "--render-section"), CommandLine.arguments.count > sectionIndex + 1,
               let section = AppModel.Section(rawValue: CommandLine.arguments[sectionIndex + 1]) { previewModel.section = section }
            if CommandLine.arguments.contains("--render-source") { previewModel.selectedCommitment = previewModel.commitments.first { $0.interactionId != nil }?.id }
            let height: CGFloat = previewModel.section == .connections ? 1700 : 850
            let view = Workspace().environmentObject(previewModel).environmentObject(Updates()).frame(width: 1320, height: height).environment(\.colorScheme, .light)
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.frame = NSRect(x: 0, y: 0, width: 1320, height: height)
            hosting.layoutSubtreeIfNeeded()
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            }
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup {
            Workspace().environmentObject(model).environmentObject(updates).frame(minWidth: 1020, minHeight: 680)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1320, height: 850).windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) { Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheck) }
            CommandGroup(replacing: .newItem) {
                Button("New Person…") { model.sheet = .person(nil) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Commitment…") { model.sheet = .commitment(nil, model.selectedPerson) }.keyboardShortcut("n")
                Button("Log Interaction…") { model.sheet = .interaction(model.selectedPerson) }.keyboardShortcut("l")
            }
            CommandGroup(after: .toolbar) { Button("Refresh") { model.reload() }.keyboardShortcut("r") }
        }
    }
}
