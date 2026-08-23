import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 首页：选择比较模式并拖入/选择两侧的文件或文件夹
struct HomeView: View {
    @Environment(AppState.self) private var state
    @AppStorage("showDemoButton") private var showDemoButton = true

    var body: some View {
        @Bindable var state = state
        ScrollView {
        VStack(spacing: 36) {
            VStack(spacing: 10) {
                Image("GrapeIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .shadow(color: .green.opacity(0.35), radius: 12, y: 6)
                Text("GrapeCompare")
                    .font(.system(size: 32, weight: .bold))
                Text("Native, fast, and professional file & folder comparison")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 44)

            HStack(spacing: 24) {
                CompareCard(
                    title: "Compare Files",
                    icon: "doc.text.magnifyingglass",
                    description: "Side-by-side diff with line and in-line highlighting",
                    acceptsFolders: false,
                    left: $state.leftFileURL,
                    right: $state.rightFileURL,
                    action: state.startFileCompare)
                CompareCard(
                    title: "Compare Folders",
                    icon: "folder.badge.questionmark",
                    description: "Recursively compare folders to find added, missing, and modified files",
                    acceptsFolders: true,
                    left: $state.leftFolderURL,
                    right: $state.rightFolderURL,
                    action: state.startFolderCompare)
            }
            .padding(.horizontal, 48)

            QuickCompareDropZone()
                .padding(.horizontal, 48)

            if state.resumableSession != nil || !state.recentComparisons.isEmpty {
                RecentComparisonsView()
                    .padding(.horizontal, 48)
            }

            MergeCard()
                .padding(.horizontal, 48)

            GitCard()
                .padding(.horizontal, 48)

            Spacer()
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if showDemoButton {
                Menu {
                    Button("Compare Swift Files", systemImage: "doc.text.magnifyingglass") {
                        state.loadFileDemo()
                    }
                    Button("Compare Swift Project Folders", systemImage: "folder.badge.questionmark") {
                        state.loadFolderDemo()
                    }
                } label: {
                    Label("Load Demo", systemImage: "sparkles")
                }
                .menuStyle(.button)
                .controlSize(.large)
                .padding(20)
            }
        }
        .alert("Unable to Load Demo", isPresented: Binding(
            get: { state.demoError != nil },
            set: { if !$0 { state.demoError = nil } }
        )) {
            Button("OK") { state.demoError = nil }
        } message: {
            Text(state.demoError ?? "Unknown error")
        }
        .alert("Unable to Open Saved Comparison", isPresented: Binding(
            get: { state.sessionError != nil },
            set: { if !$0 { state.sessionError = nil } }
        )) {
            Button("OK") { state.sessionError = nil }
        } message: {
            Text(state.sessionError ?? "Unknown error")
        }
        .alert("Quick Compare Failed", isPresented: Binding(
            get: { state.quickCompareError != nil },
            set: { if !$0 { state.quickCompareError = nil } }
        )) {
            Button("OK") { state.quickCompareError = nil }
        } message: {
            Text(state.quickCompareError ?? "")
        }
    }
}

private struct QuickCompareDropZone: View {
    @Environment(AppState.self) private var state
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Quick Compare").font(.headline)
                Text("Drop exactly two files or folders to compare immediately")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Paste Left") { state.pasteQuickComparisonSide(left: true) }
            Button("Paste Right") { state.pasteQuickComparisonSide(left: false) }
        }
        .padding(18)
        .background(
            isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor),
            in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                              style: StrokeStyle(lineWidth: 1.5, dash: [7]))
        }
        .dropDestination(for: URL.self) { items, _ in
            state.compareQuickItems(items)
            return items.count == 2
        } isTargeted: { isTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick Compare drop zone")
        .accessibilityHint("Drop exactly two files or two folders to compare them immediately")
    }
}

private struct RecentComparisonsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recent Comparisons", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                if state.resumableSession != nil {
                    Button("Resume Last Session") { state.resumeLastSession() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                }
                Button("Clear", role: .destructive) { state.clearRecentComparisons() }
                    .disabled(state.recentComparisons.isEmpty)
            }
            ForEach(state.recentComparisons.prefix(5)) { session in
                Button { state.openRecentComparison(session) } label: {
                    HStack {
                        Image(systemName: icon(for: session.kind))
                            .frame(width: 20)
                        Text(session.displayNames.joined(separator: " ↔ "))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(session.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Reopens the inputs and compares their current contents")
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 16))
    }

    private func icon(for kind: ComparisonSessionKind) -> String {
        switch kind {
        case .files: "doc.text.magnifyingglass"
        case .folders: "folder.badge.questionmark"
        case .merge: "arrow.triangle.branch"
        case .git: "point.3.connected.trianglepath.dotted"
        }
    }
}

