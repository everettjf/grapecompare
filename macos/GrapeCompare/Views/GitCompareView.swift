import SwiftUI

struct GitCompareView: View {
    @Environment(AppState.self) private var state
    @State private var selection = Set<GitChange.ID>()
    @State private var query = ""

    private var filteredChanges: [GitChange] {
        guard !query.isEmpty else { return state.gitChanges }
        return state.gitChanges.filter {
            $0.path.localizedCaseInsensitiveContains(query) ||
                $0.oldPath?.localizedCaseInsensitiveContains(query) == true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.isComparingGit {
                ProgressView("Reading Git repository…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = state.gitError {
                ContentUnavailableView(
                    "Git Comparison Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error))
            } else if state.gitChanges.isEmpty {
                ContentUnavailableView(
                    "No Git Differences",
                    systemImage: "checkmark.seal.fill",
                    description: Text("The selected repository states are equivalent."))
            } else {
                Table(filteredChanges, selection: $selection) {
                    TableColumn("Status") { change in
                        Label(change.kind.localizedTitle, systemImage: change.kind.symbol)
                            .foregroundStyle(change.kind.color)
                    }
                    .width(min: 110, ideal: 130)
                    TableColumn("Path") { change in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.path).font(Theme.mono)
                            if let oldPath = change.oldPath {
                                Text("from \(oldPath)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    TableColumn("Action") { change in
                        Button("Compare") { state.openGitChange(change) }
                            .buttonStyle(.borderless)
                    }
                    .width(80)
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
                .onSubmit {
                    if let id = selection.first,
                       let change = state.gitChanges.first(where: { $0.id == id }) {
                        state.openGitChange(change)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { state.goHome() } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .keyboardShortcut(.cancelAction)
            Divider().frame(height: 20)
            Text(state.gitRepositoryURL?.lastPathComponent ?? "Repository").bold()
            TextField("From revision", text: targetBinding(\.gitLeftTarget))
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
            Image(systemName: "arrow.right")
            TextField("To revision, INDEX, or WORKTREE", text: targetBinding(\.gitRightTarget))
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
            Menu("References") {
                ForEach(state.gitReferences) { reference in
                    Button(reference.name) { state.gitLeftTarget = reference.name }
                }
            }
            Button("Compare") {
                selection.removeAll()
                state.startGitComparison()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
            TextField("Filter paths", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Text("\(state.gitChanges.count) changes")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func targetBinding(_ keyPath: ReferenceWritableKeyPath<AppState, String>) -> Binding<String> {
        Binding(
            get: { state[keyPath: keyPath] },
            set: { state[keyPath: keyPath] = $0 })
    }
}

private extension GitChangeKind {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .added: "Added"
        case .modified: "Modified"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .copied: "Copied"
        case .typeChanged: "Type Changed"
        case .unmerged: "Unmerged"
        case .untracked: "Untracked"
        case .unknown: "Changed"
        }
    }

    var symbol: String {
        switch self {
        case .added, .untracked: "plus.circle"
        case .deleted: "minus.circle"
        case .renamed: "arrow.right.circle"
        case .copied: "doc.on.doc"
        case .unmerged: "exclamationmark.triangle"
        default: "pencil.circle"
        }
    }

    var color: Color {
        switch self {
        case .added, .untracked: .green
        case .deleted: .red
        case .renamed, .copied: .blue
        case .unmerged: .orange
        default: .secondary
        }
    }
}
