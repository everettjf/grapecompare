import Foundation

/// 行级 diff 操作
nonisolated enum LineOp: Equatable, Sendable {
    case equal(String)
    case delete(String)
    case insert(String)
}

nonisolated enum DiffRowKind: Sendable {
    case equal, added, removed, modified
}

/// 并排 diff 视图中的一行（左右两侧对齐）
nonisolated struct DiffRow: Identifiable, Sendable {
    struct Side: Sendable {
        var number: Int
        var text: String
        /// modified 行中真正不同的字符区间（用于行内高亮）
        var changedRange: Range<String.Index>?
    }

    let id: Int
    var kind: DiffRowKind
    var left: Side?
    var right: Side?
}

/// 一次文件比较的完整结果
nonisolated struct FileDiffResult: Sendable {
    var rows: [DiffRow] = []
    var addedCount = 0
    var removedCount = 0
    var modifiedCount = 0
    var isBinary = false
    var identical = false
    var leftMissing = false
    var rightMissing = false
    var isTooLarge = false
    var maxLineLength = 0
    /// 两侧是否仅在文件末尾换行符的存在性上不同（仍会标记最后一行便于导航）。
    var finalNewlineDiffers = false
    /// 所有差异行（kind != .equal）在 rows 中的下标，用于上一处/下一处导航
    var differenceRowIndices: [Int] = []

    var differenceCount: Int { differenceRowIndices.count }
}

