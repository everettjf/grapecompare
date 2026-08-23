import Foundation

nonisolated enum FileOperationPersistenceError: LocalizedError, Equatable, Sendable {
    case unsupportedJournalVersion(Int)
    case unsupportedRecipeVersion(Int)
    case invalidRelativePath(String)
    case emptyRecipe

    var errorDescription: String? {
        switch self {
        case .unsupportedJournalVersion(let version):
            return String(localized: "This operation history uses an unsupported format (version \(version)).")
        case .unsupportedRecipeVersion(let version):
            return String(localized: "This operation plan uses an unsupported format (version \(version)).")
        case .invalidRelativePath(let path):
            return String(localized: "The operation plan contains an unsafe relative path: \(path)")
        case .emptyRecipe:
            return String(localized: "The operation plan does not contain any operations.")
        }
    }
}

nonisolated struct FileOperationRecipe: Equatable, Sendable, Codable {
    static let currentSchemaVersion = 1

    struct Operation: Identifiable, Equatable, Sendable, Codable {
        let id: UUID
        let kind: FileOperationKind
        let relativePath: String
        let sourceSide: FileOperationSide

        init(
            id: UUID = UUID(),
            kind: FileOperationKind,
            relativePath: String,
            sourceSide: FileOperationSide
        ) {
            self.id = id
            self.kind = kind
            self.relativePath = relativePath
            self.sourceSide = sourceSide
        }
    }

    let schemaVersion: Int
    let createdAt: Date
    let operations: [Operation]

    init(
        schemaVersion: Int = currentSchemaVersion,
        createdAt: Date = Date(),
        operations: [Operation]
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.operations = operations
    }

    init(drafts: [FileOperationDraft], createdAt: Date = Date()) throws {
        guard !drafts.isEmpty else { throw FileOperationPersistenceError.emptyRecipe }
        let operations = try drafts.map { draft in
            try Self.validate(relativePath: draft.relativePath)
            return Operation(
                id: draft.id,
                kind: draft.kind,
                relativePath: draft.relativePath,
                sourceSide: draft.sourceSide)
        }
        self.init(createdAt: createdAt, operations: operations)
    }

    func drafts(leftRoot: URL, rightRoot: URL) throws -> [FileOperationDraft] {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw FileOperationPersistenceError.unsupportedRecipeVersion(schemaVersion)
        }
        guard !operations.isEmpty else { throw FileOperationPersistenceError.emptyRecipe }
        var seenIDs: Set<UUID> = []
        return try operations.map { operation in
            try Self.validate(relativePath: operation.relativePath)
            guard seenIDs.insert(operation.id).inserted else {
                throw FileOperationPersistenceError.invalidRelativePath(operation.relativePath)
            }
            let sourceRoot = operation.sourceSide == .left ? leftRoot : rightRoot
            let destinationRoot = operation.sourceSide == .left ? rightRoot : leftRoot
            let source = try Self.descendantURL(root: sourceRoot, relativePath: operation.relativePath)
            let destination = try Self.descendantURL(root: destinationRoot, relativePath: operation.relativePath)
            return FileOperationDraft(
                id: operation.id,
                kind: operation.kind,
                relativePath: operation.relativePath,
                sourceSide: operation.sourceSide,
                sourceURL: source,
                destinationURL: operation.kind == .trash
                    ? nil
                    : destination)
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> FileOperationRecipe {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let recipe = try decoder.decode(FileOperationRecipe.self, from: data)
        guard recipe.schemaVersion == currentSchemaVersion else {
            throw FileOperationPersistenceError.unsupportedRecipeVersion(recipe.schemaVersion)
        }
        guard !recipe.operations.isEmpty else { throw FileOperationPersistenceError.emptyRecipe }
        for operation in recipe.operations { try validate(relativePath: operation.relativePath) }
        return recipe
    }

    static func validate(relativePath: String) throws {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw FileOperationPersistenceError.invalidRelativePath(relativePath)
        }
    }

    private static func descendantURL(root: URL, relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/").map(String.init)
        var intermediate = root.standardizedFileURL
        for component in components.dropLast() {
            intermediate.append(path: component)
            if let attributes = try? FileManager.default.attributesOfItem(
                atPath: intermediate.path(percentEncoded: false)),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw FileOperationPersistenceError.invalidRelativePath(relativePath)
            }
        }
        let standardizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appending(path: relativePath).standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = standardizedRoot.path(percentEncoded: false)
        let candidatePath = candidate.path(percentEncoded: false)
        guard candidatePath.hasPrefix(rootPath + "/") else {
            throw FileOperationPersistenceError.invalidRelativePath(relativePath)
        }
        return root.appending(path: relativePath).standardizedFileURL
    }
}

