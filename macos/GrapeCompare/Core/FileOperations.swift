import Foundation
import Darwin

nonisolated enum FileOperationSide: String, Sendable, Codable {
    case left
    case right
}

nonisolated enum FileOperationKind: String, Sendable, Codable {
    case copy
    case replace
    case move
    case trash
}

nonisolated enum FileSystemEntryKind: String, Sendable, Codable {
    case regularFile
    case directory
    case symbolicLink
}

nonisolated struct FileSystemSnapshot: Equatable, Sendable, Codable {
    let kind: FileSystemEntryKind
    let itemCount: Int
    let byteCount: Int64
    let fingerprint: UInt64
}

nonisolated struct FileOperationDraft: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let kind: FileOperationKind
    let relativePath: String
    let sourceSide: FileOperationSide
    let sourceURL: URL
    let destinationURL: URL?

    init(
        id: UUID = UUID(),
        kind: FileOperationKind,
        relativePath: String,
        sourceSide: FileOperationSide,
        sourceURL: URL,
        destinationURL: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
        self.sourceSide = sourceSide
        self.sourceURL = sourceURL.standardizedFileURL
        self.destinationURL = destinationURL?.standardizedFileURL
    }
}

nonisolated struct PreparedFileOperation: Identifiable, Equatable, Sendable {
    let draft: FileOperationDraft
    let sourceSnapshot: FileSystemSnapshot
    let destinationSnapshot: FileSystemSnapshot?
    /// Destination ancestors that did not exist during review, ordered from
    /// the highest missing directory to the immediate parent.
    let missingDestinationParents: [URL]

    var id: UUID { draft.id }
    var kind: FileOperationKind { draft.kind }
    var relativePath: String { draft.relativePath }
    var itemCount: Int { sourceSnapshot.itemCount + missingDestinationParents.count }
    var byteCount: Int64 { sourceSnapshot.byteCount }
}

nonisolated struct FileOperationPlan: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let operations: [PreparedFileOperation]

    init(id: UUID = UUID(), createdAt: Date = Date(), operations: [PreparedFileOperation]) {
        self.id = id
        self.createdAt = createdAt
        self.operations = operations
    }

    var itemCount: Int {
        let sourceItems = operations.reduce(0) { $0 + $1.sourceSnapshot.itemCount }
        let destinationParents = Set(operations.flatMap(\.missingDestinationParents)).count
        return sourceItems + destinationParents
    }
    var byteCount: Int64 { operations.reduce(0) { $0 + $1.byteCount } }
    var replacementCount: Int { operations.count { $0.kind == .replace } }
    var trashCount: Int { operations.count { $0.kind == .trash } }
    var moveCount: Int { operations.count { $0.kind == .move } }
}

nonisolated enum FileOperationFailurePolicy: String, CaseIterable, Sendable, Codable {
    case stopOnFirstFailure
    case continueAfterFailures
}

nonisolated struct FileOperationProgress: Equatable, Sendable {
    let completedOperations: Int
    let totalOperations: Int
    let completedBytes: Int64
    let totalBytes: Int64
    let currentPath: String
    let bytesPerSecond: Double?
    let estimatedTimeRemaining: TimeInterval?

    init(
        completedOperations: Int,
        totalOperations: Int,
        completedBytes: Int64,
        totalBytes: Int64,
        currentPath: String,
        bytesPerSecond: Double? = nil,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.completedOperations = completedOperations
        self.totalOperations = totalOperations
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.currentPath = currentPath
        self.bytesPerSecond = bytesPerSecond
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
}

nonisolated struct FileOperationFailure: Identifiable, Equatable, Sendable {
    let id: UUID
    let relativePath: String
    let message: String
}

nonisolated struct FileOperationResult: Sendable {
    let transaction: FileOperationTransaction?
    let failures: [FileOperationFailure]
    let wasCancelled: Bool
    let completedOperations: Int
}

nonisolated struct FileOperationTransaction: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let completedAt: Date
    let undoRecords: [FileOperationUndoRecord]

    var operationCount: Int { undoRecords.count }
    var displayPaths: [String] { undoRecords.map(\.displayPath) }
    var byteCount: Int64 { undoRecords.reduce(0) { $0 + $1.expectedOutput.byteCount } }
}

