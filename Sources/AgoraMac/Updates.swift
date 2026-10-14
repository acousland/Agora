import SwiftUI
import Sparkle

@MainActor final class Updates: ObservableObject {
    let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticDownloads = false
    private var observations: [NSKeyValueObservation] = []
    init() {
        let packaged = Bundle.main.bundleIdentifier == "au.com.acousland.Agora"
        let testing = CommandLine.arguments.contains("--render-preview") || CommandLine.arguments.contains("--smoke-window-reopen") || ProcessInfo.processInfo.environment["AGORA_TEST_OUTLOOK_PORT"] != nil
        controller = SPUStandardUpdaterController(startingUpdater: packaged && !testing, updaterDelegate: nil, userDriverDelegate: nil)
        let updater = controller.updater
        canCheck = updater.canCheckForUpdates
        automaticChecks = updater.automaticallyChecksForUpdates
        automaticDownloads = updater.automaticallyDownloadsUpdates
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.canCheck = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.automaticChecks = updater.automaticallyChecksForUpdates }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.automaticDownloads = updater.automaticallyDownloadsUpdates }
            }
        ]
    }
    func check() { controller.checkForUpdates(nil) }
    func setAutomaticChecks(_ value: Bool) { controller.updater.automaticallyChecksForUpdates = value }
    func setAutomaticDownloads(_ value: Bool) { controller.updater.automaticallyDownloadsUpdates = value }
}

struct UpdatesView: View {
    @EnvironmentObject var updates: Updates
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("App updates", systemImage: "arrow.down.circle").font(.system(size: 16, weight: .semibold))
                Text("Agora checks for signed updates from GitHub Releases once a day while open. Updates include the MCP helper; restart your AI client after installing an update.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                Toggle("Check for updates automatically", isOn: Binding(get: { updates.automaticChecks }, set: updates.setAutomaticChecks))
                Toggle("Download and install updates automatically", isOn: Binding(get: { updates.automaticDownloads }, set: updates.setAutomaticDownloads)).disabled(!updates.automaticChecks)
                Button("Check for Updates…") { updates.check() }.buttonStyle(.bordered).disabled(!updates.canCheck)
            }.font(.system(size: 12))
        }
    }
}
