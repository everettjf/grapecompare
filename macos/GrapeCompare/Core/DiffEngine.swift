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
    /// 所有差异行（kind != .equal）在 rows 中的下标，用于上一处/下一处导航
    var differenceRowIndices: [Int] = []

    var differenceCount: Int { differenceRowIndices.count }
}

nonisolated enum DiffEngine {
    /// Myers 精确 diff 允许的最大编辑距离；超过则退化为粗粒度 diff，避免内存爆炸
    static let maxEditDistance = 2000

    /// 比较两份数据（nil 视为空文件，用于文件夹对比中"仅一侧存在"的情况）
    static func compare(left: Data?, right: Data?) -> FileDiffResult {
        let ld = left ?? Data()
        let rd = right ?? Data()
        if ld == rd {
            return FileDiffResult(identical: true)
        }
        if isBinary(ld) || isBinary(rd) {
            return FileDiffResult(isBinary: true)
        }
        let lt = String(decoding: ld, as: UTF8.self)
        let rt = String(decoding: rd, as: UTF8.self)
        return diffText(left: lt, right: rt)
    }

    static func diffText(left: String, right: String) -> FileDiffResult {
        let a = splitLines(left)
        let b = splitLines(right)
        let ops = diff(old: a, new: b)
        return buildRows(ops)
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

    // MARK: - Myers O(ND) diff

    static func diff(old a: [String], new b: [String]) -> [LineOp] {
        // 去掉公共前缀/后缀，极大缩小 Myers 的工作集
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        var ae = a.count
        var be = b.count
        while ae > start, be > start, a[ae - 1] == b[be - 1] { ae -= 1; be -= 1 }

        var ops: [LineOp] = []
        ops.reserveCapacity(a.count + (b.count - be) + (ae - start))
        for i in 0..<start { ops.append(.equal(a[i])) }
        ops.append(contentsOf: myers(Array(a[start..<ae]), Array(b[start..<be])))
        for i in ae..<a.count { ops.append(.equal(a[i])) }
        return ops
    }

    private static func myers(_ a: [String], _ b: [String]) -> [LineOp] {
        let n = a.count
        let m = b.count
        if n == 0 { return b.map { .insert($0) } }
        if m == 0 { return a.map { .delete($0) } }

        let max = n + m
        var trace: [[Int: Int]] = []
        trace.reserveCapacity(min(max, maxEditDistance) + 1)
        var v: [Int: Int] = [1: 0]
        var foundD = -1

        outer: for d in 0...max {
            if d > maxEditDistance { break }
            trace.append(v)
            for k in stride(from: -d, through: d, by: 2) {
                var x: Int
                if k == -d || (k != d && (v[k - 1] ?? -1) < (v[k + 1] ?? -1)) {
                    x = v[k + 1] ?? 0
                } else {
                    x = (v[k - 1] ?? 0) + 1
                }
                var y = x - k
                while x < n, y < m, a[x] == b[y] { x += 1; y += 1 }
                v[k] = x
                if x >= n, y >= m {
                    foundD = d
                    break outer
                }
            }
        }

        guard foundD >= 0 else {
            // 差异过大：退化为"全部删除 + 全部插入"，保证正确性
            return a.map { .delete($0) } + b.map { .insert($0) }
        }

        // 回溯构造操作序列
        var ops: [LineOp] = []
        ops.reserveCapacity(n + m)
        var x = n
        var y = m
        if foundD > 0 {
            for d in stride(from: foundD, through: 1, by: -1) {
                let prevV = trace[d]
                let k = x - y
                let prevK: Int
                if k == -d || (k != d && (prevV[k - 1] ?? -1) < (prevV[k + 1] ?? -1)) {
                    prevK = k + 1
                } else {
                    prevK = k - 1
                }
                let prevX = prevV[prevK] ?? 0
                let prevY = prevX - prevK
                while x > prevX, y > prevY {
                    ops.append(.equal(a[x - 1]))
                    x -= 1
                    y -= 1
                }
                if x == prevX {
                    ops.append(.insert(b[y - 1]))
                    y -= 1
                } else {
                    ops.append(.delete(a[x - 1]))
                    x -= 1
                }
            }
        }
        while x > 0, y > 0 {
            ops.append(.equal(a[x - 1]))
            x -= 1
            y -= 1
        }
        return ops.reversed()
    }

    // MARK: - 构建对齐行

    static func buildRows(_ ops: [LineOp]) -> FileDiffResult {
        var result = FileDiffResult()
        var leftNo = 1
        var rightNo = 1
        var i = 0

        while i < ops.count {
            if case .equal(let s) = ops[i] {
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
                let (lr, rr) = changedRanges(deletes[p], inserts[p])
                result.rows.append(DiffRow(
                    id: result.rows.count, kind: .modified,
                    left: .init(number: leftNo, text: deletes[p], changedRange: lr),
                    right: .init(number: rightNo, text: inserts[p], changedRange: rr)))
                leftNo += 1
                rightNo += 1
                result.modifiedCount += 1
            }
            for d in deletes.dropFirst(paired) {
                result.rows.append(DiffRow(
                    id: result.rows.count, kind: .removed,
                    left: .init(number: leftNo, text: d, changedRange: nil),
                    right: nil))
                leftNo += 1
                result.removedCount += 1
            }
            for s in inserts.dropFirst(paired) {
                result.rows.append(DiffRow(
                    id: result.rows.count, kind: .added,
                    left: nil,
                    right: .init(number: rightNo, text: s, changedRange: nil)))
                rightNo += 1
                result.addedCount += 1
            }
        }

        result.differenceRowIndices = result.rows.indices.filter { result.rows[$0].kind != .equal }
        return result
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
