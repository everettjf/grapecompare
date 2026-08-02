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
let missingEmpty = DiffEngine.compare(left: nil, right: Data())
check(!missingEmpty.identical && missingEmpty.leftMissing && missingEmpty.rows.isEmpty,
      "compare: missing file is distinct from an empty file")
let emptyMissing = DiffEngine.compare(left: Data(), right: nil)
check(!emptyMissing.identical && emptyMissing.rightMissing && emptyMissing.rows.isEmpty,
      "compare: empty file is distinct from a missing file")
let limited = try! DiffEngine.compareCancellable(
    left: Data("abc".utf8), right: Data("abd".utf8), textDiffByteLimit: 2)
check(limited.isTooLarge && limited.rows.isEmpty,
      "compare: text materialization limit avoids building rows")
do {
    _ = try DiffEngine.diffCancellable(old: big1, new: big2, shouldCancel: { true })
    check(false, "diff cancellation throws")
} catch is CancellationError {
    check(true, "diff cancellation throws")
} catch {
    check(false, "diff cancellation throws expected error")
}

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

let stats = FolderComparator.stats(for: tree)
check(stats.same == 2 && stats.different == 2 && stats.onlyLeft == 1 && stats.onlyRight == 1,
      "stats: 2 same / 2 diff / 1 left / 1 right (got \(stats.same)/\(stats.different)/\(stats.onlyLeft)/\(stats.onlyRight))")

// 同一路径、大小不同必须直接判为不同。
let sizeL = tmp.appending(path: "size-L")
let sizeR = tmp.appending(path: "size-R")
try! FileManager.default.createDirectory(at: sizeL, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: sizeR, withIntermediateDirectories: true)
write("abc", sizeL.appending(path: "payload.bin"))
write("abcd", sizeR.appending(path: "payload.bin"))
let sizeTree = FolderComparator.compare(leftRoot: sizeL, rightRoot: sizeR)
check(sizeTree.children?.first?.status == .different,
      "same relative path with different sizes -> different")

do {
    _ = try FolderComparator.compareCancellable(
        leftRoot: tmp.appending(path: "does-not-exist"),
        rightRoot: R)
    check(false, "unreadable folder scan reports an error")
} catch is FolderScanError {
    check(true, "unreadable folder scan reports an error")
} catch {
    check(false, "unreadable folder scan reports expected error")
}

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

// MARK: - Safe file operations

