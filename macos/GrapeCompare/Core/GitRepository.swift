import Darwin
import Foundation

nonisolated enum GitComparisonTarget: Equatable, Sendable {
    case revision(String)
    case index
    case workingTree

    var displayName: String {
        switch self {
        case .revision(let name): name
        case .index: "INDEX"
        case .workingTree: "WORKTREE"
        }
    }

    static func parse(_ value: String) -> GitComparisonTarget {
        switch value.uppercased() {
        case "INDEX": .index
        case "WORKTREE", "WORKING TREE": .workingTree
        default: .revision(value)
        }
    }
}

nonisolated struct GitReference: Identifiable, Equatable, Sendable {
    let name: String
    let objectID: String
    var id: String { name }
}

nonisolated struct GitCommit: Identifiable, Equatable, Sendable {
    let objectID: String
    let parentIDs: [String]
    let authorName: String
    let authorEmail: String
    let authoredDate: Date
    let subject: String

    var id: String { objectID }
    var shortObjectID: String { String(objectID.prefix(8)) }
}

nonisolated struct GitFileRevision: Identifiable, Equatable, Sendable {
    let commit: GitCommit
    let path: String

    var id: String { "\(commit.objectID)\u{0}\(path)" }
}

nonisolated enum GitFileKind: String, Equatable, Sendable {
    case text
    case binary
    case lfsPointer
    case submodule
    case largeFile
    case missing
}

nonisolated struct GitFileInspection: Equatable, Sendable {
    let kind: GitFileKind
    let byteCount: Int64?
}

nonisolated enum GitChangeKind: String, CaseIterable, Identifiable, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case typeChanged
    case unmerged
    case untracked
    case unknown

    var id: Self { self }
}

nonisolated enum GitChangeStage: String, CaseIterable, Identifiable, Sendable {
    case comparison
    case staged
    case unstaged
    case untracked

    var id: Self { self }
}

nonisolated struct GitChange: Identifiable, Equatable, Sendable {
    let kind: GitChangeKind
    let path: String
    let oldPath: String?
    let stage: GitChangeStage

    init(
        kind: GitChangeKind,
        path: String,
        oldPath: String?,
        stage: GitChangeStage = .comparison
    ) {
        self.kind = kind
        self.path = path
        self.oldPath = oldPath
        self.stage = stage
    }

    var id: String { "\(stage.rawValue)\u{0}\(oldPath ?? "")\u{0}\(path)" }
}

nonisolated struct GitCommandPolicy: @unchecked Sendable {
    var timeout: TimeInterval
    var maximumOutputBytes: Int64
    var isCancelled: @Sendable () -> Bool

    init(
        timeout: TimeInterval = 30,
        maximumOutputBytes: Int64 = 64 * 1_024 * 1_024,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) {
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
        self.isCancelled = isCancelled
    }

    static let standard = GitCommandPolicy(
        timeout: 30,
        maximumOutputBytes: 64 * 1_024 * 1_024,
        isCancelled: { false })
}

nonisolated enum GitRepositoryError: Error, Equatable, LocalizedError {
    case commandFailed(arguments: [String], message: String)
    case malformedOutput
    case unsupportedTargetPair
    case unsafePath
    case timedOut
    case cancelled
    case outputTooLarge(limit: Int64)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let arguments, let message):
            "git \(arguments.joined(separator: " ")) failed: \(message)"
        case .malformedOutput: "Git returned malformed output."
        case .unsupportedTargetPair: "That Git comparison target pair is not supported."
        case .unsafePath: "Git returned a path outside the selected repository."
        case .timedOut: "Git did not finish before the safety timeout."
        case .cancelled: "Git comparison was cancelled."
        case .outputTooLarge(let limit):
            "Git output exceeded the \(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)) safety limit."
        }
    }
}

