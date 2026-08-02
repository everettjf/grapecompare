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

@Observable
@MainActor
final class AppState {
    enum Screen: Equatable {
        case home, fileDiff, folderCompare
    }

    enum ComparisonPhase: Equatable {
        case idle, file, folder
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

    var isComparingFile: Bool { comparisonPhase == .file }
    var isComparingFolder: Bool { comparisonPhase == .folder }

    /// 待处理的启动参数（`GrapeCompare <左> <右>`）
    private var pendingArgs: (left: URL, right: URL)?
    @ObservationIgnored private var comparisonTask: Task<Void, Never>?
    @ObservationIgnored private var comparisonCancellation: ComparisonCancellation?
    @ObservationIgnored private var requestGeneration: UInt = 0
    @ObservationIgnored private var operationLeftRoot: URL?
    @ObservationIgnored private var operationRightRoot: URL?

    /// 启动时只记录参数，不在此触发比较：scene 构建期间改动 @Published
    /// 状态会导致窗口完全不创建（macOS 27 beta，与 .preferredColorScheme 同因）
    init() {
        let args = ProcessInfo.processInfo.arguments
        guard args.count >= 3 else { return }
        let l = URL(fileURLWithPath: args[1]).standardizedFileURL
        let r = URL(fileURLWithPath: args[2]).standardizedFileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: l.path(percentEncoded: false)),
              fm.fileExists(atPath: r.path(percentEncoded: false)) else { return }
        pendingArgs = (l, r)
    }

    /// 首个窗口出现后处理启动参数：目录走文件夹比较，其余走文件比较
    func consumePendingArgs() {
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
        diffReturnScreen = .home
        runFileDiff(left: l, right: r)
    }

    func startFolderCompare() {
        guard let l = leftFolderURL, let r = rightFolderURL else { return }
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

    func swapFolders() {
        swap(&leftFolderURL, &rightFolderURL)
        startFolderCompare()
    }

    func goHome() {
        cancelCurrentComparison()
        operations.clearDrafts()
        screen = .home
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
        screen = .fileDiff
        comparisonTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                // Mapping avoids the first full-size copy. DiffEngine applies a
                // separate text materialization limit before decoding.
                let ld = try left.map { try Data(contentsOf: $0, options: .mappedIfSafe) }
                let rd = try right.map { try Data(contentsOf: $0, options: .mappedIfSafe) }
                return try DiffEngine.compareCancellable(
                    left: ld,
                    right: rd,
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
            case .success(let diff): self.fileDiff = diff
            case .failure(let error):
                if !(error is CancellationError) {
                    self.fileError = error.localizedDescription
                }
            }
            self.finishComparison(request)
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
}
