import Foundation
import Darwin
import Dispatch

nonisolated enum CompareStatus: String, Sendable {
    case same, different, onlyLeft, onlyRight

    fileprivate var bit: UInt8 {
        switch self {
        case .same: return 1 << 0
        case .different: return 1 << 1
        case .onlyLeft: return 1 << 2
        case .onlyRight: return 1 << 3
        }
    }
}

nonisolated struct FileMeta: Sendable, Equatable {
    var size: Int64
    var modified: Date?
    var isDirectory = false
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
    /// 自身及后代包含的状态位，用于大目录筛选时 O(1) 判断，避免反复遍历子树。
    fileprivate var subtreeStatusBits: UInt8

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
        self.subtreeStatusBits = status.bit
    }

    /// 是否包含任何差异（自身或后代）
    var containsDifferences: Bool {
        status != .same
    }

    func subtreeContains(_ status: CompareStatus) -> Bool {
        subtreeStatusBits & status.bit != 0
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
        var kind: EntryKind
        var meta: FileMeta

        var isFolder: Bool { kind == .directory }
    }

    private enum EntryKind: Sendable {
        case directory, regularFile, symbolicLink, other
    }

    private struct FileComparison: Sendable {
        let pathIndex: Int
        let leftPath: String
        let rightPath: String
        let kind: EntryKind
    }

    private final class ComparisonResults: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Bool]

        init(count: Int) {
            values = Array(repeating: false, count: count)
        }

        func merge(_ local: [(Int, Bool)]) {
            lock.lock()
            for (index, value) in local { values[index] = value }
            lock.unlock()
        }

        func snapshot() -> [Bool] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    /// 递归比较两个文件夹，返回树根（relativePath 为 ""）
    static func compare(leftRoot: URL, rightRoot: URL) -> FolderNode {
        let leftItems = scan(root: leftRoot)
        let rightItems = scan(root: rightRoot)
        let allPaths = Set(leftItems.keys).union(rightItems.keys).sorted()

        // 元数据能直接判定大部分状态；仅把同类型、同大小文件送入内容比较。
        var statuses = Array(repeating: CompareStatus.same, count: allPaths.count)
        var comparisons: [FileComparison] = []
        comparisons.reserveCapacity(min(leftItems.count, rightItems.count))
        for (index, path) in allPaths.enumerated() {
            let left = leftItems[path]
            let right = rightItems[path]
            if left == nil {
                statuses[index] = .onlyRight
            } else if right == nil {
                statuses[index] = .onlyLeft
            } else if left!.kind != right!.kind {
                statuses[index] = .different
            } else if left!.isFolder {
                statuses[index] = .same
            } else if left!.meta.size != right!.meta.size {
                statuses[index] = .different
            } else {
                comparisons.append(FileComparison(
                    pathIndex: index,
                    leftPath: leftRoot.appending(path: path).path(percentEncoded: false),
                    rightPath: rightRoot.appending(path: path).path(percentEncoded: false),
                    kind: left!.kind))
            }
        }

        let equalFiles = compareFileContents(comparisons, resultCount: allPaths.count)
        for comparison in comparisons where !equalFiles[comparison.pathIndex] {
            statuses[comparison.pathIndex] = .different
        }

        let root = FolderNode(name: leftRoot.lastPathComponent, relativePath: "",
                              isFolder: true, status: .same,
                              left: FileMeta(size: 0, modified: nil, isDirectory: true),
                              right: FileMeta(size: 0, modified: nil, isDirectory: true),
                              children: [])
        var dirMap: [String: FolderNode] = ["": root]

        for (index, path) in allPaths.enumerated() {
            let l = leftItems[path]
            let r = rightItems[path]
            // 任一侧为目录，就必须建立容器节点，确保“文件 vs 目录”时后代不会丢失。
            let isFolder = (l?.isFolder ?? false) || (r?.isFolder ?? false)

            let node = FolderNode(
                name: (path as NSString).lastPathComponent,
                relativePath: path,
                isFolder: isFolder,
                status: statuses[index],
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
            if node.isFolder {
                if let left = node.left, let right = node.right,
                   left.isDirectory != right.isDirectory {
                    s.different += 1
                }
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
        guard node.isFolder, let children = node.children else {
            node.subtreeStatusBits = node.status.bit
            return node.status
        }
        var descendantsDiffer = false
        var bits = node.status.bit
        for child in children {
            let childStatus = rollup(child)
            bits |= child.subtreeStatusBits
            descendantsDiffer = descendantsDiffer || childStatus != .same
        }
        if node.left != nil, node.right != nil, node.status == .same, descendantsDiffer {
            node.status = .different
        }
        node.subtreeStatusBits = bits | node.status.bit
        return node.status
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
        result.reserveCapacity(4_096)
        var pendingDirectories: [(absolute: String, relative: String)] = [
            (root.standardizedFileURL.path(percentEncoded: false), "")
        ]

        while let directory = pendingDirectories.popLast() {
            let stream = directory.absolute.withCString { opendir($0) }
            guard let stream else { continue }
            while let entry = readdir(stream) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." || name == ".DS_Store" { continue }

                let absolutePath = directory.absolute == "/"
                    ? "/" + name
                    : directory.absolute + "/" + name
                let relativePath = directory.relative.isEmpty
                    ? name
                    : directory.relative + "/" + name
                var info = stat()
                guard absolutePath.withCString({ lstat($0, &info) }) == 0 else { continue }

                let type = info.st_mode & mode_t(S_IFMT)
                let kind: EntryKind
                switch type {
                case mode_t(S_IFDIR): kind = .directory
                case mode_t(S_IFREG): kind = .regularFile
                case mode_t(S_IFLNK): kind = .symbolicLink
                default: kind = .other
                }
                let modified = Date(
                    timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                        + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
                result[relativePath] = ScannedItem(
                    kind: kind,
                    meta: FileMeta(
                        size: Int64(info.st_size),
                        modified: modified,
                        isDirectory: kind == .directory))
                if kind == .directory {
                    pendingDirectories.append((absolutePath, relativePath))
                }
            }
            closedir(stream)
        }
        return result
    }

    /// 有界并行比较：每个 worker 复用两个缓冲区，避免每个文件/分块产生 Data 和 FileHandle 对象。
    private static func compareFileContents(
        _ comparisons: [FileComparison], resultCount: Int
    ) -> [Bool] {
        guard !comparisons.isEmpty else { return Array(repeating: false, count: resultCount) }
        let results = ComparisonResults(count: resultCount)
        let workerCount = min(
            comparisons.count,
            max(1, min(8, ProcessInfo.processInfo.activeProcessorCount)))

        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            let chunkSize = 256 * 1024
            var leftBuffer = [UInt8](repeating: 0, count: chunkSize)
            var rightBuffer = [UInt8](repeating: 0, count: chunkSize)
            var local: [(Int, Bool)] = []
            local.reserveCapacity((comparisons.count + workerCount - 1) / workerCount)
            for comparisonIndex in stride(from: worker, to: comparisons.count, by: workerCount) {
                let comparison = comparisons[comparisonIndex]
                let equal: Bool
                switch comparison.kind {
                case .regularFile:
                    equal = filesEqual(
                        comparison.leftPath, comparison.rightPath,
                        leftBuffer: &leftBuffer, rightBuffer: &rightBuffer)
                case .symbolicLink:
                    equal = linkTargetsEqual(comparison.leftPath, comparison.rightPath)
                case .other:
                    equal = true
                case .directory:
                    equal = false // 目录不会进入内容比较队列
                }
                local.append((comparison.pathIndex, equal))
            }
            results.merge(local)
        }
        return results.snapshot()
    }

    private static func filesEqual(
        _ leftPath: String, _ rightPath: String,
        leftBuffer: inout [UInt8], rightBuffer: inout [UInt8]
    ) -> Bool {
        let leftDescriptor = leftPath.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC) }
        guard leftDescriptor >= 0 else { return false }
        defer { Darwin.close(leftDescriptor) }
        let rightDescriptor = rightPath.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC) }
        guard rightDescriptor >= 0 else { return false }
        defer { Darwin.close(rightDescriptor) }

        var leftInfo = stat()
        var rightInfo = stat()
        guard fstat(leftDescriptor, &leftInfo) == 0,
              fstat(rightDescriptor, &rightInfo) == 0,
              leftInfo.st_size == rightInfo.st_size else { return false }

        var remaining = Int64(leftInfo.st_size)
        while remaining > 0 {
            let count = min(leftBuffer.count, Int(remaining))
            let buffersEqual = leftBuffer.withUnsafeMutableBytes { leftBytes in
                rightBuffer.withUnsafeMutableBytes { rightBytes in
                    guard let leftBase = leftBytes.baseAddress,
                          let rightBase = rightBytes.baseAddress,
                          readExactly(leftDescriptor, into: leftBase, count: count),
                          readExactly(rightDescriptor, into: rightBase, count: count) else {
                        return false
                    }
                    return memcmp(leftBase, rightBase, count) == 0
                }
            }
            if !buffersEqual { return false }
            remaining -= Int64(count)
        }
        return true
    }

    private static func linkTargetsEqual(_ leftPath: String, _ rightPath: String) -> Bool {
        func target(of path: String) -> [UInt8]? {
            var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX))
            let count = buffer.withUnsafeMutableBytes { bytes in
                path.withCString { readlink($0, bytes.baseAddress, bytes.count) }
            }
            guard count >= 0 else { return nil }
            return Array(buffer.prefix(count))
        }
        guard let leftTarget = target(of: leftPath),
              let rightTarget = target(of: rightPath) else { return false }
        return leftTarget == rightTarget
    }

    private static func readExactly(
        _ descriptor: Int32, into buffer: UnsafeMutableRawPointer, count: Int
    ) -> Bool {
        var completed = 0
        while completed < count {
            let result = Darwin.read(descriptor, buffer.advanced(by: completed), count - completed)
            if result > 0 {
                completed += result
            } else if result < 0, errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }
}
