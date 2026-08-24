import Foundation
import Darwin

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

// MARK: - Text snapshots, comparison rules, and hunk output

let mixedTextData = Data("first\r\nsecond\rthird\nfourth".utf8)
let mixedSnapshot = try! TextSnapshot(data: mixedTextData)
check(mixedSnapshot.lines.map(\.ending) == [.crlf, .cr, .lf, .none],
      "text snapshot preserves mixed line endings")
check(try! mixedSnapshot.encodedData() == mixedTextData,
      "UTF-8 snapshot round-trips byte for byte")

var utf16Body = "grape 🍇\r\ncompare".data(using: .utf16LittleEndian)!
utf16Body.insert(contentsOf: [0xFF, 0xFE], at: 0)
let utf16Snapshot = try! TextSnapshot(data: utf16Body)
check(utf16Snapshot.encoding == .utf16LittleEndian &&
      (try! utf16Snapshot.encodedData()) == utf16Body,
      "UTF-16 LE BOM snapshot round-trips byte for byte")

do {
    _ = try TextSnapshot(data: Data([0x66, 0x80]))
    check(false, "invalid UTF-8 is rejected instead of replacement-decoded")
} catch TextSnapshotError.unsupportedEncoding {
    check(true, "invalid UTF-8 is rejected instead of replacement-decoded")
} catch {
    check(false, "invalid UTF-8 reports unsupported encoding")
}

let ruleLeft = try! TextSnapshot(data: Data("  Alpha  beta\r\nTail\n".utf8))
let ruleRight = try! TextSnapshot(data: Data("alpha beta\nTAIL\n".utf8))
let ruleExact = TextComparisonEngine.compare(left: ruleLeft, right: ruleRight)
check(!ruleExact.equivalentUnderOptions && !ruleExact.exactIdentical,
      "exact text comparison reports whitespace, case, and line-ending differences")
let ignoredRules = TextComparisonOptions(
    whitespace: .ignoreChanges,
    ignoreCase: true,
    ignoreLineEndingFormat: true)
let ruleIgnored = TextComparisonEngine.compare(
    left: ruleLeft, right: ruleRight, options: ignoredRules)
check(ruleIgnored.equivalentUnderOptions && !ruleIgnored.exactIdentical,
      "comparison rules distinguish equivalent content from byte identity")

let allWhitespaceLeft = try! TextSnapshot(data: Data("a b\tc".utf8))
let allWhitespaceRight = try! TextSnapshot(data: Data("abc".utf8))
let allWhitespaceResult = TextComparisonEngine.compare(
    left: allWhitespaceLeft,
    right: allWhitespaceRight,
    options: TextComparisonOptions(whitespace: .ignoreAll))
check(allWhitespaceResult.equivalentUnderOptions,
      "ignore-all-whitespace removes horizontal whitespace from matching keys")

let commentLeft = try! TextSnapshot(text: "let url = \"https://xnu.app\" // old note\n# old shell note\n<p><!--old-->value</p>\n")
let commentRight = try! TextSnapshot(text: "let url = \"https://xnu.app\" // new note\n# new shell note\n<p><!--new-->value</p>\n")
let ignoredComments = TextComparisonEngine.compare(
    left: commentLeft,
    right: commentRight,
    options: TextComparisonOptions(
        ignoreCStyleLineComments: true,
        ignoreShellLineComments: true,
        ignoreHTMLComments: true))
check(ignoredComments.equivalentUnderOptions,
      "text filters ignore C-style, shell, and single-line HTML comment changes without stripping quoted URLs")