nonisolated enum GitRepositoryComparator {
    static func repositoryRoot(at url: URL, policy: GitCommandPolicy = .standard) throws -> URL {
        let result = try run(["rev-parse", "--show-toplevel"], in: url, policy: policy)
        guard let path = String(data: result, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { throw GitRepositoryError.malformedOutput }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    static func references(
        in repository: URL,
        policy: GitCommandPolicy = .standard
    ) throws -> [GitReference] {
        let data = try run([
            "for-each-ref", "--format=%(refname:short)%09%(objectname)",
            "refs/heads", "refs/tags"
        ], in: repository, policy: policy)
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { line in
                let fields = line.split(separator: "\t", maxSplits: 1)
                return GitReference(
                    name: fields.first.map(String.init) ?? "",
                    objectID: fields.count == 2 ? String(fields[1]) : "")
            }
            .filter { !$0.name.isEmpty && !$0.objectID.isEmpty }
    }

    static func changes(
        in repository: URL,
        from left: GitComparisonTarget,
        to right: GitComparisonTarget,
        policy: GitCommandPolicy = .standard
    ) throws -> [GitChange] {
        switch (left, right) {
        case (.revision(let lhs), .revision(let rhs)):
            return try parsedChanges(
                ["diff", "--name-status", "-z", "--find-renames", "--end-of-options", lhs, rhs, "--"],
                stage: .comparison, in: repository, policy: policy)
        case (.revision(let lhs), .index):
            return try parsedChanges(
                ["diff", "--cached", "--name-status", "-z", "--find-renames", "--end-of-options", lhs, "--"],
                stage: .staged, in: repository, policy: policy)
        case (.revision(let lhs), .workingTree):
            var changes = try parsedChanges(
                ["diff", "--cached", "--name-status", "-z", "--find-renames", "--end-of-options", lhs, "--"],
                stage: .staged, in: repository, policy: policy)
            changes += try parsedChanges(
                ["diff", "--name-status", "-z", "--find-renames", "--"],
                stage: .unstaged, in: repository, policy: policy)
            changes += try untrackedChanges(in: repository, policy: policy)
            return sorted(changes)
        case (.index, .workingTree):
            var changes = try parsedChanges(
                ["diff", "--name-status", "-z", "--find-renames", "--"],
                stage: .unstaged, in: repository, policy: policy)
            changes += try untrackedChanges(in: repository, policy: policy)
            return sorted(changes)
        default:
            throw GitRepositoryError.unsupportedTargetPair
        }
    }

    static func commit(
        in repository: URL,
        revision: String,
        policy: GitCommandPolicy = .standard
    ) throws -> GitCommit {
        let data = try run([
            "show", "-s", "--format=%H%x00%P%x00%an%x00%ae%x00%aI%x00%s%x00",
            "--end-of-options", revision
        ], in: repository, policy: policy)
        guard let commit = try parseCommits(data).first else {
            throw GitRepositoryError.malformedOutput
        }
        return commit
    }

    static func fileHistory(
        in repository: URL,
        path: String,
        revision: String = "HEAD",
        limit: Int = 200,
        policy: GitCommandPolicy = .standard
    ) throws -> [GitCommit] {
        try fileRevisions(
            in: repository, path: path, revision: revision, limit: limit, policy: policy
        ).map(\.commit)
    }

    static func fileRevisions(
        in repository: URL,
        path: String,
        revision: String = "HEAD",
        limit: Int = 200,
        skip: Int = 0,
        policy: GitCommandPolicy = .standard
    ) throws -> [GitFileRevision] {
        guard isSafeRelativePath(path) else { throw GitRepositoryError.unsafePath }
        let boundedLimit = min(max(limit, 1), 1_000)
        guard skip < 10_000 else { return [] }
        let boundedSkip = min(max(skip, 0), 9_999)
        let fetchLimit = min(boundedSkip + boundedLimit, 10_000)
        let data = try run([
            "log", "--follow", "--max-count=\(fetchLimit)",
            "--format=%x1e%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%s",
            "--name-only", "-z",
            "--end-of-options", revision, "--", path
        ], in: repository, policy: policy)
        return Array(try parseFileRevisions(data).dropFirst(boundedSkip).prefix(boundedLimit))
    }

    static func fileData(
        in repository: URL,
        target: GitComparisonTarget,
        path: String,
        policy: GitCommandPolicy = .standard
    ) throws -> Data? {
        guard isSafeRelativePath(path) else { throw GitRepositoryError.unsafePath }
        switch target {
        case .revision(let revision):
            do {
                return try run(["show", "--end-of-options", "\(revision):\(path)"], in: repository, policy: policy)
            } catch GitRepositoryError.commandFailed {
                return nil
            }
        case .index:
            do {
                return try run(["show", ":\(path)"], in: repository, policy: policy)
            } catch GitRepositoryError.commandFailed {
                return nil
            }
        case .workingTree:
            let root = try repositoryRoot(at: repository, policy: policy)
            let file = root.appending(path: path).standardizedFileURL
            guard file.path.hasPrefix(root.path + "/") else {
                throw GitRepositoryError.unsafePath
            }
            return try? Data(contentsOf: file, options: .mappedIfSafe)
        }
    }

    static func inspectFile(
        in repository: URL,
        target: GitComparisonTarget,
        path: String,
        probeLimit: Int64 = 8 * 1_024 * 1_024,
        policy: GitCommandPolicy = .standard
    ) throws -> GitFileInspection {
        guard isSafeRelativePath(path) else { throw GitRepositoryError.unsafePath }
        if try isSubmodule(in: repository, target: target, path: path, policy: policy) {
            return GitFileInspection(kind: .submodule, byteCount: nil)
        }

        let size: Int64?
        switch target {
        case .workingTree:
            let root = try repositoryRoot(at: repository, policy: policy)
            let file = root.appending(path: path).standardizedFileURL
            guard file.path.hasPrefix(root.path + "/") else { throw GitRepositoryError.unsafePath }
            guard FileManager.default.fileExists(atPath: file.path) else {
                return GitFileInspection(kind: .missing, byteCount: nil)
            }
            size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        case .revision(let revision):
            size = try blobSize("\(revision):\(path)", in: repository, policy: policy)
        case .index:
            size = try blobSize(":\(path)", in: repository, policy: policy)
        }
        guard let size else { return GitFileInspection(kind: .missing, byteCount: nil) }
        guard size <= probeLimit else { return GitFileInspection(kind: .largeFile, byteCount: size) }

        let data = try fileData(in: repository, target: target, path: path, policy: policy) ?? Data()
        let lfsHeader = Data("version https://git-lfs.github.com/spec/v1".utf8)
        if data.starts(with: lfsHeader) {
            return GitFileInspection(kind: .lfsPointer, byteCount: size)
        }
        return GitFileInspection(
            kind: data.contains(0) ? .binary : .text,
            byteCount: size)
    }

    private static func blobSize(
        _ object: String,
        in repository: URL,
        policy: GitCommandPolicy
    ) throws -> Int64? {
        do {
            let data = try run(["cat-file", "-s", "--", object], in: repository, policy: policy)
            return Int64(String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines))
        } catch GitRepositoryError.commandFailed {
            return nil
        }
    }

    private static func isSubmodule(
        in repository: URL,
        target: GitComparisonTarget,
        path: String,
        policy: GitCommandPolicy
    ) throws -> Bool {
        switch target {
        case .revision(let revision):
            let data = try run(
                ["ls-tree", "-z", "--end-of-options", revision, "--", path],
                in: repository,
                policy: policy)
            return String(decoding: data, as: UTF8.self).hasPrefix("160000 ")
        case .index:
            let data = try run(["ls-files", "-s", "-z", "--", path], in: repository, policy: policy)
            return String(decoding: data, as: UTF8.self).hasPrefix("160000 ")
        case .workingTree:
            let root = try repositoryRoot(at: repository, policy: policy)
            let directory = root.appending(path: path).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            return FileManager.default.fileExists(atPath: directory.appending(path: ".git").path)
        }
    }

    private static func parseNameStatus(_ data: Data) throws -> [GitChange] {
        let fields = splitNUL(data)
        var result: [GitChange] = []
        var index = 0
        while index < fields.count {
            let status = fields[index]
            index += 1
            guard let code = status.first else { throw GitRepositoryError.malformedOutput }
            if code == "R" || code == "C" {
                guard index + 1 < fields.count else { throw GitRepositoryError.malformedOutput }
                result.append(GitChange(
                    kind: code == "R" ? .renamed : .copied,
                    path: fields[index + 1],
                    oldPath: fields[index]))
                index += 2
            } else {
                guard index < fields.count else { throw GitRepositoryError.malformedOutput }
                result.append(GitChange(
                    kind: kind(for: code),
                    path: fields[index],
                    oldPath: nil))
                index += 1
            }
        }
        return result
    }

    private static func parsedChanges(
        _ arguments: [String],
        stage: GitChangeStage,
        in repository: URL,
        policy: GitCommandPolicy
    ) throws -> [GitChange] {
        try parseNameStatus(run(arguments, in: repository, policy: policy)).map {
            GitChange(kind: $0.kind, path: $0.path, oldPath: $0.oldPath, stage: stage)
        }
    }

    private static func untrackedChanges(
        in repository: URL,
        policy: GitCommandPolicy
    ) throws -> [GitChange] {
        splitNUL(try run([
            "ls-files", "--others", "--exclude-standard", "-z", "--"
        ], in: repository, policy: policy)).map {
            GitChange(kind: .untracked, path: $0, oldPath: nil, stage: .untracked)
        }
    }

    private static func sorted(_ changes: [GitChange]) -> [GitChange] {
        changes.sorted {
            let order = $0.path.localizedStandardCompare($1.path)
            return order == .orderedSame ? $0.stage.rawValue < $1.stage.rawValue : order == .orderedAscending
        }
    }

    private static func kind(for code: Character) -> GitChangeKind {
        switch code {
        case "A": .added
        case "M": .modified
        case "D": .deleted
        case "T": .typeChanged
        case "U": .unmerged
        default: .unknown
        }
    }

    static func splitNUL(_ data: Data) -> [String] {
        data.split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    private static func parseCommits(_ data: Data) throws -> [GitCommit] {
        var fields = data.split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        while let last = fields.last,
              last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.removeLast()
        }
        guard fields.count.isMultiple(of: 6) else {
            throw GitRepositoryError.malformedOutput
        }
        let formatter = ISO8601DateFormatter()
        return try stride(from: 0, to: fields.count, by: 6).map { index in
            let objectID = fields[index].trimmingCharacters(in: .newlines)
            let parentIDs = fields[index + 1].split(separator: " ").map(String.init)
            guard objectID.count >= 7,
                  let date = formatter.date(from: fields[index + 4]) else {
                throw GitRepositoryError.malformedOutput
            }
            return GitCommit(
                objectID: objectID,
                parentIDs: parentIDs,
                authorName: fields[index + 2],
                authorEmail: fields[index + 3],
                authoredDate: date,
                subject: fields[index + 5])
        }
    }

    private static func parseFileRevisions(_ data: Data) throws -> [GitFileRevision] {
        let formatter = ISO8601DateFormatter()
        return try data.split(separator: 0x1E).map { record in
            let chunks = Data(record).split(separator: 0, omittingEmptySubsequences: false)
                .map { String(decoding: $0, as: UTF8.self) }
            guard let metadata = chunks.first else { throw GitRepositoryError.malformedOutput }
            let fields = metadata.split(separator: "\u{1F}", omittingEmptySubsequences: false)
                .map(String.init)
            let paths = chunks.dropFirst().map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            guard fields.count == 6,
                  let path = paths.last,
                  isSafeRelativePath(path),
                  let date = formatter.date(from: fields[4]) else {
                throw GitRepositoryError.malformedOutput
            }
            let commit = GitCommit(
                objectID: fields[0],
                parentIDs: fields[1].split(separator: " ").map(String.init),
                authorName: fields[2],
                authorEmail: fields[3],
                authoredDate: date,
                subject: fields[5])
            return GitFileRevision(commit: commit, path: path)
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains("..")
    }

    static func run(
        _ arguments: [String],
        in directory: URL,
        policy: GitCommandPolicy = .standard
    ) throws -> Data {
        try runExecutable(
            URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            in: directory,
            policy: policy)
    }

    static func runProcessForTesting(
        executable: URL,
        arguments: [String],
        in directory: URL,
        policy: GitCommandPolicy
    ) throws -> Data {
        try runExecutable(executable, arguments: arguments, in: directory, policy: policy)
    }

    private static func runExecutable(
        _ executable: URL,
        arguments: [String],
        in directory: URL,
        policy: GitCommandPolicy
    ) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let temporary = FileManager.default.temporaryDirectory
        let outputURL = temporary.appendingPathComponent("GrapeCompare-git-\(UUID().uuidString).stdout")
        let errorURL = temporary.appendingPathComponent("GrapeCompare-git-\(UUID().uuidString).stderr")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            throw GitRepositoryError.commandFailed(arguments: arguments, message: "Unable to capture Git diagnostics.")
        }
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        try process.run()
        let deadline = Date().addingTimeInterval(max(policy.timeout, 0.1))
        while process.isRunning {
            if policy.isCancelled() {
                stop(process)
                throw GitRepositoryError.cancelled
            }
            if Date() >= deadline {
                stop(process)
                throw GitRepositoryError.timedOut
            }
            let outputSize = fileSize(outputURL)
            let errorSize = fileSize(errorURL)
            if outputSize > policy.maximumOutputBytes || errorSize > policy.maximumOutputBytes {
                stop(process)
                throw GitRepositoryError.outputTooLarge(limit: policy.maximumOutputBytes)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        try outputHandle.synchronize()
        try errorHandle.synchronize()
        let outputSize = fileSize(outputURL)
        let errorSize = fileSize(errorURL)
        guard outputSize <= policy.maximumOutputBytes else {
            throw GitRepositoryError.outputTooLarge(limit: policy.maximumOutputBytes)
        }
        guard errorSize <= policy.maximumOutputBytes else {
            throw GitRepositoryError.outputTooLarge(limit: policy.maximumOutputBytes)
        }
        let errorData = (try? Data(contentsOf: errorURL)) ?? Data()
        guard process.terminationStatus == 0 else {
            throw GitRepositoryError.commandFailed(
                arguments: arguments,
                message: String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (try? Data(contentsOf: outputURL, options: .mappedIfSafe)) ?? Data()
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func stop(_ process: Process) {
        process.terminate()
        let graceDeadline = Date().addingTimeInterval(0.2)
        while process.isRunning && Date() < graceDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }
}
