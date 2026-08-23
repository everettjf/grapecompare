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

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        ExternalCompareRequest.store(filenames.map(URL.init(fileURLWithPath:)))
        sender.reply(toOpenOrPrint: filenames.count == 2 ? .success : .failure)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.flatMap { $0.isFileURL ? [$0] : ExternalCompareRequest.decode($0) }
        ExternalCompareRequest.store(files)
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
            MergeCommands()
            GitCommands()
            WorkspaceCommands()
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
    @State private var workspace = WorkspaceController()
    @Environment(\.scenePhase) private var scenePhase

    private var state: AppState { workspace.selectedState }

    var body: some View {
        WorkspaceView(workspace: workspace)
            .onAppear {
                state.consumePendingArgs()
                state.consumeQuickAction()
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active { state.consumeQuickAction() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .compareFilesIntentReceived)) { _ in
                state.consumeQuickAction()
            }
            .onReceive(NotificationCenter.default.publisher(for: .externalCompareRequestReceived)) { _ in
                state.consumeQuickAction()
            }
            .onOpenURL { url in
                ExternalCompareRequest.store(ExternalCompareRequest.decode(url))
            }
            .focusedSceneValue(\.fileOperationController, state.operations)
            .focusedSceneValue(\.appState, state)
            .focusedSceneValue(\.workspaceController, workspace)
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
    @Entry var appState: AppState?
    @Entry var workspaceController: WorkspaceController?
}

private struct GitCommands: Commands {
    @FocusedValue(\.appState) private var state

    private var isGitScreen: Bool { state?.screen == .git }

    var body: some Commands {
        CommandMenu("Git") {
            Button("Compare HEAD ↔ WORKTREE") {
                state?.useGitComparisonShortcut(left: "HEAD", right: "WORKTREE")
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
            .disabled(!isGitScreen)
            Button("Compare HEAD ↔ INDEX") {
                state?.useGitComparisonShortcut(left: "HEAD", right: "INDEX")
            }
            .keyboardShortcut("2", modifiers: [.command, .shift])
            .disabled(!isGitScreen)
            Button("Compare INDEX ↔ WORKTREE") {
                state?.useGitComparisonShortcut(left: "INDEX", right: "WORKTREE")
            }
            .keyboardShortcut("3", modifiers: [.command, .shift])
            .disabled(!isGitScreen)
            Divider()
            Button("Refresh Git Comparison") { state?.startGitComparison() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!isGitScreen || state?.isComparingGit == true)
        }
    }
}

private struct WorkspaceCommands: Commands {
    @FocusedValue(\.workspaceController) private var workspace

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Comparison") { workspace?.addComparison() }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(workspace == nil)
        }
        CommandGroup(before: .windowArrangement) {
            Button("Close Comparison") {
                guard let workspace else { return }
                workspace.close(workspace.selectedID)
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(workspace?.selectedState.canCloseWorkspaceItem != true)
        }
    }
}

private struct MergeCommands: Commands {
    @FocusedValue(\.appState) private var state

    private var isMerging: Bool { state?.screen == .merge && state?.mergeResult != nil }

    var body: some Commands {
        CommandMenu("Merge") {
            Button("Previous Conflict") { state?.selectAdjacentMergeConflict(offset: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(!isMerging)
            Button("Next Conflict") { state?.selectAdjacentMergeConflict(offset: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command])
                .disabled(!isMerging)
            Divider()
            Button("Accept Base for Conflict") { state?.resolveSelectedMergeConflict(with: .base) }
                .keyboardShortcut("1", modifiers: [.command])
                .disabled(!isMerging || state?.selectedMergeConflictID == nil)
            Button("Accept Ours for Conflict") { state?.resolveSelectedMergeConflict(with: .ours) }
                .keyboardShortcut("2", modifiers: [.command])
                .disabled(!isMerging || state?.selectedMergeConflictID == nil)
            Button("Accept Theirs for Conflict") { state?.resolveSelectedMergeConflict(with: .theirs) }
                .keyboardShortcut("3", modifiers: [.command])
                .disabled(!isMerging || state?.selectedMergeConflictID == nil)
            Button("Accept Both for Conflict") { state?.resolveSelectedMergeConflict(with: .both) }
                .keyboardShortcut("4", modifiers: [.command])
                .disabled(!isMerging || state?.selectedMergeConflictID == nil)
            Divider()
            Button("Accept Ours for All Conflicts") { state?.resolveAllMergeConflicts(with: .ours) }
                .keyboardShortcut("2", modifiers: [.command, .shift])
                .disabled(!isMerging)
            Button("Accept Theirs for All Conflicts") { state?.resolveAllMergeConflicts(with: .theirs) }
                .keyboardShortcut("3", modifiers: [.command, .shift])
                .disabled(!isMerging)
            Divider()
            Button("Undo Conflict Resolution") { state?.undoMergeResolution() }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(state?.canUndoMergeResolution != true)
            Button("Redo Conflict Resolution") { state?.redoMergeResolution() }
                .keyboardShortcut("z", modifiers: [.command, .option, .shift])
                .disabled(state?.canRedoMergeResolution != true)
        }
    }
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