nonisolated enum FileOperationError: LocalizedError, Equatable, Sendable {
    case sourceMissing(String)
    case destinationMissing(String)
    case destinationAlreadyExists(String)
    case destinationRequired
    case nestedPaths
    case unsupportedEntry(String)
    case staleSource(String)
    case staleDestination(String)
    case changedOutput(String)
    case undoCollision(String)
    case verificationFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sourceMissing(let path): return String(localized: "The source no longer exists: \(path)")
        case .destinationMissing(let path): return String(localized: "The item to replace no longer exists: \(path)")
        case .destinationAlreadyExists(let path): return String(localized: "The destination already exists: \(path)")
        case .destinationRequired: return String(localized: "This operation requires a destination.")
        case .nestedPaths: return String(localized: "The destination cannot be inside the source.")
        case .unsupportedEntry(let path): return String(localized: "This file type cannot be operated on safely: \(path)")
        case .staleSource(let path): return String(localized: "The source changed after the plan was reviewed: \(path)")
        case .staleDestination(let path): return String(localized: "The destination changed after the plan was reviewed: \(path)")
        case .changedOutput(let path): return String(localized: "Undo stopped because the output changed: \(path)")
        case .undoCollision(let path): return String(localized: "Undo stopped because another item now exists here: \(path)")
        case .verificationFailed(let path): return String(localized: "The copied data could not be verified: \(path)")
        case .cancelled: return String(localized: "The operation was cancelled.")
        }
    }
}

