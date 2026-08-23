import Foundation
import Security

nonisolated struct XCStringsCatalogSummary: Equatable, Sendable {
    let sourceLanguage: String?
    let localizations: Set<String>
    let keys: Set<String>
    let canonical: StructuredValue
}

nonisolated enum XCStringsComparator {
    static func decode(_ data: Data) throws -> XCStringsCatalogSummary {
        let canonical = try StructuredDataComparator.decode(data, format: .json)
        guard case .object(let root) = canonical,
              case .object(let strings)? = root["strings"] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var locales: Set<String> = []
        for value in strings.values {
            guard case .object(let entry) = value,
                  case .object(let localizations)? = entry["localizations"] else { continue }
            locales.formUnion(localizations.keys)
        }
        let source: String?
        if case .string(let value)? = root["sourceLanguage"] { source = value } else { source = nil }
        return XCStringsCatalogSummary(sourceLanguage: source, localizations: locales,
                                       keys: Set(strings.keys), canonical: canonical)
    }

    static func compare(left: XCStringsCatalogSummary, right: XCStringsCatalogSummary) -> [StructuredDifference] {
        StructuredDataComparator.compare(left: left.canonical, right: right.canonical)
    }
}

nonisolated struct PBXProjectSection: Identifiable, Equatable, Sendable {
    let name: String
    let canonicalEntries: [String]
    var id: String { name }
}

nonisolated struct PBXProjectSnapshot: Equatable, Sendable {
    let archiveVersion: String?
    let objectVersion: String?
    let rootObject: String?
    let sections: [PBXProjectSection]
}

nonisolated enum PBXProjectComparator {
    static func decode(_ data: Data) throws -> PBXProjectSnapshot {
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix("// !$*UTF8*$!") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let archive = scalar(named: "archiveVersion", in: text)
        let object = scalar(named: "objectVersion", in: text)
        let pattern = #"/\* Begin ([^*]+) section \*/([\s\S]*?)/\* End \1 section \*/"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let sections = regex.matches(in: text, range: range).compactMap { match -> PBXProjectSection? in
            guard let nameRange = Range(match.range(at: 1), in: text),
                  let bodyRange = Range(match.range(at: 2), in: text) else { return nil }
            let entries = text[bodyRange].split(separator: "\n").map(String.init)
                .map(canonicalLine).filter { !$0.isEmpty }.sorted()
            return PBXProjectSection(name: String(text[nameRange]).trimmingCharacters(in: .whitespaces),
                                     canonicalEntries: entries)
        }.sorted { $0.name < $1.name }
        guard !sections.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return PBXProjectSnapshot(archiveVersion: archive, objectVersion: object,
                                  rootObject: scalar(named: "rootObject", in: text), sections: sections)
    }

    private static func scalar(named name: String, in text: String) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*([^;]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return canonicalLine(String(text[range]))
    }

    private static func canonicalLine(_ line: String) -> String {
        let withoutComments = line.replacingOccurrences(of: #"/\*.*?\*/"#, with: "",
                                                         options: .regularExpression)
        return withoutComments.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func structuredValue(_ snapshot: PBXProjectSnapshot) -> StructuredValue {
        .object([
            "archiveVersion": snapshot.archiveVersion.map(StructuredValue.string) ?? .null,
            "objectVersion": snapshot.objectVersion.map(StructuredValue.string) ?? .null,
            "rootObject": snapshot.rootObject.map(StructuredValue.string) ?? .null,
            "sections": .object(Dictionary(uniqueKeysWithValues: snapshot.sections.map { section in
                (section.name, .array(section.canonicalEntries.map(StructuredValue.string)))
            }))
        ])
    }
}

nonisolated struct AppleBundleSnapshot: Equatable, Sendable {
    let bundleIdentifier: String?
    let version: String?
    let executable: String?
    let packageType: String?
    let fileCount: Int
    let nestedCodePaths: [String]
}

