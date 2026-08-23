import Darwin
import Foundation

private func runGit(_ arguments: [String], in directory: URL) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  process.arguments = arguments
  process.currentDirectoryURL = directory
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw GitRepositoryError.commandFailed(arguments: arguments, message: "fixture setup failed")
  }
}

private func measure<T>(_ operation: () throws -> T) rethrows -> (T, Double) {
  let start = ContinuousClock.now
  let value = try operation()
  return (value, Double(start.duration(to: .now).components.attoseconds) / 1e18)
}

@main
private enum GitBenchmark {
  static func main() throws {
    let arguments = CommandLine.arguments
    let changedFileCount = arguments.count > 1 ? max(Int(arguments[1]) ?? 5_000, 1) : 5_000
    let historyCommitCount = arguments.count > 2 ? max(Int(arguments[2]) ?? 100, 2) : 100
    let root = FileManager.default.temporaryDirectory
      .appending(path: "grapecompare-git-benchmark-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try runGit(["init", "-q", "-b", "main"], in: root)
    try runGit(["config", "user.email", "benchmark@grapecompare.local"], in: root)
    try runGit(["config", "user.name", "GrapeCompare Benchmark"], in: root)

    print("Preparing \(changedFileCount) tracked files…")
    for index in 0..<changedFileCount {
      try Data("before \(index)\n".utf8).write(to: root.appending(path: "file-\(index).txt"))
    }
    try runGit(["add", "."], in: root)
    try runGit(["commit", "-q", "-m", "baseline"], in: root)
    for index in 0..<changedFileCount {
      try Data("after \(index)\n".utf8).write(to: root.appending(path: "file-\(index).txt"))
    }

    let (changes, changesSeconds) = try measure {
      try GitRepositoryComparator.changes(in: root, from: .revision("HEAD"), to: .workingTree)
    }
    guard changes.count == changedFileCount else {
      fatalError("Expected \(changedFileCount) changes, got \(changes.count)")
    }

    try runGit(["add", "."], in: root)
    try runGit(["commit", "-q", "-m", "changed files"], in: root)
    let historyFile = root.appending(path: "history.txt")
    for index in 0..<historyCommitCount {
      try Data("revision \(index)\n".utf8).write(to: historyFile)
      try runGit(["add", "history.txt"], in: root)
      try runGit(["commit", "-q", "-m", "history \(index)"], in: root)
    }
    let (history, historySeconds) = try measure {
      try GitRepositoryComparator.fileRevisions(
        in: root, path: "history.txt", limit: historyCommitCount)
    }
    guard history.count == historyCommitCount else {
      fatalError("Expected \(historyCommitCount) history entries, got \(history.count)")
    }

    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let peakResidentMB = Double(usage.ru_maxrss) / 1_048_576
    print(String(format: "Git changeset (%d files): %.3f s", changedFileCount, changesSeconds))
    print(String(format: "Git history (%d commits): %.3f s", historyCommitCount, historySeconds))
    print(String(format: "Peak resident memory: %.1f MB", peakResidentMB))

    if ProcessInfo.processInfo.environment["GRAPECOMPARE_VERIFY_PERFORMANCE"] == "1" {
      let changesBudget = max(2.0, Double(changedFileCount) / 5_000 * 2.0)
      let historyBudget = max(1.0, Double(historyCommitCount) / 100)
      var violations: [String] = []
      if changesSeconds > changesBudget {
        violations.append("changeset \(changesSeconds)s exceeded \(changesBudget)s")
      }
      if historySeconds > historyBudget {
        violations.append("history \(historySeconds)s exceeded \(historyBudget)s")
      }
      if peakResidentMB > 512 {
        violations.append("peak memory \(peakResidentMB)MB exceeded 512MB")
      }
      guard violations.isEmpty else {
        violations.forEach { fputs("PERFORMANCE REGRESSION: \($0)\n", stderr) }
        exit(2)
      }
      print("GIT PERFORMANCE BUDGETS PASSED")
    }
  }
}