/// A synchronous, UI-independent transaction engine. Work should be dispatched
/// off the main actor. Transactions are serialized process-wide so independent
/// windows cannot commit at the same time.
nonisolated final class FileOperationEngine: @unchecked Sendable {
    typealias ProgressHandler = @Sendable (FileOperationProgress) -> Void
    typealias CancellationHandler = @Sendable () -> Bool

    private static let executionLock = NSLock()
    private let fileManager: FileManager
    private let testTrashDirectory: URL?
    private let forceCrossVolumeMoves: Bool
    private let now: @Sendable () -> Date

    init(
        fileManager: FileManager = .default,
        testTrashDirectory: URL? = nil,
        forceCrossVolumeMoves: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        self.testTrashDirectory = testTrashDirectory?.standardizedFileURL
        self.forceCrossVolumeMoves = forceCrossVolumeMoves
        self.now = now
    }

    func prepare(
        drafts: [FileOperationDraft],
        shouldCancel: CancellationHandler = { false }
    ) throws -> FileOperationPlan {
        var prepared: [PreparedFileOperation] = []
        prepared.reserveCapacity(drafts.count)
        for draft in drafts {
            try checkCancellation(shouldCancel)
            let source = try snapshot(at: draft.sourceURL, shouldCancel: shouldCancel)
            let destination = try destinationSnapshot(for: draft, shouldCancel: shouldCancel)
            try validatePathRelationship(draft)
            let missingParents = try missingDestinationParents(for: draft)
            prepared.append(PreparedFileOperation(
                draft: draft,
                sourceSnapshot: source,
                destinationSnapshot: destination,
                missingDestinationParents: missingParents))
        }
        return FileOperationPlan(operations: prepared)
    }

    func execute(
        _ plan: FileOperationPlan,
        failurePolicy: FileOperationFailurePolicy = .continueAfterFailures,
        shouldCancel: CancellationHandler = { false },
        progress: ProgressHandler = { _ in }
    ) -> FileOperationResult {
        Self.executionLock.lock()
        defer { Self.executionLock.unlock() }

        var records: [FileOperationUndoRecord] = []
        var failures: [FileOperationFailure] = []
        var completedBytes: Int64 = 0
        var wasCancelled = false
        var createdParentsInTransaction: Set<URL> = []
        let estimator = FileOperationProgressEstimator(
            totalBytes: plan.byteCount,
            totalOperations: plan.operations.count,
            startedAt: now())

        for operation in plan.operations {
            if shouldCancel() {
                wasCancelled = true
                break
            }
            progress(estimator.progress(
                completedOperations: records.count,
                completedBytes: completedBytes,
                currentPath: operation.relativePath,
                at: now()))
            do {
                try validatePreconditions(
                    operation,
                    createdParentsInTransaction: createdParentsInTransaction,
                    shouldCancel: shouldCancel)
                let record = try executeOne(operation, shouldCancel: shouldCancel)
                records.append(record)
                createdParentsInTransaction.formUnion(record.createdParents)
                completedBytes += operation.byteCount
            } catch FileOperationError.cancelled {
                wasCancelled = true
                break
            } catch is CancellationError {
                wasCancelled = true
                break
            } catch {
                failures.append(FileOperationFailure(
                    id: operation.id,
                    relativePath: operation.relativePath,
                    message: error.localizedDescription))
                if failurePolicy == .stopOnFirstFailure { break }
            }
        }

        progress(estimator.progress(
            completedOperations: records.count,
            completedBytes: completedBytes,
            currentPath: "",
            at: now()))
        let transaction = records.isEmpty ? nil : FileOperationTransaction(
            id: plan.id,
            completedAt: now(),
            undoRecords: records)
        return FileOperationResult(
            transaction: transaction,
            failures: failures,
            wasCancelled: wasCancelled,
            completedOperations: records.count)
    }

    func undo(
        _ transaction: FileOperationTransaction,
        shouldCancel: CancellationHandler = { false },
        progress: ProgressHandler = { _ in }
    ) throws {
        Self.executionLock.lock()
        defer { Self.executionLock.unlock() }

        let records = Array(transaction.undoRecords.reversed())
        let totalBytes = records.reduce(Int64(0)) { $0 + $1.expectedOutput.byteCount }
        var completedBytes: Int64 = 0
        let estimator = FileOperationProgressEstimator(
            totalBytes: totalBytes,
            totalOperations: records.count,
            startedAt: now())
        // Validate the whole undo transaction before changing anything. A user
        // edit in a later record must not be discovered after earlier records
        // have already been restored.
        for record in records {
            try checkCancellation(shouldCancel)
            try validateUndo(record, shouldCancel: shouldCancel)
        }
        for (index, record) in records.enumerated() {
            try checkCancellation(shouldCancel)
            progress(estimator.progress(
                completedOperations: index,
                completedBytes: completedBytes,
                currentPath: record.displayPath,
                at: now()))
            try undoOne(record, shouldCancel: shouldCancel)
            completedBytes += record.expectedOutput.byteCount
        }
        progress(estimator.progress(
            completedOperations: records.count,
            completedBytes: completedBytes,
            currentPath: "",
            at: now()))
    }

    /// Releases private replacement backups after a history entry is intentionally
    /// discarded. Items in the system Trash are never removed here.
    func discard(_ transaction: FileOperationTransaction) {
        for record in transaction.undoRecords {
            if case .replaced(_, let backup, _, let expectedBackup, _) = record,
               (try? optionalSnapshot(at: backup, shouldCancel: { false })) == expectedBackup {
                try? fileManager.removeItem(at: backup)
            }
        }
    }

    // MARK: - Preparation and validation

    private func destinationSnapshot(
        for draft: FileOperationDraft,
        shouldCancel: CancellationHandler
    ) throws -> FileSystemSnapshot? {
        if draft.kind == .trash { return nil }
        guard let destination = draft.destinationURL else {
            throw FileOperationError.destinationRequired
        }
        let current = try optionalSnapshot(at: destination, shouldCancel: shouldCancel)
        switch draft.kind {
        case .copy, .move:
            if current != nil {
                throw FileOperationError.destinationAlreadyExists(destination.path(percentEncoded: false))
            }
        case .replace:
            if current == nil {
                throw FileOperationError.destinationMissing(destination.path(percentEncoded: false))
            }
        case .trash:
            break
        }
        return current
    }

    private func validatePathRelationship(_ draft: FileOperationDraft) throws {
        guard let destination = draft.destinationURL else { return }
        let sourcePath = draft.sourceURL.resolvingSymlinksInPath().standardizedFileURL.path
        let destinationPath = destination.resolvingSymlinksInPath().standardizedFileURL.path
        if destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/") {
            throw FileOperationError.nestedPaths
        }
    }

    private func missingDestinationParents(for draft: FileOperationDraft) throws -> [URL] {
        guard draft.kind == .copy || draft.kind == .move,
              let destination = draft.destinationURL else { return [] }
        var current = destination.deletingLastPathComponent().standardizedFileURL
        var missing: [URL] = []
        while true {
            if let kind = try optionalEntryKind(at: current) {
                guard kind == .directory else {
                    throw FileOperationError.unsupportedEntry(current.path(percentEncoded: false))
                }
                break
            }
            missing.append(current)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent != current else {
                throw FileOperationError.destinationMissing(current.path(percentEncoded: false))
            }
            current = parent
        }
        return missing.reversed()
    }

    private func validatePreconditions(
        _ operation: PreparedFileOperation,
        createdParentsInTransaction: Set<URL>,
        shouldCancel: CancellationHandler
    ) throws {
        let source = try optionalSnapshot(at: operation.draft.sourceURL, shouldCancel: shouldCancel)
        guard source == operation.sourceSnapshot else {
            throw FileOperationError.staleSource(operation.draft.sourceURL.path(percentEncoded: false))
        }
        guard operation.kind != .trash, let destination = operation.draft.destinationURL else { return }
        let current = try optionalSnapshot(at: destination, shouldCancel: shouldCancel)
        guard current == operation.destinationSnapshot else {
            throw FileOperationError.staleDestination(destination.path(percentEncoded: false))
        }
        for parent in operation.missingDestinationParents {
            if createdParentsInTransaction.contains(parent) { continue }
            guard try optionalSnapshot(at: parent, shouldCancel: shouldCancel) == nil else {
                throw FileOperationError.staleDestination(parent.path(percentEncoded: false))
            }
        }
    }

    // MARK: - Execution

    private func executeOne(
        _ operation: PreparedFileOperation,
        shouldCancel: CancellationHandler
    ) throws -> FileOperationUndoRecord {
        let createdParents = try createDestinationParents(operation.missingDestinationParents)
        do {
            switch operation.kind {
            case .copy:
                return try executeCopy(operation, createdParents: createdParents, shouldCancel: shouldCancel)
            case .replace:
                return try executeReplace(operation, shouldCancel: shouldCancel)
            case .move:
                return try executeMove(operation, createdParents: createdParents, shouldCancel: shouldCancel)
            case .trash:
                return try executeTrash(operation, shouldCancel: shouldCancel)
            }
        } catch {
            removeEmptyDirectories(createdParents.reversed())
            throw error
        }
    }

    private func executeCopy(
        _ operation: PreparedFileOperation,
        createdParents: [URL],
        shouldCancel: CancellationHandler
    ) throws -> FileOperationUndoRecord {
        guard let destination = operation.draft.destinationURL else {
            throw FileOperationError.destinationRequired
        }
        let stage = stagingURL(nextTo: destination, label: "stage")
        defer { try? fileManager.removeItem(at: stage) }
        try copyItem(at: operation.draft.sourceURL, to: stage, shouldCancel: shouldCancel)
        try checkCancellation(shouldCancel)
        guard try snapshot(at: stage) == operation.sourceSnapshot,
              try contentsEqual(operation.draft.sourceURL, stage, shouldCancel: shouldCancel) else {
            throw FileOperationError.verificationFailed(operation.relativePath)
        }
        try fileManager.moveItem(at: stage, to: destination)
        let output = try snapshot(at: destination)
        return .created(
            destination: destination,
            expectedOutput: output,
            createdParents: createdParents,
            displayPath: operation.relativePath)
    }

    private func executeReplace(
        _ operation: PreparedFileOperation,
        shouldCancel: CancellationHandler
    ) throws -> FileOperationUndoRecord {
        guard let destination = operation.draft.destinationURL,
              let original = operation.destinationSnapshot else {
            throw FileOperationError.destinationRequired
        }
        let stage = stagingURL(nextTo: destination, label: "stage")
        let backup = stagingURL(nextTo: destination, label: "backup")
        defer { try? fileManager.removeItem(at: stage) }
        try copyItem(at: operation.draft.sourceURL, to: stage, shouldCancel: shouldCancel)
        try checkCancellation(shouldCancel)
        guard try snapshot(at: stage) == operation.sourceSnapshot,
              try contentsEqual(operation.draft.sourceURL, stage, shouldCancel: shouldCancel) else {
            throw FileOperationError.verificationFailed(operation.relativePath)
        }
        guard try optionalSnapshot(at: destination, shouldCancel: shouldCancel) == original else {
            throw FileOperationError.staleDestination(destination.path(percentEncoded: false))
        }
        _ = try fileManager.replaceItemAt(
            destination,
            withItemAt: stage,
            backupItemName: backup.lastPathComponent,
            options: .withoutDeletingBackupItem)
        let output = try snapshot(at: destination)
        return .replaced(
            destination: destination,
            backup: backup,
            expectedOutput: output,
            expectedBackup: original,
            displayPath: operation.relativePath)
    }

    private func executeMove(
        _ operation: PreparedFileOperation,
        createdParents: [URL],
        shouldCancel: CancellationHandler
    ) throws -> FileOperationUndoRecord {
        guard let destination = operation.draft.destinationURL else {
            throw FileOperationError.destinationRequired
        }
        let source = operation.draft.sourceURL
        if try isSameVolume(source, destination.deletingLastPathComponent()) {
            try checkCancellation(shouldCancel)
            try fileManager.moveItem(at: source, to: destination)
            let output = try snapshot(at: destination)
            return .moved(
                source: source,
                destination: destination,
                expectedOutput: output,
                createdParents: createdParents,
                displayPath: operation.relativePath)
        }

        let stage = stagingURL(nextTo: destination, label: "stage")
        defer { try? fileManager.removeItem(at: stage) }
        try copyItem(at: source, to: stage, shouldCancel: shouldCancel)
        try checkCancellation(shouldCancel)
        guard try snapshot(at: stage) == operation.sourceSnapshot,
              try contentsEqual(source, stage, shouldCancel: shouldCancel) else {
            throw FileOperationError.verificationFailed(operation.relativePath)
        }
        try fileManager.moveItem(at: stage, to: destination)
        do {
            guard try snapshot(at: source, shouldCancel: shouldCancel) == operation.sourceSnapshot else {
                throw FileOperationError.staleSource(source.path(percentEncoded: false))
            }
            let trashedSource = try trashItem(at: source)
            let output = try snapshot(at: destination)
            let trashed = try snapshot(at: trashedSource)
            return .crossVolumeMoved(
                source: source,
                destination: destination,
                trashedSource: trashedSource,
                expectedOutput: output,
                expectedTrashedSource: trashed,
                createdParents: createdParents,
                displayPath: operation.relativePath)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private func executeTrash(
        _ operation: PreparedFileOperation,
        shouldCancel: CancellationHandler
    ) throws -> FileOperationUndoRecord {
        try checkCancellation(shouldCancel)
        let original = operation.draft.sourceURL
        let trashed = try trashItem(at: original)
        let output = try snapshot(at: trashed)
        return .trashed(
            original: original,
            trashed: trashed,
            expectedOutput: output,
            displayPath: operation.relativePath)
    }

    // MARK: - Undo

    private func undoOne(
        _ record: FileOperationUndoRecord,
        shouldCancel: CancellationHandler
    ) throws {
        try checkCancellation(shouldCancel)
        switch record {
        case .created(let destination, let expected, let createdParents, _):
            try requireUnchanged(destination, expected: expected, shouldCancel: shouldCancel)
            try fileManager.removeItem(at: destination)
            removeEmptyDirectories(createdParents.reversed())

        case .replaced(let destination, let backup, let expected, let expectedBackup, _):
            try requireUnchanged(destination, expected: expected, shouldCancel: shouldCancel)
            try requireUnchanged(backup, expected: expectedBackup, shouldCancel: shouldCancel)
            _ = try fileManager.replaceItemAt(destination, withItemAt: backup)

        case .moved(let source, let destination, let expected, let createdParents, _):
            guard try optionalSnapshot(at: source, shouldCancel: shouldCancel) == nil else {
                throw FileOperationError.undoCollision(source.path(percentEncoded: false))
            }
            try requireUnchanged(destination, expected: expected, shouldCancel: shouldCancel)
            try fileManager.moveItem(at: destination, to: source)
            removeEmptyDirectories(createdParents.reversed())

        case .crossVolumeMoved(
            let source, let destination, let trashedSource,
            let expected, let expectedTrashed, let createdParents, _
        ):
            guard try optionalSnapshot(at: source, shouldCancel: shouldCancel) == nil else {
                throw FileOperationError.undoCollision(source.path(percentEncoded: false))
            }
            try requireUnchanged(destination, expected: expected, shouldCancel: shouldCancel)
            try requireUnchanged(trashedSource, expected: expectedTrashed, shouldCancel: shouldCancel)
            try fileManager.moveItem(at: trashedSource, to: source)
            try fileManager.removeItem(at: destination)
            removeEmptyDirectories(createdParents.reversed())

        case .trashed(let original, let trashed, let expected, _):
            guard try optionalSnapshot(at: original, shouldCancel: shouldCancel) == nil else {
                throw FileOperationError.undoCollision(original.path(percentEncoded: false))
            }
            try requireUnchanged(trashed, expected: expected, shouldCancel: shouldCancel)
            try fileManager.moveItem(at: trashed, to: original)
        }
    }

    private func validateUndo(
        _ record: FileOperationUndoRecord,
        shouldCancel: CancellationHandler
    ) throws {
        switch record {
        case .created(let destination, let expected, _, _):
            try requireUnchanged(destination, expected: expected, shouldCancel: shouldCancel)
        case .replaced(let destination, let backup, let expected, let expectedBackup, _):
            try requireUnchanged(destination, expected: expected, shouldCancel: shouldCancel)
            try requireUnchanged(backup, expected: expectedBackup, shouldCancel: shouldCancel)
        case .moved(let source, let destination, let expected, _, _):
            guard try optionalSnapshot(at: source, shouldCancel: shouldCancel) == nil else {
                throw FileOperationError.undoCollision(source.path(percentEncoded: false))
            }
            try requireUnchanged(destination, expected: expected, shouldCancel: shouldCancel)
        case .crossVolumeMoved(
            let source, let destination, let trashedSource,
            let expected, let expectedTrashed, _, _
        ):
            guard try optionalSnapshot(at: source, shouldCancel: shouldCancel) == nil else {
                throw FileOperationError.undoCollision(source.path(percentEncoded: false))
            }
            try requireUnchanged(destination, expected: expected, shouldCancel: shouldCancel)
            try requireUnchanged(trashedSource, expected: expectedTrashed, shouldCancel: shouldCancel)
        case .trashed(let original, let trashed, let expected, _):
            guard try optionalSnapshot(at: original, shouldCancel: shouldCancel) == nil else {
                throw FileOperationError.undoCollision(original.path(percentEncoded: false))
            }
            try requireUnchanged(trashed, expected: expected, shouldCancel: shouldCancel)
        }
    }

    private func requireUnchanged(
        _ url: URL,
        expected: FileSystemSnapshot,
        shouldCancel: CancellationHandler
    ) throws {
        guard try optionalSnapshot(at: url, shouldCancel: shouldCancel) == expected else {
            throw FileOperationError.changedOutput(url.path(percentEncoded: false))
        }
    }

    // MARK: - File primitives

    private func copyItem(
        at source: URL,
        to destination: URL,
        shouldCancel: CancellationHandler
    ) throws {
        try checkCancellation(shouldCancel)
        let info = try entryInfo(at: source)
        switch info.kind {
        case .regularFile:
            try fileManager.copyItem(at: source, to: destination)
        case .symbolicLink:
            let target = try fileManager.destinationOfSymbolicLink(atPath: source.path(percentEncoded: false))
            try fileManager.createSymbolicLink(atPath: destination.path(percentEncoded: false), withDestinationPath: target)
        case .directory:
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            let entries = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
                options: [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for child in entries {
                try copyItem(
                    at: child,
                    to: destination.appending(path: child.lastPathComponent),
                    shouldCancel: shouldCancel)
            }
            if let attributes = try? fileManager.attributesOfItem(atPath: source.path(percentEncoded: false)) {
                var preserved: [FileAttributeKey: Any] = [:]
                preserved[.posixPermissions] = attributes[.posixPermissions]
                preserved[.modificationDate] = attributes[.modificationDate]
                try? fileManager.setAttributes(preserved, ofItemAtPath: destination.path(percentEncoded: false))
            }
        }
    }

    private func trashItem(at url: URL) throws -> URL {
        if let testTrashDirectory {
            try fileManager.createDirectory(at: testTrashDirectory, withIntermediateDirectories: true)
            var destination = testTrashDirectory.appending(path: url.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                destination = testTrashDirectory.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
            }
            try fileManager.moveItem(at: url, to: destination)
            return destination
        }
        var result: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &result)
        guard let result else {
            throw CocoaError(.fileNoSuchFile)
        }
        return result as URL
    }

    private func stagingURL(nextTo destination: URL, label: String) -> URL {
        destination.deletingLastPathComponent().appending(
            path: ".grapecompare-\(label)-\(UUID().uuidString)")
    }

    private func createDestinationParents(_ parents: [URL]) throws -> [URL] {
        var created: [URL] = []
        do {
            for parent in parents {
                if let kind = try optionalEntryKind(at: parent) {
                    guard kind == .directory else {
                        throw FileOperationError.staleDestination(parent.path(percentEncoded: false))
                    }
                    continue
                }
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: false)
                created.append(parent)
            }
            return created
        } catch {
            removeEmptyDirectories(created.reversed())
            throw error
        }
    }

    private func removeEmptyDirectories<S: Sequence>(_ directories: S) where S.Element == URL {
        for directory in directories {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false)),
                  entries.isEmpty else { continue }
            try? fileManager.removeItem(at: directory)
        }
    }

    private func isSameVolume(_ source: URL, _ destinationDirectory: URL) throws -> Bool {
        if forceCrossVolumeMoves { return false }
        var sourceInfo = stat()
        var destinationInfo = stat()
        guard source.path.withCString({ lstat($0, &sourceInfo) }) == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        guard destinationDirectory.path.withCString({ lstat($0, &destinationInfo) }) == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        return sourceInfo.st_dev == destinationInfo.st_dev
    }

    private func contentsEqual(
        _ left: URL,
        _ right: URL,
        shouldCancel: CancellationHandler
    ) throws -> Bool {
        let leftInfo = try entryInfo(at: left)
        let rightInfo = try entryInfo(at: right)
        guard leftInfo.kind == rightInfo.kind else { return false }
        switch leftInfo.kind {
        case .symbolicLink:
            return try fileManager.destinationOfSymbolicLink(atPath: left.path) ==
                fileManager.destinationOfSymbolicLink(atPath: right.path)
        case .regularFile:
            guard leftInfo.size == rightInfo.size else { return false }
            let leftHandle = try FileHandle(forReadingFrom: left)
            let rightHandle = try FileHandle(forReadingFrom: right)
            defer {
                try? leftHandle.close()
                try? rightHandle.close()
            }
            while true {
                try checkCancellation(shouldCancel)
                let leftData = try leftHandle.read(upToCount: 1_048_576) ?? Data()
                let rightData = try rightHandle.read(upToCount: 1_048_576) ?? Data()
                if leftData != rightData { return false }
                if leftData.isEmpty { return true }
            }
        case .directory:
            let leftEntries = try fileManager.contentsOfDirectory(atPath: left.path).sorted()
            let rightEntries = try fileManager.contentsOfDirectory(atPath: right.path).sorted()
            guard leftEntries == rightEntries else { return false }
            for name in leftEntries {
                if try !contentsEqual(
                    left.appending(path: name),
                    right.appending(path: name),
                    shouldCancel: shouldCancel) { return false }
            }
            return true
        }
    }

    // MARK: - Snapshots

    func snapshot(
        at url: URL,
        shouldCancel: CancellationHandler = { false }
    ) throws -> FileSystemSnapshot {
        guard let value = try optionalSnapshot(at: url, shouldCancel: shouldCancel) else {
            throw FileOperationError.sourceMissing(url.path(percentEncoded: false))
        }
        return value
    }

    private func optionalSnapshot(
        at url: URL,
        shouldCancel: CancellationHandler
    ) throws -> FileSystemSnapshot? {
        var info = stat()
        let path = url.path(percentEncoded: false)
        let status = path.withCString { lstat($0, &info) }
        if status != 0 {
            if errno == ENOENT { return nil }
            throw CocoaError(.fileReadUnknown)
        }
        var hasher = StableHasher()
        var itemCount = 0
        var byteCount: Int64 = 0
        let kind = try accumulateSnapshot(
            at: url,
            relativePath: "",
            hasher: &hasher,
            itemCount: &itemCount,
            byteCount: &byteCount,
            shouldCancel: shouldCancel)
        return FileSystemSnapshot(
            kind: kind,
            itemCount: itemCount,
            byteCount: byteCount,
            fingerprint: hasher.value)
    }

    private func accumulateSnapshot(
        at url: URL,
        relativePath: String,
        hasher: inout StableHasher,
        itemCount: inout Int,
        byteCount: inout Int64,
        shouldCancel: CancellationHandler
    ) throws -> FileSystemEntryKind {
        try checkCancellation(shouldCancel)
        let info = try entryInfo(at: url)
        itemCount += 1
        byteCount += info.size
        hasher.mix(relativePath)
        hasher.mix(info.kind.rawValue)
        hasher.mix(info.size)
        if info.kind != .symbolicLink {
            hasher.mix(Int64(info.mode))
            hasher.mix(info.modifiedSeconds)
            hasher.mix(info.modifiedNanoseconds)
        }

        switch info.kind {
        case .regularFile:
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            while true {
                try checkCancellation(shouldCancel)
                let data = try handle.read(upToCount: 1_048_576) ?? Data()
                if data.isEmpty { break }
                hasher.mix(data)
            }
        case .symbolicLink:
            let target = try fileManager.destinationOfSymbolicLink(atPath: url.path(percentEncoded: false))
            hasher.mix(target)
        case .directory:
            let entries = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for child in entries {
                let childPath = relativePath.isEmpty
                    ? child.lastPathComponent
                    : relativePath + "/" + child.lastPathComponent
                _ = try accumulateSnapshot(
                    at: child,
                    relativePath: childPath,
                    hasher: &hasher,
                    itemCount: &itemCount,
                    byteCount: &byteCount,
                    shouldCancel: shouldCancel)
            }
        }
        return info.kind
    }

    private func entryInfo(at url: URL) throws -> (
        kind: FileSystemEntryKind,
        size: Int64,
        mode: UInt16,
        modifiedSeconds: Int64,
        modifiedNanoseconds: Int64
    ) {
        var info = stat()
        let path = url.path(percentEncoded: false)
        guard path.withCString({ lstat($0, &info) }) == 0 else {
            if errno == ENOENT { throw FileOperationError.sourceMissing(path) }
            throw CocoaError(.fileReadUnknown)
        }
        let type = info.st_mode & mode_t(S_IFMT)
        let mode = UInt16(info.st_mode & 0o7777)
        let seconds = Int64(info.st_mtimespec.tv_sec)
        let nanoseconds = Int64(info.st_mtimespec.tv_nsec)
        switch type {
        case mode_t(S_IFREG): return (.regularFile, Int64(info.st_size), mode, seconds, nanoseconds)
        case mode_t(S_IFDIR): return (.directory, 0, mode, seconds, nanoseconds)
        case mode_t(S_IFLNK): return (.symbolicLink, Int64(info.st_size), mode, seconds, nanoseconds)
        default: throw FileOperationError.unsupportedEntry(path)
        }
    }

    private func optionalEntryKind(at url: URL) throws -> FileSystemEntryKind? {
        var info = stat()
        let path = url.path(percentEncoded: false)
        guard path.withCString({ lstat($0, &info) }) == 0 else {
            if errno == ENOENT { return nil }
            throw CocoaError(.fileReadUnknown)
        }
        let type = info.st_mode & mode_t(S_IFMT)
        switch type {
        case mode_t(S_IFREG): return .regularFile
        case mode_t(S_IFDIR): return .directory
        case mode_t(S_IFLNK): return .symbolicLink
        default: throw FileOperationError.unsupportedEntry(path)
        }
    }

    private func checkCancellation(_ shouldCancel: CancellationHandler) throws {
        if shouldCancel() { throw FileOperationError.cancelled }
    }
}

