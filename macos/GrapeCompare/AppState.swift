import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

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

@Observable
@MainActor
final class AppState {
    enum Screen: Equatable {
        case home, fileDiff, folderCompare, merge
    }

    enum ComparisonPhase: Equatable {
        case idle, file, folder, merge
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
    private var mergeOutputEncoding: TextFileEncoding = .utf8
    var liveUpdatesEnabled = true
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
    var reportActionError: String?
    var quickCompareError: String?

    var isComparingFile: Bool { comparisonPhase == .file }
    var isComparingFolder: Bool { comparisonPhase == .folder }
    var isComparingMerge: Bool { comparisonPhase == .merge }

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
        }
    }

    var workspaceIcon: String {
        switch screen {
        case .home: "plus.square"
        case .fileDiff: "doc.text.magnifyingglass"
        case .folderCompare: "folder.badge.questionmark"
        case .merge: "arrow.triangle.branch"
        }
    }

    @ObservationIgnored private var comparisonTask: Task<Void, Never>?
    @ObservationIgnored private var comparisonCancellation: ComparisonCancellation?
    @ObservationIgnored private var requestGeneration: UInt = 0
    @ObservationIgnored private var operationLeftRoot: URL?
    @ObservationIgnored private var operationRightRoot: URL?
    @ObservationIgnored private let sessionStore = ComparisonSessionStore()
    @ObservationIgnored private var restoredSecurityScopedURLs: [URL] = []
    @ObservationIgnored private var filesystemWatcher: FilesystemWatcher?
    @ObservationIgnored private var liveRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var watchedExactPaths: Set<String> = []
    @ObservationIgnored private var watchedRootPaths: [String] = []
    @ObservationIgnored private var isLiveRefresh = false
    @ObservationIgnored private let textComparisonOptionsDefaultsKey = "textComparisonOptions.v1"
    @ObservationIgnored private let liveUpdatesDefaultsKey = "liveUpdatesEnabled.v1"
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

    init() {
        let savedSessions = sessionStore.load()
        recentComparisons = savedSessions.recents
        resumableSession = savedSessions.current
        if UserDefaults.standard.object(forKey: liveUpdatesDefaultsKey) != nil {
            liveUpdatesEnabled = UserDefaults.standard.bool(forKey: liveUpdatesDefaultsKey)
        }
        if let data = UserDefaults.standard.data(forKey: textComparisonOptionsDefaultsKey),
           let stored = try? JSONDecoder().decode(TextComparisonOptions.self, from: data) {
            textComparisonOptions = stored
        }
    }

    func consumeQuickAction() {
        guard let bookmarks = UserDefaults.standard.array(forKey: quickActionBookmarksKey) as? [Data],
              bookmarks.count == 2 else { return }
        UserDefaults.standard.removeObject(forKey: quickActionBookmarksKey)
        do {
            let urls = try bookmarks.map { bookmark in
                var stale = false
                let url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale)
                guard !stale else { throw CocoaError(.fileReadUnknown) }
                retainSecurityScopedAccess(to: url)
                return url.standardizedFileURL
            }
            compareQuickItems(urls)
        } catch {
            quickCompareError = error.localizedDescription
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
        // Preserve the last complete tree during a live refresh so the folder
        // browser keeps its layout and selection until the replacement is ready.
        if !isLiveRefresh {
            folderRoot = nil
            folderStats = nil
            folderError = nil
        }
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
                self.folderError = nil
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
        if !isLiveRefresh {
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

    func openComparedFileExternally(left: Bool) {
        guard let url = left ? diffLeftURL : diffRightURL else { return }
        NSWorkspace.shared.open(url)
    }

    func revealComparedFileInFinder(left: Bool) {
        guard let url = left ? diffLeftURL : diffRightURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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

    var mergeOutputHasConflictMarkers: Bool {
        MergeOutputValidator.containsConflictMarkers(mergeOutputText)
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
        // A live refresh keeps the last complete comparison visible until its
        // replacement is ready. Clearing these values here makes the entire
        // comparison view alternate between results and a progress placeholder.
        if !isLiveRefresh {
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
        }
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
        comparisonTask = nil
        comparisonCancellation = nil
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
            exactURLs = [diffLeftURL, diffRightURL].compactMap { $0 }
            roots = exactURLs.map { $0.deletingLastPathComponent() }
        case .folderCompare:
            exactURLs = []
            roots = [leftFolderURL, rightFolderURL].compactMap { $0 }
        case .merge:
            exactURLs = [baseFileURL, oursFileURL, theirsFileURL].compactMap { $0 }
            roots = exactURLs.map { $0.deletingLastPathComponent() }
        case .home:
            return
        }
        guard !roots.isEmpty else { return }
        watchedExactPaths = Set(exactURLs.map { $0.standardizedFileURL.path(percentEncoded: false) })
        watchedRootPaths = roots.map { $0.standardizedFileURL.path(percentEncoded: false) }
        let watcher = FilesystemWatcher()
        filesystemWatcher = watcher
        watcher.start(watching: roots, exactFiles: exactURLs) { [weak self] changedURLs in
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
        pendingLiveEventCount = 0
        switch screen {
        case .fileDiff:
            runFileDiff(left: diffLeftURL, right: diffRightURL)
        case .folderCompare:
            startFolderCompare()
        case .merge:
            startThreeWayMerge()
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

}
