import Foundation

var failures = 0
func check(_ cond: Bool, _ name: String) {
    if cond { print("PASS: \(name)") } else { print("FAIL: \(name)"); failures += 1 }
}

// MARK: - DiffEngine 行级 diff

let t1 = DiffEngine.diffText(left: "a\nb\nc\n", right: "a\nb\nc\n")
check(t1.rows.allSatisfy { $0.kind == .equal } && t1.rows.count == 3, "identical text -> all equal")

let t2 = DiffEngine.diffText(left: "a\nb\nc\n", right: "a\nx\nc\n")
check(t2.rows.count == 3 && t2.rows[1].kind == .modified, "single line modify -> modified row")
check(t2.rows[1].left?.text == "b" && t2.rows[1].right?.text == "x", "modified row content")
check(t2.modifiedCount == 1 && t2.addedCount == 0 && t2.removedCount == 0, "modified stats")

let t3 = DiffEngine.diffText(left: "a\nc\n", right: "a\nb\nc\n")
check(t3.rows.count == 3 && t3.rows[1].kind == .added && t3.rows[1].left == nil, "insertion -> added row, left nil")
check(t3.rows[1].right?.number == 2, "added row right line number")

let t4 = DiffEngine.diffText(left: "a\nb\nc\n", right: "a\nc\n")
check(t4.rows.count == 3 && t4.rows[1].kind == .removed && t4.rows[1].right == nil, "deletion -> removed row, right nil")

let t5 = DiffEngine.diffText(left: "", right: "x\ny\n")
check(t5.rows.count == 2 && t5.rows.allSatisfy { $0.kind == .added }, "empty vs non-empty -> all added")

let t6 = DiffEngine.diffText(left: "hello world\n", right: "hello there\n")
check(t6.rows.count == 1 && t6.rows[0].kind == .modified, "prefix/suffix trim: one modified row")
if let lr = t6.rows[0].left?.changedRange, let txt = t6.rows[0].left?.text {
    check(String(txt[lr]) == "world", "left changed range is 'world' (got '\(String(txt[lr]))')")
} else { check(false, "left changed range exists") }
if let rr = t6.rows[0].right?.changedRange, let txt = t6.rows[0].right?.text {
    check(String(txt[rr]) == "there", "right changed range is 'there'")
} else { check(false, "right changed range exists") }

// CRLF 处理
let t7 = DiffEngine.diffText(left: "a\r\nb\r\n", right: "a\nb\n")
check(t7.rows.allSatisfy { $0.kind == .equal }, "CRLF vs LF treated equal")

// 大文件性能：100k 行，少量差异
var big1 = (0..<100_000).map { "line \($0)" }
var big2 = big1
big2[50_000] = "changed"
big2.insert("inserted", at: 80_000)
big1.remove(at: 10_000)
let t0 = Date()
let t8 = DiffEngine.diffText(left: big1.joined(separator: "\n"), right: big2.joined(separator: "\n"))
let elapsed = Date().timeIntervalSince(t0)
check(t8.modifiedCount == 1 && t8.addedCount == 2 && t8.removedCount == 0, "big file diff counts correct")
check(elapsed < 3.0, "big file diff fast (\(String(format: "%.2f", elapsed))s)")

// 行号对齐：插入后右侧行号偏移
let t9 = DiffEngine.diffText(left: "1\n2\n3\n4\n", right: "1\n2\nX\n3\n4\n")
check(t9.rows.last?.right?.number == 5 && t9.rows.last?.left?.number == 4, "line numbers aligned after insertion")

let finalNewline = DiffEngine.diffText(left: "same line", right: "same line\n")
check(finalNewline.finalNewlineDiffers && finalNewline.differenceCount == 1,
      "missing final newline is represented as a navigable difference")

// 小序列随机性质测试：操作必须能无损重建两侧，且 Myers 快速路径必须是最短编辑脚本。
struct DeterministicRandom {
    var state: UInt64 = 0x4752_4150_4543_4D50
    mutating func next(_ upperBound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int(state % UInt64(upperBound))
    }
}

func rebuild(_ operations: [LineOp]) -> (old: [String], new: [String], edits: Int) {
    var old: [String] = []
    var new: [String] = []
    var edits = 0
    for operation in operations {
        switch operation {
        case .equal(let line): old.append(line); new.append(line)
        case .delete(let line): old.append(line); edits += 1
        case .insert(let line): new.append(line); edits += 1
        }
    }
    return (old, new, edits)
}

