import Foundation

nonisolated struct GitWorktree: Identifiable, Equatable, Sendable {
    let path: URL
    let headObjectID: String
    let branch: String?
    let isBare: Bool
    let isDetached: Bool
    let isLocked: Bool
    let lockReason: String?
    let isPrunable: Bool

    var id: String { path.standardizedFileURL.path }
}

nonisolated struct GitBranchContext: Equatable, Sendable {
    let branch: String?
    let upstream: String?
    let ahead: Int
    let behind: Int
    let mergeBaseObjectID: String?

    var isDetached: Bool { branch == nil }
}

nonisolated struct GitCommitGraphRow: Identifiable, Equatable, Sendable {
    let commit: GitCommit
    let decorations: [String]
    var id: String { commit.objectID }
}

nonisolated final class GitChangesetTreeNode: Identifiable, @unchecked Sendable {
    let id: String
    let name: String
    let path: String
    let change: GitChange?
    var children: [GitChangesetTreeNode]

    var isDirectory: Bool { change == nil }
    var outlineChildren: [GitChangesetTreeNode]? { children.isEmpty ? nil : children }

    init(id: String, name: String, path: String, change: GitChange?, children: [GitChangesetTreeNode] = []) {
        self.id = id
        self.name = name
        self.path = path
        self.change = change
        self.children = children
    }
}

nonisolated enum GitChangesetTreeBuilder {
    static func build(_ changes: [GitChange]) -> [GitChangesetTreeNode] {
        let root = MutableNode(name: "", path: "")
        for change in changes {
            let parts = change.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !parts.isEmpty else { continue }
            var cursor = root
            for (index, part) in parts.enumerated() {
                let path = parts.prefix(index + 1).joined(separator: "/")
                if index == parts.count - 1 {
                    cursor.files.append(GitChangesetTreeNode(
                        id: change.id, name: part, path: path, change: change))
                } else {
                    cursor = cursor.directory(named: part, path: path)
                }
            }
        }
        return freeze(root)
    }

    private final class MutableNode {
        let name: String
        let path: String
        var directories: [String: MutableNode] = [:]
        var files: [GitChangesetTreeNode] = []

        init(name: String, path: String) {
            self.name = name
            self.path = path
        }

        func directory(named name: String, path: String) -> MutableNode {
            if let existing = directories[name] { return existing }
            let node = MutableNode(name: name, path: path)
            directories[name] = node
            return node
        }
    }

    private static func freeze(_ node: MutableNode) -> [GitChangesetTreeNode] {
        let directories = node.directories.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.map { directory in
            GitChangesetTreeNode(
                id: "directory:\(directory.path)",
                name: directory.name,
                path: directory.path,
                change: nil,
                children: freeze(directory))
        }
        let files = node.files.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return directories + files
    }
}

nonisolated enum GitReviewState: String, Codable, Sendable {
    case unreviewed
    case reviewed
}

nonisolated struct GitRepositoryLibraryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var bookmark: Data
    var lastOpenedAt: Date
}

