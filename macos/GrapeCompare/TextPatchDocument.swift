import SwiftUI
import UniformTypeIdentifiers

struct TextPatchDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.diff] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private extension UTType {
    static let diff = UTType(filenameExtension: "diff", conformingTo: .plainText) ?? .plainText
}
