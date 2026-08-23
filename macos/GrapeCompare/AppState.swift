import AppKit
import Observation
import SwiftUI

/// Appearance preference: follow system, force light, or force dark.
/// Colors throughout the app are semantic/opacity-based, so both schemes
/// render correctly; this is applied via NSApp.appearance.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .system: return "Follow System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@Observable
@MainActor
final class AppearanceSettings {
    var mode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "appearance")
            NSApp.appearance = mode.nsAppearance
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: "appearance")
        mode = AppearanceMode(rawValue: stored ?? "") ?? .system
    }
}

nonisolated final class ComparisonCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func cancel() {
        lock.withLock { value = true }
    }

    var isCancelled: Bool {
        lock.withLock { value }
    }
}

nonisolated private struct FileComparisonPayload: Sendable {
    let diff: FileDiffResult
    let leftText: TextSnapshot?
    let rightText: TextSnapshot?
    let textComparison: TextComparisonResult?
    let imageComparison: ImageDifferenceResult?
    let structuredDifferences: [StructuredDifference]?
}

nonisolated private struct MergePayload: Sendable {
    let base: TextSnapshot
    let ours: TextSnapshot
    let theirs: TextSnapshot
    let result: ThreeWayMergeResult
}

nonisolated private struct GitComparisonPayload: Sendable {
    let root: URL
    let references: [GitReference]
    let changes: [GitChange]
}

@Observable
@MainActor
final class AppState {
    enum Screen: Equatable {
        case home, fileDiff, folderCompare, merge, git
    }

    enum ComparisonPhase: Equatable {
        case idle, file, folder, merge, git
    }

    var screen: Screen = .home
    let operations = FileOperationController()
    /// diff 视图点"返回"时回到哪个页面
    private var diffReturnScreen: Screen = .home

    // MARK: 文件比较

    var leftFileURL: URL?
    var rightFileURL: URL?
    var diffLeftURL: URL?
    var diffRightURL: URL?
    var leftFileName = ""
    var rightFileName = ""
    var fileDiff: FileDiffResult?
    var fileError: String?
    var leftTextSnapshot: TextSnapshot?
    var rightTextSnapshot: TextSnapshot?
    var textComparison: TextComparisonResult?
    var imageComparison: ImageDifferenceResult?
    var structuredDifferences: [StructuredDifference]?
    var textComparisonOptions = TextComparisonOptions()
    var outputText = ""
    var outputVisible = false
    var outputIsDirty = false
    var outputError: String?
    private var hunkChoices: [DiffHunk.ID: TextSide] = [:]

    // MARK: 三方合并

    var baseFileURL: URL?
    var oursFileURL: URL?
    var theirsFileURL: URL?
    var mergeResult: ThreeWayMergeResult?
    var mergeOutputText = ""
    var mergeError: String?
    var mergeSaveError: String?
    var mergeOutputIsDirty = false
    var mergeChoices: [MergeConflict.ID: MergeConflictChoice] = [:]
    var selectedMergeConflictID: MergeConflict.ID?
    private var mergeChoiceUndoStack: [[MergeConflict.ID: MergeConflictChoice]] = []
    private var mergeChoiceRedoStack: [[MergeConflict.ID: MergeConflictChoice]] = []
    var mergeDestinationURL: URL?
    var mergeSentinelURL: URL?
    var isExternalMerge = false
    private var mergeOutputEncoding: TextFileEncoding = .utf8
    private var pendingExternalMerge = false
    private var externalMergeRequest: ExternalMergeRequest?

    // MARK: Git 比较

    var gitRepositoryURL: URL?
    var gitReferences: [GitReference] = []
    var gitChanges: [GitChange] = []
    var gitLeftTarget = "HEAD"
    var gitRightTarget = "WORKTREE"
    var gitError: String?

    // MARK: 文件夹比较

    var leftFolderURL: URL?
    var rightFolderURL: URL?
    var folderRoot: FolderNode?
    var folderStats: FolderCompareStats?
    var folderError: String?
    /// 每次完成文件夹比较自增，驱动视图重置展开状态
    var treeVersion = 0
    private var folderNeedsRefresh = false