nonisolated final class GitRepositoryLibraryStore: @unchecked Sendable {
    private let storageURL: URL
    private let maximumEntries: Int
    private let usesSecurityScopedBookmarks: Bool

    init(storageURL: URL? = nil, maximumEntries: Int = 30,
         usesSecurityScopedBookmarks: Bool = true) {
        self.maximumEntries = max(1, maximumEntries)
        self.usesSecurityScopedBookmarks = usesSecurityScopedBookmarks
        self.storageURL = storageURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GrapeCompare/repositories.json")
    }

    func load() -> [GitRepositoryLibraryEntry] {
        guard let data = try? Data(contentsOf: storageURL),
              let entries = try? JSONDecoder().decode([GitRepositoryLibraryEntry].self, from: data) else {
            return []
        }
        return Array(entries.prefix(maximumEntries))
    }

    func remember(_ url: URL, now: Date = Date()) throws -> [GitRepositoryLibraryEntry] {
        let normalized = url.standardizedFileURL
        let bookmark: Data
        if usesSecurityScopedBookmarks {
          do {
            bookmark = try normalized.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
          } catch {
            // Direct-distribution and command-line test processes may not have a
            // ScopedBookmarksAgent. A regular bookmark still gives stable
            // persistence there; App Store builds take the security-scoped path.
            bookmark = try normalized.bookmarkData(
                options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
          }
        } else {
            bookmark = try normalized.bookmarkData(
                options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        var entries = load().filter { entry in
            guard let existing = try? resolve(entry).url else { return true }
            return existing.standardizedFileURL.path != normalized.path
        }
        entries.insert(GitRepositoryLibraryEntry(
            id: UUID(), displayName: normalized.lastPathComponent,
            bookmark: bookmark, lastOpenedAt: now), at: 0)
        entries = Array(entries.prefix(maximumEntries))
        try persist(entries)
        return entries
    }

    func resolve(_ entry: GitRepositoryLibraryEntry) throws -> (url: URL, stale: Bool) {
        var stale = false
        let url: URL
        if usesSecurityScopedBookmarks {
          do {
            url = try URL(resolvingBookmarkData: entry.bookmark,
                          options: [.withSecurityScope, .withoutUI],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
          } catch {
            url = try URL(resolvingBookmarkData: entry.bookmark,
                          options: [.withoutUI], relativeTo: nil,
                          bookmarkDataIsStale: &stale)
          }
        } else {
            url = try URL(resolvingBookmarkData: entry.bookmark,
                          options: [.withoutUI], relativeTo: nil,
                          bookmarkDataIsStale: &stale)
        }
        return (url.standardizedFileURL, stale)
    }

    func remove(id: UUID) throws -> [GitRepositoryLibraryEntry] {
        let entries = load().filter { $0.id != id }
        try persist(entries)
        return entries
    }

    private func persist(_ entries: [GitRepositoryLibraryEntry]) throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(entries).write(to: storageURL, options: .atomic)
    }
}

extension GitRepositoryComparator {
    nonisolated static func revision(
        in repository: URL,
        before date: Date,
        policy: GitCommandPolicy = .standard
    ) throws -> String? {
        let formatter = ISO8601DateFormatter()
        let data = try run([
            "rev-list", "--max-count=1", "--before=\(formatter.string(from: date))", "HEAD", "--"
        ], in: repository, policy: policy)
        let revision = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return revision.isEmpty ? nil : revision
    }

    nonisolated static func worktrees(
        in repository: URL,
        policy: GitCommandPolicy = .standard
    ) throws -> [GitWorktree] {
        let fields = splitNUL(try run([
            "worktree", "list", "--porcelain", "-z"
        ], in: repository, policy: policy))
        var result: [GitWorktree] = []
        var record: [String] = []
        func appendRecord() throws {
            guard !record.isEmpty else { return }
            guard let worktree = record.first(where: { $0.hasPrefix("worktree ") }) else {
                throw GitRepositoryError.malformedOutput
            }
            let rawPath = String(worktree.dropFirst("worktree ".count))
            guard rawPath.hasPrefix("/") else { throw GitRepositoryError.malformedOutput }
            let head = record.first(where: { $0.hasPrefix("HEAD ") })
                .map { String($0.dropFirst("HEAD ".count)) } ?? ""
            let branch = record.first(where: { $0.hasPrefix("branch ") }).map {
                String($0.dropFirst("branch refs/heads/".count))
            }
            let locked = record.first(where: { $0 == "locked" || $0.hasPrefix("locked ") })
            result.append(GitWorktree(
                path: URL(fileURLWithPath: rawPath).standardizedFileURL,
                headObjectID: head,
                branch: branch,
                isBare: record.contains("bare"),
                isDetached: record.contains("detached"),
                isLocked: locked != nil,
                lockReason: locked?.dropFirst("locked".count).trimmingCharacters(in: .whitespaces),
                isPrunable: record.contains(where: { $0 == "prunable" || $0.hasPrefix("prunable ") })))
            record.removeAll(keepingCapacity: true)
        }
        for field in fields {
            if field.hasPrefix("worktree "), !record.isEmpty { try appendRecord() }
            record.append(field)
        }
        try appendRecord()
        return result
    }

    nonisolated static func branchContext(
        in repository: URL,
        comparisonRevision: String = "HEAD",
        policy: GitCommandPolicy = .standard
    ) throws -> GitBranchContext {
        let branch: String?
        do {
            let branchData = try run(["symbolic-ref", "--quiet", "--short", "HEAD"], in: repository, policy: policy)
            let value = String(decoding: branchData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            branch = value.isEmpty ? nil : value
        } catch GitRepositoryError.commandFailed {
            branch = nil
        }
        let upstream: String?
        do {
            let data = try run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], in: repository, policy: policy)
            upstream = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch GitRepositoryError.commandFailed {
            upstream = nil
        }
        var ahead = 0
        var behind = 0
        if upstream != nil {
            let counts = try run(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], in: repository, policy: policy)
            let parts = String(decoding: counts, as: UTF8.self).split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 2, let lhs = Int(parts[0]), let rhs = Int(parts[1]) else {
                throw GitRepositoryError.malformedOutput
            }
            ahead = lhs
            behind = rhs
        }
        let mergeBase: String?
        do {
            let data = try run(["merge-base", "--", "HEAD", comparisonRevision], in: repository, policy: policy)
            mergeBase = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch GitRepositoryError.commandFailed {
            mergeBase = nil
        }
        return GitBranchContext(branch: branch, upstream: upstream,
                                ahead: ahead, behind: behind, mergeBaseObjectID: mergeBase)
    }

    nonisolated static func commitGraph(
        in repository: URL,
        revision: String = "--all",
        limit: Int = 200,
        skip: Int = 0,
        policy: GitCommandPolicy = .standard
    ) throws -> [GitCommitGraphRow] {
        let boundedLimit = min(max(limit, 1), 1_000)
        let boundedSkip = min(max(skip, 0), 100_000)
        var arguments = ["log", "--date=iso-strict", "--max-count=\(boundedLimit)", "--skip=\(boundedSkip)",
                         "--format=%H%x00%P%x00%an%x00%ae%x00%aI%x00%s%x00%D%x00"]
        if revision == "--all" { arguments.append("--all") }
        else { arguments += ["--end-of-options", revision] }
        let data = try run(arguments, in: repository, policy: policy)
        var fields = data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        while let last = fields.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields.removeLast() }
        guard fields.count.isMultiple(of: 7) else { throw GitRepositoryError.malformedOutput }
        let formatter = ISO8601DateFormatter()
        return try stride(from: 0, to: fields.count, by: 7).map { index in
            let objectID = fields[index].trimmingCharacters(in: .newlines)
            guard objectID.count >= 7, let date = formatter.date(from: fields[index + 4]) else {
                throw GitRepositoryError.malformedOutput
            }
            return GitCommitGraphRow(commit: GitCommit(
                objectID: objectID,
                parentIDs: fields[index + 1].split(separator: " ").map(String.init),
                authorName: fields[index + 2], authorEmail: fields[index + 3],
                authoredDate: date, subject: fields[index + 5]),
                decorations: fields[index + 6].split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }.filter { !$0.isEmpty })
        }
    }
}
