import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct BlitzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Blitz") {
            ContentView().environmentObject(model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Video…") { model.tab = .compose; model.showImporter = true }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Accounts…") { model.showAccounts = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
