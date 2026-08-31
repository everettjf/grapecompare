import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
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
        .frame(
            minWidth: AppLayoutPolicy.minimumContentWidth,
            minHeight: AppLayoutPolicy.minimumContentHeight)
        .onChange(of: state.operations.mutationVersion) {
            state.handleFilesystemMutation()
        }
    }
}