    private(set) var comparisonPhase: ComparisonPhase = .idle
    var demoError: String?
    var recentComparisons: [ComparisonSession] = []
    var resumableSession: ComparisonSession?
    var sessionError: String?

    var isComparingFile: Bool { comparisonPhase == .file }
    var isComparingFolder: Bool { comparisonPhase == .folder }
    var isComparingMerge: Bool { comparisonPhase == .merge }
    var isComparingGit: Bool { comparisonPhase == .git }

    var workspaceHasUnsavedOutput: Bool { outputIsDirty || mergeOutputIsDirty }
    var workspaceIsBusy: Bool {
        comparisonPhase != .idle || operations.phase == .executing || operations.phase == .undoing
    }
    var canCloseWorkspaceItem: Bool { !workspaceIsBusy && !workspaceHasUnsavedOutput }

    var workspaceTitle: String {
        switch screen {
        case .home: return String(localized: "New Comparison")
        case .fileDiff: return "\(leftFileName) ↔ \(rightFileName)"
        case .folderCompare:
            return "\(leftFolderURL?.lastPathComponent ?? "Left") ↔ \(rightFolderURL?.lastPathComponent ?? "Right")"
        case .merge: return oursFileURL?.lastPathComponent ?? String(localized: "Merge")
        case .git: return gitRepositoryURL?.lastPathComponent ?? String(localized: "Git")
        }
    }

    var workspaceIcon: String {
        switch screen {
        case .home: "plus.square"
        case .fileDiff: "doc.text.magnifyingglass"
        case .folderCompare: "folder.badge.questionmark"
        case .merge: "arrow.triangle.branch"
        case .git: "point.3.connected.trianglepath.dotted"
        }
    }

    /// 待处理的启动参数（`GrapeCompare <左> <右>`）
    private var pendingArgs: (left: URL, right: URL)?
    @ObservationIgnored private var comparisonTask: Task<Void, Never>?
    @ObservationIgnored private var comparisonCancellation: ComparisonCancellation?
    @ObservationIgnored private var requestGeneration: UInt = 0
    @ObservationIgnored private var operationLeftRoot: URL?
    @ObservationIgnored private var operationRightRoot: URL?
    @ObservationIgnored private var gitTemporaryDirectories: [URL] = []
    @ObservationIgnored private let sessionStore = ComparisonSessionStore()
    @ObservationIgnored private var restoredSecurityScopedURLs: [URL] = []

