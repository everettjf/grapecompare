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

nonisolated struct FolderScanError: LocalizedError, Sendable {
    let operation: String
    let path: String
    let code: Int32

    var errorDescription: String? {
        "Unable to \(operation) “\(path)”: \(String(cString: strerror(code)))"
    }
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

    private enum FileContentResult: Sendable {
        case equal, different, failed(FolderScanError)
    }

    private final class ComparisonResults: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [FileContentResult]

        init(count: Int) {
            values = Array(repeating: .different, count: count)
        }

        func merge(_ local: [(Int, FileContentResult)]) {
            lock.lock()
            for (index, value) in local { values[index] = value }
            lock.unlock()
        }

        func snapshot() -> [FileContentResult] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    private final class ScanResults: @unchecked Sendable {
        private let lock = NSLock()
        private var left: Result<[String: ScannedItem], Error>?
        private var right: Result<[String: ScannedItem], Error>?

        func store(_ result: Result<[String: ScannedItem], Error>, onLeft: Bool) {
            lock.lock()
            if onLeft { left = result } else { right = result }
            lock.unlock()
        }

        func snapshots() -> (
            Result<[String: ScannedItem], Error>,
            Result<[String: ScannedItem], Error>
        ) {
            lock.lock()
            defer { lock.unlock() }
            return (left!, right!)
        }
    }

    /// 递归比较两个文件夹，返回树根（relativePath 为 ""）
    static func compare(leftRoot: URL, rightRoot: URL) -> FolderNode {
        try! compareCancellable(leftRoot: leftRoot, rightRoot: rightRoot)
    }

    static func compareCancellable(
        leftRoot: URL, rightRoot: URL,
        compareMetadata: Bool = false,
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> FolderNode {
        // Directory metadata walks are independent and usually I/O-bound. Scan
        // both roots together so very large comparisons do not pay two full,
        // serial tree walks before content comparison can begin.
        let scans = ScanResults()
        DispatchQueue.concurrentPerform(iterations: 2) { side in
            let root = side == 0 ? leftRoot : rightRoot
            scans.store(Result { try scan(root: root, shouldCancel: shouldCancel) }, onLeft: side == 0)
        }
        let (leftResult, rightResult) = scans.snapshots()
        let leftItems = try leftResult.get()
        let rightItems = try rightResult.get()
        let allPaths = Set(leftItems.keys).union(rightItems.keys).sorted()

        // 元数据能直接判定大部分状态；仅把同类型、同大小文件送入内容比较。
        var statuses = Array(repeating: CompareStatus.same, count: allPaths.count)
        var comparisons: [FileComparison] = []
        comparisons.reserveCapacity(min(leftItems.count, rightItems.count))
        for (index, path) in allPaths.enumerated() {
            if index & 0x3FFF == 0, shouldCancel() { throw CancellationError() }
            let left = leftItems[path]
            let right = rightItems[path]
            if left == nil {
                statuses[index] = .onlyRight
            } else if right == nil {
                statuses[index] = .onlyLeft
            } else if left!.kind != right!.kind {
                statuses[index] = .different
            } else if compareMetadata,
                      try FileMetadataComparator.snapshot(at: leftRoot.appending(path: path)) !=
                        FileMetadataComparator.snapshot(at: rightRoot.appending(path: path)) {
                statuses[index] = .different
            } else if left!.isFolder {
                statuses[index] = .same
            } else if left!.kind == .other {
                // Sockets, devices and other special entries cannot be compared
                // safely as ordinary files. Never claim they are equal.
                statuses[index] = .different
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

        let contentResults = try compareFileContents(
            comparisons,
            resultCount: allPaths.count,
            shouldCancel: shouldCancel)
        for comparison in comparisons {
            switch contentResults[comparison.pathIndex] {
            case .equal: break
            case .different: statuses[comparison.pathIndex] = .different
            case .failed(let error): throw error
            }
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

    private static func scan(
        root: URL,
        shouldCancel: @Sendable () -> Bool
    ) throws -> [String: ScannedItem] {
        var result: [String: ScannedItem] = [:]
        result.reserveCapacity(4_096)
        var pendingDirectories: [(absolute: String, relative: String)] = [
            (root.standardizedFileURL.path(percentEncoded: false), "")
        ]

        while let directory = pendingDirectories.popLast() {
            if shouldCancel() { throw CancellationError() }
            let stream = directory.absolute.withCString { opendir($0) }
            guard let stream else {
                throw FolderScanError(
                    operation: "open directory",
                    path: directory.absolute,
                    code: errno)
            }
            defer { closedir(stream) }
            while true {
                errno = 0
                guard let entry = readdir(stream) else {
                    if errno != 0 {
                        throw FolderScanError(
                            operation: "read directory",
                            path: directory.absolute,
                            code: errno)
                    }
                    break
                }
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
                guard absolutePath.withCString({ lstat($0, &info) }) == 0 else {
                    throw FolderScanError(
                        operation: "read metadata for",
                        path: absolutePath,
                        code: errno)
                }

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
        }
        return result
    }

    /// 有界并行比较：每个 worker 复用两个缓冲区，避免每个文件/分块产生 Data 和 FileHandle 对象。
    private static func compareFileContents(
        _ comparisons: [FileComparison], resultCount: Int,
        shouldCancel: @Sendable () -> Bool
    ) throws -> [FileContentResult] {
        guard !comparisons.isEmpty else {
            return Array(repeating: .different, count: resultCount)
        }
        let results = ComparisonResults(count: resultCount)
        let workerCount = min(
            comparisons.count,
            max(1, min(8, ProcessInfo.processInfo.activeProcessorCount)))

        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            let chunkSize = 256 * 1024
            var leftBuffer = [UInt8](repeating: 0, count: chunkSize)
            var rightBuffer = [UInt8](repeating: 0, count: chunkSize)
            var local: [(Int, FileContentResult)] = []
            local.reserveCapacity((comparisons.count + workerCount - 1) / workerCount)
            for comparisonIndex in stride(from: worker, to: comparisons.count, by: workerCount) {
                if shouldCancel() { break }
                let comparison = comparisons[comparisonIndex]
                let result: FileContentResult
                switch comparison.kind {
                case .regularFile:
                    result = filesEqual(
                        comparison.leftPath, comparison.rightPath,
                        leftBuffer: &leftBuffer, rightBuffer: &rightBuffer)
                case .symbolicLink:
                    result = linkTargetsEqual(comparison.leftPath, comparison.rightPath)
                case .other:
                    result = .different
                case .directory:
                    result = .different // 目录不会进入内容比较队列
                }
                local.append((comparison.pathIndex, result))
            }
            results.merge(local)
        }
        if shouldCancel() { throw CancellationError() }
        return results.snapshot()
    }

    private static func filesEqual(
        _ leftPath: String, _ rightPath: String,
        leftBuffer: inout [UInt8], rightBuffer: inout [UInt8]
    ) -> FileContentResult {
        let leftDescriptor = leftPath.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC) }
        guard leftDescriptor >= 0 else {
            return .failed(FolderScanError(
                operation: "open file", path: leftPath, code: errno))
        }
        defer { Darwin.close(leftDescriptor) }
        let rightDescriptor = rightPath.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC) }
        guard rightDescriptor >= 0 else {
            return .failed(FolderScanError(
                operation: "open file", path: rightPath, code: errno))
        }
        defer { Darwin.close(rightDescriptor) }

        var leftInfo = stat()
        var rightInfo = stat()
        guard fstat(leftDescriptor, &leftInfo) == 0 else {
            return .failed(FolderScanError(
                operation: "read file metadata for", path: leftPath, code: errno))
        }
        guard fstat(rightDescriptor, &rightInfo) == 0 else {
            return .failed(FolderScanError(
                operation: "read file metadata for", path: rightPath, code: errno))
        }
        guard leftInfo.st_size == rightInfo.st_size else { return .different }

        var remaining = Int64(leftInfo.st_size)
        while remaining > 0 {
            let count = min(leftBuffer.count, Int(remaining))
            let chunkResult = leftBuffer.withUnsafeMutableBytes { leftBytes in
                rightBuffer.withUnsafeMutableBytes { rightBytes in
                    guard let leftBase = leftBytes.baseAddress,
                          let rightBase = rightBytes.baseAddress else {
                        return FileContentResult.different
                    }
                    if let code = readExactly(leftDescriptor, into: leftBase, count: count) {
                        return .failed(FolderScanError(
                            operation: "read file", path: leftPath, code: code))
                    }
                    if let code = readExactly(rightDescriptor, into: rightBase, count: count) {
                        return .failed(FolderScanError(
                            operation: "read file", path: rightPath, code: code))
                    }
                    return memcmp(leftBase, rightBase, count) == 0 ? .equal : .different
                }
            }
            if case .equal = chunkResult {
                // Continue with the next chunk.
            } else {
                return chunkResult
            }
            remaining -= Int64(count)
        }
        return .equal
    }

    private static func linkTargetsEqual(
        _ leftPath: String, _ rightPath: String
    ) -> FileContentResult {
        func target(of path: String) -> Result<[UInt8], FolderScanError> {
            var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX))
            let count = buffer.withUnsafeMutableBytes { bytes in
                path.withCString { readlink($0, bytes.baseAddress, bytes.count) }
            }
            guard count >= 0 else {
                return .failure(FolderScanError(
                    operation: "read symbolic link", path: path, code: errno))
            }
            return .success(Array(buffer.prefix(count)))
        }
        switch (target(of: leftPath), target(of: rightPath)) {
        case (.success(let left), .success(let right)):
            return left == right ? .equal : .different
        case (.failure(let error), _), (_, .failure(let error)):
            return .failed(error)
        }
    }

    private static func readExactly(
        _ descriptor: Int32, into buffer: UnsafeMutableRawPointer, count: Int
    ) -> Int32? {
        var completed = 0
        while completed < count {
            let result = Darwin.read(descriptor, buffer.advanced(by: completed), count - completed)
            if result > 0 {
                completed += result
            } else if result < 0, errno == EINTR {
                continue
            } else {
                return result == 0 ? EIO : errno
            }
        }
        return nil
    }
}
