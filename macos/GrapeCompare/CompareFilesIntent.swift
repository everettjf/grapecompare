import AppIntents
import Foundation
import UniformTypeIdentifiers

nonisolated let quickActionBookmarksKey = "pendingCompareFilesIntentBookmarks"
nonisolated let quickActionErrorKey = "pendingCompareFilesIntentError"

extension Notification.Name {
    nonisolated static let compareFilesIntentReceived = Notification.Name("CompareFilesIntentReceived")
}

nonisolated enum PendingComparisonRequest {
    static func store(_ urls: [URL]) throws {
        let selected = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard selected.count == 2 else { throw CompareFilesIntentError.requiresTwoLocalFiles }
        let bookmarks = try selected.map { url in
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil)
        }
        UserDefaults.standard.removeObject(forKey: quickActionErrorKey)
        UserDefaults.standard.set(bookmarks, forKey: quickActionBookmarksKey)
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
        var urls: [URL] = []
        for file in files {
            if let url = try await file.id.fileURL {
                urls.append(url.standardizedFileURL)
            }
        }
        try PendingComparisonRequest.store(urls)
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
