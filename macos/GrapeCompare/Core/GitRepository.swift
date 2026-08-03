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

nonisolated enum GitChangeKind: String, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    case typeChanged
    case unmerged
    case untracked
    case unknown
}

nonisolated struct GitChange: Identifiable, Equatable, Sendable {
    let kind: GitChangeKind
    let path: String
    let oldPath: String?

    var id: String { "\(oldPath ?? "")\u{0}\(path)" }
}

nonisolated enum GitRepositoryError: Error, Equatable, LocalizedError {
    case commandFailed(arguments: [String], message: String)
    case malformedOutput
    case unsupportedTargetPair
    case unsafePath

    var errorDescription: String? {
        switch self {
        case .commandFailed(let arguments, let message):
            "git \(arguments.joined(separator: " ")) failed: \(message)"
        case .malformedOutput: "Git returned malformed output."
        case .unsupportedTargetPair: "That Git comparison target pair is not supported."
        case .unsafePath: "Git returned a path outside the selected repository."
        }
    }
}

nonisolated enum GitRepositoryComparator {
    static func repositoryRoot(at url: URL) throws -> URL {
        let result = try run(["rev-parse", "--show-toplevel"], in: url)
        guard let path = String(data: result, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { throw GitRepositoryError.malformedOutput }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    static func references(in repository: URL) throws -> [GitReference] {
        let data = try run([
            "for-each-ref", "--format=%(refname:short)%09%(objectname)",
            "refs/heads", "refs/tags"
        ], in: repository)
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
        to right: GitComparisonTarget
    ) throws -> [GitChange] {
        let arguments: [String]
        switch (left, right) {
        case (.revision(let lhs), .revision(let rhs)):
            arguments = ["diff", "--name-status", "-z", "--find-renames", lhs, rhs, "--"]
        case (.revision(let lhs), .index):
            arguments = ["diff", "--cached", "--name-status", "-z", "--find-renames", lhs, "--"]
        case (.revision(let lhs), .workingTree):
            arguments = ["diff", "--name-status", "-z", "--find-renames", lhs, "--"]
        case (.index, .workingTree):
            arguments = ["diff", "--name-status", "-z", "--find-renames", "--"]
        default:
            throw GitRepositoryError.unsupportedTargetPair
        }
        var changes = try parseNameStatus(try run(arguments, in: repository))
        if right == .workingTree {
            let untracked = splitNUL(try run([
                "ls-files", "--others", "--exclude-standard", "-z", "--"
            ], in: repository))
            changes.append(contentsOf: untracked.map {
                GitChange(kind: .untracked, path: $0, oldPath: nil)
            })
        }
        return changes.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    static func fileData(
        in repository: URL,
        target: GitComparisonTarget,
        path: String
    ) throws -> Data? {
        guard isSafeRelativePath(path) else { throw GitRepositoryError.unsafePath }
        switch target {
        case .revision(let revision):
            do {
                return try run(["show", "\(revision):\(path)"], in: repository)
            } catch {
                return nil
            }
        case .index:
            do {
                return try run(["show", ":\(path)"], in: repository)
            } catch {
                return nil
            }
        case .workingTree:
            let root = try repositoryRoot(at: repository)
            let file = root.appending(path: path).standardizedFileURL
            guard file.path.hasPrefix(root.path + "/") else {
                throw GitRepositoryError.unsafePath
            }
            return try? Data(contentsOf: file, options: .mappedIfSafe)
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

    private static func splitNUL(_ data: Data) -> [String] {
        data.split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains("..")
    }

    private static func run(_ arguments: [String], in directory: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrapeCompare-git-\(UUID().uuidString).stderr")
        guard FileManager.default.createFile(atPath: errorURL.path, contents: nil),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            throw GitRepositoryError.commandFailed(arguments: arguments, message: "Unable to capture Git diagnostics.")
        }
        defer {
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: errorURL)
        }
        process.standardOutput = output
        process.standardError = errorHandle
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try errorHandle.synchronize()
        let errorData = (try? Data(contentsOf: errorURL)) ?? Data()
        guard process.terminationStatus == 0 else {
            throw GitRepositoryError.commandFailed(
                arguments: arguments,
                message: String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }
}