func minimumEditCount(_ old: [String], _ new: [String]) -> Int {
    var previous = Array(0...new.count)
    for (oldIndex, oldLine) in old.enumerated() {
        var current = Array(repeating: 0, count: new.count + 1)
        current[0] = oldIndex + 1
        for (newIndex, newLine) in new.enumerated() {
            current[newIndex + 1] = oldLine == newLine
                ? previous[newIndex]
                : min(previous[newIndex + 1], current[newIndex]) + 1
        }
        previous = current
    }
    return previous[new.count]
}

var random = DeterministicRandom()
var randomDiffsAreValid = true
for _ in 0..<300 {
    let old = (0..<random.next(24)).map { _ in "token-\(random.next(8))" }
    let new = (0..<random.next(24)).map { _ in "token-\(random.next(8))" }
    let operations = DiffEngine.diff(old: old, new: new)
    let rebuilt = rebuild(operations)
    if rebuilt.old != old || rebuilt.new != new || rebuilt.edits != minimumEditCount(old, new) {
        randomDiffsAreValid = false
        break
    }
}
check(randomDiffsAreValid, "300 randomized diffs reconstruct exactly and use a shortest edit script")

// 大范围重写仍应保留稳定的公共结构，而不是超过固定 D 后把整个文件抹成一块。
let churnLineCount = 20_000
let churnLeft = (0..<churnLineCount).map {
    $0 % 100 == 0 ? "// MARK: \($0 / 100)" : "old-\($0)"
}
let churnRight = (0..<churnLineCount).map {
    $0 % 100 == 0 ? "// MARK: \($0 / 100)" : "new-\($0)"
}
let churnStart = Date()
let churnOps = DiffEngine.diff(old: churnLeft, new: churnRight)
let churnElapsed = Date().timeIntervalSince(churnStart)
let churnRebuilt = rebuild(churnOps)
let retainedAnchors = churnOps.reduce(into: 0) { count, operation in
    if case .equal = operation { count += 1 }
}
check(churnRebuilt.old == churnLeft && churnRebuilt.new == churnRight,
      "20k-line high-churn diff reconstructs both inputs")
check(retainedAnchors == churnLineCount / 100,
      "20k-line high-churn diff retains all \(churnLineCount / 100) structural anchors")
check(churnElapsed < 1.0, "20k-line high-churn diff fast (\(String(format: "%.3f", churnElapsed))s)")

let unrelatedCount = 20_000
let unrelatedLeft = (0..<unrelatedCount).map { "left-only-\($0)" }
let unrelatedRight = (0..<unrelatedCount).map { "right-only-\($0)" }
let unrelatedStart = Date()
let unrelatedOps = DiffEngine.diff(old: unrelatedLeft, new: unrelatedRight)
let unrelatedElapsed = Date().timeIntervalSince(unrelatedStart)
let unrelatedRebuilt = rebuild(unrelatedOps)
check(unrelatedRebuilt.old == unrelatedLeft && unrelatedRebuilt.new == unrelatedRight,
      "20k fully unrelated lines reconstruct exactly")
check(unrelatedElapsed < 1.0, "20k fully unrelated lines fast (\(String(format: "%.3f", unrelatedElapsed))s)")

// MARK: - DiffEngine.compare (Data)

let identical = DiffEngine.compare(left: Data("same".utf8), right: Data("same".utf8))
check(identical.identical, "compare: identical data")
let bin = DiffEngine.compare(left: Data([0, 1, 2, 0, 3]), right: Data([0, 1, 2, 0, 4]))
check(bin.isBinary, "compare: binary detected")
let oneSided = DiffEngine.compare(left: Data("a\nb\n".utf8), right: nil)
check(oneSided.rows.count == 2 && oneSided.rows.allSatisfy { $0.kind == .removed }, "compare: nil right -> all removed")

// MARK: - FolderComparator

let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "grapetest-\(UUID().uuidString)")
let L = tmp.appending(path: "L")
let R = tmp.appending(path: "R")
try! FileManager.default.createDirectory(at: L.appending(path: "sub"), withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: R.appending(path: "sub"), withIntermediateDirectories: true)
func write(_ s: String, _ url: URL) { try! Data(s.utf8).write(to: url) }

write("same content", L.appending(path: "same.txt"))
write("same content", R.appending(path: "same.txt"))
write("version 1", L.appending(path: "changed.txt"))
write("version 2", R.appending(path: "changed.txt"))
write("only left", L.appending(path: "onlyleft.txt"))
write("only right", R.appending(path: "onlyright.txt"))
write("nested same", L.appending(path: "sub/nested.txt"))
write("nested same", R.appending(path: "sub/nested.txt"))
write("nested diff A", L.appending(path: "sub/diff.txt"))
write("nested diff B", R.appending(path: "sub/diff.txt"))

let tree = FolderComparator.compare(leftRoot: L, rightRoot: R)
let nodes = tree.children ?? []
check(nodes.count == 5, "root has 5 children (got \(nodes.count))")