private struct GitCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 16) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Compare Git Repository").font(.headline)
                Text("Compare branches, commits, index, and working tree without checkout")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DropSlot(
                label: "Repository",
                acceptsFolders: true,
                url: $state.gitRepositoryURL)
                .frame(maxWidth: 300)
            Button("Open Repository") { state.startGitComparison() }
                .buttonStyle(.borderedProminent)
                .disabled(state.gitRepositoryURL == nil)
            if !state.gitRepositoryLibrary.isEmpty {
                Menu("Recent Repositories") {
                    ForEach(state.gitRepositoryLibrary) { entry in
                        Button {
                            state.openGitRepositoryLibraryEntry(entry)
                        } label: {
                            Label(entry.displayName, systemImage: "externaldrive")
                        }
                        Button("Forget \(entry.displayName)", role: .destructive) {
                            state.removeGitRepositoryLibraryEntry(entry)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

private struct MergeCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Three-Way Merge").font(.headline)
                    Text("Compare base, ours, and theirs; resolve conflicts into editable output")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Merge") { state.startThreeWayMerge() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.baseFileURL == nil || state.oursFileURL == nil || state.theirsFileURL == nil)
            }
            HStack(spacing: 10) {
                DropSlot(label: "Base", acceptsFolders: false, url: $state.baseFileURL)
                DropSlot(label: "Ours", acceptsFolders: false, url: $state.oursFileURL)
                DropSlot(label: "Theirs", acceptsFolders: false, url: $state.theirsFileURL)
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

private struct CompareCard: View {
    let title: LocalizedStringResource
    let icon: String
    let description: LocalizedStringResource
    let acceptsFolders: Bool
    @Binding var left: URL?
    @Binding var right: URL?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title3).bold()
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                DropSlot(label: "Left", acceptsFolders: acceptsFolders, url: $left)
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.tertiary)
                DropSlot(label: "Right", acceptsFolders: acceptsFolders, url: $right)
            }

            Button("Compare", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(left == nil || right == nil)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

/// 拖放/点选槽位
struct DropSlot: View {
    let label: LocalizedStringResource
    let acceptsFolders: Bool
    @Binding var url: URL?
    @State private var isTargeted = false
    @State private var invalidDropMessage: LocalizedStringResource?

    var body: some View {
        VStack(spacing: 6) {
            if let url {
                Image(systemName: acceptsFolders ? "folder.fill" : "doc.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text(url.lastPathComponent)
                    .font(.callout).bold()
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text((url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Remove") { setURL(nil) }
                    .font(.caption)
                    .buttonStyle(.link)
            } else {
                Image(systemName: "arrow.down.doc")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if acceptsFolders {
                    Text("Drop a folder here")
                        .font(.caption)
                } else {
                    Text("Drop a file here")
                        .font(.caption)
                }
                Text("or choose below")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Choose…", action: pick)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 116)
        .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { item, _ in
                DispatchQueue.main.async {
                    guard let item else { return }
                    guard item.hasDirectoryPath == self.acceptsFolders else {
                        if self.acceptsFolders {
                            self.invalidDropMessage = "Please drop a folder."
                        } else {
                            self.invalidDropMessage = "Please drop a file."
                        }
                        return
                    }
                    self.setURL(item)
                }
            }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
        .alert("Unsupported Item", isPresented: Binding(
            get: { invalidDropMessage != nil },
            set: { if !$0 { invalidDropMessage = nil } }
        )) {
            Button("OK") { invalidDropMessage = nil }
        } message: {
            if let invalidDropMessage {
                Text(invalidDropMessage)
            }
        }
    }

    /// 设置槽位 URL 并管理沙盒安全作用域访问。
    /// App Sandbox 下，拖放得来的 URL 是 security-scoped 的，必须先
    /// startAccessing 才能读取其内容（文件夹访问权覆盖其所有子项）。
    /// NSOpenPanel 返回的 URL 已获授权，startAccessing 会返回 false，无害。
    private func setURL(_ new: URL?) {
        guard new != url else { return }
        url?.stopAccessingSecurityScopedResource()
        if let new { _ = new.startAccessingSecurityScopedResource() }
        url = new
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !acceptsFolders
        panel.canChooseDirectories = acceptsFolders
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            setURL(panel.url)
        }
    }
}
