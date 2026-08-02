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