nonisolated enum FileOperationUndoRecord: Equatable, Sendable, Codable {
    case created(
        destination: URL,
        expectedOutput: FileSystemSnapshot,
        createdParents: [URL],
        displayPath: String)
    case replaced(
        destination: URL,
        backup: URL,
        expectedOutput: FileSystemSnapshot,
        expectedBackup: FileSystemSnapshot,
        displayPath: String)
    case moved(
        source: URL,
        destination: URL,
        expectedOutput: FileSystemSnapshot,
        createdParents: [URL],
        displayPath: String)
    case crossVolumeMoved(
        source: URL,
        destination: URL,
        trashedSource: URL,
        expectedOutput: FileSystemSnapshot,
        expectedTrashedSource: FileSystemSnapshot,
        createdParents: [URL],
        displayPath: String)
    case trashed(original: URL, trashed: URL, expectedOutput: FileSystemSnapshot, displayPath: String)

    var expectedOutput: FileSystemSnapshot {
        switch self {
        case .created(_, let value, _, _),
             .moved(_, _, let value, _, _),
             .trashed(_, _, let value, _): return value
        case .replaced(_, _, let value, _, _),
             .crossVolumeMoved(_, _, _, let value, _, _, _): return value
        }
    }

    var displayPath: String {
        switch self {
        case .created(_, _, _, let value),
             .moved(_, _, _, _, let value),
             .trashed(_, _, _, let value): return value
        case .replaced(_, _, _, _, let value),
             .crossVolumeMoved(_, _, _, _, _, _, let value): return value
        }
    }

    var createdParents: [URL] {
        switch self {
        case .created(_, _, let value, _),
             .moved(_, _, _, let value, _),
             .crossVolumeMoved(_, _, _, _, _, let value, _): return value
        case .replaced, .trashed: return []
        }
    }

    var accessCandidates: [URL] {
        switch self {
        case .created(let destination, _, let parents, _):
            return [destination.deletingLastPathComponent()] + parents
        case .replaced(let destination, let backup, _, _, _):
            return [destination.deletingLastPathComponent(), backup.deletingLastPathComponent()]
        case .moved(let source, let destination, _, let parents, _):
            return [source.deletingLastPathComponent(), destination.deletingLastPathComponent()] + parents
        case .crossVolumeMoved(let source, let destination, let trashed, _, _, let parents, _):
            return [source.deletingLastPathComponent(), destination.deletingLastPathComponent(),
                    trashed.deletingLastPathComponent()] + parents
        case .trashed(let original, let trashed, _, _):
            return [original.deletingLastPathComponent(), trashed.deletingLastPathComponent()]
        }
    }
}

