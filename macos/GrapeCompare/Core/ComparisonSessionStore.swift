import Foundation

nonisolated enum WorkspaceTabBarPolicy {
    static func isVisible(itemCount: Int) -> Bool {
        itemCount > 1
    }

    static func usesCompactNewComparisonButton(itemCount: Int) -> Bool {
        !isVisible(itemCount: itemCount)
    }
}

nonisolated enum ComparisonSessionKind: String, Codable, Sendable {
    case files
    case folders
    case merge
    case git
}

nonisolated struct ComparisonSession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: ComparisonSessionKind
    let createdAt: Date
    let displayNames: [String]
    let bookmarks: [Data]

    init(
        id: UUID = UUID(),
        kind: ComparisonSessionKind,
        createdAt: Date = Date(),
        displayNames: [String],
        bookmarks: [Data]
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.displayNames = displayNames
        self.bookmarks = bookmarks
    }
}

nonisolated struct ComparisonSessionEnvelope: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    var schemaVersion = Self.schemaVersion
    var current: ComparisonSession?
    var recents: [ComparisonSession] = []
}

nonisolated final class ComparisonSessionStore: @unchecked Sendable {
    private let fileURL: URL
    private let maximumRecents: Int
    private let lock = NSLock()

    init(fileURL: URL? = nil, maximumRecents: Int = 12) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "GrapeCompare", directoryHint: .isDirectory)
            self.fileURL = root.appending(path: "comparison-sessions.json", directoryHint: .notDirectory)
        }
        self.maximumRecents = max(1, maximumRecents)
    }

    func load() -> ComparisonSessionEnvelope {
        lock.withLock {
            guard let data = try? Data(contentsOf: fileURL),
                  let envelope = try? JSONDecoder().decode(ComparisonSessionEnvelope.self, from: data),
                  envelope.schemaVersion == ComparisonSessionEnvelope.schemaVersion else {
                return ComparisonSessionEnvelope()
            }
            return envelope
        }
    }

    func record(_ session: ComparisonSession) throws -> ComparisonSessionEnvelope {
        try lock.withLock {
            var envelope = loadUnlocked()
            envelope.current = session
            envelope.recents.removeAll {
                $0.kind == session.kind && $0.bookmarks == session.bookmarks
            }
            envelope.recents.insert(session, at: 0)
            envelope.recents = Array(envelope.recents.prefix(maximumRecents))
            try saveUnlocked(envelope)
            return envelope
        }
    }

    func clear() throws {
        try lock.withLock { try saveUnlocked(ComparisonSessionEnvelope()) }
    }

    private func loadUnlocked() -> ComparisonSessionEnvelope {
        guard let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(ComparisonSessionEnvelope.self, from: data),
              envelope.schemaVersion == ComparisonSessionEnvelope.schemaVersion else {
            return ComparisonSessionEnvelope()
        }
        return envelope
    }

    private func saveUnlocked(_ envelope: ComparisonSessionEnvelope) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(envelope).write(to: fileURL, options: .atomic)
    }
}
