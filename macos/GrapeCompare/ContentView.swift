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
            case .git:
                GitCompareView()
            }
        }
        .frame(minWidth: AppLayoutPolicy.minimumContentWidth, minHeight: 560)
        .onAppear { state.consumePendingArgs() }
        .onChange(of: state.operations.mutationVersion) {
            state.handleFilesystemMutation()
        }
    }
}
