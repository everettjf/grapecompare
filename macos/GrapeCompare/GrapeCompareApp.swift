import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Never save or restore window state. On this macOS release a failed
    /// restore (e.g. stale scene-type identifier) leaves the app running
    /// with zero windows, and the restoration storage cannot be cleared
    /// reliably from outside.
    func applicationShouldSaveApplicationState(_ application: NSApplication, coder: NSCoder) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ application: NSApplication, coder: NSCoder) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply the persisted appearance here — NSApp.appearance must not be
        // touched during scene construction (see AppState).
        let stored = UserDefaults.standard.string(forKey: "appearance")
        NSApp.appearance = (AppearanceMode(rawValue: stored ?? "") ?? .system).nsAppearance
    }
}

@main
struct GrapeCompareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
        }
        .defaultSize(width: 1120, height: 740)
        .windowToolbarStyle(.unified)
        // NB: do NOT apply .preferredColorScheme on the scene content — it
        // prevents the window from being created at all (macOS 27 beta).
        .commands {
            CommandMenu("Appearance") {
                Picker("Appearance", selection: $state.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}
