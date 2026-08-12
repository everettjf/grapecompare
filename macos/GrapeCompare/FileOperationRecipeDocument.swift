import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let grapeComparePlan = UTType(exportedAs: "com.xnu.compare.operation-plan", conformingTo: .json)
}

struct FileOperationRecipeDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.grapeComparePlan, .json] }

    var recipe: FileOperationRecipe

    init(recipe: FileOperationRecipe) {
        self.recipe = recipe
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        recipe = try FileOperationRecipe.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: try recipe.encoded())
    }
}

@available(macOS 27.0, *)
@MainActor
final class AsyncFileOperationRecipeDocument: WritableDocument {
    typealias Writer = FileWrapperDocumentWriter<Data>
    static var writableContentTypes: [UTType] { [.grapeComparePlan, .json] }
    private let recipe: FileOperationRecipe

    init(recipe: FileOperationRecipe) { self.recipe = recipe }

    nonisolated func writer(configuration: sending WriteConfiguration) -> sending Writer {
        FileWrapperDocumentWriter(configuration) { snapshot, previous in
            if previous?.regularFileContents == snapshot, let previous { return previous }
            return FileWrapper(regularFileWithContents: snapshot)
        }
    }

    func snapshot(contentType: UTType) async throws -> sending Data { try recipe.encoded() }
}

struct RecipeExportModifier: ViewModifier {
    @Binding var isPresented: Bool
    let legacyDocument: FileOperationRecipeDocument?
    let recipe: FileOperationRecipe?
    let onCompletion: (Result<URL, any Error>) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 27.0, *) {
            content.fileExporter(isPresented: $isPresented,
                                 document: recipe.map(AsyncFileOperationRecipeDocument.init(recipe:)),
                                 contentType: .grapeComparePlan,
                                 defaultFilename: "GrapeCompare Plan",
                                 onCompletion: onCompletion)
        } else {
            content.fileExporter(isPresented: $isPresented,
                                 document: legacyDocument,
                                 contentType: .grapeComparePlan,
                                 defaultFilename: "GrapeCompare Plan",
                                 onCompletion: onCompletion)
        }
    }
}
