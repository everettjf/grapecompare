import Foundation

@main
enum RealFolderBenchmark {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            fputs("usage: real-folder-benchmark <left-directory> <right-directory>\n", stderr)
            exit(64)
        }

        let left = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
        let right = URL(fileURLWithPath: arguments[2], isDirectory: true).standardizedFileURL
        var leftIsDirectory: ObjCBool = false
        var rightIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: left.path, isDirectory: &leftIsDirectory),
              FileManager.default.fileExists(atPath: right.path, isDirectory: &rightIsDirectory),
              leftIsDirectory.boolValue, rightIsDirectory.boolValue else {
            fputs("both inputs must be existing directories\n", stderr)
            exit(66)
        }

        let started = ContinuousClock.now
        let root = try FolderComparator.compareCancellable(leftRoot: left, rightRoot: right)
        let elapsed = started.duration(to: .now)
        let stats = FolderComparator.stats(for: root)
        let seconds = Double(elapsed.components.seconds) +
            Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

        print("left=\(left.path)")
        print("right=\(right.path)")
        print("elapsed_seconds=\(String(format: "%.6f", seconds))")
        print("same=\(stats.same)")
        print("different=\(stats.different)")
        print("only_left=\(stats.onlyLeft)")
        print("only_right=\(stats.onlyRight)")
        print("total_leaves=\(stats.same + stats.different + stats.onlyLeft + stats.onlyRight)")
    }
}
