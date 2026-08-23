import Foundation

private enum Exit: Int32 {
    case success = 0
    case different = 1
    case usageOrFailure = 2
}

private func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func usage() -> Never {
    writeStandardError("""
    Usage:
      grapecompare diff <left> <right> [--patch]
      grapecompare merge <base> <ours> <theirs> <output>
      grapecompare structured <json|plist> <left> <right>
      grapecompare image <left> <right>
      grapecompare git <repository> <from> <to|INDEX|WORKTREE>
      grapecompare folder-sync <left> <right> <mirror|update> --dry-run
      grapecompare git-config

    Exit status: 0 identical/resolved, 1 different/conflicts, 2 invalid input or failure.
    """)
    exit(Exit.usageOrFailure.rawValue)
}

private func read(_ path: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
}

private func atomicWrite(_ data: Data, to path: String) throws {
    let destination = URL(fileURLWithPath: path).standardizedFileURL
    let parent = destination.deletingLastPathComponent()
    let temporary = parent.appending(
        path: ".grapecompare-cli-\(UUID().uuidString).tmp",
        directoryHint: .notDirectory)
    do {
        try data.write(to: temporary, options: [.atomic])
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    } catch {
        try? FileManager.default.removeItem(at: temporary)
        throw error
    }
}

private func conflictText(_ result: ThreeWayMergeResult) -> String {
    var output = ""
    for segment in result.segments {
        switch segment {
        case .resolved(let lines):
            output += lines.map { $0.content + $0.ending.text }.joined()
        case .conflict(let conflict):
            output += "<<<<<<< ours\n"
            output += conflict.oursLines.map { $0.content + "\n" }.joined()
            output += "||||||| base\n"
            output += conflict.baseLines.map { $0.content + "\n" }.joined()
            output += "=======\n"
            output += conflict.theirsLines.map { $0.content + "\n" }.joined()
            output += ">>>>>>> theirs\n"
        }
    }
    return output
}

private func run() throws -> Exit {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { usage() }
    switch command {
    case "diff":
        guard arguments.count == 3 ||
              (arguments.count == 4 && arguments[3] == "--patch") else { usage() }
        let left = try TextSnapshot(data: read(arguments[1]))
        let right = try TextSnapshot(data: read(arguments[2]))
        let comparison = TextComparisonEngine.compare(left: left, right: right)
        if arguments.last == "--patch", !comparison.exactIdentical {
            print(try UnifiedDiffWriter.makePatch(
                left: left,
                right: right,
                leftPath: "a/\(URL(fileURLWithPath: arguments[1]).lastPathComponent)",
                rightPath: "b/\(URL(fileURLWithPath: arguments[2]).lastPathComponent)"),
                terminator: "")
        } else {
            print(comparison.exactIdentical
                ? "identical"
                : "different: \(comparison.hunks.count) hunk(s)")
        }
        return comparison.exactIdentical ? .success : .different

    case "merge":
        guard arguments.count == 5 else { usage() }
        let base = try TextSnapshot(data: read(arguments[1]))
        let ours = try TextSnapshot(data: read(arguments[2]))
        let theirs = try TextSnapshot(data: read(arguments[3]))
        let result = ThreeWayMergeEngine.merge(base: base, ours: ours, theirs: theirs)
        if let lines = result.renderedLines() {
            let output = try TextSnapshot(lines: lines, encoding: ours.encoding)
            try atomicWrite(try output.encodedData(), to: arguments[4])
            print("merged")
            return .success
        }
        try atomicWrite(Data(conflictText(result).utf8), to: arguments[4])
        print("conflicts: \(result.conflictCount)")
        return .different

    case "structured":
        guard arguments.count == 4,
              let format = [
                "json": StructuredFormat.json,
                "plist": StructuredFormat.propertyList
              ][arguments[1]] else { usage() }
        let left = try StructuredDataComparator.decode(read(arguments[2]), format: format)
        let right = try StructuredDataComparator.decode(read(arguments[3]), format: format)
        let differences = StructuredDataComparator.compare(left: left, right: right)
        for difference in differences {
            print("\(difference.kind.rawValue)\t\(difference.path)\t" +
                  "\(difference.left?.summary ?? "-")\t\(difference.right?.summary ?? "-")")
        }
        return differences.isEmpty ? .success : .different

    case "image":
        guard arguments.count == 3 else { usage() }
        let left = try ImageRaster.decode(read(arguments[1]))
        let right = try ImageRaster.decode(read(arguments[2]))
        let result = ImageComparisonEngine.compare(left: left, right: right)
        print("left=\(result.leftWidth)x\(result.leftHeight) " +
              "right=\(result.rightWidth)x\(result.rightHeight) " +
              "pixels=\(result.differingPixelCount)/\(result.comparedPixelCount) " +
              "mean=\(result.meanAbsoluteDifference)")
        return result.identical ? .success : .different

    case "git":
        guard arguments.count == 4 else { usage() }
        let repository = URL(fileURLWithPath: arguments[1])
        let changes = try GitRepositoryComparator.changes(
            in: try GitRepositoryComparator.repositoryRoot(at: repository),
            from: GitComparisonTarget.parse(arguments[2]),
            to: GitComparisonTarget.parse(arguments[3]))
        for change in changes {
            if let oldPath = change.oldPath {
                print("\(change.kind.rawValue)\t\(oldPath)\t\(change.path)")
            } else {
                print("\(change.kind.rawValue)\t\(change.path)")
            }
        }
        return changes.isEmpty ? .success : .different

    case "git-config":
        guard arguments.count == 1 else { usage() }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        print("""
        [diff]
            tool = grapecompare
        [difftool "grapecompare"]
            cmd = \"\(executable)\" diff \"$LOCAL\" \"$REMOTE\"; code=$?; test $code -le 1
        [merge]
            tool = grapecompare
        [mergetool "grapecompare"]
            cmd = sentinel=\"$MERGED.grapecompare-resolved.$$\"; open -W -n -a GrapeCompare --args --merge \"$BASE\" \"$LOCAL\" \"$REMOTE\" \"$MERGED\" \"$sentinel\"; code=$?; test $code -eq 0 && test -f \"$sentinel\"; code=$?; rm -f \"$sentinel\"; exit $code
            trustExitCode = true
        """)
        return .success

    case "folder-sync":
        guard arguments.count == 5, arguments[4] == "--dry-run",
              let mode = FolderSyncMode(rawValue: arguments[3]), mode != .custom else { usage() }
        let left = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        let right = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        let tree = try FolderComparator.compareCancellable(leftRoot: left, rightRoot: right)
        let drafts = FolderSyncPlanner.drafts(root: tree, leftRoot: left, rightRoot: right, mode: mode)
        let plan = try FileOperationEngine().prepare(drafts: drafts)
        FileHandle.standardOutput.write(try FileOperationReport(plan: plan, dryRun: true).encodedJSON())
        FileHandle.standardOutput.write(Data("\n".utf8))
        return drafts.isEmpty ? .success : .different

    default:
        usage()
    }
}

do {
    exit(try run().rawValue)
} catch {
    writeStandardError("grapecompare: \(error.localizedDescription)")
    exit(Exit.usageOrFailure.rawValue)
}
