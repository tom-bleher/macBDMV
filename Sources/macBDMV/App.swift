import AppKit
import SwiftUI

@main
struct MacBDMVApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private var model: AppModel { delegate.model }

    var body: some Scene {
        Window("macBDMV", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 540)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { SoftwareUpdate.shared.checkForUpdates() }
                    .disabled(!SoftwareUpdate.shared.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Blu-ray Folder…") { openPanel(model) }
                    .keyboardShortcut("o")
                    .disabled(model.running || model.scanning)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    /// Folders dropped on the Dock icon or opened with `open -a macBDMV <folder>`.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { await model.open(url) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)  // needed when launched via `swift run`
        NSApp.activate()
        _ = SoftwareUpdate.shared  // starts Sparkle's scheduled checks
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
}

@MainActor
func chooseFolder(prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.prompt = prompt
    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor
func openPanel(_ model: AppModel) {
    guard let url = chooseFolder(prompt: "Open") else { return }
    Task { await model.open(url) }
}
