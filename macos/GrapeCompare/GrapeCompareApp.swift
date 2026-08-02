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
    @State private var appearance = AppearanceSettings()

    var body: some Scene {
        WindowGroup {
            WindowRootView()
                .environment(appearance)
        }
        .defaultSize(width: 1120, height: 740)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        // NB: do NOT apply .preferredColorScheme on the scene content — it
        // prevents the window from being created at all (macOS 27 beta).
        .commands {
            FileOperationCommands()
            CommandMenu("Appearance") {
                Picker("Appearance", selection: Binding(
                    get: { appearance.mode },
                    set: { appearance.mode = $0 }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }
        }

        Settings {
            DemoSettingsView()
        }
    }
}

private struct WindowRootView: View {
    @State private var state = AppState()

    var body: some View {
        ContentView()
            .environment(state)
            .focusedSceneValue(\.fileOperationController, state.operations)
            .sheet(isPresented: Binding(
                get: { state.operations.historyPresented },
                set: { state.operations.historyPresented = $0 }
            )) {
                FileOperationHistorySheet(controller: state.operations)
            }
            .sheet(item: Binding(
                get: { state.operations.reviewPresentation },
                set: { state.operations.reviewPresentation = $0 }
            ), onDismiss: {
                state.operations.reviewDidDismiss()
            }) { _ in
                FileOperationReviewSheet(controller: state.operations)
                    .interactiveDismissDisabled(
                        state.operations.phase == .executing || state.operations.phase == .undoing)
            }
    }
}

extension FocusedValues {
    @Entry var fileOperationController: FileOperationController?
}

private struct FileOperationCommands: Commands {
    @FocusedValue(\.fileOperationController) private var controller

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Last File Operation") {
                controller?.undoLastTransaction()
            }
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(controller?.canUndo != true)
            Divider()
            Button("Operation History") {
                controller?.showHistory()
            }
            .disabled(controller == nil)
        }
    }
}

private struct DemoSettingsView: View {
    @AppStorage("showDemoButton") private var showDemoButton = true

    var body: some View {
        Form {
            Toggle("Show Load Demo button on the home screen", isOn: $showDemoButton)
            Text("Demo data is generated locally and never leaves your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 430)
    }
}
