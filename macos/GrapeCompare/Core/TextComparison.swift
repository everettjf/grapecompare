import Foundation

nonisolated enum TextFileEncoding: String, Sendable {
    case utf8
    case utf8WithBOM
    case utf16LittleEndian
    case utf16BigEndian

    var byteOrderMark: Data {
        switch self {
        case .utf8: Data()
        case .utf8WithBOM: Data([0xEF, 0xBB, 0xBF])
        case .utf16LittleEndian: Data([0xFF, 0xFE])
        case .utf16BigEndian: Data([0xFE, 0xFF])
        }
    }

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8, .utf8WithBOM: .utf8
        case .utf16LittleEndian: .utf16LittleEndian
        case .utf16BigEndian: .utf16BigEndian
        }
    }
}

nonisolated enum TextLineEnding: String, CaseIterable, Sendable {
    case none
    case lf
    case crlf
    case cr

    var text: String {
        switch self {
        case .none: ""
        case .lf: "\n"
        case .crlf: "\r\n"
        case .cr: "\r"
        }
    }
}

nonisolated struct TextLine: Equatable, Sendable {
    var content: String
    var ending: TextLineEnding
}

nonisolated enum TextSnapshotError: Error, Equatable, LocalizedError {
    case binary
    case unsupportedEncoding
    case cannotEncode

    var errorDescription: String? {
        switch self {
        case .binary: "The file contains binary data."
        case .unsupportedEncoding: "The text encoding cannot be decoded without data loss."
        case .cannotEncode: "The edited text cannot be written using the original encoding."
        }
    }
}

/// Lossless, immutable text input. Line endings remain attached to their source lines so
/// comparison normalization can never silently change the bytes later written or exported.
nonisolated struct TextSnapshot: Equatable, Sendable {
    let lines: [TextLine]
    let encoding: TextFileEncoding
    let fingerprint: UInt64
    let byteCount: Int

    init(data: Data) throws {
        let decoded: (String, TextFileEncoding)
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let string = String(data: data.dropFirst(3), encoding: .utf8) else {
                throw TextSnapshotError.unsupportedEncoding
            }
            decoded = (string, .utf8WithBOM)
        } else if data.starts(with: [0xFF, 0xFE]) {
            guard let string = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) else {
                throw TextSnapshotError.unsupportedEncoding
            }
            decoded = (string, .utf16LittleEndian)
        } else if data.starts(with: [0xFE, 0xFF]) {
            guard let string = String(data: data.dropFirst(2), encoding: .utf16BigEndian) else {
                throw TextSnapshotError.unsupportedEncoding
            }
            decoded = (string, .utf16BigEndian)
        } else {
            if data.prefix(8_000).contains(0) { throw TextSnapshotError.binary }
            guard let string = String(data: data, encoding: .utf8) else {
                throw TextSnapshotError.unsupportedEncoding
            }
            decoded = (string, .utf8)
        }

        lines = Self.tokenize(decoded.0)
        encoding = decoded.1
        fingerprint = Self.fingerprint(data)
        byteCount = data.count
    }

    init(lines: [TextLine], encoding: TextFileEncoding = .utf8) throws {
        self.lines = lines
        self.encoding = encoding
        let encoded = try Self.encode(lines: lines, encoding: encoding)
        fingerprint = Self.fingerprint(encoded)
        byteCount = encoded.count
    }

    init(text: String, encoding: TextFileEncoding = .utf8) throws {
        try self.init(lines: Self.tokenize(text), encoding: encoding)
    }

    var text: String {
        lines.reduce(into: "") { result, line in
            result += line.content
            result += line.ending.text
        }
    }

    var hasFinalNewline: Bool {
        lines.last?.ending != TextLineEnding.none
    }

    var dominantLineEnding: TextLineEnding {
        var counts: [TextLineEnding: Int] = [:]
        for line in lines where line.ending != .none {
            counts[line.ending, default: 0] += 1
        }
        return TextLineEnding.allCases
            .filter { $0 != .none }
            .max { lhs, rhs in
                let leftCount = counts[lhs, default: 0]
                let rightCount = counts[rhs, default: 0]
                return leftCount == rightCount
                    ? Self.endingRank(lhs) > Self.endingRank(rhs)
                    : leftCount < rightCount
            } ?? .lf
    }

    func encodedData() throws -> Data {
        try Self.encode(lines: lines, encoding: encoding)
    }

    private static func tokenize(_ text: String) -> [TextLine] {
        guard !text.isEmpty else { return [] }
        let scalars = Array(text.unicodeScalars.map(\.value))
        var result: [TextLine] = []
        var content: [UInt32] = []
        var index = 0

        func decodedContent() -> String {
            String(decoding: content, as: UTF32.self)
        }

        while index < scalars.count {
            switch scalars[index] {
            case 0x0A:
                result.append(TextLine(content: decodedContent(), ending: .lf))
                content.removeAll(keepingCapacity: true)
            case 0x0D:
                if index + 1 < scalars.count, scalars[index + 1] == 0x0A {
                    result.append(TextLine(content: decodedContent(), ending: .crlf))
                    index += 1
                } else {
                    result.append(TextLine(content: decodedContent(), ending: .cr))
                }
                content.removeAll(keepingCapacity: true)
            default:
                content.append(scalars[index])
            }
            index += 1
        }
        if !content.isEmpty {
            result.append(TextLine(content: decodedContent(), ending: .none))
        }
        return result
    }

    private static func encode(lines: [TextLine], encoding: TextFileEncoding) throws -> Data {
        let string = lines.reduce(into: "") { result, line in
            result += line.content
            result += line.ending.text
        }
        guard let body = string.data(using: encoding.stringEncoding, allowLossyConversion: false) else {
            throw TextSnapshotError.cannotEncode
        }
        var result = encoding.byteOrderMark
        result.append(body)
        return result
    }

    private static func fingerprint(_ data: Data) -> UInt64 {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return value
    }

    private static func endingRank(_ ending: TextLineEnding) -> Int {
        switch ending {
        case .lf: 0
        case .crlf: 1
        case .cr: 2
        case .none: 3
        }
    }
}