let operationRoot = tmp.appending(path: "operations")
let operationTrash = operationRoot.appending(path: "Trash")
try! FileManager.default.createDirectory(at: operationRoot, withIntermediateDirectories: true)
let operationEngine = FileOperationEngine(testTrashDirectory: operationTrash)
func operationDirectory(_ name: String) -> URL {
    let url = operationRoot.appending(path: name)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
func readText(_ url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
}

// Copy to an absent destination, then remove only the verified created output on undo.
do {
    let root = operationDirectory("copy")
    let source = root.appending(path: "source.txt")
    let destination = root.appending(path: "destination.txt")
    write("copy payload", source)
    let draft = FileOperationDraft(
        kind: .copy, relativePath: "destination.txt", sourceSide: .left,
        sourceURL: source, destinationURL: destination)
    let plan = try operationEngine.prepare(drafts: [draft])
    let result = operationEngine.execute(plan)
    check(readText(destination) == "copy payload" && result.failures.isEmpty,
          "safe copy commits the reviewed source")
    try operationEngine.undo(result.transaction!)
    check(!FileManager.default.fileExists(atPath: destination.path) && readText(source) == "copy payload",
          "copy undo removes the unchanged output and preserves source")
} catch {
    check(false, "copy and undo complete without error: \(error)")
}

do {
    let root = operationDirectory("missing-parents")
    let sourceA = root.appending(path: "source-a.txt")
    let sourceB = root.appending(path: "source-b.txt")
    let destinationA = root.appending(path: "new/deep/a.txt")
    let destinationB = root.appending(path: "new/deep/b.txt")
    write("a", sourceA)
    write("b", sourceB)
    let drafts = [
        FileOperationDraft(kind: .copy, relativePath: "new/deep/a.txt", sourceSide: .left,
                           sourceURL: sourceA, destinationURL: destinationA),
        FileOperationDraft(kind: .copy, relativePath: "new/deep/b.txt", sourceSide: .left,
                           sourceURL: sourceB, destinationURL: destinationB)
    ]
    let plan = try operationEngine.prepare(drafts: drafts)
    check(plan.itemCount == 4, "preflight counts shared destination directories once")
    let result = operationEngine.execute(plan)
    check(readText(destinationA) == "a" && readText(destinationB) == "b" && result.failures.isEmpty,
          "multiple per-item copies can share destination parents created by the transaction")
    try operationEngine.undo(result.transaction!)
    check(!FileManager.default.fileExists(atPath: root.appending(path: "new").path),
          "undo removes destination parents that the transaction created and left empty")
} catch {
    check(false, "missing-parent copy and undo complete without error: \(error)")
}

// Replace retains the displaced item as a transaction backup and restores it on undo.
do {
    let root = operationDirectory("replace")
    let source = root.appending(path: "source.txt")
    let destination = root.appending(path: "destination.txt")
    write("new value", source)
    write("old value", destination)
    let draft = FileOperationDraft(
        kind: .replace, relativePath: "destination.txt", sourceSide: .left,
        sourceURL: source, destinationURL: destination)
    let result = operationEngine.execute(try operationEngine.prepare(drafts: [draft]))
    check(readText(destination) == "new value", "replace commits new value after backup")
    try operationEngine.undo(result.transaction!)
    check(readText(destination) == "old value", "replace undo restores the displaced value")
} catch {
    check(false, "replace and undo complete without error: \(error)")
}

do {
    let root = operationDirectory("replace-type-conflict")
    let source = root.appending(path: "source.txt")
    let destination = root.appending(path: "destination")
    write("file replaces folder", source)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    write("original child", destination.appending(path: "child.txt"))
    let draft = FileOperationDraft(
        kind: .replace, relativePath: "destination", sourceSide: .left,
        sourceURL: source, destinationURL: destination)
    let result = operationEngine.execute(try operationEngine.prepare(drafts: [draft]))
    check(readText(destination) == "file replaces folder", "replace safely handles a file/folder type conflict")
    try operationEngine.undo(result.transaction!)
    check(readText(destination.appending(path: "child.txt")) == "original child",
          "type-conflict undo restores the original folder and descendants")
} catch {
    check(false, "type-conflict replace and undo complete without error: \(error)")
}

// Same-volume move and Trash both remain undoable.
do {
    let root = operationDirectory("move")
    let source = root.appending(path: "source.txt")
    let destination = root.appending(path: "destination.txt")
    write("moving", source)
    let draft = FileOperationDraft(
        kind: .move, relativePath: "source.txt", sourceSide: .left,
        sourceURL: source, destinationURL: destination)
    let result = operationEngine.execute(try operationEngine.prepare(drafts: [draft]))
    check(readText(destination) == "moving" && !FileManager.default.fileExists(atPath: source.path),
          "same-volume move changes location")
    try operationEngine.undo(result.transaction!)
    check(readText(source) == "moving" && !FileManager.default.fileExists(atPath: destination.path),
          "move undo restores the original location")
} catch {
    check(false, "move and undo complete without error: \(error)")
}

do {
    let root = operationDirectory("cross-volume-move")
    let trash = root.appending(path: "Trash")
    let engine = FileOperationEngine(testTrashDirectory: trash, forceCrossVolumeMoves: true)
    let source = root.appending(path: "source.txt")
    let destination = root.appending(path: "destination.txt")
    write("verified cross-volume payload", source)
    let draft = FileOperationDraft(
        kind: .move, relativePath: "source.txt", sourceSide: .left,
        sourceURL: source, destinationURL: destination)
    let result = engine.execute(try engine.prepare(drafts: [draft]))
    check(readText(destination) == "verified cross-volume payload" &&
          !FileManager.default.fileExists(atPath: source.path),
          "cross-volume move copies, verifies, commits, then trashes source")
    try engine.undo(result.transaction!)
    check(readText(source) == "verified cross-volume payload" &&
          !FileManager.default.fileExists(atPath: destination.path),
          "cross-volume move undo restores source and removes verified copy")
} catch {
    check(false, "cross-volume move and undo complete without error: \(error)")
}

do {
    let root = operationDirectory("trash")
    let source = root.appending(path: "delete-me.txt")
    write("recoverable", source)
    let draft = FileOperationDraft(
        kind: .trash, relativePath: "delete-me.txt", sourceSide: .right,
        sourceURL: source)
    let result = operationEngine.execute(try operationEngine.prepare(drafts: [draft]))
    check(!FileManager.default.fileExists(atPath: source.path) && result.transaction != nil,
          "delete means recoverable move to Trash")
    try operationEngine.undo(result.transaction!)
    check(readText(source) == "recoverable", "Trash undo restores the original item")
} catch {
    check(false, "Trash and undo complete without error: \(error)")
}

// Preflight includes hidden descendants and symbolic links are copied as links, not followed.
do {
    let root = operationDirectory("folder-impact")
    let source = root.appending(path: "source")
    let destination = root.appending(path: "destination")
    try FileManager.default.createDirectory(at: source.appending(path: "nested"), withIntermediateDirectories: true)
    write("hidden", source.appending(path: ".hidden"))
    write("visible", source.appending(path: "nested/visible.txt"))
    let draft = FileOperationDraft(
        kind: .copy, relativePath: "destination", sourceSide: .left,
        sourceURL: source, destinationURL: destination)
    let plan = try operationEngine.prepare(drafts: [draft])
    check(plan.itemCount == 4 && plan.byteCount == 13,
          "folder preflight counts root, hidden entries, descendants, and real bytes")
} catch {
    check(false, "folder impact preflight completes without error: \(error)")
}

do {
    let root = operationDirectory("symlink")
    let target = root.appending(path: "target.txt")
    let source = root.appending(path: "source-link")
    let destination = root.appending(path: "destination-link")
    write("target stays untouched", target)
    try FileManager.default.createSymbolicLink(atPath: source.path, withDestinationPath: "target.txt")
    let draft = FileOperationDraft(
        kind: .copy, relativePath: "destination-link", sourceSide: .left,
        sourceURL: source, destinationURL: destination)
    let result = operationEngine.execute(try operationEngine.prepare(drafts: [draft]))
    let copiedTarget = try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
    check(copiedTarget == "target.txt" && readText(target) == "target stays untouched" && result.failures.isEmpty,
          "symlink operation copies the link and never mutates its target")
} catch {
    check(false, "symlink copy completes without error: \(error)")
}

// A source changed after review is rejected before commit.
do {
    let root = operationDirectory("stale")
    let source = root.appending(path: "source.txt")
    let destination = root.appending(path: "destination.txt")
    write("reviewed", source)
    let draft = FileOperationDraft(
        kind: .copy, relativePath: "destination.txt", sourceSide: .left,
        sourceURL: source, destinationURL: destination)
    let plan = try operationEngine.prepare(drafts: [draft])
    write("changed later", source)
    let result = operationEngine.execute(plan)
    check(result.failures.count == 1 && !FileManager.default.fileExists(atPath: destination.path),
          "changed source invalidates a reviewed plan before commit")
} catch {
    check(false, "stale-plan setup completes without error: \(error)")
}

do {
    let root = operationDirectory("stale-destination")
    let source = root.appending(path: "source.txt")
    let destination = root.appending(path: "destination.txt")
    write("replacement", source)
    write("reviewed destination", destination)
    let draft = FileOperationDraft(
        kind: .replace, relativePath: "destination.txt", sourceSide: .left,
        sourceURL: source, destinationURL: destination)
    let plan = try operationEngine.prepare(drafts: [draft])
    write("newer destination edit", destination)
    let result = operationEngine.execute(plan)
    check(result.failures.count == 1 && readText(destination) == "newer destination edit",
          "changed destination invalidates replace without losing the newer edit")
} catch {
    check(false, "stale-destination setup completes without error: \(error)")
}

// Undo refuses to destroy a user edit made after execution.
do {
    let root = operationDirectory("changed-output")
    let source = root.appending(path: "source.txt")
    let destination = root.appending(path: "destination.txt")
    write("created by plan", source)
    let draft = FileOperationDraft(
        kind: .copy, relativePath: "destination.txt", sourceSide: .left,
        sourceURL: source, destinationURL: destination)
    let result = operationEngine.execute(try operationEngine.prepare(drafts: [draft]))
    write("user edit", destination)
    do {
        try operationEngine.undo(result.transaction!)
        check(false, "changed output blocks undo")
    } catch FileOperationError.changedOutput {
        check(readText(destination) == "user edit", "changed output blocks undo without losing the edit")
    } catch {
        check(false, "changed output reports the expected undo error: \(error)")
    }
} catch {
    check(false, "changed-output setup completes without error: \(error)")
}

do {
    let root = operationDirectory("atomic-undo-preflight")
    let sourceA = root.appending(path: "source-a.txt")
    let sourceB = root.appending(path: "source-b.txt")
    let destinationA = root.appending(path: "destination-a.txt")
    let destinationB = root.appending(path: "destination-b.txt")
    write("a", sourceA)
    write("b", sourceB)
    let drafts = [
        FileOperationDraft(kind: .copy, relativePath: "destination-a.txt", sourceSide: .left,
                           sourceURL: sourceA, destinationURL: destinationA),
        FileOperationDraft(kind: .copy, relativePath: "destination-b.txt", sourceSide: .left,
                           sourceURL: sourceB, destinationURL: destinationB)
    ]
    let result = operationEngine.execute(try operationEngine.prepare(drafts: drafts))
    write("edited b", destinationB)
    do {
        try operationEngine.undo(result.transaction!)
        check(false, "undo preflight rejects a changed record")
    } catch FileOperationError.changedOutput {
        check(readText(destinationA) == "a" && readText(destinationB) == "edited b",
              "undo validates every record before mutating any output")
    } catch {
        check(false, "undo preflight reports the expected error: \(error)")
    }
} catch {
    check(false, "undo preflight setup completes without error: \(error)")
}

// Cancellation occurs between safe commits and leaves remaining destinations absent.
do {
    let root = operationDirectory("cancel")
    let sourceA = root.appending(path: "a.txt")
    let sourceB = root.appending(path: "b.txt")
    let destinationA = root.appending(path: "a-copy.txt")
    let destinationB = root.appending(path: "b-copy.txt")
    write("a", sourceA)
    write("b", sourceB)
    let drafts = [
        FileOperationDraft(kind: .copy, relativePath: "a-copy.txt", sourceSide: .left,
                           sourceURL: sourceA, destinationURL: destinationA),
        FileOperationDraft(kind: .copy, relativePath: "b-copy.txt", sourceSide: .left,
                           sourceURL: sourceB, destinationURL: destinationB)
    ]
    let plan = try operationEngine.prepare(drafts: drafts)
    let result = operationEngine.execute(plan, shouldCancel: {
        FileManager.default.fileExists(atPath: destinationA.path)
    })
    check(result.wasCancelled && readText(destinationA) == "a" &&
          !FileManager.default.fileExists(atPath: destinationB.path),
          "cancellation stops between commits without a partial next destination")
    try operationEngine.undo(result.transaction!)
} catch {
    check(false, "cancellation test completes without error: \(error)")
}

do {
    let root = operationDirectory("cancel-folder")
    let source = root.appending(path: "source")
    let destination = root.appending(path: "destination")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    write("first", source.appending(path: "a.txt"))
    write("second", source.appending(path: "b.txt"))
    let draft = FileOperationDraft(
        kind: .copy, relativePath: "destination", sourceSide: .left,
        sourceURL: source, destinationURL: destination)
    let plan = try operationEngine.prepare(drafts: [draft])
    let result = operationEngine.execute(plan, shouldCancel: {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return entries.contains { name in
            guard name.hasPrefix(".grapecompare-stage-") else { return false }
            let stage = root.appending(path: name)
            return ((try? FileManager.default.contentsOfDirectory(atPath: stage.path))?.isEmpty == false)
        }
    })
    let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    check(result.wasCancelled && !FileManager.default.fileExists(atPath: destination.path) &&
          !leftovers.contains(where: { $0.hasPrefix(".grapecompare-stage-") }),
          "mid-folder cancellation removes staging and never commits a partial destination")
} catch {
    check(false, "folder cancellation test completes without error: \(error)")
}

// MARK: - Durable operation workflows (1.4)

do {
    let estimator = FileOperationProgressEstimator(
        totalBytes: 1_000,
        totalOperations: 4,
        startedAt: Date(timeIntervalSince1970: 100))
    let byteProgress = estimator.progress(
        completedOperations: 2,
        completedBytes: 500,
        currentPath: "half",
        at: Date(timeIntervalSince1970: 105))
    check(byteProgress.bytesPerSecond == 100 && byteProgress.estimatedTimeRemaining == 5,
          "progress estimator reports deterministic throughput and ETA")
    let countProgress = FileOperationProgressEstimator(
        totalBytes: 0,
        totalOperations: 4,
        startedAt: Date(timeIntervalSince1970: 100))
        .progress(
            completedOperations: 1,
            completedBytes: 0,
            currentPath: "one",
            at: Date(timeIntervalSince1970: 102))
    check(countProgress.bytesPerSecond == nil && countProgress.estimatedTimeRemaining == 6,
          "zero-byte operations estimate remaining time by operation count")
    let clockSkew = estimator.progress(
        completedOperations: 1,
        completedBytes: 100,
        currentPath: "skew",
        at: Date(timeIntervalSince1970: 99))
    check(clockSkew.bytesPerSecond == nil && clockSkew.estimatedTimeRemaining == nil,
          "progress estimator never emits invalid values when the clock moves backwards")
}

func makeFailurePolicyPlan(_ name: String) throws -> (
    engine: FileOperationEngine,
    plan: FileOperationPlan,
    destinations: [URL]
) {
    let root = operationDirectory(name)
    let sources = (0..<3).map { root.appending(path: "source-\($0).txt") }
    let destinations = (0..<3).map { root.appending(path: "destination-\($0).txt") }
    for (index, source) in sources.enumerated() { write("value \(index)", source) }
    let drafts = zip(sources, destinations).enumerated().map { index, pair in
        FileOperationDraft(
            kind: .copy,
            relativePath: "destination-\(index).txt",
            sourceSide: .left,
            sourceURL: pair.0,
            destinationURL: pair.1)
    }
    let engine = FileOperationEngine(testTrashDirectory: operationTrash)
    let plan = try engine.prepare(drafts: drafts)
    write("changed after review", sources[1])
    return (engine, plan, destinations)
}

do {
    let fixture = try makeFailurePolicyPlan("failure-policy-stop")
    let result = fixture.engine.execute(fixture.plan, failurePolicy: .stopOnFirstFailure)
    check(result.completedOperations == 1 && result.failures.count == 1 &&
          readText(fixture.destinations[0]) == "value 0" &&
          !FileManager.default.fileExists(atPath: fixture.destinations[2].path),
          "stop-on-first-failure leaves later reviewed operations untouched")
    if let transaction = result.transaction { try fixture.engine.undo(transaction) }
} catch {
    check(false, "stop-on-first-failure test completes without error: \(error)")
}

do {
    let fixture = try makeFailurePolicyPlan("failure-policy-continue")
    let result = fixture.engine.execute(fixture.plan, failurePolicy: .continueAfterFailures)
    check(result.completedOperations == 2 && result.failures.count == 1 &&
          readText(fixture.destinations[0]) == "value 0" &&
          readText(fixture.destinations[2]) == "value 2",
          "continue-after-failures safely commits later independent operations")
    if let transaction = result.transaction { try fixture.engine.undo(transaction) }
} catch {
    check(false, "continue-after-failures test completes without error: \(error)")
}

do {
    let leftA = URL(fileURLWithPath: "/tmp/recipe-left-a")
    let rightA = URL(fileURLWithPath: "/tmp/recipe-right-a")
    let drafts = [
        FileOperationDraft(
            kind: .replace,
            relativePath: "Sources/App.swift",
            sourceSide: .left,
            sourceURL: leftA.appending(path: "Sources/App.swift"),
            destinationURL: rightA.appending(path: "Sources/App.swift")),
        FileOperationDraft(
            kind: .trash,
            relativePath: "Legacy/Old.swift",
            sourceSide: .right,
            sourceURL: rightA.appending(path: "Legacy/Old.swift"))
    ]
    let recipe = try FileOperationRecipe(drafts: drafts, createdAt: Date(timeIntervalSince1970: 123))
    let decoded = try FileOperationRecipe.decode(recipe.encoded())
    let leftB = URL(fileURLWithPath: "/tmp/recipe-left-b")
    let rightB = URL(fileURLWithPath: "/tmp/recipe-right-b")
    let mapped = try decoded.drafts(leftRoot: leftB, rightRoot: rightB)
    check(decoded == recipe &&
          mapped[0].sourceURL == leftB.appending(path: "Sources/App.swift") &&
          mapped[0].destinationURL == rightB.appending(path: "Sources/App.swift") &&
          mapped[1].sourceURL == rightB.appending(path: "Legacy/Old.swift") &&
          mapped[1].destinationURL == nil,
          "operation recipe round-trips and remaps only relative paths to current roots")

    let unsafe = FileOperationRecipe(operations: [
        .init(kind: .copy, relativePath: "../escape", sourceSide: .left)
    ])
    do {
        _ = try unsafe.drafts(leftRoot: leftB, rightRoot: rightB)
        check(false, "operation recipe rejects parent traversal")
    } catch FileOperationPersistenceError.invalidRelativePath {
        check(true, "operation recipe rejects parent traversal")
    }

    let future = FileOperationRecipe(schemaVersion: 99, operations: [
        .init(kind: .copy, relativePath: "safe.txt", sourceSide: .left)
    ])
    do {
        _ = try FileOperationRecipe.decode(future.encoded())
        check(false, "operation recipe rejects unsupported schema versions")
    } catch FileOperationPersistenceError.unsupportedRecipeVersion {
        check(true, "operation recipe rejects unsupported schema versions")
    }

    let linkRoot = operationDirectory("recipe-symlink-root")
    let outsideRoot = operationDirectory("recipe-symlink-outside")
    try FileManager.default.createSymbolicLink(
        at: linkRoot.appending(path: "escape"),
        withDestinationURL: outsideRoot)
    let symlinkEscape = FileOperationRecipe(operations: [
        .init(kind: .copy, relativePath: "escape/outside.txt", sourceSide: .left)
    ])
    do {
        _ = try symlinkEscape.drafts(leftRoot: linkRoot, rightRoot: rightB)
        check(false, "operation recipe rejects an intermediate symlink escape")
    } catch FileOperationPersistenceError.invalidRelativePath {
        check(true, "operation recipe rejects an intermediate symlink escape")
    }
} catch {
    check(false, "operation recipe tests complete without error: \(error)")
}

do {
    let root = operationDirectory("journal-relaunch")
    let journal = root.appending(path: "history.json")
    let source = root.appending(path: "source.txt")
    let destination = root.appending(path: "destination.txt")
    write("durable", source)
    let engineA = FileOperationEngine(testTrashDirectory: root.appending(path: "Trash"))
    let result = engineA.execute(try engineA.prepare(drafts: [
        FileOperationDraft(
            kind: .copy,
            relativePath: "destination.txt",
            sourceSide: .left,
            sourceURL: source,
            destinationURL: destination)
    ]))
    let transaction = result.transaction!
    let storeA = FileOperationJournalStore(
        journalURL: journal,
        fileManager: .default,
        usesSecurityScopedBookmarks: false)
    _ = try storeA.append(transaction)

    let storeB = FileOperationJournalStore(
        journalURL: journal,
        fileManager: .default,
        usesSecurityScopedBookmarks: false)
    let reloaded = storeB.load()
    let engineB = FileOperationEngine(testTrashDirectory: root.appending(path: "Trash"))
    try engineB.undo(reloaded[0])
    try storeB.remove(transactionID: reloaded[0].id)
    check(reloaded.map(\.id) == [transaction.id] &&
          reloaded.first?.operationCount == transaction.operationCount &&
          !FileManager.default.fileExists(atPath: destination.path) &&
          storeB.load().isEmpty,
          "a new store and engine instance load and undo a journaled transaction")
} catch {
    check(false, "journal relaunch test completes without error: \(error)")
}

do {
    let root = operationDirectory("journal-changed-output")
    let journal = root.appending(path: "history.json")
    let source = root.appending(path: "source.txt")
    let destination = root.appending(path: "destination.txt")
    write("journaled", source)
    let engine = FileOperationEngine(testTrashDirectory: root.appending(path: "Trash"))
    let transaction = engine.execute(try engine.prepare(drafts: [
        FileOperationDraft(
            kind: .copy,
            relativePath: "destination.txt",
            sourceSide: .left,
            sourceURL: source,
            destinationURL: destination)
    ])).transaction!
    let store = FileOperationJournalStore(
        journalURL: journal,
        fileManager: .default,
        usesSecurityScopedBookmarks: false)
    _ = try store.append(transaction)
    write("user edit after relaunch", destination)
    do {
        try engine.undo(store.load()[0])
        check(false, "persisted undo refuses a changed output")
    } catch FileOperationError.changedOutput {
        check(readText(destination) == "user edit after relaunch" && store.load().count == 1,
              "persisted undo refuses changed output without dropping history or data")
    }
} catch {
    check(false, "persisted changed-output test completes without error: \(error)")
}

do {
    let root = operationDirectory("journal-retention")
    let journal = root.appending(path: "history.json")
    let store = FileOperationJournalStore(
        journalURL: journal,
        maxEntries: 2,
        fileManager: .default,
        usesSecurityScopedBookmarks: false)
    var transactions: [FileOperationTransaction] = []
    for index in 0..<3 {
        let source = root.appending(path: "source-\(index).txt")
        let destination = root.appending(path: "destination-\(index).txt")
        write("\(index)", source)
        let transaction = operationEngine.execute(try operationEngine.prepare(drafts: [
            FileOperationDraft(
                kind: .copy,
                relativePath: "destination-\(index).txt",
                sourceSide: .left,
                sourceURL: source,
                destinationURL: destination)
        ])).transaction!
        transactions.append(transaction)
        let evicted = try store.append(transaction)
        check(evicted.count == (index == 2 ? 1 : 0),
              "journal retention reports evicted entries at append \(index + 1)")
    }
    check(store.load().map(\.id) == Array(transactions.suffix(2)).map(\.id),
          "journal retention keeps the newest bounded history in order")
} catch {
    check(false, "journal retention test completes without error: \(error)")
}

do {
    let root = operationDirectory("journal-corrupt")
    let journal = root.appending(path: "history.json")
    try Data("not valid json".utf8).write(to: journal)
    let store = FileOperationJournalStore(
        journalURL: journal,
        fileManager: .default,
        usesSecurityScopedBookmarks: false)
    let loaded = store.load()
    let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
    check(loaded.isEmpty && !FileManager.default.fileExists(atPath: journal.path) &&
          names.contains(where: { $0.hasPrefix("history.json.corrupt-") }),
          "a corrupt journal is quarantined instead of overwritten")
} catch {
    check(false, "corrupt journal test completes without error: \(error)")
}

try? FileManager.default.removeItem(at: tmp)

print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
