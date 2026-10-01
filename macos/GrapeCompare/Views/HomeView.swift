import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A single automatic input area, with explicit controls available on demand.
struct HomeView: View {
    @Environment(AppState.self) private var state
    @AppStorage("showDemoButton") private var showDemoButton = true
    @State private var showMoreOptions = false

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
                    QuickCompareBar()
                    if !state.shelfItems.isEmpty { InputShelfView() }

                    DisclosureGroup("More Options", isExpanded: $showMoreOptions) {
                        VStack(spacing: 16) {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 16) { primaryCards }
                                VStack(spacing: 16) { primaryCards }
                            }
                            HStack {
                                Button("Paste Left") { state.pasteQuickComparisonSide(left: true) }
                                Button("Paste Right") { state.pasteQuickComparisonSide(left: false) }
                                Spacer()
                            }
                            MergeCard()
                        }
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, 4)

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
        .sheet(isPresented: Binding(
            get: { !state.pendingMergeItems.isEmpty },
            set: { if !$0 { state.cancelPendingMerge() } }
        )) {
            MergeInputSheet(items: state.pendingMergeItems,
                            onConfirm: state.confirmPendingMerge,
                            onCancel: state.cancelPendingMerge)
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
                .frame(width: 56, height: 56)
                .shadow(color: .green.opacity(0.2), radius: 7, y: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("GrapeCompare")
                    .font(.largeTitle.bold())
                Text("Private, sandboxed comparison for files, folders, images, and merges")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
        .padding(.vertical, 14)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.Radius.hero))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.hero)
                .strokeBorder(Theme.panelBorder)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct QuickCompareBar: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Drop Files or Folders")
                .font(.title2.bold())
            Text("Add one item at a time, or drop two to compare. Keep more file versions on the shelf.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Items…", action: chooseItems)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Text("Choose any two versions on the shelf. Three-way merge is available separately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 250)
        .contentShape(Rectangle())
        .background(isTargeted ? Theme.selectedBackground : Theme.subtleBackground,
                    in: .rect(cornerRadius: Theme.Radius.hero))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.hero)
                .strokeBorder(isTargeted ? Color.accentColor : Theme.panelBorder,
                              style: StrokeStyle(lineWidth: 2, dash: [8]))
                .allowsHitTesting(false)
        }
        .dropDestination(for: URL.self) { items, _ in
            state.stageInputs(items)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: AccessibilityPresentationPolicy.standardAnimationDuration),
                   value: isTargeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop Files or Folders")
        .accessibilityHint("Add one item at a time, or drop two to compare. Keep more file versions on the shelf.")
    }

    private func chooseItems() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Choose Items…")
        panel.message = String(localized: "Add files or folders to the shelf.")
        if panel.runModal() == .OK { state.stageInputs(panel.urls) }
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
        }
    }

    private func kindTitle(for kind: ComparisonSessionKind) -> LocalizedStringResource {
        switch kind {
        case .files: "Files"
        case .folders: "Folders"
        case .merge: "Merge"
        }
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
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
                HStack(spacing: 12) {
                    Button("Choose…", action: pick)
                    Button("Remove") { setURL(nil) }
                }
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
            guard items.count == 1, let item = items.first else {
                invalidDropMessage = "Drop one item in each slot, or use the main drop area for multiple items."
                return false
            }
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
        .help(url?.path(percentEncoded: false) ?? String(localized: label))
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
        panel.prompt = String(localized: "Choose…")
        panel.message = String(localized: label)
        panel.directoryURL = url?.deletingLastPathComponent()
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

// MARK: - Confirm the roles of three dropped files

private struct MergeInputSheet: View {
    @State private var orderedItems: [URL]
    let onConfirm: ([URL]) -> Void
    let onCancel: () -> Void

    init(items: [URL], onConfirm: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
        _orderedItems = State(initialValue: items)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Three-Way Merge").font(.title2.bold())
            Text("Choose the base (original) file, then confirm the left and right versions.")
                .foregroundStyle(.secondary)
            ForEach(orderedItems.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    Text(role(index)).font(.headline).frame(width: 70, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(orderedItems[index].lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Text(orderedItems[index].path(percentEncoded: false))
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .help(orderedItems[index].path(percentEncoded: false))
                    Spacer()
                    if index > 0 {
                        Button("Use as Base") { orderedItems.swapAt(0, index) }
                    }
                }
                .padding(12)
                .background(Theme.subtleBackground, in: .rect(cornerRadius: 10))
            }
            Button("Swap Left and Right") { orderedItems.swapAt(1, 2) }
                .disabled(orderedItems.count != 3)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Merge") { onConfirm(orderedItems) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(orderedItems.count != 3)
            }
        }
        .padding(24)
        .frame(width: 570)
    }

    private func role(_ index: Int) -> LocalizedStringResource {
        switch index {
        case 0: "Base"
        case 1: "Left"
        default: "Right"
        }
    }
}

private struct InputShelfView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Input Shelf").font(.headline)
                Spacer()
                Button("Clear Shelf") { state.clearShelf() }
            }
            ForEach(state.shelfItems, id: \.self) { url in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).lineLimit(1)
                        Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }.help(url.path)
                    Spacer()
                    Button { state.shelfLeft = url; if state.shelfRight == url { state.shelfRight = nil } } label: {
                        Label("Left", systemImage: state.shelfLeft == url ? "checkmark.circle.fill" : "circle")
                    }
                    Button { state.shelfRight = url; if state.shelfLeft == url { state.shelfLeft = nil } } label: {
                        Label("Right", systemImage: state.shelfRight == url ? "checkmark.circle.fill" : "circle")
                    }
                    Button { state.removeShelfItem(url) } label: { Image(systemName: "xmark") }
                        .help("Remove from Shelf")
                        .accessibilityLabel("Remove from Shelf")
                }
            }
            HStack {
                Button("Compare Selected Versions") { state.compareShelfPair() }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.shelfLeft == nil || state.shelfRight == nil || state.shelfLeft == state.shelfRight)
                if state.shelfItems.count == 3 {
                    Button("Three-Way Merge…") { state.compareQuickItems(state.shelfItems) }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.Radius.hero))
    }
}
