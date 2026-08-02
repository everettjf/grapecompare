import Foundation
import Observation

nonisolated final class FileOperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.withLock { cancelled = true }
    }

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }
}

struct FileOperationReviewPresentation: Identifiable {
    let id = UUID()
}

@Observable
@MainActor
final class FileOperationController {
    enum Phase: Equatable {
        case idle
        case preparing
        case ready
        case executing
        case finished
        case undoing
    }

    private let engine: FileOperationEngine
    private let journalStore: FileOperationJournalStore
    var drafts: [FileOperationDraft] = []
    var plan: FileOperationPlan?
    var phase: Phase = .idle
    var progress: FileOperationProgress?
    var failures: [FileOperationFailure] = []
    var errorMessage: String?
    var wasCancelled = false
    var reviewPresentation: FileOperationReviewPresentation?
    var failurePolicy: FileOperationFailurePolicy = .stopOnFirstFailure
    var historyPresented = false
    var persistenceWarning: String?
    private(set) var transactionHistory: [FileOperationTransaction]
    private(set) var mutationVersion = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cancellation: FileOperationCancellation?

    init(
        engine: FileOperationEngine = FileOperationEngine(),
        journalStore: FileOperationJournalStore = FileOperationJournalStore()
    ) {
        self.engine = engine
        self.journalStore = journalStore
        self.transactionHistory = journalStore.load()
    }

    var canUndo: Bool {
        lastTransaction != nil && phase != .executing && phase != .undoing && phase != .preparing
    }

    var lastTransaction: FileOperationTransaction? { transactionHistory.last }

    var recipe: FileOperationRecipe? { try? FileOperationRecipe(drafts: drafts) }

