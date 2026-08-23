import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

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
    let structuredError: String?
}

nonisolated private struct TextMergePayload: Sendable {
    let base: TextSnapshot
    let ours: TextSnapshot
    let theirs: TextSnapshot
    let result: ThreeWayMergeResult
}

nonisolated private struct ImageMergePayload: Sendable {
    let base: Data
    let ours: Data
    let theirs: Data
    let oursDifference: ImageDifferenceResult
    let theirsDifference: ImageDifferenceResult
}

nonisolated private enum MergePayload: Sendable {
    case text(TextMergePayload)
    case image(ImageMergePayload)
}

enum ImageMergeChoice: String, CaseIterable, Identifiable {
    case base, ours, theirs
    var id: Self { self }
}

nonisolated private struct GitComparisonPayload: Sendable {
    let root: URL
    let references: [GitReference]
    let changes: [GitChange]
    let leftCommit: GitCommit?
    let rightCommit: GitCommit?
    let worktrees: [GitWorktree]
    let branchContext: GitBranchContext
    let commitGraph: [GitCommitGraphRow]
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
    var structuredError: String?
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
    var imageMergeBaseData: Data?
    var imageMergeOursData: Data?
    var imageMergeTheirsData: Data?
    var imageMergeOursDifference: ImageDifferenceResult?
    var imageMergeTheirsDifference: ImageDifferenceResult?
    var imageMergeChoice: ImageMergeChoice?
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
    var gitLeftCommit: GitCommit?
    var gitRightCommit: GitCommit?
    var gitWorktrees: [GitWorktree] = []
    var gitBranchContext: GitBranchContext?
    var gitCommitGraph: [GitCommitGraphRow] = []
    var gitCommitGraphHasMore = false
    var isLoadingGitCommitGraph = false
    var gitReviewedChangeIDs: Set<GitChange.ID> = []
    var gitReviewNotes: [GitChange.ID: String] = [:]
    var gitSelectedChangeID: GitChange.ID?
    var gitRepositoryLibrary: [GitRepositoryLibraryEntry] = []
    var gitFileRevisions: [GitFileRevision] = []
    var gitHistoryPath: String?
    var gitHistoryError: String?
    var isLoadingGitHistory = false
    var gitHistoryHasMore = false
    var gitSelectedFileInspection: GitFileInspection?
    var gitLeftTarget = "HEAD"
    var gitRightTarget = "WORKTREE"
    var gitError: String?
    var liveUpdatesEnabled = true
    var liveNotificationsEnabled = false
    var liveUpdatePausedReason: String?
    var lastLiveRefresh: Date?
    private(set) var liveRefreshCount = 0

    // MARK: 文件夹比较

    var leftFolderURL: URL?
    var rightFolderURL: URL?
    var folderRoot: FolderNode?
    var folderStats: FolderCompareStats?
    var folderError: String?
    var compareFolderMetadata = false
    /// 每次完成文件夹比较自增，驱动视图重置展开状态
    var treeVersion = 0
    private var folderNeedsRefresh = false

    private(set) var comparisonPhase: ComparisonPhase = .idle
    var demoError: String?
    var recentComparisons: [ComparisonSession] = []
    var resumableSession: ComparisonSession?
    var sessionError: String?
    var gitActionError: String?
    var reportActionError: String?
    var quickCompareError: String?

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
    @ObservationIgnored private var gitHistoryTask: Task<Void, Never>?
    @ObservationIgnored private var gitHistoryCancellation: ComparisonCancellation?
    @ObservationIgnored private var gitHistoryGeneration: UInt = 0
    @ObservationIgnored private var gitHistoryRevision = "HEAD"
    @ObservationIgnored private let gitHistoryPageSize = 100
    @ObservationIgnored private let sessionStore = ComparisonSessionStore()
    @ObservationIgnored private let gitRepositoryLibraryStore = GitRepositoryLibraryStore()
    @ObservationIgnored private var restoredSecurityScopedURLs: [URL] = []
    @ObservationIgnored private var filesystemWatcher: FilesystemWatcher?
    @ObservationIgnored private var liveRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var watchedExactPaths: Set<String> = []
    @ObservationIgnored private var watchedRootPaths: [String] = []
    @ObservationIgnored private var isLiveRefresh = false
    @ObservationIgnored private let gitReviewDefaultsKey = "gitReviewedChanges.v1"
    @ObservationIgnored private let gitReviewNotesDefaultsKey = "gitReviewNotes.v1"
    @ObservationIgnored private let textComparisonOptionsDefaultsKey = "textComparisonOptions.v1"
    @ObservationIgnored private let liveUpdatesDefaultsKey = "liveUpdatesEnabled.v1"
    @ObservationIgnored private let liveNotificationsDefaultsKey = "liveNotificationsEnabled.v1"
    @ObservationIgnored private var pendingLiveEventCount = 0
    @ObservationIgnored private var sharedReportURL: URL?
    @ObservationIgnored private var sharingPicker: NSSharingServicePicker?
    @ObservationIgnored private var temporaryClipboardURLs: [URL] = []

    func compareQuickItems(_ urls: [URL]) {
        guard urls.count == 2 else {
            quickCompareError = String(localized: "Drop exactly two files or two folders.")
            return
        }
        let standardized = urls.map(\.standardizedFileURL)
        let folderFlags = standardized.map(\.hasDirectoryPath)
        guard folderFlags[0] == folderFlags[1] else {
            quickCompareError = String(localized: "Both items must be the same kind.")
            return
        }
        standardized.forEach { _ = $0.startAccessingSecurityScopedResource() }
        if folderFlags[0] {
            leftFolderURL = standardized[0]
            rightFolderURL = standardized[1]
            startFolderCompare()
        } else {
            leftFileURL = standardized[0]
            rightFileURL = standardized[1]
            startFileCompare()
        }
    }

    func pasteQuickComparisonSide(left: Bool) {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], let url = urls.first {
            assignQuickFile(url, left: left)
            return
        }
        guard let text = pasteboard.string(forType: .string) else {
            quickCompareError = String(localized: "The clipboard does not contain a file or text.")
            return
        }
        let data = Data(text.utf8)
        guard data.count <= 8 * 1_024 * 1_024 else {
            quickCompareError = String(localized: "Clipboard text exceeds the 8 MiB safety limit.")
            return
        }
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("GrapeCompare-Clipboard", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let destination = directory.appendingPathComponent(UUID().uuidString + ".txt")
            try data.write(to: destination, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            temporaryClipboardURLs.append(destination)
            assignQuickFile(destination, left: left)
        } catch {
            quickCompareError = error.localizedDescription
        }
    }

    private func assignQuickFile(_ url: URL, left: Bool) {
        guard !url.hasDirectoryPath else {
            quickCompareError = String(localized: "Paste a file or text for file comparison.")
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        if left { leftFileURL = url } else { rightFileURL = url }
        if leftFileURL != nil, rightFileURL != nil { startFileCompare() }
    }

    var canCreateComparisonReport: Bool {
        switch screen {
        case .home: false
        case .fileDiff: fileDiff != nil
        case .folderCompare: folderRoot != nil
        case .merge: mergeResult != nil || imageMergeBaseData != nil
        case .git: gitRepositoryURL != nil && gitError == nil
        }
    }

    func printComparisonReport() {
        guard let report = makeComparisonReport() else { return }
        let view = printableReportView(report)
        let operation = NSPrintOperation(view: view)
        operation.jobTitle = workspaceTitle
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    func exportComparisonReportPDF() {
        guard let report = makeComparisonReport() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = sanitizedReportFilename + ".pdf"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let view = printableReportView(report)
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        let savingURLKey = NSPrintInfo.AttributeKey.jobSavingURL
        info.dictionary()[savingURLKey] = destination
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = workspaceTitle
        operation.showsPrintPanel = false
        operation.showsProgressPanel = true
        if !operation.run() {
            reportActionError = String(localized: "The PDF report could not be created.")
        }
    }

    func shareComparisonReport() {
        guard let report = makeComparisonReport(),
              let contentView = NSApp.keyWindow?.contentView else { return }
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("GrapeCompare-Shared-Reports", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let destination = directory.appendingPathComponent(sanitizedReportFilename + ".pdf")
            let view = printableReportView(report)
            let info = NSPrintInfo.shared.copy() as! NSPrintInfo
            info.jobDisposition = .save
            let savingURLKey = NSPrintInfo.AttributeKey.jobSavingURL
            info.dictionary()[savingURLKey] = destination
            let operation = NSPrintOperation(view: view, printInfo: info)
            operation.jobTitle = workspaceTitle
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            guard operation.run() else {
                throw CocoaError(.fileWriteUnknown)
            }
            sharedReportURL = destination
            let picker = NSSharingServicePicker(items: [destination])
            sharingPicker = picker
            picker.show(
                relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        } catch {
            reportActionError = error.localizedDescription
        }
    }

    private var sanitizedReportFilename: String {
        let invalid = CharacterSet(charactersIn: "/:")
        let parts = workspaceTitle.components(separatedBy: invalid).filter { !$0.isEmpty }
        return (parts.joined(separator: "-").isEmpty ? "GrapeCompare" : parts.joined(separator: "-"))
            + "-comparison"
    }

    private func printableReportView(_ report: NSAttributedString) -> NSTextView {
        let width: CGFloat = 720
        let storage = NSTextStorage(attributedString: report)
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 900), textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.textContainerInset = NSSize(width: 28, height: 28)
        layout.ensureLayout(for: container)
        view.frame.size.height = max(900, layout.usedRect(for: container).height + 56)
        return view
    }

    private func makeComparisonReport() -> NSAttributedString? {
        guard canCreateComparisonReport else { return nil }
        let maximumLines = 20_000
        let maximumCharacters = 8 * 1_024 * 1_024
        var lines: [String] = ["GrapeCompare", workspaceTitle, Date().formatted(date: .long, time: .standard), ""]
        var characterBytes = lines.reduce(0) { $0 + $1.utf8.count + 1 }
        var truncated = false

        func append(_ line: String) {
            let lineBytes = line.utf8.count + 1
            guard lines.count < maximumLines, characterBytes + lineBytes <= maximumCharacters else {
                truncated = true
                return
            }
            lines.append(line)
            characterBytes += lineBytes
        }

        switch screen {
        case .fileDiff:
            if let diff = fileDiff {
                append("Added: \(diff.addedCount)    Removed: \(diff.removedCount)    Modified: \(diff.modifiedCount)")
                append("")
                for row in diff.rows {
                    if truncated { break }
                    let marker = switch row.kind {
                    case .equal: " "
                    case .added: "+"
                    case .removed: "−"
                    case .modified: "±"
                    }
                    append("\(marker) L\(row.left?.number.description ?? "-") R\(row.right?.number.description ?? "-")  \(row.left?.text ?? row.right?.text ?? "")")
                    if row.kind == .modified, let right = row.right?.text { append("  → \(right)") }
                }
            }
        case .folderCompare:
            if let stats = folderStats {
                append("Same: \(stats.same)    Different: \(stats.different)    Left only: \(stats.onlyLeft)    Right only: \(stats.onlyRight)")
            }
            append("")
            func walk(_ node: FolderNode) {
                guard !truncated else { return }
                if !node.relativePath.isEmpty { append("[\(node.status.rawValue)] \(node.relativePath)") }
                node.children?.forEach(walk)
            }
            if let folderRoot { walk(folderRoot) }
        case .merge:
            if let choice = imageMergeChoice {
                append("Image conflict resolution: \(choice.rawValue)")
                if let ours = imageMergeOursDifference {
                    append("Base ↔ Ours: \(ours.differingPixelCount) differing pixels")
                }
                if let theirs = imageMergeTheirsDifference {
                    append("Base ↔ Theirs: \(theirs.differingPixelCount) differing pixels")
                }
            } else if let result = mergeResult {
                append("Conflicts: \(result.conflictCount)    Resolved: \(mergeChoices.count)")
                append("")
                mergeOutputText.prefix(maximumCharacters)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .forEach { append(String($0)) }
            }
        case .git:
            append("Repository: \(gitRepositoryURL?.path ?? "")")
            append("Range: \(gitLeftTarget) ↔ \(gitRightTarget)    Changes: \(gitChanges.count)")
            append("")
            for change in gitChanges {
                if truncated { break }
                append("[\(change.stage.rawValue)] \(change.kind.rawValue)  \(change.oldPath.map { $0 + " → " } ?? "")\(change.path)")
            }
        case .home:
            return nil
        }
        if truncated { lines.append(""); lines.append("Report truncated at the safe export limit.") }

        let body = lines.joined(separator: "\n")
        let result = NSMutableAttributedString(string: body, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ])
        if let firstBreak = body.firstIndex(of: "\n") {
            result.addAttributes([
                .font: NSFont.systemFont(ofSize: 20, weight: .bold)
            ], range: NSRange(body.startIndex..<firstBreak, in: body))
        }
        return result
    }

    /// 启动时只记录参数，不在此触发比较：scene 构建期间改动 @Published
    /// 状态会导致窗口完全不创建（macOS 27 beta，与 .preferredColorScheme 同因）
    init(processLaunchArguments: Bool = true) {
        let savedSessions = sessionStore.load()
        recentComparisons = savedSessions.recents
        resumableSession = savedSessions.current
        gitRepositoryLibrary = gitRepositoryLibraryStore.load()
        if UserDefaults.standard.object(forKey: liveUpdatesDefaultsKey) != nil {
            liveUpdatesEnabled = UserDefaults.standard.bool(forKey: liveUpdatesDefaultsKey)
        }
        liveNotificationsEnabled = UserDefaults.standard.bool(forKey: liveNotificationsDefaultsKey)
        if let data = UserDefaults.standard.data(forKey: textComparisonOptionsDefaultsKey),
           let stored = try? JSONDecoder().decode(TextComparisonOptions.self, from: data) {
            textComparisonOptions = stored
        }
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
        if !isLiveRefresh { recordSession(kind: .files, urls: [l, r]) }
        diffReturnScreen = .home
        runFileDiff(left: l, right: r)
    }

    func startFolderCompare() {
        guard let l = leftFolderURL, let r = rightFolderURL else { return }
        if !isLiveRefresh { recordSession(kind: .folders, urls: [l, r]) }
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
        let compareMetadata = compareFolderMetadata
        comparisonTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                try FolderComparator.compareCancellable(
                    leftRoot: l,
                    rightRoot: r,
                    compareMetadata: compareMetadata,
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
        if !isExternalMerge && !isLiveRefresh {
            recordSession(kind: .merge, urls: [baseURL, oursURL, theirsURL])
        }
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
        imageMergeBaseData = nil
        imageMergeOursData = nil
        imageMergeTheirsData = nil
        imageMergeOursDifference = nil
        imageMergeTheirsDifference = nil
        imageMergeChoice = nil
        screen = .merge
        comparisonTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                try Self.checkMergeCancellation(cancellation)
                let baseData = try Data(contentsOf: baseURL, options: .mappedIfSafe)
                let oursData = try Data(contentsOf: oursURL, options: .mappedIfSafe)
                let theirsData = try Data(contentsOf: theirsURL, options: .mappedIfSafe)
                if let baseRaster = try? ImageRaster.decode(baseData),
                   let oursRaster = try? ImageRaster.decode(oursData),
                   let theirsRaster = try? ImageRaster.decode(theirsData) {
                    return MergePayload.image(ImageMergePayload(
                        base: baseData,
                        ours: oursData,
                        theirs: theirsData,
                        oursDifference: ImageComparisonEngine.compare(left: baseRaster, right: oursRaster),
                        theirsDifference: ImageComparisonEngine.compare(left: baseRaster, right: theirsRaster)))
                }
                let base = try TextSnapshot(data: baseData)
                let ours = try TextSnapshot(data: oursData)
                let theirs = try TextSnapshot(data: theirsData)
                try Self.checkMergeCancellation(cancellation)
                return MergePayload.text(TextMergePayload(
                    base: base,
                    ours: ours,
                    theirs: theirs,
                    result: ThreeWayMergeEngine.merge(base: base, ours: ours, theirs: theirs)))
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
            case .success(.image(let payload)):
                self.imageMergeBaseData = payload.base
                self.imageMergeOursData = payload.ours
                self.imageMergeTheirsData = payload.theirs
                self.imageMergeOursDifference = payload.oursDifference
                self.imageMergeTheirsDifference = payload.theirsDifference
            case .success(.text(let payload)):
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

    func chooseImageMerge(_ choice: ImageMergeChoice) {
        imageMergeChoice = choice
        mergeOutputIsDirty = true
    }

    func saveImageMerge() {
        guard let data = selectedImageMergeData else { return }
        if isExternalMerge, let request = externalMergeRequest {
            do {
                try request.complete(with: data)
                mergeOutputIsDirty = false
                NSApp.terminate(nil)
            } catch { mergeSaveError = error.localizedDescription }
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = oursFileURL?.lastPathComponent ?? "merged-image.png"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try data.write(to: destination, options: .atomic)
            mergeOutputIsDirty = false
        } catch { mergeSaveError = error.localizedDescription }
    }

    private var selectedImageMergeData: Data? {
        switch imageMergeChoice {
        case .base: imageMergeBaseData
        case .ours: imageMergeOursData
        case .theirs: imageMergeTheirsData
        case nil: nil
        }
    }

    func startGitComparison() {
        guard let selectedRepository = gitRepositoryURL else { return }
        if !isLiveRefresh { recordSession(kind: .git, urls: [selectedRepository]) }
        let left = GitComparisonTarget.parse(gitLeftTarget)
        let right = GitComparisonTarget.parse(gitRightTarget)
        let (request, cancellation) = beginComparison(.git)
        gitError = nil
        screen = .git
        comparisonTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                try Self.checkMergeCancellation(cancellation)
                let policy = GitCommandPolicy(isCancelled: { cancellation.isCancelled })
                let root = try GitRepositoryComparator.repositoryRoot(
                    at: selectedRepository, policy: policy)
                let references = try GitRepositoryComparator.references(in: root, policy: policy)
                let changes = try GitRepositoryComparator.changes(
                    in: root,
                    from: left,
                    to: right,
                    policy: policy)
                let leftCommit: GitCommit?
                if case .revision(let revision) = left {
                    leftCommit = try GitRepositoryComparator.commit(
                        in: root, revision: revision, policy: policy)
                } else {
                    leftCommit = nil
                }
                let rightCommit: GitCommit?
                if case .revision(let revision) = right {
                    rightCommit = try GitRepositoryComparator.commit(
                        in: root, revision: revision, policy: policy)
                } else {
                    rightCommit = nil
                }
                let worktrees = try GitRepositoryComparator.worktrees(in: root, policy: policy)
                let comparisonRevision: String
                if case .revision(let revision) = left { comparisonRevision = revision }
                else if case .revision(let revision) = right { comparisonRevision = revision }
                else { comparisonRevision = "HEAD" }
                let branchContext = try GitRepositoryComparator.branchContext(
                    in: root, comparisonRevision: comparisonRevision, policy: policy)
                let commitGraph = try GitRepositoryComparator.commitGraph(
                    in: root, limit: 200, policy: policy)
                return GitComparisonPayload(
                    root: root,
                    references: references,
                    changes: changes,
                    leftCommit: leftCommit,
                    rightCommit: rightCommit,
                    worktrees: worktrees,
                    branchContext: branchContext,
                    commitGraph: commitGraph)
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
                self.gitLeftCommit = payload.leftCommit
                self.gitRightCommit = payload.rightCommit
                self.gitWorktrees = payload.worktrees
                self.gitBranchContext = payload.branchContext
                self.gitCommitGraph = payload.commitGraph
                self.gitCommitGraphHasMore = payload.commitGraph.count == 200
                self.gitSelectedChangeID = payload.changes.first?.id
                self.gitReviewedChangeIDs = self.loadGitReviewedChanges(
                    repository: payload.root, changes: payload.changes)
                self.gitReviewNotes = self.loadGitReviewNotes(
                    repository: payload.root, changes: payload.changes)
                self.gitRepositoryLibrary = (try? self.gitRepositoryLibraryStore.remember(payload.root))
                    ?? self.gitRepositoryLibrary
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
            let selectedTargets = targets(for: change)
            let leftPath = change.oldPath ?? change.path
            let leftURL = try materializeGitFile(
                repository: repository, target: selectedTargets.left, path: leftPath, side: "left")
            let rightURL = try materializeGitFile(
                repository: repository, target: selectedTargets.right, path: change.path, side: "right")
            diffReturnScreen = .git
            runFileDiff(left: leftURL, right: rightURL)
        } catch {
            gitError = error.localizedDescription
        }
    }

    func selectAdjacentGitChange(forward: Bool) {
        guard !gitChanges.isEmpty else { return }
        let current = gitSelectedChangeID.flatMap { id in gitChanges.firstIndex { $0.id == id } }
        let index: Int
        if forward { index = min((current ?? -1) + 1, gitChanges.count - 1) }
        else { index = max((current ?? gitChanges.count) - 1, 0) }
        gitSelectedChangeID = gitChanges[index].id
        loadGitFileHistory(gitChanges[index])
    }

    func toggleGitReviewed(_ change: GitChange) {
        if gitReviewedChangeIDs.contains(change.id) { gitReviewedChangeIDs.remove(change.id) }
        else { gitReviewedChangeIDs.insert(change.id) }
        persistGitReviewedChanges()
    }

    func updateGitReviewNote(_ note: String, for change: GitChange) {
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            gitReviewNotes.removeValue(forKey: change.id)
        } else {
            gitReviewNotes[change.id] = note
        }
        persistGitReviewNotes()
    }

    func switchGitWorktree(_ worktree: GitWorktree) {
        gitRepositoryURL = worktree.path
        startGitComparison()
    }

    func compareGitChanges(since interval: TimeInterval) {
        guard let repository = gitRepositoryURL, interval > 0 else { return }
        let cutoff = Date().addingTimeInterval(-interval)
        let (request, cancellation) = beginComparison(.git)
        gitError = nil
        comparisonTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try GitRepositoryComparator.revision(
                        in: repository,
                        before: cutoff,
                        policy: GitCommandPolicy(isCancelled: { cancellation.isCancelled }))
                }
            }.value
            guard let self,
                  !Task.isCancelled,
                  self.requestGeneration == request,
                  !cancellation.isCancelled else { return }
            switch result {
            case .success(let revision):
                guard let revision else {
                    self.gitError = String(localized: "No commit exists before the selected time range.")
                    self.finishComparison(request)
                    return
                }
                self.gitLeftTarget = revision
                self.gitRightTarget = "WORKTREE"
                self.finishComparison(request)
                self.startGitComparison()
            case .failure(let error):
                if !(error is CancellationError) { self.gitError = error.localizedDescription }
                self.finishComparison(request)
            }
        }
    }

    func openGitCommitChangeset(_ commit: GitCommit) {
        guard let parent = commit.parentIDs.first else { return }
        useGitComparisonShortcut(left: parent, right: commit.objectID)
    }

    func revealGitRepositoryInFinder() {
        guard let repository = gitRepositoryURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([repository])
    }

    func openGitRepositoryInTerminal() {
        guard let repository = gitRepositoryURL else { return }
        NSWorkspace.shared.open(
            [repository],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: NSWorkspace.OpenConfiguration())
    }

    func openComparedFileExternally(left: Bool) {
        guard let url = left ? diffLeftURL : diffRightURL else { return }
        NSWorkspace.shared.open(url)
    }

    func revealComparedFileInFinder(left: Bool) {
        guard let url = left ? diffLeftURL : diffRightURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openGitRepositoryLibraryEntry(_ entry: GitRepositoryLibraryEntry) {
        do {
            let resolved = try gitRepositoryLibraryStore.resolve(entry)
            retainSecurityScopedAccess(to: resolved.url)
            gitRepositoryURL = resolved.url
            startGitComparison()
        } catch {
            gitError = error.localizedDescription
        }
    }

    func removeGitRepositoryLibraryEntry(_ entry: GitRepositoryLibraryEntry) {
        gitRepositoryLibrary = (try? gitRepositoryLibraryStore.remove(id: entry.id)) ?? gitRepositoryLibrary
    }

    func loadMoreGitCommitGraph() {
        guard let repository = gitRepositoryURL,
              gitCommitGraphHasMore, !isLoadingGitCommitGraph else { return }
        isLoadingGitCommitGraph = true
        let skip = gitCommitGraph.count
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try GitRepositoryComparator.commitGraph(
                    in: repository, limit: 200, skip: skip) }
            }.value
            guard let self else { return }
            switch result {
            case .success(let rows):
                let existing = Set(self.gitCommitGraph.map(\.id))
                self.gitCommitGraph.append(contentsOf: rows.filter { !existing.contains($0.id) })
                self.gitCommitGraphHasMore = rows.count == 200
            case .failure(let error): self.gitError = error.localizedDescription
            }
            self.isLoadingGitCommitGraph = false
        }
    }

    private func gitReviewKey(repository: URL) -> String {
        "\(repository.standardizedFileURL.path)\u{0}\(gitLeftTarget)\u{0}\(gitRightTarget)"
    }

    private func loadGitReviewedChanges(repository: URL, changes: [GitChange]) -> Set<GitChange.ID> {
        guard let data = UserDefaults.standard.data(forKey: gitReviewDefaultsKey),
              let stored = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [] }
        let valid = Set(changes.map(\.id))
        return Set(stored[gitReviewKey(repository: repository)] ?? []).intersection(valid)
    }

    private func persistGitReviewedChanges() {
        guard let repository = gitRepositoryURL else { return }
        var stored: [String: [String]] = [:]
        if let data = UserDefaults.standard.data(forKey: gitReviewDefaultsKey) {
            stored = (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
        }
        stored[gitReviewKey(repository: repository)] = gitReviewedChangeIDs.sorted()
        if stored.count > 100 {
            for key in stored.keys.sorted().prefix(stored.count - 100) { stored.removeValue(forKey: key) }
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: gitReviewDefaultsKey)
        }
    }

    private func loadGitReviewNotes(
        repository: URL, changes: [GitChange]
    ) -> [GitChange.ID: String] {
        guard let data = UserDefaults.standard.data(forKey: gitReviewNotesDefaultsKey),
              let stored = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return [:] }
        let valid = Set(changes.map(\.id))
        return (stored[gitReviewKey(repository: repository)] ?? [:]).filter {
            valid.contains($0.key)
        }
    }

    private func persistGitReviewNotes() {
        guard let repository = gitRepositoryURL else { return }
        var stored: [String: [String: String]] = [:]
        if let data = UserDefaults.standard.data(forKey: gitReviewNotesDefaultsKey) {
            stored = (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
        }
        stored[gitReviewKey(repository: repository)] = gitReviewNotes
        if stored.count > 100 {
            for key in stored.keys.sorted().prefix(stored.count - 100) { stored.removeValue(forKey: key) }
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: gitReviewNotesDefaultsKey)
        }
    }

    func loadGitFileHistory(_ change: GitChange) {
        guard let repository = gitRepositoryURL else { return }
        gitHistoryTask?.cancel()
        gitHistoryCancellation?.cancel()
        let cancellation = ComparisonCancellation()
        gitHistoryCancellation = cancellation
        gitHistoryGeneration &+= 1
        let generation = gitHistoryGeneration
        let right = GitComparisonTarget.parse(gitRightTarget)
        let left = GitComparisonTarget.parse(gitLeftTarget)
        let revision: String
        let path: String
        let selectedTargets = targets(for: change)
        let leftPath = change.oldPath ?? change.path
        if case .revision(let value) = right {
            revision = value
            path = change.path
        } else if case .revision(let value) = left {
            revision = value
            path = change.oldPath ?? change.path
        } else {
            revision = "HEAD"
            path = change.oldPath ?? change.path
        }
        gitHistoryPath = path
        gitHistoryRevision = revision
        gitFileRevisions = []
        gitHistoryHasMore = false
        gitSelectedFileInspection = nil
        gitHistoryError = nil
        isLoadingGitHistory = true
        let pageSize = gitHistoryPageSize
        gitHistoryTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    let revisions = try GitRepositoryComparator.fileRevisions(
                        in: repository,
                        path: path,
                        revision: revision,
                        limit: pageSize,
                        policy: GitCommandPolicy(isCancelled: { cancellation.isCancelled }))
                    let rightInspection = try GitRepositoryComparator.inspectFile(
                        in: repository,
                        target: selectedTargets.right,
                        path: change.path,
                        policy: GitCommandPolicy(isCancelled: { cancellation.isCancelled }))
                    let inspection = rightInspection.kind == .missing
                        ? try GitRepositoryComparator.inspectFile(
                            in: repository,
                            target: selectedTargets.left,
                            path: leftPath,
                            policy: GitCommandPolicy(isCancelled: { cancellation.isCancelled }))
                        : rightInspection
                    return (revisions, inspection)
                }
            }.value
            guard let self, !Task.isCancelled, self.gitHistoryGeneration == generation else { return }
            self.isLoadingGitHistory = false
            self.gitHistoryTask = nil
            self.gitHistoryCancellation = nil
            switch result {
            case .success(let payload):
                let revisions = payload.0
                self.gitFileRevisions = revisions
                self.gitHistoryHasMore = revisions.count == self.gitHistoryPageSize
                self.gitSelectedFileInspection = payload.1
            case .failure(let error):
                self.gitHistoryError = error.localizedDescription
            }
        }
    }

    func loadMoreGitFileHistory() {
        guard let repository = gitRepositoryURL,
              let path = gitHistoryPath,
              gitHistoryHasMore,
              !isLoadingGitHistory else { return }
        gitHistoryGeneration &+= 1
        let generation = gitHistoryGeneration
        let revision = gitHistoryRevision
        let skip = gitFileRevisions.count
        let pageSize = gitHistoryPageSize
        gitHistoryCancellation?.cancel()
        let cancellation = ComparisonCancellation()
        gitHistoryCancellation = cancellation
        gitHistoryError = nil
        isLoadingGitHistory = true
        gitHistoryTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try GitRepositoryComparator.fileRevisions(
                        in: repository,
                        path: path,
                        revision: revision,
                        limit: pageSize,
                        skip: skip,
                        policy: GitCommandPolicy(isCancelled: { cancellation.isCancelled }))
                }
            }.value
            guard let self, !Task.isCancelled, self.gitHistoryGeneration == generation else { return }
            self.isLoadingGitHistory = false
            self.gitHistoryTask = nil
            self.gitHistoryCancellation = nil
            switch result {
            case .success(let revisions):
                let existing = Set(self.gitFileRevisions.map(\.id))
                self.gitFileRevisions += revisions.filter { !existing.contains($0.id) }
                self.gitHistoryHasMore = revisions.count == pageSize && self.gitFileRevisions.count < 10_000
            case .failure(let error):
                self.gitHistoryError = error.localizedDescription
            }
        }
    }

    func useGitComparisonShortcut(left: String, right: String) {
        gitLeftTarget = left
        gitRightTarget = right
        startGitComparison()
    }

    func compareGitFileRevisions(_ left: GitFileRevision, _ right: GitFileRevision) {
        guard let repository = gitRepositoryURL else { return }
        do {
            let leftURL = try materializeGitFile(
                repository: repository,
                target: .revision(left.commit.objectID),
                path: left.path,
                side: "\(left.commit.shortObjectID)-left")
            let rightURL = try materializeGitFile(
                repository: repository,
                target: .revision(right.commit.objectID),
                path: right.path,
                side: "\(right.commit.shortObjectID)-right")
            diffReturnScreen = .git
            runFileDiff(left: leftURL, right: rightURL)
        } catch {
            gitHistoryError = error.localizedDescription
        }
    }

    func compareGitRevisionWithPrevious(_ revision: GitFileRevision) {
        guard let index = gitFileRevisions.firstIndex(where: { $0.id == revision.id }),
              gitFileRevisions.indices.contains(index + 1) else { return }
        compareGitFileRevisions(gitFileRevisions[index + 1], revision)
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
        guard !MergeOutputValidator.containsConflictMarkers(mergeOutputText) else {
            mergeSaveError = String(localized: "The merge output still contains conflict markers.")
            return
        }
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

    var mergeOutputHasConflictMarkers: Bool {
        MergeOutputValidator.containsConflictMarkers(mergeOutputText)
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
        if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: textComparisonOptionsDefaultsKey)
        }
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
        stopLiveUpdates()
        operations.clearDrafts()
        screen = .home
    }

    /// Ends all work and releases resources owned by this workspace. This is
    /// intentionally explicit because a closed SwiftUI workspace can remain
    /// retained briefly while views finish updating.
    func prepareForClose() {
        cancelCurrentComparison()
        stopLiveUpdates()
        operations.clearDrafts()
        for url in restoredSecurityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        restoredSecurityScopedURLs.removeAll(keepingCapacity: false)
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

    func setLiveUpdatesEnabled(_ enabled: Bool) {
        liveUpdatesEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: liveUpdatesDefaultsKey)
        liveUpdatePausedReason = nil
        if enabled { configureLiveUpdates() } else { stopLiveUpdates() }
    }

    func setLiveNotificationsEnabled(_ enabled: Bool) {
        liveNotificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: liveNotificationsDefaultsKey)
        guard enabled else { return }
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound])
                if !granted {
                    liveNotificationsEnabled = false
                    UserDefaults.standard.set(false, forKey: liveNotificationsDefaultsKey)
                    gitActionError = String(localized: "Notifications are disabled in System Settings.")
                }
            } catch {
                liveNotificationsEnabled = false
                UserDefaults.standard.set(false, forKey: liveNotificationsDefaultsKey)
                gitActionError = error.localizedDescription
            }
        }
    }

    func copyGitChangePath(_ change: GitChange) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(change.path, forType: .string)
    }

    func copyGitChangeContents(_ change: GitChange) {
        loadGitChangeContent(change) { data, _ in
            guard let text = String(data: data, encoding: .utf8) else {
                self.gitActionError = String(localized: "The selected file is not UTF-8 text.")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    func saveGitChangeCopy(_ change: GitChange) {
        loadGitChangeContent(change) { data, filename in
            let panel = NSSavePanel()
            panel.nameFieldStringValue = filename
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            do {
                try data.write(to: destination, options: .atomic)
            } catch {
                self.gitActionError = error.localizedDescription
            }
        }
    }

    func revealGitChangeInFinder(_ change: GitChange) {
        guard let url = workingTreeURL(for: change) else {
            gitActionError = String(localized: "This comparison side is not a working-tree file.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openGitChangeExternally(_ change: GitChange) {
        guard let url = workingTreeURL(for: change) else {
            gitActionError = String(localized: "This comparison side is not a working-tree file.")
            return
        }
        NSWorkspace.shared.open(url)
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
        structuredError = nil
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
                let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "svg"]
                let imageComparison: ImageDifferenceResult?
                if extensions.allSatisfy({ $0.map(imageExtensions.contains) == true }),
                   let ld, let rd,
                   let leftImage = try? ImageRaster.decode(ld, formatHint: extensions[0]),
                   let rightImage = try? ImageRaster.decode(rd, formatHint: extensions[1]) {
                    imageComparison = ImageComparisonEngine.compare(left: leftImage, right: rightImage)
                } else {
                    imageComparison = nil
                }
                let structuredFormat: StructuredFormat?
                if extensions.allSatisfy({ $0 == "json" || $0 == "xcstrings" }) {
                    structuredFormat = .json
                } else if extensions.allSatisfy({ $0 == "plist" }) {
                    structuredFormat = .propertyList
                } else {
                    structuredFormat = nil
                }
                var structuredDifferences: [StructuredDifference]?
                var structuredError: String?
                let maximumStructuredBytes = 64 * 1024 * 1024
                if extensions.allSatisfy({ $0 == "pbxproj" }), let ld, let rd,
                   max(ld.count, rd.count) <= maximumStructuredBytes,
                   let leftProject = try? PBXProjectComparator.decode(ld),
                   let rightProject = try? PBXProjectComparator.decode(rd) {
                    structuredDifferences = StructuredDataComparator.compare(
                        left: PBXProjectComparator.structuredValue(leftProject),
                        right: PBXProjectComparator.structuredValue(rightProject))
                } else if let ld, let rd,
                          let leftMachO = try? MachOInspector.inspect(ld),
                          let rightMachO = try? MachOInspector.inspect(rd) {
                    structuredDifferences = StructuredDataComparator.compare(
                        left: MachOInspector.structuredValue(leftMachO),
                        right: MachOInspector.structuredValue(rightMachO))
                } else if let structuredFormat, let ld, let rd,
                          max(ld.count, rd.count) <= maximumStructuredBytes {
                    do {
                        let leftValue = try StructuredDataComparator.decode(ld, format: structuredFormat)
                        do {
                            let rightValue = try StructuredDataComparator.decode(rd, format: structuredFormat)
                            structuredDifferences = StructuredDataComparator.compare(
                                left: leftValue,
                                right: rightValue)
                        } catch {
                            structuredError = "Invalid \(structuredFormat.displayName) in the right file: \(error.localizedDescription)"
                        }
                    } catch {
                        structuredError = "Invalid \(structuredFormat.displayName) in the left file: \(error.localizedDescription)"
                    }
                } else {
                    structuredDifferences = nil
                }
                return FileComparisonPayload(
                    diff: diff,
                    leftText: leftText,
                    rightText: rightText,
                    textComparison: textComparison,
                    imageComparison: imageComparison,
                    structuredDifferences: structuredDifferences,
                    structuredError: structuredError)
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
                self.structuredError = payload.structuredError
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
                retainSecurityScopedAccess(to: url)
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
        configureLiveUpdates()
    }

    private func cancelCurrentComparison() {
        requestGeneration &+= 1
        comparisonCancellation?.cancel()
        comparisonTask?.cancel()
        gitHistoryCancellation?.cancel()
        gitHistoryTask?.cancel()
        comparisonTask = nil
        comparisonCancellation = nil
        gitHistoryTask = nil
        gitHistoryCancellation = nil
        isLoadingGitHistory = false
        comparisonPhase = .idle
        stopLiveUpdates()
    }

    private func configureLiveUpdates() {
        stopLiveUpdates()
        guard liveUpdatesEnabled, comparisonPhase == .idle else { return }

        let roots: [URL]
        let exactURLs: [URL]
        switch screen {
        case .fileDiff:
            guard diffReturnScreen != .git else { return }
            exactURLs = [diffLeftURL, diffRightURL].compactMap { $0 }
            roots = exactURLs.map { $0.deletingLastPathComponent() }
        case .folderCompare:
            exactURLs = []
            roots = [leftFolderURL, rightFolderURL].compactMap { $0 }
        case .merge:
            guard !isExternalMerge else { return }
            exactURLs = [baseFileURL, oursFileURL, theirsFileURL].compactMap { $0 }
            roots = exactURLs.map { $0.deletingLastPathComponent() }
        case .git:
            exactURLs = []
            roots = [gitRepositoryURL].compactMap { $0 }
        case .home:
            return
        }
        guard !roots.isEmpty else { return }
        watchedExactPaths = Set(exactURLs.map { $0.standardizedFileURL.path(percentEncoded: false) })
        watchedRootPaths = roots.map { $0.standardizedFileURL.path(percentEncoded: false) }
        let watcher = FilesystemWatcher()
        filesystemWatcher = watcher
        watcher.start(watching: roots) { [weak self] changedURLs in
            Task { @MainActor [weak self] in self?.filesystemEventsArrived(changedURLs) }
        }
    }

    private func stopLiveUpdates() {
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
        filesystemWatcher?.stop()
        filesystemWatcher = nil
        watchedExactPaths.removeAll()
        watchedRootPaths.removeAll()
        pendingLiveEventCount = 0
    }

    private func retainSecurityScopedAccess(to url: URL) {
        let standardized = url.standardizedFileURL
        guard !restoredSecurityScopedURLs.contains(where: {
            $0.standardizedFileURL.path == standardized.path
        }) else { return }
        if standardized.startAccessingSecurityScopedResource() {
            restoredSecurityScopedURLs.append(standardized)
        }
    }

    private func filesystemEventsArrived(_ changedURLs: [URL]) {
        guard liveUpdatesEnabled, comparisonPhase == .idle else { return }
        let paths = changedURLs.map { $0.standardizedFileURL.path(percentEncoded: false) }
        let isRelevant: Bool
        if !watchedExactPaths.isEmpty {
            isRelevant = paths.contains { path in
                watchedExactPaths.contains(path) || watchedRootPaths.contains(path)
            }
        } else {
            isRelevant = paths.contains { path in
                watchedRootPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
            }
        }
        guard isRelevant else { return }
        pendingLiveEventCount = max(pendingLiveEventCount, changedURLs.count)
        if workspaceHasUnsavedOutput {
            liveUpdatePausedReason = String(localized: "Live updates are paused to protect unsaved output.")
            return
        }
        liveUpdatePausedReason = nil
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.liveRefreshTask = nil
            self.performLiveRefresh()
        }
    }

    private func performLiveRefresh() {
        guard comparisonPhase == .idle, !workspaceHasUnsavedOutput else { return }
        isLiveRefresh = true
        defer { isLiveRefresh = false }
        liveRefreshCount &+= 1
        lastLiveRefresh = Date()
        if screen == .git, liveNotificationsEnabled, pendingLiveEventCount > 0 {
            postGitLiveNotification(eventCount: pendingLiveEventCount)
        }
        pendingLiveEventCount = 0
        switch screen {
        case .fileDiff:
            runFileDiff(left: diffLeftURL, right: diffRightURL)
        case .folderCompare:
            startFolderCompare()
        case .merge:
            startThreeWayMerge()
        case .git:
            startGitComparison()
        case .home:
            break
        }
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

    private func targets(for change: GitChange) -> (left: GitComparisonTarget, right: GitComparisonTarget) {
        switch change.stage {
        case .staged:
            return (GitComparisonTarget.parse(gitLeftTarget), .index)
        case .unstaged, .untracked:
            return (.index, .workingTree)
        case .comparison:
            return (GitComparisonTarget.parse(gitLeftTarget), GitComparisonTarget.parse(gitRightTarget))
        }
    }

    private func loadGitChangeContent(
        _ change: GitChange,
        completion: @escaping (Data, String) -> Void
    ) {
        guard let repository = gitRepositoryURL else { return }
        let selectedTargets = targets(for: change)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result<(Data, String), Error> {
                    let policy = GitCommandPolicy(maximumOutputBytes: 8 * 1_024 * 1_024)
                    if let data = try GitRepositoryComparator.fileData(
                        in: repository, target: selectedTargets.right,
                        path: change.path, policy: policy) {
                        guard data.count <= 8 * 1_024 * 1_024 else {
                            throw CocoaError(.fileReadTooLarge)
                        }
                        return (data, URL(fileURLWithPath: change.path).lastPathComponent)
                    }
                    let leftPath = change.oldPath ?? change.path
                    guard let data = try GitRepositoryComparator.fileData(
                        in: repository, target: selectedTargets.left,
                        path: leftPath, policy: policy),
                          data.count <= 8 * 1_024 * 1_024 else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    return (data, URL(fileURLWithPath: leftPath).lastPathComponent)
                }
            }.value
            switch result {
            case .success(let value): completion(value.0, value.1)
            case .failure(let error): gitActionError = error.localizedDescription
            }
        }
    }

    private func workingTreeURL(for change: GitChange) -> URL? {
        guard let repository = gitRepositoryURL else { return nil }
        let selectedTargets = targets(for: change)
        guard selectedTargets.right == .workingTree else { return nil }
        let url = repository.appending(path: change.path).standardizedFileURL
        guard url.path.hasPrefix(repository.standardizedFileURL.path + "/"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func postGitLiveNotification(eventCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "GrapeCompare Git changes updated")
        let repositoryName = gitRepositoryURL?.lastPathComponent ?? String(localized: "Repository")
        content.body = String(localized: "\(repositoryName): \(eventCount) filesystem events refreshed.")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "grapecompare.git.\(UUID().uuidString)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
