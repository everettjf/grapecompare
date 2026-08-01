import SwiftUI

/// 文件夹比较视图：树形结构、状态着色、筛选、双击打开文件 diff
struct FolderCompareView: View {
    @EnvironmentObject var state: AppState
    @State private var filter: Filter = .all
    @State private var expanded: Set<String> = []

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case differences = "Differences"
        case onlyLeft = "Left Only"
        case onlyRight = "Right Only"
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            statusBar
        }
        .onChange(of: state.treeVersion) {
            initExpansion()
        }
    }

    // MARK: 顶部工具栏

    private var header: some View {
        HStack(spacing: 12) {
            Button { state.goHome() } label: {
                Label("Back", systemImage: "chevron.left")
            }

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
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)

            Button { state.startFolderCompare() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Compare again")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if state.isComparing {
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning and comparing folders…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let root = state.folderRoot {
            let nodes = visibleNodes(of: root)
            if nodes.isEmpty {
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
                    List(nodes) { item in
                        FolderRow(
                            node: item.node,
                            depth: item.depth,
                            isExpanded: expanded.contains(item.node.id),
                            onToggle: { toggle(item.node) },
                            onOpen: { state.openDiff(for: item.node) })
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
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

            Text("Status")
                .frame(width: 86)
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
    }
}

/// 文件夹树中的一行
private struct FolderRow: View {
    let node: FolderNode
    let depth: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            side(node.left, isLeft: true)

            statusIndicator
                .frame(width: 86)
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
            if node.isFolder { onToggle() } else { onOpen() }
        }
        .onTapGesture(count: 1) {
            if node.isFolder { onToggle() }
        }
    }

    private func side(_ meta: FileMeta?, isLeft: Bool) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: CGFloat(depth * 18))

            if meta?.isDirectory == true {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
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

    @ViewBuilder
    private var statusIndicator: some View {
        switch node.status {
        case .same:
            Label("Same", systemImage: "equal")
                .foregroundStyle(.secondary)
        case .different:
            Label("Changed", systemImage: "not.equal")
                .foregroundStyle(.orange)
        case .onlyLeft:
            Image(systemName: "arrow.left")
                .foregroundStyle(.blue)
                .help("Only on the left")
        case .onlyRight:
            Image(systemName: "arrow.right")
                .foregroundStyle(.blue)
                .help("Only on the right")
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

    private var iconColor: Color {
        switch node.status {
        case .same: return node.isFolder ? .blue : .secondary
        case .different: return .orange
        case .onlyLeft, .onlyRight: return .purple
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch node.status {
        case .same:
            EmptyView()
        case .different:
            badge("Different", .orange)
        case .onlyLeft:
            badge("Left only", .purple)
        case .onlyRight:
            badge("Right only", .purple)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.12), in: .capsule)
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

    private func folderSummary(_ left: FileMeta?, _ right: FileMeta?) -> String {
        guard left != nil, right != nil else { return "—" }
        return ""
    }

    private var helpText: String {
        var parts = [node.relativePath]
        let fmt = Date.FormatStyle(date: .abbreviated, time: .shortened)
        if let d = node.left?.modified { parts.append("Left modified: \(d.formatted(fmt))") }
        if let d = node.right?.modified { parts.append("Right modified: \(d.formatted(fmt))") }
        return parts.joined(separator: "\n")
    }
}