    /// 启动时只记录参数，不在此触发比较：scene 构建期间改动 @Published
    /// 状态会导致窗口完全不创建（macOS 27 beta，与 .preferredColorScheme 同因）
    init(processLaunchArguments: Bool = true) {
        let savedSessions = sessionStore.load()
        recentComparisons = savedSessions.recents
        resumableSession = savedSessions.current
        guard processLaunchArguments else { return }
        let args = ProcessInfo.processInfo.arguments
        if let request = ExternalMergeRequest(commandLineArguments: args) {
            baseFileURL = request.baseURL
            oursFileURL = request.oursURL
            theirsFileURL = request.theirsURL
            mergeDestinationURL = request.destinationURL
            mergeSentinelURL = request.sentinelURL
            externalMergeRequest = request
            isExternalMerge = true
            pendingExternalMerge = true
            return
        }
        guard args.count >= 3 else { return }
        let l = URL(fileURLWithPath: args[1]).standardizedFileURL
        let r = URL(fileURLWithPath: args[2]).standardizedFileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: l.path(percentEncoded: false)),
              fm.fileExists(atPath: r.path(percentEncoded: false)) else { return }
        pendingArgs = (l, r)
    }

    func consumeQuickAction() {
        guard let paths = UserDefaults.standard.stringArray(forKey: quickActionPathsKey),
              paths.count == 2 else { return }
        UserDefaults.standard.removeObject(forKey: quickActionPathsKey)
        pendingArgs = (URL(fileURLWithPath: paths[0]).standardizedFileURL,
                       URL(fileURLWithPath: paths[1]).standardizedFileURL)
        consumePendingArgs()
    }

    /// 首个窗口出现后处理启动参数：目录走文件夹比较，其余走文件比较
    func consumePendingArgs() {
        if pendingExternalMerge {
            pendingExternalMerge = false
            startThreeWayMerge()
            return
        }
        guard let (l, r) = pendingArgs else { return }
        pendingArgs = nil
        var isDirL: ObjCBool = false
        var isDirR: ObjCBool = false
        let fm = FileManager.default
        fm.fileExists(atPath: l.path(percentEncoded: false), isDirectory: &isDirL)
        fm.fileExists(atPath: r.path(percentEncoded: false), isDirectory: &isDirR)
        if isDirL.boolValue, isDirR.boolValue {
            leftFolderURL = l
            rightFolderURL = r
            startFolderCompare()
        } else {
            leftFileURL = l
            rightFileURL = r
            startFileCompare()
        }
    }

    // MARK: 动作

    func startFileCompare() {
        guard let l = leftFileURL, let r = rightFileURL else { return }
        recordSession(kind: .files, urls: [l, r])
        diffReturnScreen = .home
        runFileDiff(left: l, right: r)
    }

    func startFolderCompare() {
        guard let l = leftFolderURL, let r = rightFolderURL else { return }
        recordSession(kind: .folders, urls: [l, r])
        if operationLeftRoot != l.standardizedFileURL || operationRightRoot != r.standardizedFileURL {
            operations.clearDrafts()
            operationLeftRoot = l.standardizedFileURL
            operationRightRoot = r.standardizedFileURL
        }
        let (request, cancellation) = beginComparison(.folder)
        folderRoot = nil
        folderStats = nil
        folderError = nil
        folderNeedsRefresh = false
        screen = .folderCompare
        comparisonTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                try FolderComparator.compareCancellable(
                    leftRoot: l,
                    rightRoot: r,
                    shouldCancel: { cancellation.isCancelled })
            }
            let result = await withTaskCancellationHandler {
                await worker.result
            } onCancel: {
                cancellation.cancel()
                worker.cancel()
            }
            guard let self,
                  !Task.isCancelled,
                  self.requestGeneration == request else { return }
            switch result {
            case .success(let root):
                self.folderRoot = root
                self.folderStats = FolderComparator.stats(for: root)
                self.treeVersion += 1
            case .failure(let error):
                if !(error is CancellationError) {
                    self.folderError = error.localizedDescription
                }
            }
            self.finishComparison(request)
        }
    }

    func startThreeWayMerge() {
        guard let baseURL = baseFileURL,
              let oursURL = oursFileURL,
              let theirsURL = theirsFileURL else { return }
        if !isExternalMerge { recordSession(kind: .merge, urls: [baseURL, oursURL, theirsURL]) }
        let (request, cancellation) = beginComparison(.merge)
        mergeResult = nil
        mergeError = nil
        mergeSaveError = nil
        mergeChoices.removeAll()
        selectedMergeConflictID = nil
        mergeChoiceUndoStack.removeAll()
        mergeChoiceRedoStack.removeAll()
        mergeOutputText = ""
        mergeOutputIsDirty = false
        screen = .merge
        comparisonTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                try Self.checkMergeCancellation(cancellation)
                let base = try TextSnapshot(data: Data(contentsOf: baseURL, options: .mappedIfSafe))
                let ours = try TextSnapshot(data: Data(contentsOf: oursURL, options: .mappedIfSafe))
                let theirs = try TextSnapshot(data: Data(contentsOf: theirsURL, options: .mappedIfSafe))
                try Self.checkMergeCancellation(cancellation)
                return MergePayload(
                    base: base,
                    ours: ours,
                    theirs: theirs,
                    result: ThreeWayMergeEngine.merge(base: base, ours: ours, theirs: theirs))
            }
            let result = await withTaskCancellationHandler {
                await worker.result
            } onCancel: {
                cancellation.cancel()
                worker.cancel()
            }
            guard let self,
                  !Task.isCancelled,
                  self.requestGeneration == request else { return }
            switch result {
            case .success(let payload):
                self.mergeResult = payload.result
                self.mergeOutputText = self.renderMergeDraft(payload.result)
                self.mergeOutputEncoding = payload.ours.encoding
                self.selectedMergeConflictID = payload.result.conflicts.first?.id
            case .failure(let error):
                if !(error is CancellationError) {
                    self.mergeError = error.localizedDescription
                }
            }
            self.finishComparison(request)
        }
    }

    func startGitComparison() {
        guard let selectedRepository = gitRepositoryURL else { return }
        recordSession(kind: .git, urls: [selectedRepository])
        let left = GitComparisonTarget.parse(gitLeftTarget)
        let right = GitComparisonTarget.parse(gitRightTarget)
        let (request, cancellation) = beginComparison(.git)
        gitError = nil
        screen = .git
        comparisonTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                try Self.checkMergeCancellation(cancellation)
                let root = try GitRepositoryComparator.repositoryRoot(at: selectedRepository)
                let references = try GitRepositoryComparator.references(in: root)
                let changes = try GitRepositoryComparator.changes(
                    in: root, from: left, to: right)
                return GitComparisonPayload(root: root, references: references, changes: changes)
            }
            let result = await withTaskCancellationHandler {
                await worker.result
            } onCancel: {
                cancellation.cancel()
                worker.cancel()
            }
            guard let self,
                  !Task.isCancelled,
                  self.requestGeneration == request else { return }
            switch result {
            case .success(let payload):
                self.gitRepositoryURL = payload.root
                self.gitReferences = payload.references
                self.gitChanges = payload.changes
            case .failure(let error):
                if !(error is CancellationError) {
                    self.gitError = error.localizedDescription
                }
            }
            self.finishComparison(request)
        }
    }

    func openGitChange(_ change: GitChange) {
        guard let repository = gitRepositoryURL else { return }
        do {
            let leftTarget = GitComparisonTarget.parse(gitLeftTarget)
            let rightTarget = GitComparisonTarget.parse(gitRightTarget)
            let leftPath = change.oldPath ?? change.path
            let leftURL = try materializeGitFile(
                repository: repository, target: leftTarget, path: leftPath, side: "left")
            let rightURL = try materializeGitFile(
                repository: repository, target: rightTarget, path: change.path, side: "right")
            diffReturnScreen = .git
            runFileDiff(left: leftURL, right: rightURL)
        } catch {
            gitError = error.localizedDescription
        }
    }

    func resolveMergeConflict(_ id: MergeConflict.ID, with choice: MergeConflictChoice) {
        guard let mergeResult else { return }
        recordMergeChoiceUndo()
        mergeChoices[id] = choice
        selectedMergeConflictID = id
        mergeOutputText = renderMergeDraft(mergeResult)
        mergeOutputIsDirty = true
    }

    func resolveSelectedMergeConflict(with choice: MergeConflictChoice) {
        guard let selectedMergeConflictID else { return }
        resolveMergeConflict(selectedMergeConflictID, with: choice)
        selectAdjacentMergeConflict(offset: 1, preferringUnresolved: true)
    }

    func resolveAllMergeConflicts(with choice: MergeConflictChoice) {
        guard let mergeResult, !mergeResult.conflicts.isEmpty else { return }
        recordMergeChoiceUndo()
        for conflict in mergeResult.conflicts { mergeChoices[conflict.id] = choice }
        mergeOutputText = renderMergeDraft(mergeResult)
        mergeOutputIsDirty = true
    }

    func selectAdjacentMergeConflict(offset: Int, preferringUnresolved: Bool = false) {
        guard let conflicts = mergeResult?.conflicts, !conflicts.isEmpty else { return }
        let current = conflicts.firstIndex { $0.id == selectedMergeConflictID } ?? (offset > 0 ? -1 : 0)
        for step in 1...conflicts.count {
            let index = (current + offset * step + conflicts.count * 2) % conflicts.count
            let candidate = conflicts[index]
            if !preferringUnresolved || mergeChoices[candidate.id] == nil {
                selectedMergeConflictID = candidate.id
                return
            }
        }
        let index = (current + offset + conflicts.count) % conflicts.count
        selectedMergeConflictID = conflicts[index].id
    }

    var canUndoMergeResolution: Bool { !mergeChoiceUndoStack.isEmpty }
    var canRedoMergeResolution: Bool { !mergeChoiceRedoStack.isEmpty }

    func undoMergeResolution() {
        guard let mergeResult, let previous = mergeChoiceUndoStack.popLast() else { return }
        mergeChoiceRedoStack.append(mergeChoices)
        mergeChoices = previous
        mergeOutputText = renderMergeDraft(mergeResult)
        mergeOutputIsDirty = true
    }

    func redoMergeResolution() {
        guard let mergeResult, let next = mergeChoiceRedoStack.popLast() else { return }
        mergeChoiceUndoStack.append(mergeChoices)
        mergeChoices = next
        mergeOutputText = renderMergeDraft(mergeResult)
        mergeOutputIsDirty = true
    }

    func updateMergeOutput(_ text: String) {
        guard mergeOutputText != text else { return }
        mergeOutputText = text
        mergeOutputIsDirty = true
    }

    func saveExternalMerge() {
        guard isExternalMerge,
              let request = externalMergeRequest,
              let result = mergeResult,
              mergeChoices.count >= result.conflictCount else { return }
        do {
            let snapshot = try TextSnapshot(text: mergeOutputText, encoding: mergeOutputEncoding)
            try request.complete(with: snapshot)
            mergeOutputIsDirty = false
            mergeSaveError = nil
            NSApp.terminate(nil)
        } catch {
            mergeSaveError = error.localizedDescription
        }
    }

    func cancelExternalMerge() {
        guard isExternalMerge else { return }
        NSApp.terminate(nil)
    }

    /// 从文件夹对比中打开某个文件的 diff（支持仅一侧存在的情况）
    func openDiff(for node: FolderNode) {
        guard !node.isFolder, let lf = leftFolderURL, let rf = rightFolderURL else { return }
        let l: URL? = node.left != nil ? lf.appending(path: node.relativePath) : nil
        let r: URL? = node.right != nil ? rf.appending(path: node.relativePath) : nil
        diffReturnScreen = .folderCompare
        runFileDiff(left: l, right: r)
    }

    func swapDiffSides() {
        swap(&diffLeftURL, &diffRightURL)
        runFileDiff(left: diffLeftURL, right: diffRightURL)
    }

    func updateTextComparisonOptions(_ options: TextComparisonOptions) {
        guard textComparisonOptions != options, !outputIsDirty else { return }
        textComparisonOptions = options
        runFileDiff(left: diffLeftURL, right: diffRightURL)
    }

    func showOutput() {
        outputVisible = true
    }

    func updateOutputText(_ text: String) {
        guard outputText != text else { return }
        outputText = text
        outputIsDirty = true
    }

    func accept(_ side: TextSide, hunkID: DiffHunk.ID) {
        guard let left = leftTextSnapshot,
              let right = rightTextSnapshot,
              let comparison = textComparison else { return }
        var session = TextOutputSession(
            left: left,
            right: right,
            comparison: comparison)
        for (id, choice) in hunkChoices {
            session.accept(choice, hunkID: id)
        }
        do {
            let currentOutput = try TextSnapshot(text: outputText, encoding: right.encoding)
            outputText = try session.acceptPreservingManualEdits(
                side, hunkID: hunkID, currentOutput: currentOutput).text
            hunkChoices[hunkID] = side
            outputVisible = true
            outputIsDirty = true
            outputError = nil
        } catch {
            outputError = error.localizedDescription
        }
    }

    func resetOutput() {
        guard let right = rightTextSnapshot else { return }
        hunkChoices.removeAll()
        outputText = right.text
        outputIsDirty = false
        outputError = nil
    }

    func saveOutput() {
        guard let destination = diffRightURL,
              let original = rightTextSnapshot else {
            outputError = String(localized: "A writable right-side file is required.")
            return
        }
        do {
            let currentData = try Data(contentsOf: destination, options: .mappedIfSafe)
            let current = try TextSnapshot(data: currentData)
            guard current.fingerprint == original.fingerprint,
                  current.byteCount == original.byteCount else {
                outputError = String(localized: "The right-side file changed on disk. Compare again before saving.")
                return
            }
            let edited = try TextSnapshot(text: outputText, encoding: original.encoding)
            try edited.encodedData().write(to: destination, options: .atomic)
            outputIsDirty = false
            outputError = nil
            runFileDiff(left: diffLeftURL, right: diffRightURL)
        } catch {
            outputError = error.localizedDescription
        }
    }

    func makePatch() throws -> String {
        guard let left = leftTextSnapshot,
              let right = rightTextSnapshot else {
            throw TextSnapshotError.unsupportedEncoding
        }
        return try UnifiedDiffWriter.makePatch(
            left: left,
            right: right,
            leftPath: "a/\(diffLeftURL?.lastPathComponent ?? "left")",
            rightPath: "b/\(diffRightURL?.lastPathComponent ?? "right")")
    }

    func swapFolders() {
        swap(&leftFolderURL, &rightFolderURL)
        startFolderCompare()
    }

    func goHome() {
        cancelCurrentComparison()
        operations.clearDrafts()
        screen = .home
    }

    func resumeLastSession() {
        guard let resumableSession else { return }
        openSession(resumableSession)
    }

    func openRecentComparison(_ session: ComparisonSession) {
        openSession(session)
    }

    func clearRecentComparisons() {
        do {
            try sessionStore.clear()
            recentComparisons = []
            resumableSession = nil
            sessionError = nil
        } catch {
            sessionError = error.localizedDescription
        }
    }

    func discardWorkspaceOutput() {
        outputIsDirty = false
        mergeOutputIsDirty = false
    }

    func loadFileDemo() {
        do {
            let pair = try DemoData.makeFilePair()
            leftFileURL = pair.left
            rightFileURL = pair.right
            startFileCompare()
        } catch {
            demoError = error.localizedDescription
        }
    }

    func loadFolderDemo() {
        do {
            let pair = try DemoData.makeFolderPair()
            leftFolderURL = pair.left
            rightFolderURL = pair.right
            startFolderCompare()
        } catch {
            demoError = error.localizedDescription
        }
    }

    func backFromDiff() {
        if isComparingFile { cancelCurrentComparison() }
        if diffReturnScreen == .folderCompare, folderNeedsRefresh {
            startFolderCompare()
        } else {
            screen = diffReturnScreen
        }
    }

    /// Keep a visible folder comparison current without interrupting an
    /// unrelated file diff. If the tree is off-screen, refresh it before the
    /// user returns instead.
    func handleFilesystemMutation() {
        if screen == .folderCompare {
            startFolderCompare()
        } else {
            folderNeedsRefresh = true
        }
    }

    // MARK: 私有

    private func runFileDiff(left: URL?, right: URL?) {
        diffLeftURL = left
        diffRightURL = right
        leftFileName = left?.lastPathComponent ?? String(localized: "Missing")
        rightFileName = right?.lastPathComponent ?? String(localized: "Missing")
        let (request, cancellation) = beginComparison(.file)
        fileDiff = nil
        fileError = nil
        leftTextSnapshot = nil
        rightTextSnapshot = nil
        textComparison = nil
        imageComparison = nil
        structuredDifferences = nil
        hunkChoices.removeAll()
        outputError = nil
        let textOptions = textComparisonOptions
        screen = .fileDiff
        comparisonTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                // Mapping avoids the first full-size copy. DiffEngine applies a
                // separate text materialization limit before decoding.
                let ld = try left.map { try Data(contentsOf: $0, options: .mappedIfSafe) }
                let rd = try right.map { try Data(contentsOf: $0, options: .mappedIfSafe) }
                let diff = try DiffEngine.compareCancellable(
                    left: ld,
                    right: rd,
                    shouldCancel: { cancellation.isCancelled })
                // Do not defeat DiffEngine's memory guard by materializing the same
                // oversized inputs again for text actions.
                let supportsTextActions = !diff.isTooLarge && !diff.isBinary
                let leftText = supportsTextActions
                    ? ld.flatMap { try? TextSnapshot(data: $0) }
                    : nil
                let rightText = supportsTextActions
                    ? rd.flatMap { try? TextSnapshot(data: $0) }
                    : nil
                let textComparison = leftText.flatMap { leftSnapshot in
                    rightText.map { rightSnapshot in
                        TextComparisonEngine.compare(
                            left: leftSnapshot,
                            right: rightSnapshot,
                            options: textOptions)
                    }
                }
                let extensions = [left?.pathExtension.lowercased(), right?.pathExtension.lowercased()]
                let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp"]
                let imageComparison: ImageDifferenceResult?
                if extensions.allSatisfy({ $0.map(imageExtensions.contains) == true }),
                   let ld, let rd,
                   let leftImage = try? ImageRaster.decode(ld),
                   let rightImage = try? ImageRaster.decode(rd) {
                    imageComparison = ImageComparisonEngine.compare(left: leftImage, right: rightImage)
                } else {
                    imageComparison = nil
                }
                let structuredFormat: StructuredFormat?
                if extensions.allSatisfy({ $0 == "json" }) {
                    structuredFormat = .json
                } else if extensions.allSatisfy({ $0 == "plist" }) {
                    structuredFormat = .propertyList
                } else {
                    structuredFormat = nil
                }
                let structuredDifferences: [StructuredDifference]?
                let maximumStructuredBytes = 64 * 1024 * 1024
                if let structuredFormat, let ld, let rd,
                   max(ld.count, rd.count) <= maximumStructuredBytes,
                   let leftValue = try? StructuredDataComparator.decode(ld, format: structuredFormat),
                   let rightValue = try? StructuredDataComparator.decode(rd, format: structuredFormat) {
                    structuredDifferences = StructuredDataComparator.compare(
                        left: leftValue,
                        right: rightValue)
                } else {
                    structuredDifferences = nil
                }
                return FileComparisonPayload(
                    diff: diff,
                    leftText: leftText,
                    rightText: rightText,
                    textComparison: textComparison,
                    imageComparison: imageComparison,
                    structuredDifferences: structuredDifferences)
            }
            let result = await withTaskCancellationHandler {
                await worker.result
            } onCancel: {
                cancellation.cancel()
                worker.cancel()
            }
            guard let self,
                  !Task.isCancelled,
                  self.requestGeneration == request else { return }
            switch result {
            case .success(let payload):
                self.fileDiff = payload.diff
                self.leftTextSnapshot = payload.leftText
                self.rightTextSnapshot = payload.rightText
                self.textComparison = payload.textComparison
                self.imageComparison = payload.imageComparison
                self.structuredDifferences = payload.structuredDifferences
                self.outputText = payload.rightText?.text ?? ""
                self.outputIsDirty = false
            case .failure(let error):
                if !(error is CancellationError) {
                    self.fileError = error.localizedDescription
                }
            }
            self.finishComparison(request)
        }
    }

    private func recordSession(kind: ComparisonSessionKind, urls: [URL]) {
        do {
            let bookmarks = try urls.map {
                try $0.bookmarkData(options: .withSecurityScope)
            }
            let session = ComparisonSession(
                kind: kind,
                displayNames: urls.map(\.lastPathComponent),
                bookmarks: bookmarks)
            let envelope = try sessionStore.record(session)
            recentComparisons = envelope.recents
            resumableSession = envelope.current
            sessionError = nil
        } catch {
            // A comparison must never fail merely because its optional history
            // could not be persisted (for example, an ephemeral demo URL).
            sessionError = error.localizedDescription
        }
    }

    private func openSession(_ session: ComparisonSession) {
        do {
            guard session.bookmarks.count == session.displayNames.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            var resolved: [URL] = []
            for bookmark in session.bookmarks {
                var stale = false
                let url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale)
                guard !stale, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                if url.startAccessingSecurityScopedResource() {
                    restoredSecurityScopedURLs.append(url)
                }
                resolved.append(url.standardizedFileURL)
            }
            switch session.kind {
            case .files:
                guard resolved.count == 2 else { throw CocoaError(.fileReadCorruptFile) }
                leftFileURL = resolved[0]
                rightFileURL = resolved[1]
                startFileCompare()
            case .folders:
                guard resolved.count == 2, resolved.allSatisfy(\.hasDirectoryPath) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                leftFolderURL = resolved[0]
                rightFolderURL = resolved[1]
                startFolderCompare()
            case .merge:
                guard resolved.count == 3 else { throw CocoaError(.fileReadCorruptFile) }
                baseFileURL = resolved[0]
                oursFileURL = resolved[1]
                theirsFileURL = resolved[2]
                startThreeWayMerge()
            case .git:
                guard resolved.count == 1, resolved[0].hasDirectoryPath else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                gitRepositoryURL = resolved[0]
                startGitComparison()
            }
            sessionError = nil
        } catch {
            sessionError = String(localized: "This saved comparison can no longer be opened: \(error.localizedDescription)")
        }
    }

    private func beginComparison(
        _ phase: ComparisonPhase
    ) -> (UInt, ComparisonCancellation) {
        cancelCurrentComparison()
        comparisonPhase = phase
        let cancellation = ComparisonCancellation()
        comparisonCancellation = cancellation
        return (requestGeneration, cancellation)
    }

    private func finishComparison(_ request: UInt) {
        guard requestGeneration == request else { return }
        comparisonPhase = .idle
        comparisonTask = nil
        comparisonCancellation = nil
    }

    private func cancelCurrentComparison() {
        requestGeneration &+= 1
        comparisonCancellation?.cancel()
        comparisonTask?.cancel()
        comparisonTask = nil
        comparisonCancellation = nil
        comparisonPhase = .idle
    }

    nonisolated private static func checkMergeCancellation(
        _ cancellation: ComparisonCancellation
    ) throws {
        if cancellation.isCancelled { throw CancellationError() }
    }

    private func renderMergeDraft(_ result: ThreeWayMergeResult) -> String {
        var output = ""
        for segment in result.segments {
            switch segment {
            case .resolved(let lines):
                output += lines.map { $0.content + $0.ending.text }.joined()
            case .conflict(let conflict):
                if let choice = mergeChoices[conflict.id] {
                    let selected: [TextLine]
                    switch choice {
                    case .base: selected = conflict.baseLines
                    case .ours: selected = conflict.oursLines
                    case .theirs: selected = conflict.theirsLines
                    case .both: selected = conflict.oursLines + conflict.theirsLines
                    }
                    output += selected.map { $0.content + $0.ending.text }.joined()
                } else {
                    output += "<<<<<<< ours\n"
                    output += conflict.oursLines.map { $0.content + "\n" }.joined()
                    output += "||||||| base\n"
                    output += conflict.baseLines.map { $0.content + "\n" }.joined()
                    output += "=======\n"
                    output += conflict.theirsLines.map { $0.content + "\n" }.joined()
                    output += ">>>>>>> theirs\n"
                }
            }
        }
        return output
    }

    private func recordMergeChoiceUndo() {
        mergeChoiceUndoStack.append(mergeChoices)
        mergeChoiceRedoStack.removeAll()
    }

    private func materializeGitFile(
        repository: URL,
        target: GitComparisonTarget,
        path: String,
        side: String
    ) throws -> URL? {
        if target == .workingTree {
            let url = repository.appending(path: path).standardizedFileURL
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
        }
        guard let data = try GitRepositoryComparator.fileData(
            in: repository, target: target, path: path) else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GrapeCompareGit-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        gitTemporaryDirectories.append(directory)
        let filename = "\(side)-\(URL(fileURLWithPath: path).lastPathComponent)"
        let destination = directory.appending(path: filename, directoryHint: .notDirectory)
        try data.write(to: destination, options: .atomic)
        return destination
    }
}
