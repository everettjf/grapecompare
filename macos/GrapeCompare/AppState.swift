import AppKit
import Combine
import SwiftUI

/// Appearance preference: follow system, force light, or force dark.
/// Colors throughout the app are semantic/opacity-based, so both schemes
/// render correctly; this is applied via NSApp.appearance.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
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

@MainActor
final class AppState: ObservableObject {
    enum Screen {
        case home, fileDiff, folderCompare
    }

    @Published var screen: Screen = .home
    /// diff 视图点"返回"时回到哪个页面
    private var diffReturnScreen: Screen = .home

    @Published var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            NSApp.appearance = appearance.nsAppearance
        }
    }

    // MARK: 文件比较

    @Published var leftFileURL: URL?
    @Published var rightFileURL: URL?
    @Published var diffLeftURL: URL?
    @Published var diffRightURL: URL?
    @Published var leftFileName = ""
    @Published var rightFileName = ""
    @Published var fileDiff: FileDiffResult?
    @Published var fileError: String?

    // MARK: 文件夹比较

    @Published var leftFolderURL: URL?
    @Published var rightFolderURL: URL?
    @Published var folderRoot: FolderNode?
    @Published var folderStats: FolderCompareStats?
    /// 每次完成文件夹比较自增，驱动视图重置展开状态
    @Published var treeVersion = 0

    @Published var isComparing = false
    @Published var demoError: String?

    /// 待处理的启动参数（`GrapeCompare <左> <右>`）
    private var pendingArgs: (left: URL, right: URL)?

    /// 启动时只记录参数，不在此触发比较：scene 构建期间改动 @Published
    /// 状态会导致窗口完全不创建（macOS 27 beta，与 .preferredColorScheme 同因）
    init() {
        let stored = UserDefaults.standard.string(forKey: "appearance")
        appearance = AppearanceMode(rawValue: stored ?? "") ?? .system
        // NB: NSApp.appearance is applied lazily on first change, not at init —
        // setting it during scene construction prevents window creation.

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
        isComparing = true
        folderRoot = nil
        folderStats = nil
        screen = .folderCompare
        Task {
            let root = await Task.detached(priority: .userInitiated) {
                FolderComparator.compare(leftRoot: l, rightRoot: r)
            }.value
            folderRoot = root
            folderStats = FolderComparator.stats(for: root)
            treeVersion += 1
            isComparing = false
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
        screen = diffReturnScreen
    }

    // MARK: 私有

    private func runFileDiff(left: URL?, right: URL?) {
        diffLeftURL = left
        diffRightURL = right
        leftFileName = left?.lastPathComponent ?? "(Missing)"
        rightFileName = right?.lastPathComponent ?? "(Missing)"
        isComparing = true
        fileDiff = nil
        fileError = nil
        screen = .fileDiff
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (FileDiffResult?, String?) in
                do {
                    // 映射大文件，避免在进入 diff 前就额外复制左右两份完整内容。
                    let ld = try left.map { try Data(contentsOf: $0, options: .mappedIfSafe) }
                    let rd = try right.map { try Data(contentsOf: $0, options: .mappedIfSafe) }
                    return (DiffEngine.compare(left: ld, right: rd), nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            fileDiff = outcome.0
            fileError = outcome.1
            isComparing = false
        }
    }
}