nonisolated final class FileOperationJournalStore: @unchecked Sendable {
    private struct Entry: Codable {
        let transaction: FileOperationTransaction
        let bookmarks: [Data]
    }

    private struct Envelope: Codable {
        static let currentSchemaVersion = 1
        let schemaVersion: Int
        var entries: [Entry]
    }

    private let fileManager: FileManager
    let journalURL: URL
    let maxEntries: Int
    private let usesSecurityScopedBookmarks: Bool
    private static let persistenceLock = NSLock()
    private var accessedURLs: [URL] = []

    init(
        journalURL: URL = FileOperationJournalStore.defaultJournalURL(),
        maxEntries: Int = 50,
        fileManager: FileManager = .default,
        usesSecurityScopedBookmarks: Bool = true
    ) {
        self.journalURL = journalURL.standardizedFileURL
        self.maxEntries = max(1, maxEntries)
        self.fileManager = fileManager
        self.usesSecurityScopedBookmarks = usesSecurityScopedBookmarks
    }

    deinit {
        for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
    }

    func load() -> [FileOperationTransaction] {
        Self.persistenceLock.withLock {
            guard fileManager.fileExists(atPath: journalURL.path(percentEncoded: false)) else { return [] }
            do {
                let envelope = try decodeEnvelope()
                activateBookmarks(envelope.entries.flatMap(\.bookmarks))
                return envelope.entries.map(\.transaction)
            } catch {
                quarantineCorruptJournal()
                return []
            }
        }
    }

    /// Returns entries evicted by retention so the engine can release private backups.
    func append(_ transaction: FileOperationTransaction) throws -> [FileOperationTransaction] {
        try Self.persistenceLock.withLock {
            var envelope = try loadEnvelopeIfPresent()
            envelope.entries.removeAll { $0.transaction.id == transaction.id }
            let bookmarks = makeBookmarks(for: transaction)
            envelope.entries.append(Entry(transaction: transaction, bookmarks: bookmarks))
            var evicted: [FileOperationTransaction] = []
            if envelope.entries.count > maxEntries {
                let count = envelope.entries.count - maxEntries
                evicted = envelope.entries.prefix(count).map(\.transaction)
                envelope.entries.removeFirst(count)
            }
            try write(envelope)
            activateBookmarks(bookmarks)
            return evicted
        }
    }

    func remove(transactionID: UUID) throws {
        try Self.persistenceLock.withLock {
            var envelope = try loadEnvelopeIfPresent()
            envelope.entries.removeAll { $0.transaction.id == transactionID }
            if envelope.entries.isEmpty {
                if fileManager.fileExists(atPath: journalURL.path(percentEncoded: false)) {
                    try fileManager.removeItem(at: journalURL)
                }
            } else {
                try write(envelope)
            }
        }
    }

    func removeAll() throws -> [FileOperationTransaction] {
        try Self.persistenceLock.withLock {
            let entries = try loadEnvelopeIfPresent().entries.map(\.transaction)
            if fileManager.fileExists(atPath: journalURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: journalURL)
            }
            for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
            accessedURLs.removeAll()
            return entries
        }
    }

    static func defaultJournalURL(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)) ?? fileManager.temporaryDirectory
        return base.appending(path: "GrapeCompare/OperationHistory-v1.json")
    }

    private func loadEnvelopeIfPresent() throws -> Envelope {
        guard fileManager.fileExists(atPath: journalURL.path(percentEncoded: false)) else {
            return Envelope(schemaVersion: Envelope.currentSchemaVersion, entries: [])
        }
        return try decodeEnvelope()
    }

    private func decodeEnvelope() throws -> Envelope {
        let envelope = try JSONDecoder.grapeCompare.decode(
            Envelope.self,
            from: Data(contentsOf: journalURL))
        guard envelope.schemaVersion == Envelope.currentSchemaVersion else {
            throw FileOperationPersistenceError.unsupportedJournalVersion(envelope.schemaVersion)
        }
        return envelope
    }

    private func write(_ envelope: Envelope) throws {
        try fileManager.createDirectory(
            at: journalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder.grapeCompare.encode(envelope)
        // Atomic replacement protects the journal from partial writes. The
        // complete-file-protection option is not reliable for ordinary macOS
        // app-support and temporary paths (macOS 27 can make the replacement
        // unreadable to the creating process), which would destroy undo state.
        try data.write(to: journalURL, options: .atomic)
    }

    private func quarantineCorruptJournal() {
        let suffix = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let quarantine = journalURL.deletingLastPathComponent()
            .appending(path: journalURL.lastPathComponent + ".corrupt-" + suffix)
        try? fileManager.moveItem(at: journalURL, to: quarantine)
    }

    private func makeBookmarks(for transaction: FileOperationTransaction) -> [Data] {
        guard usesSecurityScopedBookmarks else { return [] }
        let directories = Set(transaction.undoRecords.flatMap(\.accessCandidates).compactMap(nearestExistingDirectory))
        return directories.compactMap { directory in
            try? directory.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil)
        }
    }

    private func nearestExistingDirectory(_ candidate: URL) -> URL? {
        var current = candidate.standardizedFileURL
        while current.pathComponents.count > 1 {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: current.path(percentEncoded: false), isDirectory: &isDirectory),
               isDirectory.boolValue { return current }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent != current else { break }
            current = parent
        }
        return nil
    }

    private func activateBookmarks(_ bookmarks: [Data]) {
        guard usesSecurityScopedBookmarks else { return }
        for bookmark in bookmarks {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale),
                  !accessedURLs.contains(url) else { continue }
            if url.startAccessingSecurityScopedResource() { accessedURLs.append(url) }
        }
    }
}

nonisolated private extension JSONEncoder {
    static var grapeCompare: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

nonisolated private extension JSONDecoder {
    static var grapeCompare: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
