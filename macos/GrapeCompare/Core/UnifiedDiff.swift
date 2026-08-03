import Foundation

nonisolated enum UnifiedDiffError: Error, Equatable, LocalizedError {
    case invalidContext

    var errorDescription: String? {
        switch self {
        case .invalidContext: "Patch context must be zero or greater."
        }
    }
}

/// Standards-compatible unified text diff. Input comparison is always exact: presentation
/// options such as ignored whitespace never leak into exported file contents.
nonisolated enum UnifiedDiffWriter {
    private enum Kind {
        case equal
        case delete
        case insert
    }

    private struct Operation {
        let kind: Kind
        let leftIndex: Int?
        let rightIndex: Int?

        var consumesLeft: Bool { kind != .insert }
        var consumesRight: Bool { kind != .delete }
        var isChange: Bool { kind != .equal }
    }

    static func makePatch(
        left: TextSnapshot,
        right: TextSnapshot,
        leftPath: String,
        rightPath: String,
        context: Int = 3
    ) throws -> String {
        guard context >= 0 else { throw UnifiedDiffError.invalidContext }
        let operations = makeOperations(left: left, right: right)
        let ranges = hunkRanges(operations: operations, context: context)
        guard !ranges.isEmpty else { return "" }

        var result = "--- \(sanitizePath(leftPath))\n+++ \(sanitizePath(rightPath))\n"
        for range in ranges {
            let before = operations[..<range.lowerBound]
            let oldBefore = before.lazy.filter(\.consumesLeft).count
            let newBefore = before.lazy.filter(\.consumesRight).count
            let body = operations[range]
            let oldCount = body.lazy.filter(\.consumesLeft).count
            let newCount = body.lazy.filter(\.consumesRight).count
            result += "@@ -\(coordinate(before: oldBefore, count: oldCount))"
            result += " +\(coordinate(before: newBefore, count: newCount)) @@\n"

            for operation in body {
                switch operation.kind {
                case .equal:
                    append(line: left.lines[operation.leftIndex!], prefix: " ", to: &result)
                case .delete:
                    append(line: left.lines[operation.leftIndex!], prefix: "-", to: &result)
                case .insert:
                    append(line: right.lines[operation.rightIndex!], prefix: "+", to: &result)
                }
            }
        }
        return result
    }

    private static func makeOperations(
        left: TextSnapshot,
        right: TextSnapshot
    ) -> [Operation] {
        let options = TextComparisonOptions.exact
        let leftKeys = TextComparisonEngine.keys(for: left, options: options)
        let rightKeys = TextComparisonEngine.keys(for: right, options: options)
        let lineOperations = DiffEngine.diff(old: leftKeys, new: rightKeys)
        var leftIndex = 0
        var rightIndex = 0
        return lineOperations.map { operation in
            switch operation {
            case .equal:
                defer { leftIndex += 1; rightIndex += 1 }
                return Operation(kind: .equal, leftIndex: leftIndex, rightIndex: rightIndex)
            case .delete:
                defer { leftIndex += 1 }
                return Operation(kind: .delete, leftIndex: leftIndex, rightIndex: nil)
            case .insert:
                defer { rightIndex += 1 }
                return Operation(kind: .insert, leftIndex: nil, rightIndex: rightIndex)
            }
        }
    }

    private static func hunkRanges(
        operations: [Operation],
        context: Int
    ) -> [Range<Int>] {
        let changes = operations.indices.filter { operations[$0].isChange }
        guard let first = changes.first else { return [] }
        var result: [Range<Int>] = []
        var currentStart = max(operations.startIndex, first - context)
        var currentEnd = min(operations.endIndex, first + context + 1)
        for position in changes.dropFirst() {
            let start = max(operations.startIndex, position - context)
            let end = min(operations.endIndex, position + context + 1)
            if start <= currentEnd {
                currentEnd = max(currentEnd, end)
            } else {
                result.append(currentStart..<currentEnd)
                currentStart = start
                currentEnd = end
            }
        }
        result.append(currentStart..<currentEnd)
        return result
    }

    private static func coordinate(before: Int, count: Int) -> String {
        let start = count == 0 ? before : before + 1
        return count == 1 ? String(start) : "\(start),\(count)"
    }

    private static func append(
        line: TextLine,
        prefix: Character,
        to result: inout String
    ) {
        result.append(prefix)
        result += line.content
        result.append("\n")
        if line.ending == .none {
            result += "\\ No newline at end of file\n"
        }
    }

    private static func sanitizePath(_ path: String) -> String {
        path.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
