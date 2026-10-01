import Foundation

/// The shelf owns inputs, not file contents. Reject the entire batch on invalid input.
nonisolated enum InputShelfPolicy {
    enum Failure: Error { case unavailable, mixed, tooMany }
    static let capacity = 16

    static func adding(_ incoming: [URL], to existing: [URL]) throws -> [URL] {
        var result = existing
        for url in incoming.map(\.standardizedFileURL) where !result.contains(url) {
            result.append(url)
        }
        guard result.count <= capacity else { throw Failure.tooMany }
        let kinds = result.compactMap { ComparisonInputInspector.kind(of: $0) }
        guard kinds.count == result.count else { throw Failure.unavailable }
        guard let kind = kinds.first else { return [] }
        guard kinds.allSatisfy({ $0 == kind }) else { throw Failure.mixed }
        guard kind != .folder || result.count <= 2 else { throw Failure.tooMany }
        return result
    }
}

/// Original row IDs survive folding, so navigation and patch generation remain independent.
nonisolated struct PresentedDiffRow: Identifiable, Sendable {
    let row: DiffRow
    let hiddenRange: Range<Int>?
    var id: Int { row.id }
}

nonisolated enum UnchangedTextPolicy {
    static func rows(_ rows: [DiffRow], collapsed: Bool, expanded: Set<Int>, context: Int = 3) -> [PresentedDiffRow] {
        guard collapsed else { return rows.map { PresentedDiffRow(row: $0, hiddenRange: nil) } }
        var result: [PresentedDiffRow] = []
        var index = 0
        let context = max(0, context)
        while index < rows.count {
            guard rows[index].kind == .equal else {
                result.append(PresentedDiffRow(row: rows[index], hiddenRange: nil))
                index += 1
                continue
            }
            let start = index
            while index < rows.count && rows[index].kind == .equal { index += 1 }
            let lower = min(start + context, index)
            let upper = max(lower, index - context)
            for i in start..<lower { result.append(PresentedDiffRow(row: rows[i], hiddenRange: nil)) }
            if upper - lower > 1 && !expanded.contains(rows[lower].id) {
                result.append(PresentedDiffRow(row: rows[lower], hiddenRange: lower..<upper))
            } else {
                for i in lower..<upper { result.append(PresentedDiffRow(row: rows[i], hiddenRange: nil)) }
            }
            for i in upper..<index { result.append(PresentedDiffRow(row: rows[i], hiddenRange: nil)) }
        }
        return result
    }
}

nonisolated enum FolderSearchPolicy {
    /// One post-order pass retains matching paths and their ancestors; no repeated subtree scans.
    static func matchingIDs(in root: FolderNode, query: String, accepts: (FolderNode) -> Bool) -> Set<String> {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: Set<String> = []
        func visit(_ node: FolderNode) -> Bool {
            var childMatches = false
            for child in node.children ?? [] { if visit(child) { childMatches = true } }
            let matches = accepts(node) && (query.isEmpty || node.relativePath.range(
                of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
            if matches || childMatches { result.insert(node.id); return true }
            return false
        }
        _ = visit(root)
        return result
    }
}

nonisolated struct ReadingOffset: Codable, Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
}

nonisolated struct ComparisonReadingState: Codable, Equatable, Sendable {
    var image: ImageReadingState?
    var search = ""
    var filter = "all"
    var expandedFolders: Set<String> = []
    var selection: Set<String> = []
    var topVisibleFolderID: String?
    var wraps = false
    var collapsed = false
    var expandedText: Set<Int> = []
    var difference = 0
    var hunk = 0
    var leftOffset = ReadingOffset()
    var rightOffset = ReadingOffset()
    var wrappedOffset = ReadingOffset()
}

/// Bounded local presentation state. Never stores file contents or grants filesystem access.
nonisolated final class ComparisonReadingStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private struct Entry: Codable { var key: String; var value: ComparisonReadingState }
    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GrapeCompare/reading-positions.json")) { self.url = url }
    static func key(kind: String, left: URL?, right: URL?) -> String {
        [kind, left?.standardizedFileURL.path ?? "", right?.standardizedFileURL.path ?? ""].joined(separator: "\u{0}")
    }
    private func load() -> [Entry] {
        guard let data = try? Data(contentsOf: url), data.count <= 4_000_000,
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return Array(entries.prefix(64))
    }
    func read(_ key: String) -> ComparisonReadingState? {
        lock.lock(); defer { lock.unlock() }
        return load().first(where: { $0.key == key })?.value
    }
    func save(_ value: ComparisonReadingState, for key: String) {
        lock.lock(); defer { lock.unlock() }
        var entries = load().filter { $0.key != key }
        entries.insert(Entry(key: key, value: value), at: 0)
        entries = Array(entries.prefix(64))
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

nonisolated enum FolderReviewPolicy {
    static func files(in root: FolderNode, allowedIDs: Set<String>? = nil) -> [FolderNode] {
        var result: [FolderNode] = []
        func visit(_ node: FolderNode) {
            if node.isFolder {
                for child in node.children ?? [] { visit(child) }
            } else if node.status != .same && (allowedIDs?.contains(node.id) ?? true) {
                result.append(node)
            }
        }
        visit(root)
        return result
    }

    static func adjacentID(_ ids: [String], current: String?, direction: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else {
            return direction < 0 ? ids.last : ids.first
        }
        let next = index + (direction < 0 ? -1 : 1)
        return ids.indices.contains(next) ? ids[next] : nil
    }
}

nonisolated struct ImageReadingState: Codable, Equatable, Sendable {
    var mode = "twoUp"
    var zoom = 1.0
    var panX = 0.0
    var panY = 0.0
    var split = 0.5
    var offsetX = 0
    var offsetY = 0
    var threshold = 0.0
    var channels: UInt8 = 15
    var rendering = "proportional"

    func validated() -> Self {
        var value = self
        value.zoom = zoom.isFinite ? min(8, max(0.1, zoom)) : 1
        value.panX = panX.isFinite ? min(1_000_000, max(-1_000_000, panX)) : 0
        value.panY = panY.isFinite ? min(1_000_000, max(-1_000_000, panY)) : 0
        value.split = split.isFinite ? min(1, max(0, split)) : 0.5
        value.threshold = threshold.isFinite ? min(255, max(0, threshold)) : 0
        value.offsetX = min(100_000, max(-100_000, offsetX))
        value.offsetY = min(100_000, max(-100_000, offsetY))
        value.channels &= 15
        return value
    }
}
