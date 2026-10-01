import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if state.isFolderWorkspace && state.screen == .fileDiff {
                HSplitView {
                    FolderCompareView(sidebar: true)
                        .frame(minWidth: 230, idealWidth: 300, maxWidth: 420)
                    FileDiffView().id(ComparisonReadingStore.key(kind: "preview", left: state.diffLeftURL, right: state.diffRightURL))
                        .frame(minWidth: 440)
                }
            } else {
            switch state.screen {
            case .home:
                HomeView()
            case .fileDiff:
                FileDiffView()
            case .folderCompare:
                FolderCompareView()
            case .merge:
                MergeView()
            }
            }
        }
        .confirmationDialog("Save changes before leaving?", isPresented: Binding(
            get: { state.showsNavigationConfirmation },
            set: { state.showsNavigationConfirmation = $0 }), titleVisibility: .visible) {
                Button("Save and Continue") { state.resolveFileNavigation(save: true) }
                Button("Discard Changes", role: .destructive) { state.resolveFileNavigation(save: false, discard: true) }
                Button("Cancel", role: .cancel) { state.resolveFileNavigation(save: nil) }
        } message: {
            Text("The editable output contains changes that have not been saved.")
        }
        .frame(
            minWidth: AppLayoutPolicy.minimumContentWidth,
            minHeight: AppLayoutPolicy.minimumContentHeight)
        .onChange(of: state.operations.mutationVersion) {
            state.handleFilesystemMutation()
        }
    }
}