nonisolated enum DiffEngine {
    /// Above this size we still perform an exact mapped-data equality/binary check,
    /// but avoid materializing multiple full-size Strings and row arrays.
    static let maxTextDiffBytes = 256 * 1024 * 1024
    /// 先用很小的预算寻找精确 Myers 解；大改动会尽快转入锚点分段。
    private static let fastExactEditDistance = 256
    /// 单个无锚点片段的最大精确编辑距离，约束最坏情况的时间和轨迹内存。
    static let maxEditDistance = 2_000
    /// histogram 风格的低频行上限。先使用唯一行，无唯一行时再扩展到低频行。
    private static let lowOccurrenceLimit = 4
    private static let maxAnchorCandidates = 1_000_000

    /// 比较两份数据（nil 视为空文件，用于文件夹对比中"仅一侧存在"的情况）
    static func compare(left: Data?, right: Data?) -> FileDiffResult {
        try! compareCancellable(left: left, right: right)
    }

    static func compareCancellable(
        left: Data?, right: Data?,
        textDiffByteLimit: Int = maxTextDiffBytes,
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> FileDiffResult {
        try checkCancellation(shouldCancel)
        let leftMissing = left == nil
        let rightMissing = right == nil
        let ld = left ?? Data()
        let rd = right ?? Data()
        if !leftMissing, !rightMissing, ld == rd {
            return FileDiffResult(identical: true)
        }
        if isBinary(ld) || isBinary(rd) {
            return FileDiffResult(
                isBinary: true,
                leftMissing: leftMissing,
                rightMissing: rightMissing)
        }
        if max(ld.count, rd.count) > textDiffByteLimit {
            return FileDiffResult(
                leftMissing: leftMissing,
                rightMissing: rightMissing,
                isTooLarge: true)
        }
        try checkCancellation(shouldCancel)
        let lt = String(decoding: ld, as: UTF8.self)
        let rt = String(decoding: rd, as: UTF8.self)
        var result = try diffTextCancellable(left: lt, right: rt, shouldCancel: shouldCancel)
        result.leftMissing = leftMissing
        result.rightMissing = rightMissing
        return result
    }

    static func diffText(left: String, right: String) -> FileDiffResult {
        try! diffTextCancellable(left: left, right: right)
    }

    private static func diffTextCancellable(
        left: String, right: String,
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> FileDiffResult {
        try checkCancellation(shouldCancel)
        let a = splitLines(left)
        let b = splitLines(right)
        let ops = try diffCancellable(old: a, new: b, shouldCancel: shouldCancel)
        var result = try buildRowsCancellable(ops, shouldCancel: shouldCancel)
        if hasFinalNewline(left) != hasFinalNewline(right) {
            result.finalNewlineDiffers = true
            // 当内容行完全相同时，把最后一行纳入差异导航；标题会明确说明是末尾换行差异。
            if let lastIndex = result.rows.indices.last,
               result.rows[lastIndex].kind == .equal {
                result.rows[lastIndex].kind = .modified
                result.modifiedCount += 1
                result.differenceRowIndices.append(lastIndex)
            }
        }
        return result
    }

    private static func hasFinalNewline(_ text: String) -> Bool {
        text.unicodeScalars.last == "\n"
    }

    static func isBinary(_ data: Data) -> Bool {
        data.prefix(8000).contains(0)
    }

    /// 按行拆分，处理 \r\n，并去掉末尾换行产生的空尾巴。
    /// 注意：不能用 String.split(separator: "\n")——CRLF 在 Swift 中是单个 Character，
    /// 按 Character 拆分会匹配不到其中的 LF。
    static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines = text.components(separatedBy: "\n").map { s -> String in
            s.hasSuffix("\r") ? String(s.dropLast()) : s
        }
        // components 已按标量拆分：末元素为空即说明文本以 \n 结尾（grapheme cluster
        // 会让 String.hasSuffix("\n") 在 CRLF 文本上判断失效，不能用它）
        if lines.count > 1, lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }

    // MARK: - 自适应 Myers + 低频锚点 diff

    static func diff(old a: [String], new b: [String]) -> [LineOp] {
        try! diffCancellable(old: a, new: b)
    }

    static func diffCancellable(
        old a: [String], new b: [String],
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> [LineOp] {
        var ops: [LineOp] = []
        ops.reserveCapacity(max(a.count, b.count))
        try appendDiff(
            old: a, oldRange: 0..<a.count,
            new: b, newRange: 0..<b.count,
            depth: 0, shouldCancel: shouldCancel, to: &ops)
        return ops
    }

    /// 优先获得最短编辑脚本；超过快速预算后，以低频公共行切段，再在小段内精确求解。
    /// 这兼顾了小改动的最优性和大规模重写时的人类可读性/有界资源占用。
    private static func appendDiff(
        old a: [String], oldRange: Range<Int>,
        new b: [String], newRange: Range<Int>,
        depth: Int, shouldCancel: @Sendable () -> Bool,
        to ops: inout [LineOp]
    ) throws {
        try checkCancellation(shouldCancel)
        var oldStart = oldRange.lowerBound
        var newStart = newRange.lowerBound
        var oldEnd = oldRange.upperBound
        var newEnd = newRange.upperBound

        // 每个分段都裁剪公共前后缀，避免锚点之间的小段重复做无用功。
        while oldStart < oldEnd, newStart < newEnd, a[oldStart] == b[newStart] {
            ops.append(.equal(a[oldStart]))
            oldStart += 1
            newStart += 1
        }
        while oldEnd > oldStart, newEnd > newStart, a[oldEnd - 1] == b[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }

        if oldStart == oldEnd {
            for index in newStart..<newEnd { ops.append(.insert(b[index])) }
            for index in oldEnd..<oldRange.upperBound { ops.append(.equal(a[index])) }
            return
        }
        if newStart == newEnd {
            for index in oldStart..<oldEnd { ops.append(.delete(a[index])) }
            for index in oldEnd..<oldRange.upperBound { ops.append(.equal(a[index])) }
            return
        }

        let middleOld = oldStart..<oldEnd
        let middleNew = newStart..<newEnd
        let totalLength = middleOld.count + middleNew.count
        let fastLimit = min(fastExactEditDistance, totalLength)
        if let exact = try myers(
            old: a, oldRange: middleOld,
            new: b, newRange: middleNew,
            editDistanceLimit: fastLimit,
            shouldCancel: shouldCancel)
        {
            ops.append(contentsOf: exact)
            for index in oldEnd..<oldRange.upperBound { ops.append(.equal(a[index])) }
            return
        }

        let search = try findAnchors(
            old: a, oldRange: middleOld,
            new: b, newRange: middleNew,
            shouldCancel: shouldCancel)
        if !search.anchors.isEmpty, depth < 64 {
            var previousOld = oldStart
            var previousNew = newStart
            for anchor in search.anchors {
                try appendDiff(
                    old: a, oldRange: previousOld..<anchor.oldIndex,
                    new: b, newRange: previousNew..<anchor.newIndex,
                    depth: depth + 1, shouldCancel: shouldCancel, to: &ops)
                ops.append(.equal(a[anchor.oldIndex]))
                previousOld = anchor.oldIndex + 1
                previousNew = anchor.newIndex + 1
            }
            try appendDiff(
                old: a, oldRange: previousOld..<oldEnd,
                new: b, newRange: previousNew..<newEnd,
                depth: depth + 1, shouldCancel: shouldCancel, to: &ops)
        } else if search.hasCommonLine,
                  let exact = try myers(
                    old: a, oldRange: middleOld,
                    new: b, newRange: middleNew,
                    editDistanceLimit: min(maxEditDistance, totalLength),
                    shouldCancel: shouldCancel)
        {
            // 重复行过多、无法产生可靠锚点时，给 Myers 更大的精确预算。
            ops.append(contentsOf: exact)
        } else {
            // 没有公共行，或真正的超高编辑距离片段：整块替换是准确且最省资源的表达。
            for index in middleOld { ops.append(.delete(a[index])) }
            for index in middleNew { ops.append(.insert(b[index])) }
        }

        for index in oldEnd..<oldRange.upperBound { ops.append(.equal(a[index])) }
    }

    private struct Anchor {
        let oldIndex: Int
        let newIndex: Int
    }

    private struct AnchorSearch {
        let anchors: [Anchor]
        let hasCommonLine: Bool
    }

    /// 用固定大小的槽保存至多四个位置，避免为每个唯一行单独分配 Array。
    private struct Occurrences {
        private(set) var count = 0
        private var p0 = -1
        private var p1 = -1
        private var p2 = -1
        private var p3 = -1

        mutating func add(_ position: Int) {
            switch count {
            case 0: p0 = position
            case 1: p1 = position
            case 2: p2 = position
            case 3: p3 = position
            default: break
            }
            count += 1
        }

        subscript(_ offset: Int) -> Int {
            switch offset {
            case 0: return p0
            case 1: return p1
            case 2: return p2
            default: return p3
            }
        }
    }

    private struct AnchorCandidate {
        let oldIndex: Int
        let newIndex: Int
    }

    /// patience/histogram 风格锚点：先找两边都唯一的行；若没有，再接受出现不超过四次的行。
    private static func findAnchors(
        old a: [String], oldRange: Range<Int>,
        new b: [String], newRange: Range<Int>,
        shouldCancel: @Sendable () -> Bool
    ) throws -> AnchorSearch {
        var oldOccurrences: [String: Occurrences] = [:]
        var newOccurrences: [String: Occurrences] = [:]
        oldOccurrences.reserveCapacity(oldRange.count)
        newOccurrences.reserveCapacity(newRange.count)

        for index in oldRange {
            if index & 0x3FFF == 0 { try checkCancellation(shouldCancel) }
            oldOccurrences[a[index], default: Occurrences()].add(index)
        }
        for index in newRange {
            if index & 0x3FFF == 0 { try checkCancellation(shouldCancel) }
            newOccurrences[b[index], default: Occurrences()].add(index)
        }

        let hasCommonLine: Bool
        if oldOccurrences.count <= newOccurrences.count {
            hasCommonLine = oldOccurrences.keys.contains { newOccurrences[$0] != nil }
        } else {
            hasCommonLine = newOccurrences.keys.contains { oldOccurrences[$0] != nil }
        }
        guard hasCommonLine else { return AnchorSearch(anchors: [], hasCommonLine: false) }

        var candidates = anchorCandidates(
            old: a, oldRange: oldRange,
            oldOccurrences: oldOccurrences, newOccurrences: newOccurrences,
            occurrenceLimit: 1)
        if candidates.isEmpty {
            candidates = anchorCandidates(
                old: a, oldRange: oldRange,
                oldOccurrences: oldOccurrences, newOccurrences: newOccurrences,
                occurrenceLimit: lowOccurrenceLimit)
        }
        guard !candidates.isEmpty else {
            return AnchorSearch(anchors: [], hasCommonLine: true)
        }

        // 将匹配候选的右侧行号做严格递增 LIS，得到顺序一致的公共锚点。
        var tails: [Int] = []
        var predecessors = Array(repeating: -1, count: candidates.count)
        tails.reserveCapacity(min(oldRange.count, newRange.count))

        for candidateIndex in candidates.indices {
            let newIndex = candidates[candidateIndex].newIndex
            var low = 0
            var high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if candidates[tails[middle]].newIndex < newIndex {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            if low > 0 { predecessors[candidateIndex] = tails[low - 1] }
            if low == tails.count {
                tails.append(candidateIndex)
            } else {
                tails[low] = candidateIndex
            }
        }

        var anchors: [Anchor] = []
        anchors.reserveCapacity(tails.count)
        var cursor = tails.last ?? -1
        while cursor >= 0 {
            let candidate = candidates[cursor]
            anchors.append(Anchor(oldIndex: candidate.oldIndex, newIndex: candidate.newIndex))
            cursor = predecessors[cursor]
        }
        anchors.reverse()
        return AnchorSearch(anchors: anchors, hasCommonLine: true)
    }

    private static func anchorCandidates(
        old a: [String], oldRange: Range<Int>,
        oldOccurrences: [String: Occurrences],
        newOccurrences: [String: Occurrences],
        occurrenceLimit: Int
    ) -> [AnchorCandidate] {
        var estimatedCount = 0
        for (line, oldEntry) in oldOccurrences where oldEntry.count <= occurrenceLimit {
            guard let newEntry = newOccurrences[line], newEntry.count <= occurrenceLimit else { continue }
            estimatedCount += oldEntry.count * newEntry.count
            if estimatedCount > maxAnchorCandidates { return [] }
        }

        var candidates: [AnchorCandidate] = []
        candidates.reserveCapacity(estimatedCount)
        for oldIndex in oldRange {
            let line = a[oldIndex]
            guard let oldEntry = oldOccurrences[line], oldEntry.count <= occurrenceLimit,
                  let newEntry = newOccurrences[line], newEntry.count <= occurrenceLimit else { continue }
            // 同一个旧行的右侧候选倒序加入，确保严格 LIS 不会从同一旧行取两个匹配。
            for offset in stride(from: newEntry.count - 1, through: 0, by: -1) {
                candidates.append(AnchorCandidate(oldIndex: oldIndex, newIndex: newEntry[offset]))
            }
        }
        return candidates
    }

    /// 连续数组版 Myers O(ND)。字典版每层会产生大量哈希与小对象分配；连续轨迹更可预测。
    private static func myers(
        old a: [String], oldRange: Range<Int>,
        new b: [String], newRange: Range<Int>,
        editDistanceLimit: Int,
        shouldCancel: @Sendable () -> Bool
    ) throws -> [LineOp]? {
        let n = oldRange.count
        let m = newRange.count
        let limit = min(editDistanceLimit, n + m)
        let width = limit * 2 + 3
        let offset = limit + 1
        var frontier = Array(repeating: -1, count: width)
        frontier[offset + 1] = 0
        var trace: [[Int]] = []
        trace.reserveCapacity(limit + 1)

        for distance in 0...limit {
            if distance & 0x1F == 0 { try checkCancellation(shouldCancel) }
            trace.append(frontier)
            for diagonal in stride(from: -distance, through: distance, by: 2) {
                let slot = offset + diagonal
                let x: Int
                if diagonal == -distance
                    || (diagonal != distance && frontier[slot - 1] < frontier[slot + 1])
                {
                    x = frontier[slot + 1]
                } else {
                    x = frontier[slot - 1] + 1
                }
                var snakeX = x
                var snakeY = x - diagonal
                while snakeX < n, snakeY < m,
                      a[oldRange.lowerBound + snakeX] == b[newRange.lowerBound + snakeY]
                {
                    snakeX += 1
                    snakeY += 1
                }
                frontier[slot] = snakeX
                if snakeX >= n, snakeY >= m {
                    return backtrack(
                        old: a, oldStart: oldRange.lowerBound,
                        new: b, newStart: newRange.lowerBound,
                        oldCount: n, newCount: m,
                        distance: distance, trace: trace,
                        offset: offset)
                }
            }
        }
        return nil
    }

    private static func backtrack(
        old a: [String], oldStart: Int,
        new b: [String], newStart: Int,
        oldCount: Int, newCount: Int,
        distance: Int, trace: [[Int]], offset: Int
    ) -> [LineOp] {
        var reversed: [LineOp] = []
        reversed.reserveCapacity(oldCount + newCount)
        var x = oldCount
        var y = newCount

        if distance > 0 {
            for currentDistance in stride(from: distance, through: 1, by: -1) {
                let previous = trace[currentDistance]
                let diagonal = x - y
                let slot = offset + diagonal
                let previousDiagonal: Int
                if diagonal == -currentDistance
                    || (diagonal != currentDistance && previous[slot - 1] < previous[slot + 1])
                {
                    previousDiagonal = diagonal + 1
                } else {
                    previousDiagonal = diagonal - 1
                }
                let previousX = previous[offset + previousDiagonal]
                let previousY = previousX - previousDiagonal
                while x > previousX, y > previousY {
                    reversed.append(.equal(a[oldStart + x - 1]))
                    x -= 1
                    y -= 1
                }
                if x == previousX {
                    reversed.append(.insert(b[newStart + y - 1]))
                    y -= 1
                } else {
                    reversed.append(.delete(a[oldStart + x - 1]))
                    x -= 1
                }
            }
        }
        while x > 0, y > 0 {
            reversed.append(.equal(a[oldStart + x - 1]))
            x -= 1
            y -= 1
        }
        while x > 0 {
            reversed.append(.delete(a[oldStart + x - 1]))
            x -= 1
        }
        while y > 0 {
            reversed.append(.insert(b[newStart + y - 1]))
            y -= 1
        }
        return reversed.reversed()
    }

    // MARK: - 构建对齐行

    static func buildRows(_ ops: [LineOp]) -> FileDiffResult {
        try! buildRowsCancellable(ops)
    }

    private static func buildRowsCancellable(
        _ ops: [LineOp],
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> FileDiffResult {
        var result = FileDiffResult()
        result.rows.reserveCapacity(ops.count)
        var leftNo = 1
        var rightNo = 1
        var i = 0

        while i < ops.count {
            if i & 0x3FFF == 0 { try checkCancellation(shouldCancel) }
            if case .equal(let s) = ops[i] {
                result.maxLineLength = max(result.maxLineLength, s.count)
                result.rows.append(DiffRow(
                    id: result.rows.count, kind: .equal,
                    left: .init(number: leftNo, text: s, changedRange: nil),
                    right: .init(number: rightNo, text: s, changedRange: nil)))
                leftNo += 1
                rightNo += 1
                i += 1
                continue
            }

            // 一个变更块：连续的 delete / insert
            var deletes: [String] = []
            var inserts: [String] = []
            collect: while i < ops.count {
                switch ops[i] {
                case .delete(let s): deletes.append(s); i += 1
                case .insert(let s): inserts.append(s); i += 1
                case .equal: break collect
                }
            }

            let paired = min(deletes.count, inserts.count)
            for p in 0..<paired {
                result.maxLineLength = max(
                    result.maxLineLength,
                    max(deletes[p].count, inserts[p].count))
                let (lr, rr) = changedRanges(deletes[p], inserts[p])
                result.differenceRowIndices.append(result.rows.count)
                result.rows.append(DiffRow(
                    id: result.rows.count, kind: .modified,
                    left: .init(number: leftNo, text: deletes[p], changedRange: lr),
                    right: .init(number: rightNo, text: inserts[p], changedRange: rr)))
                leftNo += 1
                rightNo += 1
                result.modifiedCount += 1
            }
            for d in deletes.dropFirst(paired) {
                result.maxLineLength = max(result.maxLineLength, d.count)
                result.differenceRowIndices.append(result.rows.count)
                result.rows.append(DiffRow(
                    id: result.rows.count, kind: .removed,
                    left: .init(number: leftNo, text: d, changedRange: nil),
                    right: nil))
                leftNo += 1
                result.removedCount += 1
            }
            for s in inserts.dropFirst(paired) {
                result.maxLineLength = max(result.maxLineLength, s.count)
                result.differenceRowIndices.append(result.rows.count)
                result.rows.append(DiffRow(
                    id: result.rows.count, kind: .added,
                    left: nil,
                    right: .init(number: rightNo, text: s, changedRange: nil)))
                rightNo += 1
                result.addedCount += 1
            }
        }

        return result
    }

    private static func checkCancellation(
        _ shouldCancel: @Sendable () -> Bool
    ) throws {
        if shouldCancel() { throw CancellationError() }
    }

    /// 计算两行之间的公共前缀/后缀，返回各自真正不同的区间（行内高亮）
    static func changedRanges(_ a: String, _ b: String) -> (Range<String.Index>?, Range<String.Index>?) {
        if a == b { return (nil, nil) }
        var ai = a.startIndex
        var bi = b.startIndex
        while ai < a.endIndex, bi < b.endIndex, a[ai] == b[bi] {
            ai = a.index(after: ai)
            bi = b.index(after: bi)
        }
        var aj = a.endIndex
        var bj = b.endIndex
        while aj > ai, bj > bi {
            let ajp = a.index(before: aj)
            let bjp = b.index(before: bj)
            if a[ajp] != b[bjp] { break }
            aj = ajp
            bj = bjp
        }
        return (ai..<aj, bi..<bj)
    }
}
