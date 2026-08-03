import AppIntents
import Foundation
import UniformTypeIdentifiers

nonisolated let quickActionPathsKey = "pendingCompareFilesIntentPaths"

extension Notification.Name {
    static let compareFilesIntentReceived = Notification.Name("CompareFilesIntentReceived")
}

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

struct SelectedFileEntity: FileEntity {
    static let supportedContentTypes: [UTType] = [.item]
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "File"
    static let defaultQuery = SelectedFileQuery()

    let id: FileEntityIdentifier
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

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

struct GrapeCompareShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CompareFilesIntent(),
                    phrases: ["Compare files with \(.applicationName)"],
                    shortTitle: "Compare Files",
                    systemImageName: "arrow.left.arrow.right")
    }
}
