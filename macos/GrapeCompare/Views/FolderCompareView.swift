import SwiftUI
import UniformTypeIdentifiers

/// 文件夹比较视图：树形结构、状态着色、筛选、双击打开文件 diff
struct FolderCompareView: View {
    @Environment(AppState.self) private var state
    @State private var filter: Filter = .all
    @State private var expanded: Set<String> = []
    @State private var visibleItems: [VisibleItem] = []
    @State private var selectedNodeIDs: Set<String> = []
    @State private var isImportingPlan = false
    @State private var isExportingPlan = false
    @State private var exportDocument: FileOperationRecipeDocument?
    @State private var exportRecipe: FileOperationRecipe?
    @State private var planError: String?

    enum Filter: CaseIterable, Identifiable {
        case all, differences, onlyLeft, onlyRight
        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .all: "All"
            case .differences: "Differences"
            case .onlyLeft: "Left Only"
            case .onlyRight: "Right Only"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            statusBar
        }
        .onChange(of: state.treeVersion, initial: true) {
            initExpansion()
        }
        .onChange(of: filter) {
            rebuildVisibleItems()
        }
        .fileImporter(
            isPresented: $isImportingPlan,
            allowedContentTypes: [.grapeComparePlan, .json],
            allowsMultipleSelection: false,
            onCompletion: importPlan)
        .modifier(RecipeExportModifier(
            isPresented: $isExportingPlan,
            legacyDocument: exportDocument,
            recipe: exportRecipe
        ) { result in
            if case .failure(let error) = result { planError = error.localizedDescription }
            exportDocument = nil
            exportRecipe = nil
        })
        .alert("Operation Plan Error", isPresented: Binding(
            get: { planError != nil },
            set: { if !$0 { planError = nil } }
        )) {
            Button("OK") { planError = nil }
        } message: {
            Text(planError ?? "Unknown error")
        }
    }

    // MARK: 顶部工具栏

    private var header: some View {
        HStack(spacing: 12) {
            Button { state.goHome() } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .keyboardShortcut(.cancelAction)

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                Image(systemName: "folder.fill").foregroundStyle(.blue)
                Text(state.leftFolderURL?.lastPathComponent ?? "").bold().lineLimit(1)
            }
            Button { state.swapFolders() } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help("Swap sides and compare again")
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").foregroundStyle(.indigo)
                Text(state.rightFolderURL?.lastPathComponent ?? "").bold().lineLimit(1)
            }

            Spacer()

            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)

            Button { state.startFolderCompare() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Compare again")
            .keyboardShortcut("r", modifiers: [.command])

            operationMenu

            Menu {
                Button("Import Plan…", systemImage: "square.and.arrow.down") {
                    isImportingPlan = true
                }
                Button("Export Current Plan…", systemImage: "square.and.arrow.up") {
                    exportPlan()
                }
                .disabled(state.operations.drafts.isEmpty)
                Divider()
                Button("Operation History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                    state.operations.showHistory()
                }
            } label: {
                Label("Plans", systemImage: "doc.badge.gearshape")
            }
            .help("Import, export, or inspect operation history")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if state.isComparingFolder {
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning and comparing folders…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = state.folderError {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Folder comparison is incomplete")
                    .font(.title3)
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.folderRoot != nil {
            if visibleItems.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: filter == .all ? "checkmark.seal.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(filter == .all ? .green : .secondary)
                    Text(filter == .all ? "Folder is empty" : "No items match the current filter")
                        .font(.title3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    columnHeader
                    Divider()
                    List(visibleItems, selection: $selectedNodeIDs) { item in
                        FolderRow(
                            node: item.node,
                            depth: item.depth,
                            isExpanded: expanded.contains(item.node.id),
                            onToggle: { toggle(item.node) },
                            onOpen: { state.openDiff(for: item.node) },
                            onQueueLeftToRight: canQueueCopy(item.node, direction: .leftToRight)
                                ? { queue(nodes: [item.node], kind: .copy, direction: .leftToRight) }
                                : nil,
                            onQueueRightToLeft: canQueueCopy(item.node, direction: .rightToLeft)
                                ? { queue(nodes: [item.node], kind: .copy, direction: .rightToLeft) }
                                : nil)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onKeyPress(.return) {
                        openSelectedNode()
                    }
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            HStack {
                Text("Left folder")
                Spacer()
                Text("Size")
            }
            .padding(.horizontal, 12)

            Text("Action")
                .frame(width: 118)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.025))

            HStack {
                Text("Right folder")
                Spacer()
                Text("Size")
            }
            .padding(.horizontal, 12)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 34)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
    }

    // MARK: 底部状态栏

    private var statusBar: some View {
        HStack(spacing: 16) {
            if let s = state.folderStats {
                Label("\(s.same) same", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                Label("\(s.different) different", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Label("\(s.onlyLeft) left only", systemImage: "arrow.left.circle")
                    .foregroundStyle(.blue)
                Label("\(s.onlyRight) right only", systemImage: "arrow.right.circle")
                    .foregroundStyle(.blue)
                Text("· Double-click a file to view its diff")
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if !state.operations.drafts.isEmpty {
                Label("\(state.operations.drafts.count) queued", systemImage: "list.bullet.clipboard")
                    .foregroundStyle(.orange)
                Button("Clear") { state.operations.clearDrafts() }
                    .buttonStyle(.plain)
                Button("Review Plan") { state.operations.showReview() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: 展开与筛选

    private struct VisibleItem: Identifiable {
        let node: FolderNode
        let depth: Int
        var id: String { node.id }
    }

    private func visibleNodes(of root: FolderNode) -> [VisibleItem] {
        var result: [VisibleItem] = []
        flatten(root, depth: 0, into: &result)
        return result
    }

    private func flatten(_ folder: FolderNode, depth: Int, into result: inout [VisibleItem]) {
        for child in folder.children ?? [] {
            guard filter == .all || descendantMatches(child) else { continue }
            result.append(VisibleItem(node: child, depth: depth))
            if child.isFolder, expanded.contains(child.id) {
                flatten(child, depth: depth + 1, into: &result)
            }
        }
    }

    private func descendantMatches(_ node: FolderNode) -> Bool {
        switch filter {
        case .all: return true
        case .differences: return node.status != .same
        case .onlyLeft: return node.subtreeContains(.onlyLeft)
        case .onlyRight: return node.subtreeContains(.onlyRight)
        }
    }

    private func toggle(_ node: FolderNode) {
        guard node.isFolder else { return }
        if expanded.contains(node.id) {
            expanded.remove(node.id)
        } else {
            expanded.insert(node.id)
        }
        rebuildVisibleItems()
    }

    /// 默认展开所有包含差异的文件夹
    private func initExpansion() {
        var set: Set<String> = []
        func walk(_ node: FolderNode) {
            guard node.isFolder, let children = node.children else { return }
            for child in children {
                if child.isFolder, child.containsDifferences {
                    set.insert(child.id)
                    walk(child)
                }
            }
        }
        if let root = state.folderRoot {
            walk(root)
        }
        expanded = set
        rebuildVisibleItems()
    }

    private func rebuildVisibleItems() {
        guard let root = state.folderRoot else {
            visibleItems = []
            return
        }
        visibleItems = visibleNodes(of: root)
        selectedNodeIDs.formIntersection(Set(visibleItems.map(\.id)))
    }

    private func openSelectedNode() -> KeyPress.Result {
        guard selectedNodeIDs.count == 1,
              let selectedNodeID = selectedNodeIDs.first,
              let item = visibleItems.first(where: { $0.id == selectedNodeID }) else {
            return .ignored
        }
        if item.node.isFolder {
            toggle(item.node)
        } else {
            state.openDiff(for: item.node)
        }
        return .handled
    }

    // MARK: Operation planning

    private enum Direction {
        case leftToRight
        case rightToLeft
    }

    private var selectedNodes: [FolderNode] {
        visibleItems.filter { selectedNodeIDs.contains($0.id) }.map(\.node)
    }

    private var operationMenu: some View {
        Menu {
            Section("Copy or Replace") {
                Button("Queue Left → Right") {
                    queue(nodes: selectedNodes, kind: .copy, direction: .leftToRight)
                }
                .disabled(!selectedNodes.contains { canQueueCopy($0, direction: .leftToRight) })
                Button("Queue Right → Left") {
                    queue(nodes: selectedNodes, kind: .copy, direction: .rightToLeft)
                }
                .disabled(!selectedNodes.contains { canQueueCopy($0, direction: .rightToLeft) })
            }
            Section("Move — destination must be empty") {
                Button("Move Left → Right") {
                    queue(nodes: selectedNodes, kind: .move, direction: .leftToRight)
                }
                .disabled(!selectedNodes.contains { canQueueMove($0, direction: .leftToRight) })
                Button("Move Right → Left") {
                    queue(nodes: selectedNodes, kind: .move, direction: .rightToLeft)
                }
                .disabled(!selectedNodes.contains { canQueueMove($0, direction: .rightToLeft) })
            }
            Section("Move to Trash") {
                Button("Trash Left Items", role: .destructive) {
                    queue(nodes: selectedNodes, kind: .trash, direction: .leftToRight)
                }
                .disabled(!selectedNodes.contains { $0.left != nil })
                Button("Trash Right Items", role: .destructive) {
                    queue(nodes: selectedNodes, kind: .trash, direction: .rightToLeft)
                }
                .disabled(!selectedNodes.contains { $0.right != nil })
            }
        } label: {
            Label("Actions", systemImage: "arrow.left.arrow.right.square")
        }
        .disabled(selectedNodeIDs.isEmpty || state.isComparingFolder)
        .help("Queue an operation for the selected rows")
    }

    private func canQueueCopy(_ node: FolderNode, direction: Direction) -> Bool {
        guard node.status != .same else { return false }
        switch direction {
        case .leftToRight: return node.left != nil
        case .rightToLeft: return node.right != nil
        }
    }

    private func canQueueMove(_ node: FolderNode, direction: Direction) -> Bool {
        switch direction {
        case .leftToRight: return node.left != nil && node.right == nil
        case .rightToLeft: return node.right != nil && node.left == nil
        }
    }

    private func queue(nodes: [FolderNode], kind requestedKind: FileOperationKind, direction: Direction) {
        guard let leftRoot = state.leftFolderURL, let rightRoot = state.rightFolderURL else { return }
        var drafts: [FileOperationDraft] = []
        for node in nodes {
            appendDrafts(
                for: node,
                requestedKind: requestedKind,
                direction: direction,
                leftRoot: leftRoot,
                rightRoot: rightRoot,
                into: &drafts)
        }
        state.operations.enqueue(drafts)
    }

    private func exportPlan() {
        do {
            exportRecipe = try FileOperationRecipe(drafts: state.operations.drafts)
            exportDocument = exportRecipe.map(FileOperationRecipeDocument.init(recipe:))
            isExportingPlan = true
        } catch {
            planError = error.localizedDescription
        }
    }

    private func importPlan(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first,
                  let leftRoot = state.leftFolderURL,
                  let rightRoot = state.rightFolderURL else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let recipe = try FileOperationRecipe.decode(Data(contentsOf: url))
            try state.operations.importRecipe(recipe, leftRoot: leftRoot, rightRoot: rightRoot)
        } catch {
            planError = error.localizedDescription
        }
    }

    private func appendDrafts(
        for node: FolderNode,
        requestedKind: FileOperationKind,
        direction: Direction,
        leftRoot: URL,
        rightRoot: URL,
        into drafts: inout [FileOperationDraft]
    ) {
        let sourceSide: FileOperationSide = direction == .leftToRight ? .left : .right
        let sourceMeta = direction == .leftToRight ? node.left : node.right
        let destinationMeta = direction == .leftToRight ? node.right : node.left
        let sourceRoot = direction == .leftToRight ? leftRoot : rightRoot
        let destinationRoot = direction == .leftToRight ? rightRoot : leftRoot
        guard sourceMeta != nil else { return }

        if requestedKind == .trash {
            drafts.append(FileOperationDraft(
                kind: .trash,
                relativePath: node.relativePath,
                sourceSide: sourceSide,
                sourceURL: sourceRoot.appending(path: node.relativePath)))
            return
        }

        if requestedKind == .move {
            guard destinationMeta == nil else { return }
            drafts.append(FileOperationDraft(
                kind: .move,
                relativePath: node.relativePath,
                sourceSide: sourceSide,
                sourceURL: sourceRoot.appending(path: node.relativePath),
                destinationURL: destinationRoot.appending(path: node.relativePath)))
            return
        }

        guard node.status != .same else { return }
        if destinationMeta == nil {
            drafts.append(FileOperationDraft(
                kind: .copy,
                relativePath: node.relativePath,
                sourceSide: sourceSide,
                sourceURL: sourceRoot.appending(path: node.relativePath),
                destinationURL: destinationRoot.appending(path: node.relativePath)))
        } else if sourceMeta?.isDirectory == true, destinationMeta?.isDirectory == true {
            for child in node.children ?? [] {
                appendDrafts(
                    for: child,
                    requestedKind: .copy,
                    direction: direction,
                    leftRoot: leftRoot,
                    rightRoot: rightRoot,
                    into: &drafts)
            }
        } else {
            drafts.append(FileOperationDraft(
                kind: .replace,
                relativePath: node.relativePath,
                sourceSide: sourceSide,
                sourceURL: sourceRoot.appending(path: node.relativePath),
                destinationURL: destinationRoot.appending(path: node.relativePath)))
        }
    }
}

/// 文件夹树中的一行
private struct FolderRow: View {
    let node: FolderNode
    let depth: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onQueueLeftToRight: (() -> Void)?
    let onQueueRightToLeft: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            side(node.left, isLeft: true)

            actionIndicator
                .frame(width: 118)
                .frame(maxHeight: .infinity)
                .background(Color.primary.opacity(0.025))

            side(node.right, isLeft: false)
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(rowTint)
        .contentShape(Rectangle())
        .help(helpText)
        .onTapGesture(count: 2) {
            if !node.isFolder { onOpen() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(node.relativePath)
        .accessibilityAction(named: node.isFolder ? "Toggle folder" : "Open file diff") {
            node.isFolder ? onToggle() : onOpen()
        }
    }

    private func side(_ meta: FileMeta?, isLeft: Bool) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: CGFloat(depth * 18))

            if meta?.isDirectory == true {
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse folder" : "Expand folder")
            } else {
                Spacer().frame(width: 12)
            }

            if let meta {
                Image(systemName: meta.isDirectory ? "folder.fill" : fileIcon)
                    .foregroundStyle(sideIconColor(isLeft: isLeft, isDirectory: meta.isDirectory))
                Text(node.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)
            if let meta, !meta.isDirectory {
                Text(sizeString(meta))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionIndicator: some View {
        HStack(spacing: 7) {
            if let onQueueRightToLeft {
                Button(action: onQueueRightToLeft) {
                    Image(systemName: "arrow.left")
                }
                .buttonStyle(.borderless)
                .help("Queue Right → Left")
                .accessibilityLabel("Queue Right to Left")
            }
            statusBadge
            if let onQueueLeftToRight {
                Button(action: onQueueLeftToRight) {
                    Image(systemName: "arrow.right")
                }
                .buttonStyle(.borderless)
                .help("Queue Left → Right")
                .accessibilityLabel("Queue Left to Right")
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch node.status {
        case .same: Image(systemName: "equal").foregroundStyle(.secondary).help("Same")
        case .different: Image(systemName: "not.equal").foregroundStyle(.orange).help("Changed")
        case .onlyLeft: Image(systemName: "arrow.left.circle").foregroundStyle(.blue).help("Only on the left")
        case .onlyRight: Image(systemName: "arrow.right.circle").foregroundStyle(.blue).help("Only on the right")
        }
    }

    private func sideIconColor(isLeft: Bool, isDirectory: Bool) -> Color {
        if isDirectory { return isLeft ? .blue : .indigo }
        switch node.status {
        case .same: return .secondary
        case .different: return .orange
        case .onlyLeft, .onlyRight: return .purple
        }
    }

    private var fileIcon: String {
        switch (node.name as NSString).pathExtension.lowercased() {
        case "swift", "c", "h", "m", "mm", "cpp", "js", "ts", "py", "rb", "go", "rs", "java", "kt":
            return "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "gif", "heic", "svg", "webp":
            return "photo"
        case "md", "txt", "rtf":
            return "doc.text"
        case "json", "xml", "yaml", "yml", "plist":
            return "curlybraces"
        default:
            return "doc"
        }
    }

    private var rowTint: Color {
        switch node.status {
        case .same: return .clear
        case .different: return .orange.opacity(0.07)
        case .onlyLeft, .onlyRight: return .purple.opacity(0.06)
        }
    }

    private func sizeString(_ meta: FileMeta?) -> String {
        guard let meta else { return "—" }
        return ByteCountFormatter.string(fromByteCount: meta.size, countStyle: .file)
    }

    private var helpText: String {
        var parts = [node.relativePath]
        let fmt = Date.FormatStyle(date: .abbreviated, time: .shortened)
        if let d = node.left?.modified { parts.append("Left modified: \(d.formatted(fmt))") }
        if let d = node.right?.modified { parts.append("Right modified: \(d.formatted(fmt))") }
        return parts.joined(separator: "\n")
    }
}