func node(_ name: String) -> FolderNode? { nodes.first { $0.name == name } }
check(node("same.txt")?.status == .same, "same.txt -> same")
check(node("changed.txt")?.status == .different, "changed.txt -> different")
check(node("onlyleft.txt")?.status == .onlyLeft, "onlyleft.txt -> onlyLeft")
check(node("onlyright.txt")?.status == .onlyRight, "onlyright.txt -> onlyRight")
check(node("sub")?.isFolder == true, "sub is folder")
check(node("sub")?.status == .different, "sub folder rollup -> different")
check(node("sub")?.children?.first { $0.name == "nested.txt" }?.status == .same, "sub/nested.txt -> same")
check(node("sub")?.children?.first { $0.name == "diff.txt" }?.status == .different, "sub/diff.txt -> different")
check(node("sub")?.containsDifferences == true && node("same.txt")?.containsDifferences == false, "containsDifferences")

// 内容相同但大小不同场景（前 1MB 分块逻辑）
write("abc", L.appending(path: "small-l.txt"))
write("abcd", R.appending(path: "small-r.txt"))

let stats = FolderComparator.stats(for: tree)
check(stats.same == 2 && stats.different == 2 && stats.onlyLeft == 1 && stats.onlyRight == 1,
      "stats: 2 same / 2 diff / 1 left / 1 right (got \(stats.same)/\(stats.different)/\(stats.onlyLeft)/\(stats.onlyRight))")

// 文件/目录类型冲突必须保留目录侧后代，并在统计中计为差异。
let edgeL = tmp.appending(path: "edge-L")
let edgeR = tmp.appending(path: "edge-R")
try! FileManager.default.createDirectory(at: edgeL, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: edgeR.appending(path: "conflict"), withIntermediateDirectories: true)
write("left is a file", edgeL.appending(path: "conflict"))
write("right child", edgeR.appending(path: "conflict/child.txt"))

// 包目录也必须递归，不能因为 .app 被系统视作 package 就漏掉内部差异。
try! FileManager.default.createDirectory(
    at: edgeL.appending(path: "Sample.app/Contents"), withIntermediateDirectories: true)
try! FileManager.default.createDirectory(
    at: edgeR.appending(path: "Sample.app/Contents"), withIntermediateDirectories: true)
write("version A", edgeL.appending(path: "Sample.app/Contents/version.txt"))
write("version B", edgeR.appending(path: "Sample.app/Contents/version.txt"))

// 符号链接按链接目标本身比较，不跟随并误读成普通文件/目录。
write("target", edgeL.appending(path: "target-a"))
write("target", edgeR.appending(path: "target-a"))
write("target", edgeL.appending(path: "target-b"))
write("target", edgeR.appending(path: "target-b"))
try! FileManager.default.createSymbolicLink(
    at: edgeL.appending(path: "same-link"), withDestinationURL: URL(fileURLWithPath: "target-a"))
try! FileManager.default.createSymbolicLink(
    at: edgeR.appending(path: "same-link"), withDestinationURL: URL(fileURLWithPath: "target-a"))
try! FileManager.default.createSymbolicLink(
    at: edgeL.appending(path: "changed-link"), withDestinationURL: URL(fileURLWithPath: "target-a"))
try! FileManager.default.createSymbolicLink(
    at: edgeR.appending(path: "changed-link"), withDestinationURL: URL(fileURLWithPath: "target-b"))

let edgeTree = FolderComparator.compare(leftRoot: edgeL, rightRoot: edgeR)
func findNode(_ path: String, in root: FolderNode) -> FolderNode? {
    if root.relativePath == path { return root }
    for child in root.children ?? [] {
        if let found = findNode(path, in: child) { return found }
    }
    return nil
}
let conflict = findNode("conflict", in: edgeTree)
check(conflict?.status == .different && conflict?.isFolder == true,
      "file vs directory at the same path -> different container")
check(conflict?.left?.isDirectory == false && conflict?.right?.isDirectory == true,
      "file vs directory preserves each side's type")
check(findNode("conflict/child.txt", in: edgeTree)?.status == .onlyRight,
      "file vs directory preserves directory-side descendants")
check(findNode("Sample.app", in: edgeTree)?.status == .different,
      "package directory contents are recursively compared")
check(findNode("same-link", in: edgeTree)?.status == .same,
      "equal symbolic-link targets -> same")
check(findNode("changed-link", in: edgeTree)?.status == .different,
      "different symbolic-link targets -> different")
let edgeStats = FolderComparator.stats(for: edgeTree)
check(edgeStats.different == 3, "folder stats include file/directory and link target differences")

try? FileManager.default.removeItem(at: tmp)

print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