nonisolated enum AppleBundleInspector {
    static func inspect(_ url: URL, maximumEntries: Int = 200_000) throws -> AppleBundleSnapshot {
        let selected = url.standardizedFileURL
        guard try selected.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let root = selected.resolvingSymlinksInPath().standardizedFileURL
        var infoCandidates = [root.appending(path: "Contents/Info.plist"),
                              root.appending(path: "Resources/Info.plist"),
                              root.appending(path: "Info.plist")]
        let versions = root.appending(path: "Versions")
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: versions, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) {
            infoCandidates += entries.filter { entry in
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isDirectory == true && values?.isSymbolicLink != true
            }.map { $0.appending(path: "Resources/Info.plist") }
        }
        guard let infoURL = infoCandidates.first(where: { candidate in
            guard FileManager.default.fileExists(atPath: candidate.path) else { return false }
            return (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        }) else { throw CocoaError(.fileNoSuchFile) }
        let data = try Data(contentsOf: infoURL, options: .mappedIfSafe)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        let nestedExtensions: Set<String> = ["app", "framework", "bundle", "appex", "xpc"]
        var pending = [root]
        var count = 0
        var nested: [String] = []
        while let directory = pending.popLast() {
            let entries = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]).sorted { $0.path < $1.path }
            for entry in entries {
                count += 1
                guard count <= maximumEntries else { throw CocoaError(.fileReadTooLarge) }
                let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { continue }
                if values.isDirectory == true {
                    if entry != root, nestedExtensions.contains(entry.pathExtension.lowercased()) {
                        nested.append(relative(entry, to: root)); continue
                    }
                    pending.append(entry)
                }
            }
        }
        return AppleBundleSnapshot(
            bundleIdentifier: plist["CFBundleIdentifier"] as? String,
            version: plist["CFBundleShortVersionString"] as? String,
            executable: plist["CFBundleExecutable"] as? String,
            packageType: plist["CFBundlePackageType"] as? String,
            fileCount: count, nestedCodePaths: nested.sorted())
    }

    private static func relative(_ url: URL, to root: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.path.count + 1))
    }
}

nonisolated struct CodeSignatureSnapshot: Equatable, Sendable {
    let isSigned: Bool
    let isValid: Bool
    let identifier: String?
    let teamIdentifier: String?
    let entitlements: [String: String]
}

nonisolated enum CodeSignatureInspector {
    static func inspect(_ url: URL) throws -> CodeSignatureSnapshot {
        var code: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard createStatus == errSecSuccess, let code else {
            return CodeSignatureSnapshot(isSigned: false, isValid: false, identifier: nil,
                                         teamIdentifier: nil, entitlements: [:])
        }
        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard infoStatus == errSecSuccess, let dictionary = information as? [String: Any] else {
            return CodeSignatureSnapshot(isSigned: false, isValid: false, identifier: nil,
                                         teamIdentifier: nil, entitlements: [:])
        }
        let entitlementDictionary = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        let normalized = entitlementDictionary.mapValues(canonicalEntitlement)
        let validity = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil)
        return CodeSignatureSnapshot(
            isSigned: validity != errSecCSUnsigned,
            isValid: validity == errSecSuccess,
            identifier: dictionary[kSecCodeInfoIdentifier as String] as? String,
            teamIdentifier: dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
            entitlements: normalized)
    }

    private static func canonicalEntitlement(_ value: Any) -> String {
        if let dictionary = value as? [String: Any] {
            return "{" + dictionary.keys.sorted().map {
                "\($0):\(canonicalEntitlement(dictionary[$0]!))"
            }.joined(separator: ",") + "}"
        }
        if let array = value as? [Any] {
            return "[" + array.map(canonicalEntitlement).joined(separator: ",") + "]"
        }
        if let data = value as? Data { return "data:\(data.base64EncodedString())" }
        if let date = value as? Date { return "date:\(date.formatted(.iso8601))" }
        return String(describing: value)
    }
}

nonisolated struct ProvisioningProfileSnapshot: Equatable, Sendable {
    let uuid: String?
    let name: String?
    let teamIdentifiers: [String]
    let expirationDate: Date?
    let applicationIdentifier: String?
}

