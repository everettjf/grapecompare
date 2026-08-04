import Foundation

private struct Measurement {
    let name: String
    let seconds: Double
    let detail: String
}

@inline(never)
private func measure(_ name: String, detail: String = "", _ body: () -> Void) -> Measurement {
    let clock = ContinuousClock()
    let start = clock.now
    body()
    let duration = start.duration(to: clock.now)
    return Measurement(
        name: name,
        seconds: Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000,
        detail: detail)
}

private func reconstructed(_ operations: [LineOp]) -> (old: [String], new: [String]) {
    var old: [String] = []
    var new: [String] = []
    old.reserveCapacity(operations.count)
    new.reserveCapacity(operations.count)
    for operation in operations {
        switch operation {
        case .equal(let line):
            old.append(line)
            new.append(line)
        case .delete(let line):
            old.append(line)
        case .insert(let line):
            new.append(line)
        }
    }
    return (old, new)
}

private func makeLargeFileScenario(lineCount: Int) -> (left: [String], right: [String]) {
    let left = (0..<lineCount).map { "func item_\($0)() { return \($0) }" }
    var right = left
    for index in stride(from: 97, to: lineCount, by: 997) {
        right[index] = "func item_\(index)() { return changed_\(index) }"
    }
    for index in stride(from: lineCount - 400, through: 400, by: -2_000) {
        right.insert("// inserted near \(index)", at: index)
    }
    return (left, right)
}

private func makeHighChurnScenario(lineCount: Int) -> (left: [String], right: [String]) {
    var left: [String] = []
    var right: [String] = []
    left.reserveCapacity(lineCount)
    right.reserveCapacity(lineCount)
    for index in 0..<lineCount {
        if index % 100 == 0 {
            let anchor = "// MARK: section \(index / 100)"
            left.append(anchor)
            right.append(anchor)
        } else {
            left.append("old payload \(index)")
            right.append("new payload \(index)")
        }
    }
    return (left, right)
}

private func write(_ contents: String, to url: URL) {
    try! Data(contents.utf8).write(to: url)
}

private func makeFolderScenario(fileCount: Int) -> (root: URL, left: URL, right: URL) {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "grapecompare-benchmark-\(UUID().uuidString)")
    let left = root.appending(path: "left")
    let right = root.appending(path: "right")
    try! FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
    try! FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)

    let directoryCount = max(1, fileCount / 100)
    for directory in 0..<directoryCount {
        try! FileManager.default.createDirectory(
            at: left.appending(path: "group-\(directory)"), withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(
            at: right.appending(path: "group-\(directory)"), withIntermediateDirectories: true)
    }
    for index in 0..<fileCount {
        let relativePath = "group-\(index % directoryCount)/item-\(index).txt"
        let common = "record \(index)\nvalue \(index * 17)\n"
        switch index % 100 {
        case 0:
            write("left-only \(index)", to: left.appending(path: relativePath))
        case 1:
            write("right-only \(index)", to: right.appending(path: relativePath))
        case 2:
            write("left changed \(index)", to: left.appending(path: relativePath))
            write("right changed payload \(index)", to: right.appending(path: relativePath))
        case 3:
            write("AAAA \(index)", to: left.appending(path: relativePath))
            write("BBBB \(index)", to: right.appending(path: relativePath))
        default:
            write(common, to: left.appending(path: relativePath))
            write(common, to: right.appending(path: relativePath))
        }
    }
    return (root, left, right)
}

private func addLargeBinaryPair(left: URL, right: URL, byteCount: Int) {
    var payload = Data(repeating: 0xA5, count: byteCount)
    payload[17] = 0
    try! payload.write(to: left.appending(path: "large-binary.bin"))
    payload[payload.count - 1] = 0x5A
    try! payload.write(to: right.appending(path: "large-binary.bin"))
}

let arguments = CommandLine.arguments.dropFirst()
let lineCount = arguments.first.flatMap(Int.init) ?? 100_000
let folderFileCount = arguments.dropFirst().first.flatMap(Int.init) ?? 10_000
private var measurements: [Measurement] = []

print("Preparing \(lineCount)-line file scenarios…")
let sparse = makeLargeFileScenario(lineCount: lineCount)
var sparseOps: [LineOp] = []
measurements.append(measure("large file / sparse edits", detail: "\(lineCount) lines") {
    sparseOps = DiffEngine.diff(old: sparse.left, new: sparse.right)
})
let sparseRebuilt = reconstructed(sparseOps)
precondition(sparseRebuilt.old == sparse.left && sparseRebuilt.new == sparse.right)
let sparseLeftText = sparse.left.joined(separator: "\n")
let sparseRightText = sparse.right.joined(separator: "\n")
var sparseResult = FileDiffResult()
measurements.append(measure("large text / sparse end-to-end", detail: "split + diff + rows") {
    sparseResult = DiffEngine.diffText(left: sparseLeftText, right: sparseRightText)
})
precondition(sparseResult.differenceCount > 0)

let churnCount = max(10_000, min(lineCount, 30_000))
let churn = makeHighChurnScenario(lineCount: churnCount)
var churnOps: [LineOp] = []
measurements.append(measure("large file / high churn", detail: "\(churnCount) lines") {
    churnOps = DiffEngine.diff(old: churn.left, new: churn.right)
})
let churnRebuilt = reconstructed(churnOps)
precondition(churnRebuilt.old == churn.left && churnRebuilt.new == churn.right)
precondition(churnOps.reduce(into: 0) { count, operation in
    if case .equal = operation { count += 1 }
} == churnCount / 100)
let churnLeftText = churn.left.joined(separator: "\n")
let churnRightText = churn.right.joined(separator: "\n")
var churnResult = FileDiffResult()
measurements.append(measure("large text / churn end-to-end", detail: "split + diff + rows") {
    churnResult = DiffEngine.diffText(left: churnLeftText, right: churnRightText)
})
precondition(churnResult.differenceCount == churnCount - churnCount / 100)

print("Preparing \(folderFileCount)-file folder scenario…")
let folders = makeFolderScenario(fileCount: folderFileCount)
defer { try? FileManager.default.removeItem(at: folders.root) }
addLargeBinaryPair(left: folders.left, right: folders.right, byteCount: 64 * 1_024 * 1_024)
var folderStats = FolderCompareStats()
measurements.append(measure("large folder", detail: "\(folderFileCount) logical files") {
    let result = FolderComparator.compare(leftRoot: folders.left, rightRoot: folders.right)
    folderStats = FolderComparator.stats(for: result)
})
let expectedBucket = folderFileCount / 100
precondition(folderStats.onlyLeft == expectedBucket)
precondition(folderStats.onlyRight == expectedBucket)
precondition(folderStats.different == expectedBucket * 2 + 1)
precondition(folderStats.same == folderFileCount - expectedBucket * 4)

print("\nPerformance results (Release, lower is better)")
for result in measurements {
    print(String(format: "  %-30s %8.3f s  %@", (result.name as NSString).utf8String!, result.seconds, result.detail))
}
