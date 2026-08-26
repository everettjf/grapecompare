import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 首页：选择比较模式并拖入/选择两侧的文件或文件夹
struct HomeView: View {
    @Environment(AppState.self) private var state
    @AppStorage("showDemoButton") private var showDemoButton = true

    var body: some View {
        @Bindable var state = state
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.055), Color.clear, Color.purple.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    HomeHero(showDemoButton: showDemoButton)
                    DashboardSectionTitle(
                        title: "Start a Comparison",
                        subtitle: "Choose a focused workflow or drop two items for a quick comparison")

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            primaryCards
                        }
                        VStack(spacing: 16) {
                            primaryCardsCompact
                        }
                    }

                    DashboardSectionTitle(
                        title: "More Workflows",
                        subtitle: "Quick compare, resolve a merge, or inspect a Git repository")
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            QuickCompareDropZone().frame(maxWidth: .infinity)
                            MergeCard().frame(maxWidth: .infinity)
                            GitCard().frame(maxWidth: .infinity)
                        }
                        VStack(spacing: 16) {
                            QuickCompareDropZone()
                            MergeCard()
                            GitCard()
                        }
                    }

                    if state.resumableSession != nil || !state.recentComparisons.isEmpty {
                        RecentComparisonsView()
                    }
                }
                .frame(maxWidth: 1160)
                .padding(.horizontal, 26)
                .padding(.top, 22)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @ViewBuilder
    private var primaryCards: some View {
        CompareCard(
            title: "Files",
            icon: "doc.text.magnifyingglass",
            description: "Text, structured data, images, and developer formats",
            acceptsFolders: false,
            left: urlBinding(\.leftFileURL),
            right: urlBinding(\.rightFileURL),
            action: state.startFileCompare)
        CompareCard(
            title: "Folders",
            icon: "folder.badge.questionmark",
            description: "Recursive comparison with safe, reviewable operations",
            acceptsFolders: true,
            left: urlBinding(\.leftFolderURL),
            right: urlBinding(\.rightFolderURL),
            action: state.startFolderCompare)
    }

    @ViewBuilder
    private var primaryCardsCompact: some View {
        primaryCards
    }

    private func urlBinding(_ keyPath: ReferenceWritableKeyPath<AppState, URL?>) -> Binding<URL?> {
        Binding(
            get: { state[keyPath: keyPath] },
            set: { state[keyPath: keyPath] = $0 })
    }
}

private struct HomeHero: View {
    @Environment(AppState.self) private var state
    let showDemoButton: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image("GrapeIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 68, height: 68)
                .shadow(color: .green.opacity(0.28), radius: 10, y: 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("GrapeCompare")
                    .font(.largeTitle.bold())
                Text("Native comparison for files, folders, images, merges, and Git")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 7) {
                    HeroBadge(title: "Local", icon: "lock.shield")
                    HeroBadge(title: "Fast", icon: "bolt")
                    HeroBadge(title: "Open Source", icon: "chevron.left.forwardslash.chevron.right")
                }
            }

            Spacer(minLength: 18)

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
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.primary.opacity(0.07))
        }
        .accessibilityElement(children: .contain)
    }
}

private struct HeroBadge: View {
    let title: LocalizedStringResource
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.055), in: .capsule)
    }
}

private struct DashboardSectionTitle: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct QuickCompareDropZone: View {
    @Environment(AppState.self) private var state
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CompactCardHeader(
                title: "Quick Compare",
                subtitle: "Drop exactly two files or folders to compare immediately",
                icon: "arrow.down.doc.fill")
            HStack {
                Label("Drop two items anywhere in this card", systemImage: "plus.square.on.square")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Paste Left") { state.pasteQuickComparisonSide(left: true) }
                Button("Paste Right") { state.pasteQuickComparisonSide(left: false) }
            }
        }
        .padding(14)
        .background(
            isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor),
            in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                              style: StrokeStyle(lineWidth: 1.5, dash: [7]))
        }
        .shadow(color: .black.opacity(0.055), radius: 9, y: 3)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Continue Comparing", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Text("Reopen inputs and compare their current contents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if state.resumableSession != nil {
                    Button("Resume Last") { state.resumeLastSession() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                }
                Menu {
                    Button("Clear Recent Comparisons", role: .destructive) {
                        state.clearRecentComparisons()
                    }
                    .disabled(state.recentComparisons.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Recent comparison actions")
            }
            if !state.recentComparisons.isEmpty {
                HStack(spacing: 10) {
                    ForEach(state.recentComparisons.prefix(3)) { session in
                        Button { state.openRecentComparison(session) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: icon(for: session.kind))
                                    Text(kindTitle(for: session.kind))
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Text(session.createdAt, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(session.displayNames.joined(separator: " ↔ "))
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 10))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Reopens the inputs and compares their current contents")
                    }
                }
            }
        }
        .padding(16)
        .dashboardCard()
    }

    private func icon(for kind: ComparisonSessionKind) -> String {
        switch kind {
        case .files: "doc.text.magnifyingglass"
        case .folders: "folder.badge.questionmark"
        case .merge: "arrow.triangle.branch"
        case .git: "point.3.connected.trianglepath.dotted"
        }
    }

    private func kindTitle(for kind: ComparisonSessionKind) -> LocalizedStringResource {
        switch kind {
        case .files: "Files"
        case .folders: "Folders"
        case .merge: "Merge"
        case .git: "Git"
        }
    }
}