nonisolated enum WhitespaceComparison: String, CaseIterable, Sendable {
    case exact
    case ignoreChanges
    case ignoreAll
}

nonisolated struct TextComparisonOptions: Equatable, Sendable {
    var whitespace: WhitespaceComparison = .exact
    var ignoreCase = false
    var ignoreLineEndingFormat = true
    var ignoreFinalNewline = false

    static let exact = TextComparisonOptions(ignoreLineEndingFormat: false)
}

nonisolated struct DiffHunk: Identifiable, Equatable, Sendable {
    let id: String
    let leftRange: Range<Int>
    let rightRange: Range<Int>
    let leftLines: [TextLine]
    let rightLines: [TextLine]
}

nonisolated struct TextComparisonResult: Equatable, Sendable {
    let leftFingerprint: UInt64
    let rightFingerprint: UInt64
    let exactIdentical: Bool
    let equivalentUnderOptions: Bool
    let hunks: [DiffHunk]
}

nonisolated enum TextComparisonEngine {
    static func compare(
        left: TextSnapshot,
        right: TextSnapshot,
        options: TextComparisonOptions = .exact
    ) -> TextComparisonResult {
        let leftKeys = keys(for: left, options: options)
        let rightKeys = keys(for: right, options: options)
        let operations = DiffEngine.diff(old: leftKeys, new: rightKeys)
        let hunks = makeHunks(operations: operations, left: left, right: right)
        return TextComparisonResult(
            leftFingerprint: left.fingerprint,
            rightFingerprint: right.fingerprint,
            exactIdentical: left.fingerprint == right.fingerprint && left.byteCount == right.byteCount,
            equivalentUnderOptions: hunks.isEmpty,
            hunks: hunks)
    }

    static func keys(
        for snapshot: TextSnapshot,
        options: TextComparisonOptions
    ) -> [String] {
        snapshot.lines.enumerated().map { index, line in
            var content = normalizeWhitespace(line.content, policy: options.whitespace)
            if options.ignoreCase {
                content = content.folding(
                    options: [.caseInsensitive],
                    locale: Locale(identifier: "en_US_POSIX"))
            }
            let isLast = index == snapshot.lines.count - 1
            let ending: String
            if options.ignoreFinalNewline && isLast {
                ending = ""
            } else if options.ignoreLineEndingFormat {
                ending = line.ending == .none ? "" : "\n"
            } else {
                ending = line.ending.text
            }
            return content + "\u{0}" + ending
        }
    }

    private static func normalizeWhitespace(
        _ value: String,
        policy: WhitespaceComparison
    ) -> String {
        guard policy != .exact else { return value }
        let isHorizontalWhitespace: (Unicode.Scalar) -> Bool = { scalar in
            scalar != "\n" && scalar != "\r" && CharacterSet.whitespaces.contains(scalar)
        }
        switch policy {
        case .exact:
            return value
        case .ignoreAll:
            return String(value.unicodeScalars.filter { !isHorizontalWhitespace($0) })
        case .ignoreChanges:
            var result = ""
            var pendingSpace = false
            for scalar in value.unicodeScalars {
                if isHorizontalWhitespace(scalar) {
                    if !result.isEmpty { pendingSpace = true }
                } else {
                    if pendingSpace { result.append(" ") }
                    result.unicodeScalars.append(scalar)
                    pendingSpace = false
                }
            }
            return result
        }
    }

    private static func makeHunks(
        operations: [LineOp],
        left: TextSnapshot,
        right: TextSnapshot
    ) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var leftIndex = 0
        var rightIndex = 0
        var hunkLeftStart: Int?
        var hunkRightStart: Int?

        func finishHunk() {
            guard let leftStart = hunkLeftStart, let rightStart = hunkRightStart else { return }
            let leftRange = leftStart..<leftIndex
            let rightRange = rightStart..<rightIndex
            let id = String(
                format: "%016llx-%016llx-%d-%d-%d-%d",
                left.fingerprint, right.fingerprint,
                leftRange.lowerBound, leftRange.upperBound,
                rightRange.lowerBound, rightRange.upperBound)
            hunks.append(DiffHunk(
                id: id,
                leftRange: leftRange,
                rightRange: rightRange,
                leftLines: Array(left.lines[leftRange]),
                rightLines: Array(right.lines[rightRange])))
            hunkLeftStart = nil
            hunkRightStart = nil
        }

        for operation in operations {
            switch operation {
            case .equal:
                finishHunk()
                leftIndex += 1
                rightIndex += 1
            case .delete:
                if hunkLeftStart == nil {
                    hunkLeftStart = leftIndex
                    hunkRightStart = rightIndex
                }
                leftIndex += 1
            case .insert:
                if hunkLeftStart == nil {
                    hunkLeftStart = leftIndex
                    hunkRightStart = rightIndex
                }
                rightIndex += 1
            }
        }
        finishHunk()
        return hunks
    }
}