let volatileLeft = try! TextSnapshot(text: """
event 2026-08-23T10:11:12Z id 550e8400-e29b-41d4-a716-446655440000 ptr 0x7ffee12abcde
build worker-12345 completed
""")
let volatileRight = try! TextSnapshot(text: """
event 2026-08-23T10:15:59Z id 123e4567-e89b-42d3-a456-426614174000 ptr 0x7ffee98fedcb
build worker-98765 completed
""")
let volatileOptions = TextComparisonOptions(
    ignoreTimestamps: true,
    ignoreUUIDs: true,
    ignoreHexAddresses: true,
    customFilterPatterns: [#"worker-\d+"#])
check(TextComparisonEngine.compare(
    left: volatileLeft, right: volatileRight, options: volatileOptions).equivalentUnderOptions,
      "reusable text filters ignore timestamps, UUIDs, addresses, and custom regex matches")
check(TextComparisonEngine.invalidFilterPatterns([#"worker-\d+"#, "["]) == ["["],
      "custom text filter validation rejects malformed regular expressions")
let encodedTextOptions = try! JSONEncoder().encode(volatileOptions)
check(try! JSONDecoder().decode(TextComparisonOptions.self, from: encodedTextOptions) == volatileOptions,
      "text comparison filter profiles round-trip for persistent reuse")

let newlineLeft = try! TextSnapshot(data: Data("same".utf8))
let newlineRight = try! TextSnapshot(data: Data("same\r\n".utf8))
let newlineVisible = TextComparisonEngine.compare(
    left: newlineLeft,
    right: newlineRight,
    options: TextComparisonOptions(ignoreLineEndingFormat: true))
check(!newlineVisible.equivalentUnderOptions,
      "final newline remains a difference when only line-ending format is ignored")
let newlineIgnored = TextComparisonEngine.compare(
    left: newlineLeft,
    right: newlineRight,
    options: TextComparisonOptions(
        ignoreLineEndingFormat: true,
        ignoreFinalNewline: true))
check(newlineIgnored.equivalentUnderOptions,
      "final newline can be ignored independently")

let hunkLeft = try! TextSnapshot(data: Data("one\ntwo\nthree\nfour\n".utf8))
let hunkRight = try! TextSnapshot(data: Data("ONE\ntwo\ninserted\nthree\n".utf8))
let hunkComparison = TextComparisonEngine.compare(left: hunkLeft, right: hunkRight)
check(hunkComparison.hunks.count == 3,
      "separated changes produce stable first-class hunks")
check(hunkComparison.hunks[0].leftRange == 0..<1 &&
      hunkComparison.hunks[0].rightRange == 0..<1,
      "replacement hunk retains exact source ranges")
check(hunkComparison.hunks[1].leftRange == 2..<2 &&
      hunkComparison.hunks[1].rightRange == 2..<3 &&
      hunkComparison.hunks[2].leftRange == 3..<4 &&
      hunkComparison.hunks[2].rightRange == 4..<4,
      "insert/delete hunks retain exact empty and non-empty source ranges")

var outputFromRight = TextOutputSession(
    left: hunkLeft,
    right: hunkRight,
    comparison: hunkComparison)
for hunk in hunkComparison.hunks {
    outputFromRight.accept(.left, hunkID: hunk.id)
}
check((try! (try! outputFromRight.snapshot()).encodedData()) == (try! hunkLeft.encodedData()),
      "accepting every left hunk reconstructs the left snapshot exactly")

var outputFromLeft = TextOutputSession(
    left: hunkLeft,
    right: hunkRight,
    comparison: hunkComparison,
    baseline: .left)
for hunk in hunkComparison.hunks {
    outputFromLeft.accept(.right, hunkID: hunk.id)
}
check((try! (try! outputFromLeft.snapshot()).encodedData()) == (try! hunkRight.encodedData()),
      "accepting every right hunk reconstructs the right snapshot exactly")

var randomHunksReconstruct = true
for _ in 0..<200 {
    let leftLines = (0..<random.next(30)).map { _ in "value-\(random.next(10))" }
    let rightLines = (0..<random.next(30)).map { _ in "value-\(random.next(10))" }
    let leftText = leftLines.joined(separator: "\n")
    let rightText = rightLines.joined(separator: "\n")
    let left = try! TextSnapshot(data: Data(leftText.utf8))
    let right = try! TextSnapshot(data: Data(rightText.utf8))
    let comparison = TextComparisonEngine.compare(left: left, right: right)
    var session = TextOutputSession(left: left, right: right, comparison: comparison)
    for hunk in comparison.hunks { session.accept(.left, hunkID: hunk.id) }
    if (try! session.snapshot()).text != left.text {
        randomHunksReconstruct = false
        break
    }
}
check(randomHunksReconstruct,
      "200 randomized hunk sets reconstruct the opposite snapshot without offset drift")

let editableLeft = try! TextSnapshot(text: "title\nleft choice\ntail\n")
let editableRight = try! TextSnapshot(text: "title\nright choice\ntail\n")
let editableComparison = TextComparisonEngine.compare(left: editableLeft, right: editableRight)
var editableSession = TextOutputSession(
    left: editableLeft, right: editableRight, comparison: editableComparison)
let manuallyEdited = try! TextSnapshot(text: "custom title\nright choice\ntail\n")
let preserved = try! editableSession.acceptPreservingManualEdits(
    .left, hunkID: editableComparison.hunks[0].id, currentOutput: manuallyEdited)
check(preserved.text == "custom title\nleft choice\ntail\n",
      "accepting a hunk preserves independent manual output edits")

var overlappingSession = TextOutputSession(
    left: editableLeft, right: editableRight, comparison: editableComparison)
let overlappingEdit = try! TextSnapshot(text: "title\nmanual choice\ntail\n")
let overlappingResult = try! overlappingSession.acceptPreservingManualEdits(
    .left, hunkID: editableComparison.hunks[0].id, currentOutput: overlappingEdit)
check(overlappingResult.text == editableLeft.text,
      "an explicit hunk choice wins over a manual edit in the same range")

let patchLeft = try! TextSnapshot(data: Data("alpha\nbeta\ngamma".utf8))
let patchRight = try! TextSnapshot(data: Data("alpha\nBETA\ngamma\ndelta\n".utf8))
let patch = try! UnifiedDiffWriter.makePatch(
    left: patchLeft,
    right: patchRight,
    leftPath: "a/sample.txt",
    rightPath: "b/sample.txt")
check(patch.hasPrefix("--- a/sample.txt\n+++ b/sample.txt\n@@ -1,3 +1,4 @@\n"),
      "unified diff emits standard headers and hunk coordinates")
check(patch.contains("-beta\n") && patch.contains("+BETA\n") && patch.contains("+delta\n"),
      "unified diff emits exact deleted and inserted content")
check(patch.contains("-gamma\n\\ No newline at end of file\n") &&
      patch.contains("+gamma\n") && patch.contains("+delta\n"),
      "unified diff emits the missing-final-newline marker on the correct source line")
check((try! UnifiedDiffWriter.makePatch(
    left: patchLeft,
    right: patchLeft,
    leftPath: "left",
    rightPath: "right")).isEmpty,
      "identical snapshots export an empty patch")
check((try! UnifiedDiffWriter.makePatch(
    left: patchLeft,
    right: patchRight,
    leftPath: "unsafe\tname\n.txt",
    rightPath: "safe.txt")).hasPrefix("--- unsafe name .txt\n"),
      "patch path labels cannot inject headers")

// MARK: - Three-way merge

func snapshot(_ text: String) -> TextSnapshot {
    try! TextSnapshot(data: Data(text.utf8))
}

let mergeBase = snapshot("one\ntwo\nthree\n")
let mergeOurs = snapshot("ONE\ntwo\nthree\n")
let mergeTheirs = snapshot("one\ntwo\nTHREE\n")
let independentMerge = ThreeWayMergeEngine.merge(
    base: mergeBase, ours: mergeOurs, theirs: mergeTheirs)
check(independentMerge.conflictCount == 0 &&
      independentMerge.renderedLines()?.map(\.content) == ["ONE", "two", "THREE"],
      "three-way merge combines independent changes from ours and theirs")

let sameOurs = snapshot("one\nTWO\nthree\n")
let sameTheirs = snapshot("one\nTWO\nthree\n")
let sameMerge = ThreeWayMergeEngine.merge(
    base: mergeBase, ours: sameOurs, theirs: sameTheirs)
check(sameMerge.conflictCount == 0 &&
      sameMerge.renderedLines()?.map(\.content) == ["one", "TWO", "three"],
      "three-way merge auto-resolves identical edits")

let conflictOurs = snapshot("one\nOURS\nthree\n")
let conflictTheirs = snapshot("one\nTHEIRS\nthree\n")
let conflictingMerge = ThreeWayMergeEngine.merge(
    base: mergeBase, ours: conflictOurs, theirs: conflictTheirs)
check(conflictingMerge.conflictCount == 1 && conflictingMerge.renderedLines() == nil,
      "three-way merge exposes overlapping divergent edits as a conflict")
check(MergeOutputValidator.containsConflictMarkers("before\n<<<<<<< ours\na\n=======\nb\n>>>>>>> theirs\n"),
      "merge output validation detects residual conflict markers")
check(!MergeOutputValidator.containsConflictMarkers("let comparison = \"a ======= b\"\n"),
      "merge output validation ignores marker text embedded inside a normal line")
if let conflict = conflictingMerge.conflicts.first {
    check(conflictingMerge.renderedLines(resolving: [conflict.id: .ours])?.map(\.content) ==
          ["one", "OURS", "three"],
          "three-way conflict can be resolved with ours")
    check(conflictingMerge.renderedLines(resolving: [conflict.id: .theirs])?.map(\.content) ==
          ["one", "THEIRS", "three"],
          "three-way conflict can be resolved with theirs")
} else {
    check(false, "three-way conflict has a stable identity")
    check(false, "three-way conflict can be resolved with theirs")
}

let insertOurs = snapshot("one\nours inserted\ntwo\nthree\n")
let insertTheirs = snapshot("one\ntheirs inserted\ntwo\nthree\n")
let insertionConflict = ThreeWayMergeEngine.merge(
    base: mergeBase, ours: insertOurs, theirs: insertTheirs)
check(insertionConflict.conflictCount == 1,
      "different insertions at the same base position conflict")

let deleteOurs = snapshot("one\nthree\n")
let modifyTheirs = snapshot("one\nTWO\nthree\n")
let deleteModifyConflict = ThreeWayMergeEngine.merge(
    base: mergeBase, ours: deleteOurs, theirs: modifyTheirs)
check(deleteModifyConflict.conflictCount == 1,
      "delete versus modify of the same base range conflicts")

let externalMergeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "grapecompare-external-merge-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: externalMergeDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: externalMergeDirectory) }
let externalArguments = [
    "GrapeCompare", "--merge",
    externalMergeDirectory.appending(path: "base").path,
    externalMergeDirectory.appending(path: "ours").path,
    externalMergeDirectory.appending(path: "theirs").path,
    externalMergeDirectory.appending(path: "merged").path,
    externalMergeDirectory.appending(path: "resolved").path
]
if let request = ExternalMergeRequest(commandLineArguments: externalArguments) {
    try! request.complete(with: snapshot("resolved\n"))
    check((try? String(contentsOf: request.destinationURL, encoding: .utf8)) == "resolved\n" &&
          FileManager.default.fileExists(atPath: request.sentinelURL.path),
          "external mergetool handoff writes output and completion sentinel")
    let imageBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
    try! request.complete(with: imageBytes)
    check((try? Data(contentsOf: request.destinationURL)) == imageBytes,
          "external mergetool handoff preserves binary image bytes")
} else {
    check(false, "external mergetool command-line handoff parses")
}
check(ExternalMergeRequest(commandLineArguments: ["GrapeCompare", "--merge"]) == nil,
      "external mergetool handoff rejects incomplete arguments")

// MARK: - Structured data comparison

let jsonLeft = Data(#"{"name":"Grape","settings":{"enabled":true,"count":2},"items":[1,2]}"#.utf8)
let jsonRight = Data(#"{"items":[1,3,4],"settings":{"count":2,"enabled":true},"name":"Grape"}"#.utf8)
let structuredLeft = try! StructuredDataComparator.decode(jsonLeft, format: .json)
let structuredRight = try! StructuredDataComparator.decode(jsonRight, format: .json)
let structuredDifferences = StructuredDataComparator.compare(
    left: structuredLeft,
    right: structuredRight)
check(structuredDifferences.map(\.path) == ["$.items[1]", "$.items[2]"],
      "JSON comparison ignores object key order and reports stable tree paths")
check(structuredDifferences.map(\.kind) == [.changed, .added],
      "JSON comparison distinguishes changed and added array values")

let jsonTypeLeft = try! StructuredDataComparator.decode(Data(#"{"value":1}"#.utf8), format: .json)
let jsonTypeRight = try! StructuredDataComparator.decode(Data(#"{"value":"1"}"#.utf8), format: .json)
check(StructuredDataComparator.compare(left: jsonTypeLeft, right: jsonTypeRight).first?.kind == .typeChanged,
      "structured comparison reports type changes separately")

let jsonFragmentLeft = try! StructuredDataComparator.decode(Data("42".utf8), format: .json)
let jsonFragmentRight = try! StructuredDataComparator.decode(Data("43".utf8), format: .json)
check(StructuredDataComparator.compare(left: jsonFragmentLeft, right: jsonFragmentRight).map(\.path) == ["$"],
      "top-level JSON fragments compare at the root path")

let smartQuoteJSON = try! StructuredDataComparator.decode(Data("{“value”: 1}".utf8), format: .json)
let straightQuoteJSON = try! StructuredDataComparator.decode(Data(#"{"value":1}"#.utf8), format: .json)
check(smartQuoteJSON == straightQuoteJSON,
      "JSON comparison preserves forgiving smart-quote normalization")

do {
    _ = try StructuredDataComparator.decode(Data("{".utf8), format: .json)
    check(false, "invalid JSON reports a parser error")
} catch {
    check(!error.localizedDescription.isEmpty, "invalid JSON reports a parser error")
}

let reorderedArrayLeft = try! StructuredDataComparator.decode(
    Data(#"{"items":["a","b","c"]}"#.utf8), format: .json)
let reorderedArrayRight = try! StructuredDataComparator.decode(
    Data(#"{"items":["b","a","c"]}"#.utf8), format: .json)
check(StructuredDataComparator.compare(left: reorderedArrayLeft, right: reorderedArrayRight).map(\.path) ==
      ["$.items[0]", "$.items[1]"],
      "JSON array order remains significant and index based")

let insertedPropertyLeft = try! StructuredDataComparator.decode(
    Data(#"{"a":1,"c":3}"#.utf8), format: .json)
let insertedPropertyRight = try! StructuredDataComparator.decode(
    Data(#"{"a":1,"b":2,"c":3}"#.utf8), format: .json)
let insertedPropertyDifferences = StructuredDataComparator.compare(
    left: insertedPropertyLeft, right: insertedPropertyRight)
check(insertedPropertyDifferences.count == 1 &&
      insertedPropertyDifferences.first?.path == "$.b" &&
      insertedPropertyDifferences.first?.kind == .added,
      "an inserted JSON property does not disturb its neighbors")

let formattingNoiseLeft = try! StructuredDataComparator.decode(
    Data("{\n  \"url\": \"https:\\/\\/xnu.app\", \"enabled\": true\n}".utf8), format: .json)
let formattingNoiseRight = try! StructuredDataComparator.decode(
    Data(#"{"enabled":true,"url":"https://xnu.app"}"#.utf8), format: .json)
check(StructuredDataComparator.compare(left: formattingNoiseLeft, right: formattingNoiseRight).isEmpty,
      "JSON formatting, escaped slashes, and object order do not create differences")

let decimalJSON = try! StructuredDataComparator.decode(
    Data(#"{"price":19.99,"weight":2.5}"#.utf8), format: .json)
if case .object(let decimalValues) = decimalJSON {
    check(decimalValues["price"]?.summary == "19.99" && decimalValues["weight"]?.summary == "2.5",
          "JSON decimal summaries retain practical source precision")
} else {
    check(false, "JSON decimal summaries retain practical source precision")
}

let largeJSONEntries = (0..<40_000).map { #""key\#($0)":\#($0)"# }.joined(separator: ",")
let largeJSON = Data("{\(largeJSONEntries)}".utf8)
let largeJSONStart = Date()
let largeJSONLeft = try! StructuredDataComparator.decode(largeJSON, format: .json)
let largeJSONRight = try! StructuredDataComparator.decode(largeJSON, format: .json)
check(StructuredDataComparator.compare(left: largeJSONLeft, right: largeJSONRight).isEmpty,
      "multi-megabyte equivalent JSON documents compare identically")
check(Date().timeIntervalSince(largeJSONStart) < 8,
      "multi-megabyte JSON comparison stays within the regression budget")

let plistLeftObject: [String: Any] = ["enabled": true, "nested": ["value": "old"]]
let plistRightObject: [String: Any] = ["enabled": true, "nested": ["value": "new"]]
let plistLeft = try! PropertyListSerialization.data(
    fromPropertyList: plistLeftObject, format: .binary, options: 0)
let plistRight = try! PropertyListSerialization.data(
    fromPropertyList: plistRightObject, format: .xml, options: 0)
let plistDifferences = StructuredDataComparator.compare(
    left: try! StructuredDataComparator.decode(plistLeft, format: .propertyList),
    right: try! StructuredDataComparator.decode(plistRight, format: .propertyList))
check(plistDifferences.count == 1 && plistDifferences[0].path == "$.nested.value",
      "binary and XML plist values share one semantic comparison model")

let xcstringsLeft = Data(#"{"sourceLanguage":"en","strings":{"Hello":{"localizations":{"en":{"stringUnit":{"state":"translated","value":"Hello"}}}}}}"#.utf8)
let xcstringsRight = Data(#"{"strings":{"Hello":{"localizations":{"zh-Hans":{"stringUnit":{"value":"你好","state":"translated"}},"en":{"stringUnit":{"value":"Hello","state":"translated"}}}}},"sourceLanguage":"en"}"#.utf8)
let catalogLeft = try! XCStringsComparator.decode(xcstringsLeft)
let catalogRight = try! XCStringsComparator.decode(xcstringsRight)
check(catalogLeft.keys == ["Hello"] && catalogRight.localizations == ["en", "zh-Hans"] &&
      !XCStringsComparator.compare(left: catalogLeft, right: catalogRight).isEmpty,
      "xcstrings comparison reports localization changes while ignoring JSON key order")

let pbxHeader = "// !$*UTF8*$!\n{ archiveVersion = 1; objectVersion = 77; objects = {\n"
let pbxLeft = Data((pbxHeader + "/* Begin PBXFileReference section */\n A = { path = A.swift; };\n B = { path = B.swift; };\n/* End PBXFileReference section */\n};}\n").utf8)
let pbxRight = Data((pbxHeader + "/* Begin PBXFileReference section */\n B = { path = B.swift; };\n A = { path = A.swift; };\n/* End PBXFileReference section */\n};}\n").utf8)
check(try! PBXProjectComparator.decode(pbxLeft) == PBXProjectComparator.decode(pbxRight),
      "pbxproj comparison is section-aware and ignores stable object ordering")

let thinArm64 = Data([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01])
check((try! MachOInspector.inspect(thinArm64)).architectures == ["arm64"],
      "Mach-O comparison decodes architecture metadata without executing the binary")

let appleFixture = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "grapetest-apple-formats-\(UUID().uuidString)")
let fixtureApp = appleFixture.appending(path: "Sample.app/Contents")
let fixtureAssets = appleFixture.appending(path: "Assets.xcassets/AppIcon.appiconset")
try! FileManager.default.createDirectory(at: fixtureApp, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: fixtureAssets, withIntermediateDirectories: true)
let fixtureInfo: [String: Any] = ["CFBundleIdentifier": "local.grapecompare.fixture",
                                  "CFBundleShortVersionString": "1.0", "CFBundleExecutable": "Sample",
                                  "CFBundlePackageType": "APPL"]
try! PropertyListSerialization.data(fromPropertyList: fixtureInfo, format: .binary, options: 0)
    .write(to: fixtureApp.appending(path: "Info.plist"))
try! Data(#"{"images":[{"filename":"icon.png","idiom":"mac","scale":"1x"}],"info":{"author":"xcode","version":1}}"#.utf8)
    .write(to: fixtureAssets.appending(path: "Contents.json"))
let fixturePNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
try! fixturePNG.write(to: fixtureAssets.appending(path: "icon.png"))
check((try! AppleBundleInspector.inspect(appleFixture.appending(path: "Sample.app"))).bundleIdentifier ==
      "local.grapecompare.fixture", "App Bundle comparison reads metadata without launching bundled code")
let assetSnapshot = try! AssetCatalogInspector.inspect(appleFixture.appending(path: "Assets.xcassets"))
check(assetSnapshot.groups == ["AppIcon.appiconset"] && assetSnapshot.imageFiles == ["AppIcon.appiconset/icon.png"],
      "asset catalog comparison inventories semantic Contents.json and image inputs " +
      "(groups=\(assetSnapshot.groups), images=\(assetSnapshot.imageFiles))")
let unsignedSignature = try! CodeSignatureInspector.inspect(appleFixture.appending(path: "Sample.app"))
check(!unsignedSignature.isValid,
      "code signature inspection reports invalid or unsigned bundles without executing them")
let assetsLink = appleFixture.appending(path: "Linked.xcassets")
try! FileManager.default.createSymbolicLink(at: assetsLink,
    withDestinationURL: appleFixture.appending(path: "Assets.xcassets"))
do {
    _ = try AssetCatalogInspector.inspect(assetsLink)
    check(false, "Apple developer format inspectors reject a symlink root")
} catch {
    check(true, "Apple developer format inspectors reject a symlink root")
}
do {
    _ = try ProvisioningProfileInspector.inspect(Data("not a profile".utf8))
    check(false, "provisioning profile inspection rejects malformed CMS data")
} catch {
    check(true, "provisioning profile inspection rejects malformed CMS data")
}
try! FileManager.default.removeItem(at: appleFixture)

// MARK: - Image comparison

let imageLeft = try! ImageRaster(
    width: 2,
    height: 1,
    rgba: Data([255, 0, 0, 255, 0, 255, 0, 255]))
let imageSame = try! ImageRaster(
    width: 2,
    height: 1,
    rgba: Data([255, 0, 0, 255, 0, 255, 0, 255]))
let identicalImageResult = ImageComparisonEngine.compare(left: imageLeft, right: imageSame)
check(identicalImageResult.identical && identicalImageResult.differingPixelCount == 0,
      "image comparison recognizes identical RGBA pixels")

let imageChanged = try! ImageRaster(
    width: 2,
    height: 1,
    rgba: Data([255, 0, 0, 255, 0, 0, 255, 255]))
let changedImageResult = ImageComparisonEngine.compare(left: imageLeft, right: imageChanged)
check(changedImageResult.dimensionsMatch &&
      changedImageResult.differingPixelCount == 1 &&
      changedImageResult.maximumChannelDifference == 255,
      "image comparison reports pixel and maximum channel differences")
check(changedImageResult.heatmap.rgba == Data([0, 0, 0, 0, 255, 0, 0, 255]),
      "image comparison produces a transparent-to-red difference heatmap")
let imageSubtle = try! ImageRaster(
    width: 2,
    height: 1,
    rgba: Data([255, 0, 0, 255, 0, 245, 0, 255]))
let absoluteImageResult = ImageComparisonEngine.compare(
    left: imageLeft, right: imageSubtle,
    options: ImageComparisonOptions(
        rendering: .absolute,
        differingColor: ImageDifferenceColor(red: 0, green: 255, blue: 255, alpha: 200)))
check(absoluteImageResult.heatmap.rgba.suffix(4) == Data([0, 255, 255, 200]),
      "absolute image rendering shows any detected change at full configured intensity")
let proportionalImageResult = ImageComparisonEngine.compare(
    left: imageLeft, right: imageSubtle,
    options: ImageComparisonOptions(rendering: .proportional))
check(proportionalImageResult.heatmap.rgba.suffix(4) == Data([255, 0, 0, 10]),
      "proportional image rendering scales configured color alpha by pixel difference")
let thresholdImageResult = ImageComparisonEngine.compare(
    left: imageLeft, right: imageChanged,
    options: ImageComparisonOptions(threshold: 255, channels: .all))
check(thresholdImageResult.differingPixelCount == 0,
      "image comparison threshold suppresses differences at or below the limit")
let alphaOnlyResult = ImageComparisonEngine.compare(
    left: imageLeft, right: imageChanged,
    options: ImageComparisonOptions(channels: .alpha))
check(alphaOnlyResult.identical,
      "image comparison can isolate the alpha channel")
let shiftedImageResult = ImageComparisonEngine.compare(
    left: imageLeft, right: imageSame,
    options: ImageComparisonOptions(rightOffsetX: 1))
check(shiftedImageResult.comparedPixelCount == 3 && shiftedImageResult.differingPixelCount == 3,
      "image comparison applies explicit alignment offsets without clipping the canvas")
let alignmentLeft = try! ImageRaster(width: 3, height: 1, rgba: Data([
    0, 0, 0, 255, 255, 0, 0, 255, 0, 255, 0, 255
]))
let alignmentRight = try! ImageRaster(width: 2, height: 1, rgba: Data([
    255, 0, 0, 255, 0, 255, 0, 255
]))
let alignment = ImageAlignmentEngine.bestTranslation(
    left: alignmentLeft, right: alignmentRight, maximumOffset: 1)
check(alignment.x == 1 && alignment.y == 0,
      "local image alignment finds a bounded translation without network access")

let imageLarger = try! ImageRaster(
    width: 3,
    height: 1,
    rgba: Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 0, 255]))
let resizedImageResult = ImageComparisonEngine.compare(left: imageLeft, right: imageLarger)
check(!resizedImageResult.dimensionsMatch && resizedImageResult.differingPixelCount == 1,
      "pixels outside the smaller image count as differences")

let onePixelPNG = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
let onePixelMetadata = try! ImageMetadata.inspect(onePixelPNG, formatHint: "png")
check(onePixelMetadata.width == 1 && onePixelMetadata.height == 1 &&
      onePixelMetadata.formatIdentifier.contains("png") && onePixelMetadata.byteCount == onePixelPNG.count,
      "image metadata reports format, dimensions, and encoded size without rendering UI")
do {
    _ = try ImageRaster.decode(onePixelPNG, maximumPixels: 0)
    check(false, "image decode enforces the pixel budget before raster allocation")
} catch ImageComparisonError.dimensionsTooLarge {
    check(true, "image decode enforces the pixel budget before raster allocation")
} catch {
    check(false, "image decode reports the pixel-budget error consistently")
}
let svgFixture = Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="2" height="1"><rect width="2" height="1" fill="#ff0000"/></svg>"##.utf8)
do {
    let svgRaster = try ImageRaster.decode(svgFixture, formatHint: "svg", maximumPixels: 10)
    check(svgRaster.width == 2 && svgRaster.height == 1 && svgRaster.rgba.count == 8,
          "SVG comparison rasterizes vector input through the local system renderer")
} catch {
    check(false, "SVG comparison rasterizes vector input through the local system renderer")
}

// MARK: - Git repository comparison

@discardableResult
func runGit(_ arguments: [String], in directory: URL) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try! process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        fatalError("git \(arguments) failed: \(String(decoding: data, as: UTF8.self))")
    }
    return String(decoding: data, as: UTF8.self)
}

let gitTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "grapetest-git-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: gitTmp, withIntermediateDirectories: true)
runGit(["init", "-b", "main"], in: gitTmp)
runGit(["config", "user.email", "tests@grapecompare.local"], in: gitTmp)
runGit(["config", "user.name", "GrapeCompare Tests"], in: gitTmp)
try! Data("base\n".utf8).write(to: gitTmp.appending(path: "tracked.txt"))
runGit(["add", "tracked.txt"], in: gitTmp)
runGit(["commit", "-m", "base"], in: gitTmp)
runGit(["checkout", "-b", "feature"], in: gitTmp)
try! Data("feature\n".utf8).write(to: gitTmp.appending(path: "tracked.txt"))
runGit(["commit", "-am", "feature"], in: gitTmp)
runGit(["checkout", "main"], in: gitTmp)

let gitRoot = try! GitRepositoryComparator.repositoryRoot(at: gitTmp)
check(gitRoot.resolvingSymlinksInPath().path == gitTmp.resolvingSymlinksInPath().path,
      "Git comparison resolves the selected repository root")
let gitReferences = try! GitRepositoryComparator.references(in: gitTmp)
check(Set(gitReferences.map(\.name)).isSuperset(of: ["main", "feature"]),
      "Git comparison lists local branches")
let branchContext = try! GitRepositoryComparator.branchContext(
    in: gitTmp, comparisonRevision: "feature")
check(branchContext.branch == "main" && branchContext.upstream == nil &&
      branchContext.mergeBaseObjectID?.count == 40,
      "Git workspace reports branch, absent upstream, and merge base")
let commitGraphPage = try! GitRepositoryComparator.commitGraph(in: gitTmp, limit: 1)
let commitGraphNextPage = try! GitRepositoryComparator.commitGraph(in: gitTmp, limit: 1, skip: 1)
check(commitGraphPage.count == 1 && commitGraphNextPage.count == 1 &&
      commitGraphPage[0].id != commitGraphNextPage[0].id,
      "Git workspace commit graph paginates with stable identities")
let revisionBeforeFuture = try! GitRepositoryComparator.revision(
    in: gitTmp, before: Date().addingTimeInterval(60))
let revisionBeforeHistory = try! GitRepositoryComparator.revision(
    in: gitTmp, before: Date(timeIntervalSince1970: 0))
let headCommit = try! GitRepositoryComparator.commit(in: gitTmp, revision: "HEAD")
check(revisionBeforeFuture == headCommit.objectID && revisionBeforeHistory == nil,
      "Git workspace resolves bounded time-range comparison revisions")
let worktreeTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "grapetest-worktree-\(UUID().uuidString)")
runGit(["worktree", "add", "--detach", worktreeTmp.path, "feature"], in: gitTmp)
let worktrees = try! GitRepositoryComparator.worktrees(in: gitTmp)
check(worktrees.count == 2 && worktrees.contains {
        $0.path.lastPathComponent == worktreeTmp.lastPathComponent && $0.isDetached
      },
      "Git workspace discovers linked and detached worktrees")
runGit(["worktree", "remove", "--force", worktreeTmp.path], in: gitTmp)
let repositoryLibraryURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "grapetest-library-\(UUID().uuidString)/repositories.json")
let repositoryLibrary = GitRepositoryLibraryStore(
    storageURL: repositoryLibraryURL, maximumEntries: 2, usesSecurityScopedBookmarks: false)
let rememberedRepositories = try! repositoryLibrary.remember(gitTmp)
let resolvedRepository = try! repositoryLibrary.resolve(rememberedRepositories[0]).url
check(rememberedRepositories.count == 1 &&
      resolvedRepository.lastPathComponent == gitTmp.lastPathComponent,
      "Git repository library persists and resolves a security-scoped bookmark")
try! FileManager.default.removeItem(at: repositoryLibraryURL.deletingLastPathComponent())
let branchChanges = try! GitRepositoryComparator.changes(
    in: gitTmp,
    from: .revision("main"),
    to: .revision("feature"))
check(branchChanges == [GitChange(kind: .modified, path: "tracked.txt", oldPath: nil)],
      "Git comparison compares two branch tips")
let changesetTree = GitChangesetTreeBuilder.build([
    GitChange(kind: .modified, path: "Sources/App/main.swift", oldPath: nil),
    GitChange(kind: .added, path: "Sources/Core/Diff.swift", oldPath: nil),
    GitChange(kind: .deleted, path: "README.md", oldPath: nil)
])
check(changesetTree.map(\.name) == ["Sources", "README.md"] &&
      changesetTree[0].children.map(\.name) == ["App", "Core"],
      "Git changeset tree groups paths with deterministic directory-first ordering")
let largeChangeset = (0..<10_000).map {
    GitChange(kind: .modified, path: "Sources/Module\($0 % 100)/File\($0).swift", oldPath: nil)
}
let treeStarted = Date()
let largeTree = GitChangesetTreeBuilder.build(largeChangeset)
check(largeTree.count == 1 && Date().timeIntervalSince(treeStarted) < 2,
      "Git changeset tree builds 10,000 paths within the performance budget")
do {
    _ = try GitRepositoryComparator.changes(
        in: gitTmp, from: .revision("--ext-diff"), to: .workingTree)
    check(false, "Git revisions cannot inject command options")
} catch GitRepositoryError.commandFailed {
    check(true, "Git revisions cannot inject command options")
} catch {
    check(false, "Git revision option injection reports a command failure")
}
let featureData = try! GitRepositoryComparator.fileData(
    in: gitTmp,
    target: .revision("feature"),
    path: "tracked.txt")
check(featureData == Data("feature\n".utf8),
      "Git comparison materializes a file from a commit without checkout")
let featureCommit = try! GitRepositoryComparator.commit(in: gitTmp, revision: "feature")
check(featureCommit.subject == "feature" && featureCommit.authorName == "GrapeCompare Tests" &&
      featureCommit.objectID.count == 40,
      "Git comparison reads stable commit metadata")
let trackedHistory = try! GitRepositoryComparator.fileHistory(
    in: gitTmp, path: "tracked.txt", revision: "feature")
check(trackedHistory.map(\.subject) == ["feature", "base"] &&
      trackedHistory.allSatisfy { !$0.objectID.isEmpty },
      "Git file history follows a path across commits")
do {
    _ = try GitRepositoryComparator.fileHistory(in: gitTmp, path: "../outside")
    check(false, "Git file history rejects parent traversal")
} catch GitRepositoryError.unsafePath {
    check(true, "Git file history rejects parent traversal")
} catch {
    check(false, "Git file history reports the expected unsafe-path error")
}
runGit(["checkout", "feature"], in: gitTmp)
runGit(["mv", "tracked.txt", "renamed.txt"], in: gitTmp)
runGit(["commit", "-m", "rename tracked file"], in: gitTmp)
let renamedHistory = try! GitRepositoryComparator.fileRevisions(
    in: gitTmp, path: "renamed.txt", revision: "feature")
check(renamedHistory.first?.path == "renamed.txt" &&
      renamedHistory.last?.path == "tracked.txt" &&
      renamedHistory.map(\.commit.subject) == ["rename tracked file", "feature", "base"],
      "Git file history preserves the valid path on both sides of a rename")
check((try! GitRepositoryComparator.fileData(
        in: gitTmp,
        target: .revision(renamedHistory.last!.commit.objectID),
        path: renamedHistory.last!.path)) == Data("base\n".utf8),
      "Git file history materializes a pre-rename revision without checkout")
runGit(["checkout", "main"], in: gitTmp)

try! Data("working\n".utf8).write(to: gitTmp.appending(path: "tracked.txt"))
try! Data("new\n".utf8).write(to: gitTmp.appending(path: "untracked.txt"))
let workingChanges = try! GitRepositoryComparator.changes(
    in: gitTmp,
    from: .revision("HEAD"),
    to: .workingTree)
check(workingChanges.contains(GitChange(
        kind: .modified, path: "tracked.txt", oldPath: nil, stage: .unstaged)) &&
      workingChanges.contains(GitChange(
        kind: .untracked, path: "untracked.txt", oldPath: nil, stage: .untracked)),
      "Git working-tree comparison includes tracked and untracked changes")
runGit(["add", "tracked.txt"], in: gitTmp)
let indexChanges = try! GitRepositoryComparator.changes(
    in: gitTmp, from: .revision("HEAD"), to: .index)
check(indexChanges == [GitChange(
        kind: .modified, path: "tracked.txt", oldPath: nil, stage: .staged)] &&
      (try! GitRepositoryComparator.fileData(
        in: gitTmp, target: .index, path: "tracked.txt")) == Data("working\n".utf8),
      "Git comparison reads staged index content")
try! Data("unstaged\n".utf8).write(to: gitTmp.appending(path: "tracked.txt"))
let indexToWorktree = try! GitRepositoryComparator.changes(
    in: gitTmp, from: .index, to: .workingTree)
check(indexToWorktree.contains(GitChange(
        kind: .modified, path: "tracked.txt", oldPath: nil, stage: .unstaged)) &&
      indexToWorktree.contains(GitChange(
        kind: .untracked, path: "untracked.txt", oldPath: nil, stage: .untracked)),
      "Git comparison distinguishes index from working-tree content")

let stagedAndUnstaged = try! GitRepositoryComparator.changes(
    in: gitTmp, from: .revision("HEAD"), to: .workingTree)
check(stagedAndUnstaged.filter { $0.path == "tracked.txt" }.map(\.stage).sorted {
        $0.rawValue < $1.rawValue
      } == [.staged, .unstaged] && Set(stagedAndUnstaged.map(\.id)).count == stagedAndUnstaged.count,
      "Git comparison preserves staged and unstaged versions of the same path")

let historyPageOne = try! GitRepositoryComparator.fileRevisions(
    in: gitTmp, path: "renamed.txt", revision: "feature", limit: 1)
let historyPageTwo = try! GitRepositoryComparator.fileRevisions(
    in: gitTmp, path: "renamed.txt", revision: "feature", limit: 1, skip: 1)
check(historyPageOne.count == 1 && historyPageTwo.count == 1 &&
      historyPageOne[0].id != historyPageTwo[0].id,
      "Git file history pagination returns stable non-overlapping pages")

try! Data([0x00, 0x01, 0x02]).write(to: gitTmp.appending(path: "binary.dat"))
try! Data("version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 3\n".utf8)
    .write(to: gitTmp.appending(path: "pointer.bin"))
try! Data(repeating: 0x41, count: 32).write(to: gitTmp.appending(path: "large.txt"))
check((try! GitRepositoryComparator.inspectFile(
        in: gitTmp, target: .workingTree, path: "binary.dat")).kind == .binary,
      "Git inspection identifies binary working-tree content")
check((try! GitRepositoryComparator.inspectFile(
        in: gitTmp, target: .workingTree, path: "pointer.bin")).kind == .lfsPointer,
      "Git inspection identifies an LFS pointer without invoking Git LFS")
check((try! GitRepositoryComparator.inspectFile(
        in: gitTmp, target: .workingTree, path: "large.txt", probeLimit: 16)).kind == .largeFile,
      "Git inspection bounds reads for large content")

do {
    _ = try GitRepositoryComparator.changes(
        in: gitTmp,
        from: .index,
        to: .workingTree,
        policy: GitCommandPolicy(maximumOutputBytes: 1))
    check(false, "Git commands enforce their output safety limit")
} catch GitRepositoryError.outputTooLarge {
    check(true, "Git commands enforce their output safety limit")
} catch {
    check(false, "Git output limit reports the expected error")
}
do {
    _ = try GitRepositoryComparator.changes(
        in: gitTmp,
        from: .index,
        to: .workingTree,
        policy: GitCommandPolicy(isCancelled: { true }))
    check(false, "Git commands observe cancellation")
} catch GitRepositoryError.cancelled {
    check(true, "Git commands observe cancellation")
} catch {
    check(false, "Git cancellation reports the expected error")
}

do {
    _ = try GitRepositoryComparator.runProcessForTesting(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "sleep 2"],
        in: gitTmp,
        policy: GitCommandPolicy(timeout: 0.05))
    check(false, "Git commands enforce their timeout")
} catch GitRepositoryError.timedOut {
    check(true, "Git commands enforce their timeout")
} catch {
    check(false, "Git timeout reports the expected error")
}

let submoduleSource = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "grapetest-submodule-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: submoduleSource, withIntermediateDirectories: true)
runGit(["init", "-b", "main"], in: submoduleSource)
runGit(["config", "user.email", "tests@grapecompare.local"], in: submoduleSource)
runGit(["config", "user.name", "GrapeCompare Tests"], in: submoduleSource)
try! Data("nested\n".utf8).write(to: submoduleSource.appending(path: "nested.txt"))
runGit(["add", "nested.txt"], in: submoduleSource)
runGit(["commit", "-m", "nested"], in: submoduleSource)
runGit(["-c", "protocol.file.allow=always", "submodule", "add", submoduleSource.path, "modules/sample"], in: gitTmp)
check((try! GitRepositoryComparator.inspectFile(
        in: gitTmp, target: .index, path: "modules/sample")).kind == .submodule &&
      (try! GitRepositoryComparator.inspectFile(
        in: gitTmp, target: .workingTree, path: "modules/sample")).kind == .submodule,
      "Git inspection identifies submodules without traversing them")

let mergeTmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "grapetest-merge-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: mergeTmp, withIntermediateDirectories: true)
runGit(["init", "-b", "main"], in: mergeTmp)
runGit(["config", "user.email", "tests@grapecompare.local"], in: mergeTmp)
runGit(["config", "user.name", "GrapeCompare Tests"], in: mergeTmp)
try! Data("base\n".utf8).write(to: mergeTmp.appending(path: "base.txt"))
runGit(["add", "base.txt"], in: mergeTmp)
runGit(["commit", "-m", "base"], in: mergeTmp)
runGit(["checkout", "-b", "side"], in: mergeTmp)
try! Data("side\n".utf8).write(to: mergeTmp.appending(path: "side.txt"))
runGit(["add", "side.txt"], in: mergeTmp)
runGit(["commit", "-m", "side"], in: mergeTmp)
runGit(["checkout", "main"], in: mergeTmp)
try! Data("main\n".utf8).write(to: mergeTmp.appending(path: "main.txt"))
runGit(["add", "main.txt"], in: mergeTmp)
runGit(["commit", "-m", "main"], in: mergeTmp)
runGit(["merge", "--no-ff", "side", "-m", "merge"], in: mergeTmp)
check((try! GitRepositoryComparator.commit(in: mergeTmp, revision: "HEAD")).parentIDs.count == 2,
      "Git commit metadata preserves both merge parents")

try! FileManager.default.removeItem(at: gitTmp)
try! FileManager.default.removeItem(at: submoduleSource)
try! FileManager.default.removeItem(at: mergeTmp)

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
let mirrorDrafts = FolderSyncPlanner.drafts(
    root: tree, leftRoot: L, rightRoot: R, mode: .mirror)
check(mirrorDrafts.count == 4 &&
      mirrorDrafts.contains { $0.kind == .copy && $0.relativePath == "onlyleft.txt" } &&
      mirrorDrafts.contains { $0.kind == .trash && $0.relativePath == "onlyright.txt" },
      "mirror sync plans copy, replace, and recoverable destination trash operations")
let ignoredDrafts = FolderSyncPlanner.drafts(
    root: tree, leftRoot: L, rightRoot: R, mode: .mirror,
    ignoreProfile: FolderIgnoreProfile(name: "Text", patterns: ["*.txt"]))
check(ignoredDrafts.isEmpty, "folder sync ignore profiles exclude matching leaves and descendants")
let mirrorPlan = try! FileOperationEngine(testTrashDirectory: tmp.appending(path: "Trash"))
    .prepare(drafts: mirrorDrafts)
let mirrorReport = FileOperationReport(plan: mirrorPlan, dryRun: true,
                                       createdAt: Date(timeIntervalSince1970: 0))
let reportDecoder = JSONDecoder()
reportDecoder.dateDecodingStrategy = .iso8601
let decodedMirrorReport = try! reportDecoder.decode(
    FileOperationReport.self, from: mirrorReport.encodedJSON())
check(decodedMirrorReport == mirrorReport && mirrorReport.rows.count == mirrorDrafts.count,
      "folder sync dry-run report is deterministic and machine-readable")
let metadataBefore = try! FileMetadataComparator.snapshot(at: L.appending(path: "same.txt"))
try! FileManager.default.setAttributes([.posixPermissions: 0o600],
                                       ofItemAtPath: L.appending(path: "same.txt").path)
let metadataAfter = try! FileMetadataComparator.snapshot(at: L.appending(path: "same.txt"))
check(metadataBefore.permissions != metadataAfter.permissions,
      "folder metadata comparison detects POSIX permission changes")
let xattrValue = Data("fixture".utf8)
let xattrStatus = xattrValue.withUnsafeBytes { bytes in
    setxattr(L.appending(path: "same.txt").path, "local.grapecompare.fixture",
             bytes.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
}
let metadataWithXattr = try! FileMetadataComparator.snapshot(at: L.appending(path: "same.txt"))
check(xattrStatus == 0 && metadataWithXattr.extendedAttributes["local.grapecompare.fixture"] != nil,
      "folder metadata comparison fingerprints extended attributes without following links")
let metadataTree = try! FolderComparator.compareCancellable(
    leftRoot: L, rightRoot: R, compareMetadata: true)
check(metadataTree.children?.first { $0.name == "same.txt" }?.status == .different,
      "folder comparison exposes permission and extended-attribute differences when enabled")
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

// A directory symlink loop must remain a leaf. Following it would recurse
// forever and could escape the selected comparison root.
try! FileManager.default.createSymbolicLink(
    at: edgeL.appending(path: "loop"), withDestinationURL: URL(fileURLWithPath: "."))
try! FileManager.default.createSymbolicLink(
    at: edgeR.appending(path: "loop"), withDestinationURL: URL(fileURLWithPath: "."))
let loopTree = FolderComparator.compare(leftRoot: edgeL, rightRoot: edgeR)
let loopNode = findNode("loop", in: loopTree)
check(loopNode?.status == .same && loopNode?.isFolder == false && loopNode?.children == nil,
      "directory symlink loops are compared as links and never followed")

// Large binary files are compared as bounded chunks instead of loading both
// payloads into memory. Exercise equality and a late-byte mismatch.
let binaryL = edgeL.appending(path: "large.bin")
let binaryR = edgeR.appending(path: "large.bin")
var binaryPayload = Data(repeating: 0xA5, count: 8 * 1_024 * 1_024)
binaryPayload[17] = 0
try! binaryPayload.write(to: binaryL)
try! binaryPayload.write(to: binaryR)
let equalBinaryTree = FolderComparator.compare(leftRoot: edgeL, rightRoot: edgeR)
check(findNode("large.bin", in: equalBinaryTree)?.status == .same,
      "large equal binary files compare exactly")
binaryPayload[binaryPayload.count - 1] = 0x5A
try! binaryPayload.write(to: binaryR)
let changedBinaryTree = FolderComparator.compare(leftRoot: edgeL, rightRoot: edgeR)
check(findNode("large.bin", in: changedBinaryTree)?.status == .different,
      "late mismatch in a large binary file is detected")

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

do {
    let root = operationDirectory("comparison-sessions")
    let store = ComparisonSessionStore(
        fileURL: root.appending(path: "sessions.json"), maximumRecents: 2)
    let first = ComparisonSession(
        kind: .files, displayNames: ["a", "b"], bookmarks: [Data([1]), Data([2])])
    let second = ComparisonSession(
        kind: .folders, displayNames: ["c", "d"], bookmarks: [Data([3]), Data([4])])
    let third = ComparisonSession(
        kind: .git, displayNames: ["repo"], bookmarks: [Data([5])])
    _ = try store.record(first)
    _ = try store.record(second)
    let envelope = try store.record(third)
    check(envelope.current == third && envelope.recents == [third, second],
          "comparison sessions retain the newest bounded history and current session")
    check(store.load() == envelope, "comparison sessions round-trip deterministically")
    try store.clear()
    check(store.load() == ComparisonSessionEnvelope(), "comparison session history clears safely")
} catch {
    check(false, "comparison session persistence tests complete without error: \(error)")
}

// FSEvents intentionally does not guarantee journal delivery for macOS's
// per-user temporary hierarchy. Exercise it on a normal filesystem path.
let watcherRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appending(path: ".filesystem-watcher-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: watcherRoot, withIntermediateDirectories: true)
let changed = DispatchSemaphore(value: 0)
let watcherLock = NSLock()
var watcherCallbackCount = 0
let watcher = FilesystemWatcher()
watcher.start(watching: [watcherRoot], latency: 0.05) { urls in
    if !urls.isEmpty {
        watcherLock.withLock { watcherCallbackCount += 1 }
        changed.signal()
    }
}
Thread.sleep(forTimeInterval: 0.1)
write("changed", watcherRoot.appending(path: "changed.txt"))
check(changed.wait(timeout: .now() + 3) == .success,
      "filesystem watcher reports a mutation inside a watched root")
for index in 0..<100 {
    write("burst \(index)", watcherRoot.appending(path: "burst-\(index).txt"))
}
check(changed.wait(timeout: .now() + 3) == .success,
      "filesystem watcher reports a 100-file mutation burst")
Thread.sleep(forTimeInterval: 0.3)
check(watcherLock.withLock { watcherCallbackCount } <= 3,
      "filesystem watcher coalesces mutation bursts into bounded callbacks")
watcher.stop()
try? FileManager.default.removeItem(at: watcherRoot)

let exactWatcherRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appending(path: ".filesystem-exact-watcher-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: exactWatcherRoot, withIntermediateDirectories: true)
let exactFile = exactWatcherRoot.appending(path: "watched.txt")
write("initial", exactFile)
let exactChanged = DispatchSemaphore(value: 0)
let exactWatcher = FilesystemWatcher()
exactWatcher.start(watching: [exactWatcherRoot], exactFiles: [exactFile], latency: 0.05) { _ in
    exactChanged.signal()
}
// Let stream and vnode-source registration settle, then discard any startup
// notification before testing the sibling mutation itself. FSEvents may replay
// a checkpoint-adjacent event on slower filesystems even though no new change
// occurred after start returned.
Thread.sleep(forTimeInterval: 0.3)
while exactChanged.wait(timeout: .now()) == .success {}
write("unrelated", exactWatcherRoot.appending(path: "sibling.txt"))
check(exactChanged.wait(timeout: .now() + 0.4) == .timedOut,
      "exact-file watcher ignores sibling mutations reported at the parent root")
write("updated with a different byte count", exactFile)
check(exactChanged.wait(timeout: .now() + 3) == .success,
      "exact-file watcher reports changes to the watched file")
exactWatcher.stop()
try? FileManager.default.removeItem(at: exactWatcherRoot)

try? FileManager.default.removeItem(at: tmp)

print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