private struct GitCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 12) {
            CompactCardHeader(
                title: "Git Repository",
                subtitle: "Branches, commits, index, worktree, and history",
                icon: "arrow.triangle.branch")
            DropSlot(
                label: "Repository",
                acceptsFolders: true,
                url: $state.gitRepositoryURL,
                compact: true)
            HStack {
                Button("Open Repository") { state.startGitComparison() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.gitRepositoryURL == nil)
                if !state.gitRepositoryLibrary.isEmpty {
                    Menu("Recent") {
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
        }
        .padding(14)
        .dashboardCard()
    }
}

private struct MergeCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                CompactCardHeader(
                    title: "Three-Way Merge",
                    subtitle: "Resolve text and image conflicts",
                    icon: "arrow.triangle.branch")
                Spacer()
                Button("Merge") { state.startThreeWayMerge() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.baseFileURL == nil || state.oursFileURL == nil || state.theirsFileURL == nil)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    mergeSlots
                }
                VStack(spacing: 8) {
                    mergeSlots
                }
            }
        }
        .padding(14)
        .dashboardCard()
    }

    @ViewBuilder
    private var mergeSlots: some View {
        DropSlot(label: "Base", acceptsFolders: false, url: urlBinding(\.baseFileURL), compact: true)
        DropSlot(label: "Ours", acceptsFolders: false, url: urlBinding(\.oursFileURL), compact: true)
        DropSlot(label: "Theirs", acceptsFolders: false, url: urlBinding(\.theirsFileURL), compact: true)
    }

    private func urlBinding(_ keyPath: ReferenceWritableKeyPath<AppState, URL?>) -> Binding<URL?> {
        Binding(
            get: { state[keyPath: keyPath] },
            set: { state[keyPath: keyPath] = $0 })
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CompactCardHeader(title: title, subtitle: description, icon: icon)
                Spacer(minLength: 12)
                Button("Compare", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(left == nil || right == nil)
            }

            HStack(spacing: 10) {
                DropSlot(label: "Left", acceptsFolders: acceptsFolders, url: $left)
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.tertiary)
                DropSlot(label: "Right", acceptsFolders: acceptsFolders, url: $right)
            }

        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .dashboardCard()
    }
}

private struct CompactCardHeader: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .panelSurface(elevated: true)
    }
}

private extension View {
    func dashboardCard() -> some View { modifier(DashboardCardModifier()) }
}

/// 拖放/点选槽位
struct DropSlot: View {
    let label: LocalizedStringResource
    let acceptsFolders: Bool
    @Binding var url: URL?
    var compact = false
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
                if !compact {
                    Text("or choose below")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("Choose…", action: pick)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: compact ? 72 : 116)
        .contentShape(Rectangle())
        .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .allowsHitTesting(false)
        }
        .dropDestination(for: URL.self) { items, _ in
            guard items.count == 1, let item = items.first else { return false }
            guard ComparisonInputInspector.accepts(item, folders: acceptsFolders) else {
                invalidDropMessage = acceptsFolders
                    ? "Please drop a folder."
                    : "Please drop a file."
                return false
            }
            setURL(item.standardizedFileURL)
            return true
        } isTargeted: { isTargeted = $0 }
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
            guard let selectedURL = panel.url,
                  ComparisonInputInspector.accepts(selectedURL, folders: acceptsFolders) else {
                invalidDropMessage = acceptsFolders
                    ? "Please choose a folder."
                    : "Please choose a file."
                return
            }
            setURL(selectedURL.standardizedFileURL)
        }
    }
}
