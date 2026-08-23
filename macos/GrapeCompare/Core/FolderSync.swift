import Darwin
import Foundation

nonisolated enum FolderSyncMode: String, CaseIterable, Codable, Sendable {
    case mirror
    case update
    case custom
}

nonisolated struct FolderIgnoreProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var patterns: [String]

    init(id: UUID = UUID(), name: String, patterns: [String]) {
        self.id = id
        self.name = name
        self.patterns = Array(patterns.prefix(1_000))
    }

    func ignores(_ relativePath: String) -> Bool {
        let path = relativePath.precomposedStringWithCanonicalMapping
        var ignored = false
        for raw in patterns {
            var pattern = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty, !pattern.hasPrefix("#") else { continue }
            let negated = pattern.hasPrefix("!")
            if negated { pattern.removeFirst() }
            let matched = fnmatch(pattern, path, FNM_PATHNAME) == 0 ||
                fnmatch(pattern, (path as NSString).lastPathComponent, 0) == 0 ||
                (pattern.hasSuffix("/") && path.hasPrefix(String(pattern.dropLast()) + "/"))
            if matched { ignored = !negated }
        }
        return ignored
    }

    static let developer = FolderIgnoreProfile(name: "Developer", patterns: [
        ".git/", ".build/", "DerivedData/", "*.xcuserstate", "xcuserdata/", ".DS_Store"
    ])
}

nonisolated struct FileMetadataSnapshot: Equatable, Sendable, Codable {
    let permissions: UInt16
    let ownerID: UInt32
    let groupID: UInt32
    let extendedAttributes: [String: UInt64]
}

nonisolated enum FileMetadataComparator {
    static func snapshot(at url: URL) throws -> FileMetadataSnapshot {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        let names = try extendedAttributeNames(at: url)
        var attributes: [String: UInt64] = [:]
        for name in names { attributes[name] = try extendedAttributeHash(name, at: url) }
        return FileMetadataSnapshot(
            permissions: UInt16(info.st_mode & 0o7777),
            ownerID: info.st_uid,
            groupID: info.st_gid,
            extendedAttributes: attributes)
    }

    private static func extendedAttributeNames(at url: URL) throws -> [String] {
        let length = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard length >= 0 else { throw CocoaError(.fileReadUnknown) }
        guard length > 0 else { return [] }
        var bytes = [CChar](repeating: 0, count: length)
        guard listxattr(url.path, &bytes, bytes.count, XATTR_NOFOLLOW) == length else {
            throw CocoaError(.fileReadUnknown)
        }
        return bytes.split(separator: 0).map { String(decoding: $0.map(UInt8.init), as: UTF8.self) }.sorted()
    }

    private static func extendedAttributeHash(_ name: String, at url: URL) throws -> UInt64 {
        let length = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard length >= 0 else { throw CocoaError(.fileReadUnknown) }
        var bytes = [UInt8](repeating: 0, count: length)
        guard getxattr(url.path, name, &bytes, bytes.count, 0, XATTR_NOFOLLOW) == length else {
            throw CocoaError(.fileReadUnknown)
        }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return hash
    }
}

nonisolated enum FolderSyncPlanner {
    static func drafts(
        root: FolderNode,
        leftRoot: URL,
        rightRoot: URL,
        mode: FolderSyncMode,
        ignoreProfile: FolderIgnoreProfile? = nil
    ) -> [FileOperationDraft] {
        guard mode != .custom else { return [] }
        var result: [FileOperationDraft] = []
        func walk(_ node: FolderNode) {
            guard !node.relativePath.isEmpty else { node.children?.forEach(walk); return }
            guard ignoreProfile?.ignores(node.relativePath) != true else { return }
            let leftURL = leftRoot.appending(path: node.relativePath)
            let rightURL = rightRoot.appending(path: node.relativePath)
            switch node.status {
            case .same: return
            case .onlyLeft:
                result.append(FileOperationDraft(kind: .copy, relativePath: node.relativePath,
                                                  sourceSide: .left, sourceURL: leftURL,
                                                  destinationURL: rightURL))
            case .onlyRight:
                if mode == .mirror {
                    result.append(FileOperationDraft(kind: .trash, relativePath: node.relativePath,
                                                      sourceSide: .right, sourceURL: rightURL))
                }
            case .different:
                if node.left?.isDirectory == true, node.right?.isDirectory == true {
                    node.children?.forEach(walk)
                } else if mode == .mirror ||
                            (node.left?.modified ?? .distantPast) >= (node.right?.modified ?? .distantPast) {
                    result.append(FileOperationDraft(kind: .replace, relativePath: node.relativePath,
                                                      sourceSide: .left, sourceURL: leftURL,
                                                      destinationURL: rightURL))
                }
            }
        }
        walk(root)
        return result.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }
}

nonisolated struct FileOperationReportRow: Codable, Equatable, Sendable {
    let kind: FileOperationKind
    let relativePath: String
    let itemCount: Int
    let byteCount: Int64
}

nonisolated struct FileOperationReport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let createdAt: Date
    let dryRun: Bool
    let rows: [FileOperationReportRow]
    let itemCount: Int
    let byteCount: Int64
    let completedOperations: Int?
    let failures: [FileOperationReportFailure]
    let wasCancelled: Bool

    init(plan: FileOperationPlan, dryRun: Bool, createdAt: Date = Date()) {
        schemaVersion = 1
        self.createdAt = createdAt
        self.dryRun = dryRun
        rows = plan.operations.map {
            FileOperationReportRow(kind: $0.kind, relativePath: $0.relativePath,
                                   itemCount: $0.itemCount, byteCount: $0.byteCount)
        }
        itemCount = plan.itemCount
        byteCount = plan.byteCount
        completedOperations = nil
        failures = []
        wasCancelled = false
    }

    init(plan: FileOperationPlan, result: FileOperationResult, createdAt: Date = Date()) {
        schemaVersion = 1
        self.createdAt = createdAt
        dryRun = false
        rows = plan.operations.map {
            FileOperationReportRow(kind: $0.kind, relativePath: $0.relativePath,
                                   itemCount: $0.itemCount, byteCount: $0.byteCount)
        }
        itemCount = plan.itemCount
        byteCount = plan.byteCount
        completedOperations = result.completedOperations
        failures = result.failures.map {
            FileOperationReportFailure(relativePath: $0.relativePath, message: $0.message)
        }
        wasCancelled = result.wasCancelled
    }

    func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

nonisolated struct FileOperationReportFailure: Codable, Equatable, Sendable {
    let relativePath: String
    let message: String
}
