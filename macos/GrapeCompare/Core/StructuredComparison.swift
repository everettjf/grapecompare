import CoreFoundation
import Foundation

nonisolated enum StructuredFormat: String, Sendable {
    case json
    case propertyList

    var displayName: String {
        switch self {
        case .json: "JSON"
        case .propertyList: "property list"
        }
    }
}

nonisolated enum StructuredValue: Equatable, Sendable {
    case null
    case boolean(Bool)
    case number(String)
    case string(String)
    case data(Data)
    case date(Date)
    case array([StructuredValue])
    case object([String: StructuredValue])

    var summary: String {
        switch self {
        case .null: "null"
        case .boolean(let value): String(value)
        case .number(let value): value
        case .string(let value): value
        case .data(let value): "<\(value.count) bytes>"
        case .date(let value): value.formatted(.iso8601)
        case .array(let value): "[\(value.count) items]"
        case .object(let value): "{\(value.count) keys}"
        }
    }
}

nonisolated enum StructuredComparisonError: Error, Equatable, LocalizedError {
    case invalidRoot
    case unsupportedValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidRoot: "The document does not contain a supported structured value."
        case .unsupportedValue(let type): "Unsupported structured value: \(type)."
        }
    }
}

nonisolated enum StructuredDifferenceKind: String, Sendable {
    case added
    case removed
    case changed
    case typeChanged
}

nonisolated struct StructuredDifference: Identifiable, Equatable, Sendable {
    let path: String
    let kind: StructuredDifferenceKind
    let left: StructuredValue?
    let right: StructuredValue?

    var id: String { path }
}

nonisolated enum StructuredDataComparator {
    static func decode(_ data: Data, format: StructuredFormat) throws -> StructuredValue {
        let object: Any
        switch format {
        case .json:
            let normalized = normalizeJSONQuotes(in: data)
            object = try JSONSerialization.jsonObject(
                with: normalized,
                options: [.fragmentsAllowed])
        case .propertyList:
            object = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil)
        }
        return try convert(object)
    }

    /// Preserve JSON Compare's forgiving paste behavior without changing the
    /// semantics of valid JSON files. Invalid UTF-8 remains a parser error.
    private static func normalizeJSONQuotes(in data: Data) -> Data {
        guard var source = String(data: data, encoding: .utf8) else { return data }
        source = source
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
        return Data(source.utf8)
    }

    static func compare(
        left: StructuredValue,
        right: StructuredValue
    ) -> [StructuredDifference] {
        var differences: [StructuredDifference] = []
        walk(left: left, right: right, path: "$", into: &differences)
        return differences
    }

    private static func convert(_ value: Any) throws -> StructuredValue {
        if value is NSNull { return .null }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            return .number(number.stringValue)
        }
        if let string = value as? String { return .string(string) }
        if let data = value as? Data { return .data(data) }
        if let date = value as? Date { return .date(date) }
        if let values = value as? [Any] {
            return .array(try values.map(convert))
        }
        if let values = value as? [String: Any] {
            return .object(try values.mapValues(convert))
        }
        throw StructuredComparisonError.unsupportedValue(String(describing: type(of: value)))
    }

    private static func walk(
        left: StructuredValue,
        right: StructuredValue,
        path: String,
        into differences: inout [StructuredDifference]
    ) {
        if left == right { return }
        switch (left, right) {
        case (.object(let lhs), .object(let rhs)):
            for key in Set(lhs.keys).union(rhs.keys).sorted() {
                let childPath = pathForKey(key, parent: path)
                switch (lhs[key], rhs[key]) {
                case (.some(let leftValue), .some(let rightValue)):
                    walk(
                        left: leftValue,
                        right: rightValue,
                        path: childPath,
                        into: &differences)
                case (.some(let leftValue), .none):
                    differences.append(StructuredDifference(
                        path: childPath,
                        kind: .removed,
                        left: leftValue,
                        right: nil))
                case (.none, .some(let rightValue)):
                    differences.append(StructuredDifference(
                        path: childPath,
                        kind: .added,
                        left: nil,
                        right: rightValue))
                case (.none, .none): break
                }
            }
        case (.array(let lhs), .array(let rhs)):
            for index in 0..<max(lhs.count, rhs.count) {
                let childPath = "\(path)[\(index)]"
                let leftValue = index < lhs.count ? lhs[index] : nil
                let rightValue = index < rhs.count ? rhs[index] : nil
                switch (leftValue, rightValue) {
                case (.some(let leftValue), .some(let rightValue)):
                    walk(
                        left: leftValue,
                        right: rightValue,
                        path: childPath,
                        into: &differences)
                case (.some(let leftValue), .none):
                    differences.append(StructuredDifference(
                        path: childPath,
                        kind: .removed,
                        left: leftValue,
                        right: nil))
                case (.none, .some(let rightValue)):
                    differences.append(StructuredDifference(
                        path: childPath,
                        kind: .added,
                        left: nil,
                        right: rightValue))
                case (.none, .none): break
                }
            }
        default:
            differences.append(StructuredDifference(
                path: path,
                kind: sameKind(left, right) ? .changed : .typeChanged,
                left: left,
                right: right))
        }
    }

    private static func sameKind(_ left: StructuredValue, _ right: StructuredValue) -> Bool {
        switch (left, right) {
        case (.null, .null),
             (.boolean, .boolean),
             (.number, .number),
             (.string, .string),
             (.data, .data),
             (.date, .date),
             (.array, .array),
             (.object, .object): true
        default: false
        }
    }

    private static func pathForKey(_ key: String, parent: String) -> String {
        let isIdentifier = key.unicodeScalars.enumerated().allSatisfy { index, scalar in
            let allowed = CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
            let validFirst = index > 0 || !CharacterSet.decimalDigits.contains(scalar)
            return allowed && validFirst
        }
        if isIdentifier, !key.isEmpty { return "\(parent).\(key)" }
        let escaped = key
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "\(parent)['\(escaped)']"
    }
}