    func enqueue(_ incoming: [FileOperationDraft]) {
        guard phase != .executing, phase != .undoing else { return }
        for draft in incoming {
            drafts.removeAll { existing in
                sameEndpoint(existing, draft) || draftContains(draft, existing)
            }
            if drafts.contains(where: { draftContains($0, draft) }) { continue }
            drafts.append(draft)
        }
        drafts.sort {
            if $0.relativePath == $1.relativePath { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        resetReviewState()
    }

    func removeDraft(id: UUID) {
        guard phase != .executing, phase != .undoing else { return }
        drafts.removeAll { $0.id == id }
        resetReviewState()
    }

    func clearDrafts() {
        guard phase != .executing, phase != .undoing else { return }
        drafts.removeAll()
        resetReviewState()
    }

    func showReview() {
        guard !drafts.isEmpty, phase != .executing, phase != .undoing else { return }
        reviewPresentation = FileOperationReviewPresentation()
        preparePlan()
    }

    func showHistory() {
        guard phase != .executing, phase != .undoing else { return }
        synchronizePersistedHistory()
        historyPresented = true
    }

    func importRecipe(_ recipe: FileOperationRecipe, leftRoot: URL, rightRoot: URL) throws {
        let imported = try recipe.drafts(leftRoot: leftRoot, rightRoot: rightRoot)
        enqueue(imported)
    }

    func closeReview() {
        guard phase != .executing, phase != .undoing else { return }
        task?.cancel()
        cancellation?.cancel()
        task = nil
        cancellation = nil
        reviewPresentation = nil
    }

    func reviewDidDismiss() {
        guard phase != .executing, phase != .undoing else { return }
        if phase == .preparing {
            cancelWorker()
            phase = .idle
        }
        reviewPresentation = nil
    }

    func preparePlan() {
        guard !drafts.isEmpty, phase != .executing, phase != .undoing else { return }
        cancelWorker()
        phase = .preparing
        plan = nil
        progress = nil
        failures = []
        errorMessage = nil
        wasCancelled = false
        let snapshot = drafts
        let cancellation = FileOperationCancellation()
        self.cancellation = cancellation
        task = Task { [weak self, engine] in
            let worker = Task.detached(priority: .userInitiated) {
                try engine.prepare(drafts: snapshot, shouldCancel: { cancellation.isCancelled })
            }
            let result = await withTaskCancellationHandler {
                await worker.result
            } onCancel: {
                cancellation.cancel()
                worker.cancel()
            }
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let plan):
                self.plan = plan
                self.phase = .ready
            case .failure(let error):
                if !cancellation.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.phase = .idle
                }
            }
            self.task = nil
            self.cancellation = nil
        }
    }

    func executePlan() {
        guard let plan, phase == .ready else { return }
        cancelWorker()
        phase = .executing
        progress = nil
        failures = []
        errorMessage = nil
        wasCancelled = false
        let cancellation = FileOperationCancellation()
        let failurePolicy = self.failurePolicy
        self.cancellation = cancellation
        task = Task { [weak self, engine] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) {
                engine.execute(
                    plan,
                    failurePolicy: failurePolicy,
                    shouldCancel: { cancellation.isCancelled },
                    progress: { [self] update in
                        Task { @MainActor in self.progress = update }
                    })
            }.value
            if let transaction = result.transaction {
                self.transactionHistory.append(transaction)
                do {
                    let evicted = try self.journalStore.append(transaction)
                    for old in evicted {
                        self.transactionHistory.removeAll { $0.id == old.id }
                        engine.discard(old)
                    }
                    self.persistenceWarning = nil
                    self.synchronizePersistedHistory()
                } catch {
                    self.persistenceWarning = String(localized: "Operation completed, but its undo history could not be saved: \(error.localizedDescription)")
                }
            }
            self.failures = result.failures
            self.wasCancelled = result.wasCancelled
            self.phase = .finished
            self.progress = nil
            self.task = nil
            self.cancellation = nil
            if result.completedOperations > 0 {
                self.mutationVersion &+= 1
            }
            self.drafts.removeAll()
        }
    }

    func cancelCurrentWork() {
        cancellation?.cancel()
    }

    func undoLastTransaction() {
        synchronizePersistedHistory()
        guard let transaction = lastTransaction, canUndo else { return }
        cancelWorker()
        if reviewPresentation == nil {
            reviewPresentation = FileOperationReviewPresentation()
        }
        phase = .undoing
        progress = nil
        failures = []
        errorMessage = nil
        wasCancelled = false
        let cancellation = FileOperationCancellation()
        self.cancellation = cancellation
        task = Task { [weak self, engine] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try engine.undo(
                        transaction,
                        shouldCancel: { cancellation.isCancelled },
                        progress: { [self] update in
                            Task { @MainActor in self.progress = update }
                        })
                }
            }.value
            switch result {
            case .success:
                _ = self.transactionHistory.popLast()
                do {
                    try self.journalStore.remove(transactionID: transaction.id)
                    self.persistenceWarning = nil
                } catch {
                    self.persistenceWarning = String(localized: "Undo completed, but the saved history could not be updated: \(error.localizedDescription)")
                }
                self.phase = .finished
                self.mutationVersion &+= 1
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                self.phase = .finished
            }
            self.progress = nil
            self.task = nil
            self.cancellation = nil
        }
    }

    func clearHistory() {
        guard phase != .executing, phase != .undoing else { return }
        do {
            let removed = try journalStore.removeAll()
            for transaction in removed { engine.discard(transaction) }
            transactionHistory.removeAll()
        } catch {
            persistenceWarning = error.localizedDescription
        }
    }

    private func resetReviewState() {
        plan = nil
        progress = nil
        failures = []
        errorMessage = nil
        wasCancelled = false
        phase = .idle
    }

    private func synchronizePersistedHistory() {
        guard persistenceWarning == nil else { return }
        transactionHistory = journalStore.load()
    }

    private func cancelWorker() {
        task?.cancel()
        cancellation?.cancel()
        task = nil
        cancellation = nil
    }

    private func sameEndpoint(_ lhs: FileOperationDraft, _ rhs: FileOperationDraft) -> Bool {
        lhs.sourceSide == rhs.sourceSide &&
            lhs.relativePath == rhs.relativePath &&
            lhs.destinationURL == rhs.destinationURL
    }

    private func draftContains(_ parent: FileOperationDraft, _ child: FileOperationDraft) -> Bool {
        let bothIndependentTrash = parent.kind == .trash && child.kind == .trash &&
            parent.sourceSide != child.sourceSide
        guard !bothIndependentTrash else { return false }
        if parent.relativePath == child.relativePath { return true }
        let prefix = parent.relativePath.isEmpty ? "" : parent.relativePath + "/"
        return child.relativePath.hasPrefix(prefix)
    }
}
