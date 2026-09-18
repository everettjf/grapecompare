import Foundation

nonisolated enum AppLayoutPolicy {
    static let minimumContentWidth: CGFloat = 720
    static let minimumContentHeight: CGFloat = 560
    static let defaultContentWidth: CGFloat = 1120
    static let defaultContentHeight: CGFloat = 740
    static let wideReviewWidth: CGFloat = 1440
    static let wideReviewHeight: CGFloat = 900
}

nonisolated enum UIQualityPolicy {
    static let spacing: [CGFloat] = [4, 6, 8, 12, 16, 24]
    static let cornerRadii: [CGFloat] = [6, 10, 14, 18]
    static let compactControlHeight: CGFloat = 28
    static let regularControlHeight: CGFloat = 32
    static let statusAccentWidth: CGFloat = 3
    static let folderStatusColumnWidth: CGFloat = 132
}

nonisolated enum HomePresentationPolicy {
    static let primaryWorkflowCount = 2
    static let secondaryWorkflowCount = 1
    static let quickCompareItemCount = 2

    static func acceptsQuickCompareDrop(itemCount: Int) -> Bool {
        itemCount == quickCompareItemCount
    }

    /// 拖入数量相对「恰好两个」的偏离方向，用于给用户明确的上限提示。
    static func quickCompareDropIssue(itemCount: Int) -> QuickCompareDropIssue {
        if itemCount == quickCompareItemCount { return .none }
        return itemCount < quickCompareItemCount
            ? .tooFew(expected: quickCompareItemCount)
            : .tooMany(expected: quickCompareItemCount)
    }
}

/// 快速对比拖放的数量问题。
nonisolated enum QuickCompareDropIssue: Equatable, Sendable {
    case none
    case tooFew(expected: Int)
    case tooMany(expected: Int)
}

nonisolated enum ComparisonTopBarPolicy {
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 8
    static let groupSpacing: CGFloat = 10
    static let separatorHeight: CGFloat = 20
}

nonisolated enum AccessibilityPresentationPolicy {
    static let standardAnimationDuration = 0.16

    static func animationDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : standardAnimationDuration
    }

    static func directionalStatusName(_ status: CompareStatus) -> String {
        switch status {
        case .same: "Same on both sides"
        case .different: "Changed on both sides"
        case .onlyLeft: "Only on the left"
        case .onlyRight: "Only on the right"
        }
    }
}

nonisolated enum ComparisonPresentationPolicy {
    static let minimumCodeFontSize = 10.0
    static let maximumCodeFontSize = 18.0
    static let lineNumberGutterWidth: CGFloat = 46
    static let currentDifferenceAccentWidth: CGFloat = 3
    static let overviewWidth: CGFloat = 6
    /// 等宽系统字体每个 ASCII 字形的实际前进宽度比例（SF Mono / Menlo ≈ 633/1024 em）。
    /// 用它替代硬编码的字宽，确保横向内容宽度随字号缩放。
    static let monospacedAdvanceRatio: CGFloat = 633.0 / 1024.0
    /// 单侧文本列宽度的上限（点）。防止单行极长的文件把横向滚动区域拉得过宽。
    static let maximumColumnWidth: CGFloat = 80_000
    /// 行号栏与两侧留白占用的固定宽度（点）：46（行号栏）+ 10（行号右侧）+ 2（文本左侧）+ 2（余量）。
    static let columnGutterPadding: CGFloat = 60

    static func codeFontSize(_ requested: Double) -> Double {
        min(max(requested, minimumCodeFontSize), maximumCodeFontSize)
    }

    /// 计算并排 diff 中单侧文本列的渲染宽度（点）。
    /// - Parameters:
    ///   - viewportWidth: 单侧列在当前窗口中的可视宽度（点）。
    ///   - maxLineLength: 两侧文件中最长一行的字符数。
    ///   - fontSize: 实际使用的代码字号（已用 ``codeFontSize(_:)`` 收敛到合法区间）。
    ///   - wrapsLines: 是否开启自动换行；开启时列宽固定为可视宽度。
    static func contentColumnWidth(
        viewportWidth: CGFloat,
        maxLineLength: Int,
        fontSize: Double,
        wrapsLines: Bool
    ) -> CGFloat {
        guard !wrapsLines else { return max(0, viewportWidth) }
        let textWidth = CGFloat(maxLineLength) * monospacedAdvanceRatio * CGFloat(fontSize)
        return max(viewportWidth, min(textWidth + columnGutterPadding, maximumColumnWidth))
    }

    static func currentDifferenceRow(indices: [Int], position: Int) -> Int? {
        guard indices.indices.contains(position) else { return nil }
        return indices[position]
    }
}

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
