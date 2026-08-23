import SwiftUI

private enum ChangesetBrowserMode: String, CaseIterable, Identifiable {
    case flat, tree
    var id: Self { self }
    var title: LocalizedStringResource { self == .flat ? "Flat" : "Tree" }
    var symbol: String { self == .flat ? "list.bullet" : "list.bullet.indent" }
}

struct GitCompareView: View {
    @Environment(AppState.self) private var state
    @State private var selection = Set<GitChange.ID>()
    @State private var query = ""
    @State private var statusFilter: GitChangeKind?
    @State private var stageFilter: GitChangeStage?
    @State private var historyA: GitFileRevision.ID?
    @State private var historyB: GitFileRevision.ID?
    @State private var browserMode = ChangesetBrowserMode.flat

    private var filteredChanges: [GitChange] {
        return state.gitChanges.filter {
            (statusFilter == nil || $0.kind == statusFilter) &&
                (stageFilter == nil || $0.stage == stageFilter) &&
                (query.isEmpty || $0.path.localizedCaseInsensitiveContains(query) ||
                    $0.oldPath?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    private var partiallyStagedPaths: Set<String> {
        let staged = Set(state.gitChanges.filter { $0.stage == .staged }.map(\.path))
        let unstaged = Set(state.gitChanges.filter { $0.stage == .unstaged }.map(\.path))
        return staged.intersection(unstaged)
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
                VStack(spacing: 0) {
                    commitContext
                    Divider()
                    HSplitView {
                        Group {
                            if browserMode == .flat {
                                changesTable
                            } else {
                                changesTree
                            }
                        }
                        .frame(minWidth: 480)
                        historyInspector
                            .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
                    }
                    .onSubmit {
                        if let id = selection.first,
                           let change = state.gitChanges.first(where: { $0.id == id }) {
                            state.openGitChange(change)
                        }
                    }
                }
                .onChange(of: selection) { _, selected in
                    guard let id = selected.first,
                          let change = state.gitChanges.first(where: { $0.id == id }) else { return }
                    state.loadGitFileHistory(change)
                    state.gitSelectedChangeID = change.id
                }
                .onChange(of: state.gitFileRevisions) { _, revisions in
                    historyA = revisions.first?.id
                    historyB = revisions.dropFirst().first?.id
                }
            }
        }
        .alert("Git Action Failed", isPresented: Binding(
            get: { state.gitActionError != nil },
            set: { if !$0 { state.gitActionError = nil } }
        )) {
            Button("OK") { state.gitActionError = nil }
        } message: {
            Text(state.gitActionError ?? "")
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
            Menu("Shortcuts") {
                Button("HEAD ↔ WORKTREE") {
                    state.useGitComparisonShortcut(left: "HEAD", right: "WORKTREE")
                }
                Button("HEAD ↔ INDEX") {
                    state.useGitComparisonShortcut(left: "HEAD", right: "INDEX")
                }
                Button("INDEX ↔ WORKTREE") {
                    state.useGitComparisonShortcut(left: "INDEX", right: "WORKTREE")
                }
                Divider()
                Button("Changes in Last 24 Hours") {
                    state.compareGitChanges(since: 24 * 60 * 60)
                }
                Button("Changes in Last 7 Days") {
                    state.compareGitChanges(since: 7 * 24 * 60 * 60)
                }
                Button("Changes in Last 30 Days") {
                    state.compareGitChanges(since: 30 * 24 * 60 * 60)
                }
            }
            if state.gitWorktrees.count > 1 {
                Menu("Worktrees") {
                    ForEach(state.gitWorktrees) { worktree in
                        Button {
                            state.switchGitWorktree(worktree)
                        } label: {
                            Label(worktree.branch ?? String(localized: "Detached HEAD"),
                                  systemImage: worktree.isLocked ? "lock" : "point.3.connected.trianglepath.dotted")
                        }
                    }
                }
            }
            Button("Compare") {
                selection.removeAll()
                state.startGitComparison()
            }
            .buttonStyle(.borderedProminent)
            Menu {
                Button("Reveal Repository in Finder") { state.revealGitRepositoryInFinder() }
                Button("Open Repository in Terminal") { state.openGitRepositoryInTerminal() }
            } label: {
                Label("Repository Actions", systemImage: "folder")
            }
            Spacer()
            Picker("Changeset layout", selection: $browserMode) {
                ForEach(ChangesetBrowserMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            Menu {
                Button("All Statuses") { statusFilter = nil }
                Divider()
                ForEach(GitChangeKind.allCases) { kind in
                    Button { statusFilter = kind } label: {
                        Label(kind.localizedTitle, systemImage: kind.symbol)
                    }
                }
            } label: {
                Label(statusFilter?.localizedTitle ?? "All Statuses", systemImage: "line.3.horizontal.decrease.circle")
            }
            Menu {
                Button("All Stages") { stageFilter = nil }
                Divider()
                ForEach(GitChangeStage.allCases) { stage in
                    Button(stage.localizedTitle) { stageFilter = stage }
                }
            } label: {
                Label(stageFilter?.localizedTitle ?? "All Stages", systemImage: "square.stack.3d.up")
            }
            TextField("Filter paths", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Text("\(state.gitChanges.count) changes")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var commitContext: some View {
        HStack(spacing: 12) {
            commitCard(target: state.gitLeftTarget, commit: state.gitLeftCommit, isLeft: true)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            commitCard(target: state.gitRightTarget, commit: state.gitRightCommit, isLeft: false)
            Spacer()
            if let context = state.gitBranchContext {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.branch ?? String(localized: "Detached HEAD")).font(.caption.bold())
                    if let upstream = context.upstream {
                        Text("\(upstream) · ↑\(context.ahead) ↓\(context.behind)")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    if let mergeBase = context.mergeBaseObjectID {
                        Button("Merge Base \(mergeBase.prefix(8))") {
                            state.useGitComparisonShortcut(left: mergeBase, right: "HEAD")
                        }
                        .buttonStyle(.link).font(.caption2.monospaced())
                    }
                }
            }
            Button { state.selectAdjacentGitChange(forward: false) } label: {
                Label("Previous Change", systemImage: "chevron.up")
            }
            .labelStyle(.iconOnly)
            .keyboardShortcut("[", modifiers: [.command])
            Button { state.selectAdjacentGitChange(forward: true) } label: {
                Label("Next Change", systemImage: "chevron.down")
            }
            .labelStyle(.iconOnly)
            .keyboardShortcut("]", modifiers: [.command])
            if let change = selectedChange {
                Button { state.toggleGitReviewed(change) } label: {
                    Label(state.gitReviewedChangeIDs.contains(change.id) ? "Reviewed" : "Mark Reviewed",
                          systemImage: state.gitReviewedChangeIDs.contains(change.id) ? "checkmark.circle.fill" : "circle")
                }
            }
            let reviewed = state.gitReviewedChangeIDs.count
            Text("\(reviewed) of \(state.gitChanges.count) reviewed")
                .font(.caption.monospacedDigit())
                .foregroundStyle(reviewed == state.gitChanges.count ? .green : .secondary)
                .accessibilityLabel("Review progress")
                .accessibilityValue("\(reviewed) of \(state.gitChanges.count) files reviewed")
            if let date = state.lastLiveRefresh {
                Label {
                    Text(date, format: .dateTime.hour().minute().second())
                } icon: {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Last live refresh")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.3))
    }

    private var selectedChange: GitChange? {
        state.gitSelectedChangeID.flatMap { id in state.gitChanges.first { $0.id == id } }
    }

    private var changesTable: some View {
        Table(filteredChanges, selection: $selection) {
            TableColumn("Stage") { change in
                Label(
                    partiallyStagedPaths.contains(change.path)
                        ? LocalizedStringResource("Partially Staged")
                        : change.stage.localizedTitle,
                    systemImage: partiallyStagedPaths.contains(change.path)
                        ? "circle.lefthalf.filled" : change.stage.symbol)
            }.width(min: 90, ideal: 110)
            TableColumn("Status") { change in
                Label(change.kind.localizedTitle, systemImage: change.kind.symbol)
                    .foregroundStyle(change.kind.color)
            }.width(min: 110, ideal: 130)
            TableColumn("Path") { change in
                HStack {
                    if state.gitReviewedChangeIDs.contains(change.id) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.path).font(Theme.mono)
                        if let oldPath = change.oldPath {
                            Text("from \(oldPath)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .contextMenu { gitChangeContextMenu(change) }
            }
            TableColumn("Action") { change in
                Button("Compare") { state.openGitChange(change) }.buttonStyle(.borderless)
            }.width(80)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
    }

    private var changesTree: some View {
        List {
            OutlineGroup(GitChangesetTreeBuilder.build(filteredChanges), children: \.outlineChildren) { node in
                if let change = node.change {
                    Button {
                        state.gitSelectedChangeID = change.id
                        selection = [change.id]
                        state.loadGitFileHistory(change)
                    } label: {
                        Label(node.name, systemImage: change.kind.symbol)
                            .foregroundStyle(change.kind.color)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { gitChangeContextMenu(change) }
                } else {
                    Label(node.name, systemImage: "folder")
                }
            }
        }
        .accessibilityLabel("Changed files tree")
    }

    @ViewBuilder
    private func gitChangeContextMenu(_ change: GitChange) -> some View {
        Button("Compare") { state.openGitChange(change) }
        Button("Open File History") {
            state.gitSelectedChangeID = change.id
            selection = [change.id]
            state.loadGitFileHistory(change)
        }
        Divider()
        Button("Copy File Path") { state.copyGitChangePath(change) }
        Button("Copy File Contents") { state.copyGitChangeContents(change) }
        Button("Save a Copy…") { state.saveGitChangeCopy(change) }
        Divider()
        Button("Open in Default Editor") { state.openGitChangeExternally(change) }
        Button("Reveal in Finder") { state.revealGitChangeInFinder(change) }
    }

    private func commitCard(target: String, commit: GitCommit?, isLeft: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(target).font(.caption.bold())
            if let commit {
                Text("\(commit.shortObjectID)  \(commit.subject)")
                    .font(Theme.mono)
                    .lineLimit(1)
                Text("\(commit.authorName) · \(commit.authoredDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !commit.parentIDs.isEmpty {
                    HStack(spacing: 4) {
                        Text("Parents:").font(.caption2).foregroundStyle(.secondary)
                        ForEach(commit.parentIDs, id: \.self) { parent in
                            Button(String(parent.prefix(8))) {
                                if isLeft {
                                    state.useGitComparisonShortcut(left: parent, right: state.gitRightTarget)
                                } else {
                                    state.useGitComparisonShortcut(left: state.gitLeftTarget, right: parent)
                                }
                            }
                            .buttonStyle(.link)
                            .font(.caption2.monospaced())
                            .help("Compare using parent commit \(parent)")
                        }
                    }
                }
            } else {
                Text(target.uppercased() == "WORKTREE" ? "Working tree" : "Staging index")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 330, alignment: .leading)
    }

    @ViewBuilder
    private var historyInspector: some View {
        TabView {
            fileHistoryInspector
                .tabItem { Label("File History", systemImage: "clock.arrow.circlepath") }
            commitGraphInspector
                .tabItem { Label("Commit Graph", systemImage: "point.3.filled.connected.trianglepath.dotted") }
        }
    }

    @ViewBuilder
    private var fileHistoryInspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let change = selectedChange {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Review Note").font(.caption.bold())
                    TextField("Add a local note for this change", text: Binding(
                        get: { state.gitReviewNotes[change.id] ?? "" },
                        set: { state.updateGitReviewNote($0, for: change) }
                    ), axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityHint("Stored locally for this repository and comparison")
                }
                .padding(12)
                Divider()
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("File History").font(.headline)
                    Text(state.gitHistoryPath ?? String(localized: "Select a changed file"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let inspection = state.gitSelectedFileInspection {
                        Text(inspection.summary)
                            .font(.caption2)
                            .foregroundStyle(inspection.kind == .text ? Color.secondary : Color.orange)
                    }
                }
                Spacer()
                Button("Compare A ↔ B") {
                    guard let left = revision(historyA), let right = revision(historyB) else { return }
                    state.compareGitFileRevisions(left, right)
                }
                .disabled(historyA == nil || historyB == nil || historyA == historyB)
            }
            .padding(12)
            Divider()
            if state.isLoadingGitHistory && state.gitFileRevisions.isEmpty {
                ProgressView("Reading file history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = state.gitHistoryError {
                ContentUnavailableView(
                    "File History Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error))
            } else if state.gitHistoryPath == nil {
                ContentUnavailableView(
                    "Select a Changed File",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Choose a row to inspect its revisions."))
            } else if state.gitFileRevisions.isEmpty {
                ContentUnavailableView("No File History", systemImage: "clock")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.gitFileRevisions) { revision in
                            historyRow(revision)
                            Divider()
                        }
                        if state.gitHistoryHasMore || state.isLoadingGitHistory {
                            Button(state.isLoadingGitHistory ? "Loading…" : "Load More") {
                                state.loadMoreGitFileHistory()
                            }
                            .disabled(state.isLoadingGitHistory)
                            .padding(12)
                        }
                    }
                }
            }
        }
    }

    private var commitGraphInspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Repository History").font(.headline)
                Spacer()
                Text("\(state.gitCommitGraph.count) commits").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            if state.gitCommitGraph.isEmpty {
                ContentUnavailableView("No Commit History", systemImage: "clock")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.gitCommitGraph) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: row.commit.parentIDs.count > 1
                                          ? "arrow.triangle.merge" : "circle.fill")
                                        .font(.caption2).foregroundStyle(.tint)
                                    Text(row.commit.shortObjectID).font(.caption.monospaced())
                                    Text(row.commit.subject.isEmpty ? String(localized: "Untitled commit") : row.commit.subject)
                                        .lineLimit(1)
                                }
                                if !row.decorations.isEmpty {
                                    Text(row.decorations.joined(separator: " · "))
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Text("\(row.commit.authorName) · \(row.commit.authoredDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .contextMenu {
                                if !row.commit.parentIDs.isEmpty {
                                    Button("Open Commit Changeset") {
                                        state.openGitCommitChangeset(row.commit)
                                    }
                                }
                                Button("Compare with HEAD") {
                                    state.useGitComparisonShortcut(left: row.commit.objectID, right: "HEAD")
                                }
                                if let parent = row.commit.parentIDs.first {
                                    Button("Compare with Parent") {
                                        state.useGitComparisonShortcut(left: parent, right: row.commit.objectID)
                                    }
                                }
                            }
                            Divider()
                        }
                        if state.gitCommitGraphHasMore || state.isLoadingGitCommitGraph {
                            Button(state.isLoadingGitCommitGraph ? "Loading…" : "Load More") {
                                state.loadMoreGitCommitGraph()
                            }
                            .disabled(state.isLoadingGitCommitGraph)
                            .padding(12)
                        }
                    }
                }
            }
        }
        .accessibilityLabel("Repository commit history")
    }

    private func historyRow(_ revision: GitFileRevision) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 5) {
                historyMarker("A", selected: historyA == revision.id) { historyA = revision.id }
                historyMarker("B", selected: historyB == revision.id) { historyB = revision.id }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(revision.commit.subject.isEmpty
                     ? String(localized: "Untitled commit")
                     : revision.commit.subject)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Text("\(revision.commit.shortObjectID) · \(revision.commit.authorName)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(revision.commit.authoredDate, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if revision.path != state.gitHistoryPath {
                    Text(revision.path).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let index = state.gitFileRevisions.firstIndex(where: { $0.id == revision.id }),
               state.gitFileRevisions.indices.contains(index + 1) {
                Button {
                    state.compareGitRevisionWithPrevious(revision)
                } label: {
                    Label("Compare with Previous", systemImage: "arrow.left.arrow.right")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Compare this revision with its previous revision")
            }
        }
        .padding(10)
        .contextMenu {
            Button("Use as A") { historyA = revision.id }
            Button("Use as B") { historyB = revision.id }
            Button("Compare with Previous") { state.compareGitRevisionWithPrevious(revision) }
            if !revision.commit.parentIDs.isEmpty {
                Button("Open Commit Changeset") {
                    state.openGitCommitChangeset(revision.commit)
                }
            }
        }
    }

    private func historyMarker(
        _ label: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(label, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(selected ? .accentColor : .secondary)
            .accessibilityLabel("Use revision as \(label)")
    }

    private func revision(_ id: GitFileRevision.ID?) -> GitFileRevision? {
        state.gitFileRevisions.first { $0.id == id }
    }

    private func targetBinding(_ keyPath: ReferenceWritableKeyPath<AppState, String>) -> Binding<String> {
        Binding(
            get: { state[keyPath: keyPath] },
            set: { state[keyPath: keyPath] = $0 })
    }
}

private extension GitChangeStage {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .comparison: "Comparison"
        case .staged: "Staged"
        case .unstaged: "Unstaged"
        case .untracked: "Untracked"
        }
    }

    var symbol: String {
        switch self {
        case .comparison: "arrow.left.arrow.right"
        case .staged: "tray.and.arrow.down.fill"
        case .unstaged: "pencil"
        case .untracked: "questionmark.diamond"
        }
    }
}

private extension GitFileInspection {
    var summary: String {
        let kindName: String
        switch kind {
        case .text: kindName = String(localized: "Text")
        case .binary: kindName = String(localized: "Binary")
        case .lfsPointer: kindName = String(localized: "Git LFS pointer")
        case .submodule: kindName = String(localized: "Git submodule")
        case .largeFile: kindName = String(localized: "Large file")
        case .missing: kindName = String(localized: "Missing")
        }
        guard let byteCount else { return kindName }
        return "\(kindName) · \(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))"
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
