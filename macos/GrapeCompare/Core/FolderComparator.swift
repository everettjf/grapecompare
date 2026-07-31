import Foundation

nonisolated enum CompareStatus: String, Sendable {
    case same, different, onlyLeft, onlyRight
}

nonisolated struct FileMeta: Sendable, Equatable {
    var size: Int64
    var modified: Date?
}

/// 文件夹比较树中的一个节点（文件或文件夹）
nonisolated final class FolderNode: Identifiable, @unchecked Sendable {
    let name: String
    let relativePath: String
    let isFolder: Bool
    var status: CompareStatus
    var left: FileMeta?
    var right: FileMeta?
    var children: [FolderNode]?

    var id: String { relativePath }

    init(name: String, relativePath: String, isFolder: Bool, status: CompareStatus,
         left: FileMeta? = nil, right: FileMeta? = nil, children: [FolderNode]? = nil) {
        self.name = name
        self.relativePath = relativePath
        self.isFolder = isFolder
        self.status = status
        self.left = left
        self.right = right
        self.children = children
    }

    /// 是否包含任何差异（自身或后代）
    var containsDifferences: Bool {
        if status != .same { return true }
        return children?.contains { $0.containsDifferences } ?? false
    }
}

/// 文件夹比较统计
nonisolated struct FolderCompareStats: Sendable {
    var same = 0
    var different = 0
    var onlyLeft = 0
    var onlyRight = 0
}

nonisolated enum FolderComparator {

    private struct ScannedItem {
        var isFolder: Bool
        var meta: FileMeta
    }

    /// 递归比较两个文件夹，返回树根（relativePath 为 ""）
    static func compare(leftRoot: URL, rightRoot: URL) -> FolderNode {
        let leftItems = scan(root: leftRoot)
        let rightItems = scan(root: rightRoot)
        let allPaths = Set(leftItems.keys).union(rightItems.keys).sorted()

        let root = FolderNode(name: leftRoot.lastPathComponent, relativePath: "",
                              isFolder: true, status: .same, children: [])
        var dirMap: [String: FolderNode] = ["": root]

        for path in allPaths {
            let l = leftItems[path]
            let r = rightItems[path]
            let isFolder = l?.isFolder ?? r?.isFolder ?? false

            let status: CompareStatus
            if l == nil {
                status = .onlyRight
            } else if r == nil {
                status = .onlyLeft
            } else if l!.isFolder != r!.isFolder {
                status = .different
            } else if isFolder {
                status = .same // 文件夹状态稍后由后代汇总
            } else {
                let same = filesEqual(
                    leftRoot.appending(path: path),
                    rightRoot.appending(path: path),
                    size: l!.meta.size)
                status = same ? .same : .different
            }

            let node = FolderNode(
                name: (path as NSString).lastPathComponent,
                relativePath: path,
                isFolder: isFolder,
                status: status,
                left: l?.meta,
                right: r?.meta,
                children: isFolder ? [] : nil)

            let parentPath = (path as NSString).deletingLastPathComponent
            dirMap[parentPath]?.children?.append(node)
            if isFolder { dirMap[path] = node }
        }

        sortChildren(root)
        rollup(root)
        return root
    }

    static func stats(for root: FolderNode) -> FolderCompareStats {
        var s = FolderCompareStats()
        func walk(_ node: FolderNode) {
            guard !node.isFolder else {
                node.children?.forEach(walk)
                return
            }
            switch node.status {
            case .same: s.same += 1
            case .different: s.different += 1
            case .onlyLeft: s.onlyLeft += 1
            case .onlyRight: s.onlyRight += 1
            }
        }
        walk(root)
        return s
    }

    // MARK: - 私有

    /// 文件夹状态汇总：两侧都存在但后代有差异 → different
    @discardableResult
    private static func rollup(_ node: FolderNode) -> CompareStatus {
        guard node.isFolder, let children = node.children else { return node.status }
        var result: CompareStatus = node.status
        for child in children {
            let childStatus = rollup(child)
            if node.left != nil, node.right != nil, childStatus != .same {
                result = .different
            } else if result == .same, childStatus != .same {
                result = childStatus
            }
        }
        node.status = result
        return result
    }

    private static func sortChildren(_ node: FolderNode) {
        node.children?.sort {
            if $0.isFolder != $1.isFolder { return $0.isFolder && !$1.isFolder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        node.children?.forEach(sortChildren)
    }

    private static func scan(root: URL) -> [String: ScannedItem] {
        var result: [String: ScannedItem] = [:]
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]) else { return result }

        let rootComponents = root.standardizedFileURL.pathComponents
        for case let url as URL in enumerator {
            if url.lastPathComponent == ".DS_Store" { continue }
            let values = try? url.resourceValues(forKeys: keys)
            let isFolder = values?.isDirectory ?? false
            let relComponents = url.standardizedFileURL.pathComponents.dropFirst(rootComponents.count)
            let relPath = relComponents.joined(separator: "/")
            guard !relPath.isEmpty else { continue }
            result[relPath] = ScannedItem(
                isFolder: isFolder,
                meta: FileMeta(
                    size: Int64(values?.fileSize ?? 0),
                    modified: values?.contentModificationDate))
        }
        return result
    }

    /// 分块流式比较两个文件内容（调用前已知大小相同）
    private static func filesEqual(_ a: URL, _ b: URL, size: Int64) -> Bool {
        guard let fa = try? FileHandle(forReadingFrom: a),
              let fb = try? FileHandle(forReadingFrom: b) else { return false }
        defer {
            try? fa.close()
            try? fb.close()
        }
        let chunk = 1024 * 1024
        while true {
            let da = try? fa.read(upToCount: chunk)
            let db = try? fb.read(upToCount: chunk)
            if da != db { return false }
            if da == nil || da!.isEmpty { return true }
        }
    }
}
