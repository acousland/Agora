import AppKit

@MainActor final class AgoraAppDelegate: NSObject, NSApplicationDelegate {
    var reopen: (() -> Void)?
    private var checkedReopen = false
    private var observedProfileID = ""
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0.title == "Agora" }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else { reopen?() }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
    /// Run against a disposable library: exercise our own window lifecycle, including
    /// the real SwiftUI openWindow action used by Dock reopen and Show Agora.
    func checkWindowReopenIfRequested(profileID: String) {
        observedProfileID = profileID
        guard CommandLine.arguments.contains("--smoke-window-reopen"), !checkedReopen else { return }
        checkedReopen = true
        let privateLibrary = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Agora").resolvingSymlinksInPath()
        guard let path = ProcessInfo.processInfo.environment["AGORA_DATA_DIR"], !path.isEmpty,
              URL(fileURLWithPath: path).resolvingSymlinksInPath() != privateLibrary else { exit(1) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let windows = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }
            guard windows.count == 1 else { self.failReopen("Expected one visible main window."); return }
            windows[0].close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { self.failReopen("The main window did not close."); return }
                _ = self.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard NSApp.windows.filter({ $0.isVisible && $0.canBecomeMain }).count == 1 else { self.failReopen("Dock reopen did not restore the main window."); return }
                    self.showMainWindow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        guard NSApp.windows.filter({ $0.isVisible && $0.canBecomeMain }).count == 1 else { self.failReopen("Show Agora created a duplicate window."); return }
                        guard self.observedProfileID == profileID else { self.failReopen("Reopening changed the selected profile."); return }
                        FileHandle.standardOutput.write(Data("Native window smoke passed: close, Dock reopen, Show Agora without duplicate windows, selected profile preserved.\n".utf8))
                        exit(0)
                    }
                }
            }
        }
    }
    private func failReopen(_ message: String) {
        FileHandle.standardError.write(Data("Window reopen test: \(message)\n".utf8)); exit(1)
    }
}