nonisolated enum TextSide: String, Sendable {
    case left
    case right
}

/// Deterministically constructs an output document from one immutable baseline and a set
/// of per-hunk choices. Rebuilding from source ranges avoids offset drift after insertions.
nonisolated struct TextOutputSession: Sendable {
    let left: TextSnapshot
    let right: TextSnapshot
    let comparison: TextComparisonResult
    var baseline: TextSide
    private(set) var choices: [DiffHunk.ID: TextSide] = [:]

    init(
        left: TextSnapshot,
        right: TextSnapshot,
        comparison: TextComparisonResult,
        baseline: TextSide = .right
    ) {
        precondition(comparison.leftFingerprint == left.fingerprint)
        precondition(comparison.rightFingerprint == right.fingerprint)
        self.left = left
        self.right = right
        self.comparison = comparison
        self.baseline = baseline
    }

    mutating func accept(_ side: TextSide, hunkID: DiffHunk.ID) {
        guard comparison.hunks.contains(where: { $0.id == hunkID }) else { return }
        choices[hunkID] = side
    }

    /// Applies a choice while retaining independent edits from the current output.
    /// The explicit hunk choice wins when a manual edit overlaps the same range.
    mutating func acceptPreservingManualEdits(
        _ side: TextSide,
        hunkID: DiffHunk.ID,
        currentOutput: TextSnapshot
    ) throws -> TextSnapshot {
        let previousGenerated = try snapshot()
        accept(side, hunkID: hunkID)
        let nextGenerated = try snapshot()
        guard currentOutput.fingerprint != previousGenerated.fingerprint ||
                currentOutput.byteCount != previousGenerated.byteCount else {
            return nextGenerated
        }
        let merged = ThreeWayMergeEngine.merge(
            base: previousGenerated,
            ours: currentOutput,
            theirs: nextGenerated)
        let resolutions = Dictionary(
            uniqueKeysWithValues: merged.conflicts.map { ($0.id, MergeConflictChoice.theirs) })
        guard let lines = merged.renderedLines(resolving: resolutions) else {
            return nextGenerated
        }
        return try TextSnapshot(lines: lines, encoding: right.encoding)
    }

    mutating func reset(hunkID: DiffHunk.ID) {
        choices.removeValue(forKey: hunkID)
    }

    func renderedLines() -> [TextLine] {
        let source = baseline == .left ? left.lines : right.lines
        var result: [TextLine] = []
        var cursor = 0
        for hunk in comparison.hunks {
            let baselineRange = baseline == .left ? hunk.leftRange : hunk.rightRange
            result.append(contentsOf: source[cursor..<baselineRange.lowerBound])
            let selectedSide = choices[hunk.id] ?? baseline
            result.append(contentsOf: selectedSide == .left ? hunk.leftLines : hunk.rightLines)
            cursor = baselineRange.upperBound
        }
        result.append(contentsOf: source[cursor..<source.count])
        return result
    }

    func snapshot() throws -> TextSnapshot {
        let encoding = baseline == .left ? left.encoding : right.encoding
        return try TextSnapshot(lines: renderedLines(), encoding: encoding)
    }
}