nonisolated struct FileOperationProgressEstimator: Sendable {
    let totalBytes: Int64
    let totalOperations: Int
    let startedAt: Date

    func progress(
        completedOperations: Int,
        completedBytes: Int64,
        currentPath: String,
        at date: Date
    ) -> FileOperationProgress {
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        let rate: Double? = elapsed > 0 && completedBytes > 0
            ? Double(completedBytes) / elapsed
            : nil
        let remaining: TimeInterval?
        if let rate, rate.isFinite, rate > 0, totalBytes > completedBytes {
            remaining = max(0, Double(totalBytes - completedBytes) / rate)
        } else if elapsed > 0, completedOperations > 0, totalOperations > completedOperations {
            remaining = max(0, elapsed / Double(completedOperations) * Double(totalOperations - completedOperations))
        } else {
            remaining = nil
        }
        return FileOperationProgress(
            completedOperations: completedOperations,
            totalOperations: totalOperations,
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            currentPath: currentPath,
            bytesPerSecond: rate?.isFinite == true ? rate : nil,
            estimatedTimeRemaining: remaining?.isFinite == true ? remaining : nil)
    }
}

nonisolated private struct StableHasher {
    private(set) var value: UInt64 = 14_695_981_039_346_656_037

    mutating func mix(_ data: Data) {
        for byte in data {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
    }

    mutating func mix(_ string: String) {
        mix(Data(string.utf8))
        value ^= 0xFF
        value &*= 1_099_511_628_211
    }

    mutating func mix(_ integer: Int64) {
        var littleEndian = integer.littleEndian
        withUnsafeBytes(of: &littleEndian) { mix(Data($0)) }
    }
}
