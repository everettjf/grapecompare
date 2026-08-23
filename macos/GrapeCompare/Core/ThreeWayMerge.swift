import Foundation

nonisolated struct MergeConflict: Identifiable, Equatable, Sendable {
    let id: String
    let baseRange: Range<Int>
    let baseLines: [TextLine]
    let oursLines: [TextLine]
    let theirsLines: [TextLine]
}

nonisolated enum MergeSegment: Equatable, Sendable {
    case resolved([TextLine])
    case conflict(MergeConflict)
}

nonisolated enum MergeConflictChoice: String, Sendable {
    case base
    case ours
    case theirs
    case both
}

nonisolated struct ThreeWayMergeResult: Equatable, Sendable {
    let baseFingerprint: UInt64
    let oursFingerprint: UInt64
    let theirsFingerprint: UInt64
    let segments: [MergeSegment]

    var conflicts: [MergeConflict] {
        segments.compactMap {
            if case .conflict(let conflict) = $0 { conflict } else { nil }
        }
    }

    var conflictCount: Int { conflicts.count }

    func renderedLines(
        resolving choices: [MergeConflict.ID: MergeConflictChoice] = [:]
    ) -> [TextLine]? {
        var output: [TextLine] = []
        for segment in segments {
            switch segment {
            case .resolved(let lines):
                output.append(contentsOf: lines)
            case .conflict(let conflict):
                guard let choice = choices[conflict.id] else { return nil }
                switch choice {
                case .base: output.append(contentsOf: conflict.baseLines)
                case .ours: output.append(contentsOf: conflict.oursLines)
                case .theirs: output.append(contentsOf: conflict.theirsLines)
                case .both:
                    output.append(contentsOf: conflict.oursLines)
                    output.append(contentsOf: conflict.theirsLines)
                }
            }
        }
        return output
    }
}

nonisolated enum ThreeWayMergeEngine {
    private enum Side: Int {
        case ours
        case theirs
    }

    private struct Edit {
        let side: Side
        let baseRange: Range<Int>
        let replacement: [TextLine]
    }

    static func merge(
        base: TextSnapshot,
        ours: TextSnapshot,
        theirs: TextSnapshot
    ) -> ThreeWayMergeResult {
        var edits = edits(from: base, to: ours, side: .ours)
        edits += self.edits(from: base, to: theirs, side: .theirs)
        edits.sort {
            if $0.baseRange.lowerBound != $1.baseRange.lowerBound {
                return $0.baseRange.lowerBound < $1.baseRange.lowerBound
            }
            if $0.baseRange.upperBound != $1.baseRange.upperBound {
                return $0.baseRange.upperBound < $1.baseRange.upperBound
            }
            return $0.side.rawValue < $1.side.rawValue
        }

        let clusters = cluster(edits)
        var segments: [MergeSegment] = []
        var cursor = 0
        for cluster in clusters {
            let lower = cluster.map(\.baseRange.lowerBound).min() ?? cursor
            let upper = cluster.map(\.baseRange.upperBound).max() ?? lower
            if cursor < lower {
                appendResolved(Array(base.lines[cursor..<lower]), to: &segments)
            }

            let range = lower..<upper
            let baseLines = Array(base.lines[range])
            let oursLines = apply(
                cluster.filter { $0.side == .ours },
                to: base.lines,
                in: range)
            let theirsLines = apply(
                cluster.filter { $0.side == .theirs },
                to: base.lines,
                in: range)

            if oursLines == theirsLines {
                appendResolved(oursLines, to: &segments)
            } else if oursLines == baseLines {
                appendResolved(theirsLines, to: &segments)
            } else if theirsLines == baseLines {
                appendResolved(oursLines, to: &segments)
            } else {
                let id = String(
                    format: "%016llx-%016llx-%016llx-%d-%d",
                    base.fingerprint, ours.fingerprint, theirs.fingerprint,
                    lower, upper)
                segments.append(.conflict(MergeConflict(
                    id: id,
                    baseRange: range,
                    baseLines: baseLines,
                    oursLines: oursLines,
                    theirsLines: theirsLines)))
            }
            cursor = max(cursor, upper)
        }
        if cursor < base.lines.count {
            appendResolved(Array(base.lines[cursor...]), to: &segments)
        }

        return ThreeWayMergeResult(
            baseFingerprint: base.fingerprint,
            oursFingerprint: ours.fingerprint,
            theirsFingerprint: theirs.fingerprint,
            segments: segments)
    }

    private static func edits(
        from base: TextSnapshot,
        to side: TextSnapshot,
        side mergeSide: Side
    ) -> [Edit] {
        TextComparisonEngine.compare(left: base, right: side)
            .hunks
            .map { Edit(
                side: mergeSide,
                baseRange: $0.leftRange,
                replacement: $0.rightLines)
            }
    }

    private static func cluster(_ edits: [Edit]) -> [[Edit]] {
        var result: [[Edit]] = []
        for edit in edits {
            guard var current = result.popLast() else {
                result.append([edit])
                continue
            }
            if current.contains(where: { overlaps($0.baseRange, edit.baseRange) }) {
                current.append(edit)
                // An edit may bridge multiple previous clusters. Merge backwards until the
                // cluster is transitively independent from its predecessor.
                while let previous = result.last,
                      previous.contains(where: { old in
                          current.contains { overlaps(old.baseRange, $0.baseRange) }
                      }) {
                    current.insert(contentsOf: result.removeLast(), at: 0)
                }
                result.append(current)
            } else {
                result.append(current)
                result.append([edit])
            }
        }
        return result
    }

    private static func overlaps(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
        if lhs.isEmpty || rhs.isEmpty {
            if lhs.isEmpty && rhs.isEmpty { return lhs.lowerBound == rhs.lowerBound }
            let insertion = lhs.isEmpty ? lhs.lowerBound : rhs.lowerBound
            let changed = lhs.isEmpty ? rhs : lhs
            return insertion > changed.lowerBound && insertion < changed.upperBound
        }
        return lhs.overlaps(rhs)
    }

    private static func apply(
        _ edits: [Edit],
        to base: [TextLine],
        in range: Range<Int>
    ) -> [TextLine] {
        guard !edits.isEmpty else { return Array(base[range]) }
        let sorted = edits.sorted {
            if $0.baseRange.lowerBound != $1.baseRange.lowerBound {
                return $0.baseRange.lowerBound < $1.baseRange.lowerBound
            }
            return $0.baseRange.upperBound < $1.baseRange.upperBound
        }
        var result: [TextLine] = []
        var cursor = range.lowerBound
        for edit in sorted {
            if cursor < edit.baseRange.lowerBound {
                result.append(contentsOf: base[cursor..<edit.baseRange.lowerBound])
            }
            result.append(contentsOf: edit.replacement)
            cursor = max(cursor, edit.baseRange.upperBound)
        }
        if cursor < range.upperBound {
            result.append(contentsOf: base[cursor..<range.upperBound])
        }
        return result
    }

    private static func appendResolved(
        _ lines: [TextLine],
        to segments: inout [MergeSegment]
    ) {
        guard !lines.isEmpty else { return }
        if case .resolved(let previous)? = segments.last {
            segments[segments.count - 1] = .resolved(previous + lines)
        } else {
            segments.append(.resolved(lines))
        }
    }
}

nonisolated enum MergeOutputValidator {
    private static let markerPrefixes = ["<<<<<<<", "|||||||", "=======", ">>>>>>>"]

    static func containsConflictMarkers(_ text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            return markerPrefixes.contains { trimmed.hasPrefix($0) }
        }
    }
}
