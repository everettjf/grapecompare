import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            switch state.screen {
            case .home:
                HomeView()
            case .fileDiff:
                FileDiffView()
            case .folderCompare:
                FolderCompareView()
            }
        }
        .frame(minWidth: 860, minHeight: 560)
    }
}