nonisolated enum ProvisioningProfileInspector {
    static func inspect(_ data: Data) throws -> ProvisioningProfileSnapshot {
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let updateStatus = data.withUnsafeBytes { bytes in
            CMSDecoderUpdateMessage(decoder, bytes.baseAddress!, data.count)
        }
        guard updateStatus == errSecSuccess,
              CMSDecoderFinalizeMessage(decoder) == errSecSuccess else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var content: CFData?
        guard CMSDecoderCopyContent(decoder, &content) == errSecSuccess,
              let content,
              let plist = try PropertyListSerialization.propertyList(
                from: content as Data, options: [], format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let entitlements = plist["Entitlements"] as? [String: Any]
        return ProvisioningProfileSnapshot(
            uuid: plist["UUID"] as? String,
            name: plist["Name"] as? String,
            teamIdentifiers: plist["TeamIdentifier"] as? [String] ?? [],
            expirationDate: plist["ExpirationDate"] as? Date,
            applicationIdentifier: entitlements?["application-identifier"] as? String)
    }
}

nonisolated struct MachOSnapshot: Equatable, Sendable {
    let isUniversal: Bool
    let architectures: [String]
    let byteOrder: String
}

nonisolated enum MachOInspector {
    static func inspect(_ data: Data) throws -> MachOSnapshot {
        guard data.count >= 8 else { throw CocoaError(.fileReadCorruptFile) }
        let magic = read32(data, 0, bigEndian: true)
        if magic == 0xCAFEBABE || magic == 0xCAFEBABF {
            let count = Int(read32(data, 4, bigEndian: true))
            guard count > 0, count <= 128 else { throw CocoaError(.fileReadCorruptFile) }
            let stride = magic == 0xCAFEBABF ? 32 : 20
            guard data.count >= 8 + count * stride else { throw CocoaError(.fileReadCorruptFile) }
            let archs = (0..<count).map { architecture(read32(data, 8 + $0 * stride, bigEndian: true)) }
            return MachOSnapshot(isUniversal: true, architectures: archs, byteOrder: "big")
        }
        let littleMagic = read32(data, 0, bigEndian: false)
        let isLittle = littleMagic == 0xFEEDFACE || littleMagic == 0xFEEDFACF
        let isBig = magic == 0xFEEDFACE || magic == 0xFEEDFACF
        guard isLittle || isBig else { throw CocoaError(.fileReadCorruptFile) }
        return MachOSnapshot(isUniversal: false,
                             architectures: [architecture(read32(data, 4, bigEndian: isBig))],
                             byteOrder: isBig ? "big" : "little")
    }

    private static func read32(_ data: Data, _ offset: Int, bigEndian: Bool) -> UInt32 {
        let values = data[offset..<(offset + 4)]
        return values.reduce(UInt32(0)) { bigEndian ? ($0 << 8) | UInt32($1) : ($0 >> 8) | (UInt32($1) << 24) }
    }

    private static func architecture(_ type: UInt32) -> String {
        switch type {
        case 0x0100000C: "arm64"
        case 0x01000007: "x86_64"
        case 12: "arm"
        case 7: "i386"
        default: String(format: "cpu-0x%08x", type)
        }
    }

    static func structuredValue(_ snapshot: MachOSnapshot) -> StructuredValue {
        .object([
            "universal": .boolean(snapshot.isUniversal),
            "architectures": .array(snapshot.architectures.map(StructuredValue.string)),
            "byteOrder": .string(snapshot.byteOrder)
        ])
    }
}

nonisolated struct AssetCatalogSnapshot: Equatable, Sendable {
    let groups: [String]
    let imageFiles: [String]
    let canonicalContents: [String: StructuredValue]
}

nonisolated enum AssetCatalogInspector {
    static func inspect(_ root: URL, maximumEntries: Int = 100_000) throws -> AssetCatalogSnapshot {
        let selected = root.standardizedFileURL
        guard try selected.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let root = selected.resolvingSymlinksInPath().standardizedFileURL
        var groups: [String] = []
        var images: [String] = []
        var contents: [String: StructuredValue] = [:]
        var pending = [root]
        var count = 0
        while let directory = pending.popLast() {
            for entry in try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) {
                count += 1
                guard count <= maximumEntries else { throw CocoaError(.fileReadTooLarge) }
                let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { continue }
                let resolvedEntry = entry.resolvingSymlinksInPath().standardizedFileURL
                guard resolvedEntry.path.hasPrefix(root.path + "/") else {
                    throw CocoaError(.fileReadNoPermission)
                }
                let path = String(resolvedEntry.path.dropFirst(root.path.count + 1))
                if values.isDirectory == true {
                    groups.append(path); pending.append(entry)
                } else if entry.lastPathComponent == "Contents.json" {
                    contents[path] = try StructuredDataComparator.decode(
                        Data(contentsOf: entry, options: .mappedIfSafe), format: .json)
                } else if ["png", "jpg", "jpeg", "pdf", "svg", "heic"].contains(entry.pathExtension.lowercased()) {
                    images.append(path)
                }
            }
        }
        return AssetCatalogSnapshot(groups: groups.sorted(), imageFiles: images.sorted(),
                                    canonicalContents: contents)
    }
}
