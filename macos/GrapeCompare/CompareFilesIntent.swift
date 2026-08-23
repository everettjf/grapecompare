import AppIntents
import Foundation
import UniformTypeIdentifiers

nonisolated let quickActionPathsKey = "pendingCompareFilesIntentPaths"

extension Notification.Name {
    nonisolated static let compareFilesIntentReceived = Notification.Name("CompareFilesIntentReceived")
    nonisolated static let externalCompareRequestReceived = Notification.Name("ExternalCompareRequestReceived")
}

nonisolated enum ExternalCompareRequest {
    static func store(_ urls: [URL]) {
        let paths = urls.filter(\.isFileURL).map { $0.standardizedFileURL.path }
        guard paths.count == 2 else { return }
        UserDefaults.standard.set(paths, forKey: quickActionPathsKey)
        NotificationCenter.default.post(name: .externalCompareRequestReceived, object: nil)
    }

    static func decode(_ url: URL) -> [URL] {
        guard url.scheme?.lowercased() == "grapecompare",
              url.host?.lowercased() == "compare",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        let items = components.queryItems ?? []
        return ["left", "right"].compactMap { key in
            items.first(where: { $0.name == key })?.value.flatMap { value in
                if let url = URL(string: value), url.isFileURL { return url }
                return URL(fileURLWithPath: value)
            }
        }
    }
}

@available(macOS 15.0, *)
struct CompareFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Compare Files"
    static let description = IntentDescription("Open two files in GrapeCompare and compare them.")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Files", description: "Choose exactly two files to compare.",
               supportedContentTypes: [.item], size: IntentCollectionSize(exactly: 2))
    var files: [SelectedFileEntity]

    static var parameterSummary: some ParameterSummary {
        Summary("Compare \(\.$files)")
    }

    func perform() async throws -> some IntentResult {
        var paths: [String] = []
        for file in files {
            if let url = try await file.id.fileURL {
                paths.append(url.standardizedFileURL.path)
            }
        }
        guard paths.count == 2 else { throw CompareFilesIntentError.requiresTwoLocalFiles }
        UserDefaults.standard.set(paths, forKey: quickActionPathsKey)
        await MainActor.run {
            NotificationCenter.default.post(name: .compareFilesIntentReceived, object: nil)
        }
        return .result()
    }
}

@available(macOS 15.0, *)
struct SelectedFileEntity: FileEntity {
    static let supportedContentTypes: [UTType] = [.item]
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "File"
    static let defaultQuery = SelectedFileQuery()

    let id: FileEntityIdentifier
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

@available(macOS 15.0, *)
struct SelectedFileQuery: EntityQuery {
    func entities(for identifiers: [FileEntityIdentifier]) async throws -> [SelectedFileEntity] {
        var entities: [SelectedFileEntity] = []
        for identifier in identifiers {
            if let url = try await identifier.fileURL {
                entities.append(SelectedFileEntity(id: identifier, name: url.lastPathComponent))
            }
        }
        return entities
    }
}

enum CompareFilesIntentError: LocalizedError {
    case requiresTwoLocalFiles
    var errorDescription: String? { String(localized: "Choose exactly two local files.") }
}

@available(macOS 15.0, *)
struct GrapeCompareShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CompareFilesIntent(),
                    phrases: ["Compare files with \(.applicationName)"],
                    shortTitle: "Compare Files",
                    systemImageName: "arrow.left.arrow.right")
    }
}
