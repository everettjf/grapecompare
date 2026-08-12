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

@available(macOS 27.0, *)
@MainActor
final class AsyncTextPatchDocument: WritableDocument {
    typealias Writer = FileWrapperDocumentWriter<Data>
    static var writableContentTypes: [UTType] { [.diff, .plainText] }
    private let text: String

    init(text: String) { self.text = text }

    nonisolated func writer(configuration: sending WriteConfiguration) -> sending Writer {
        FileWrapperDocumentWriter(configuration) { snapshot, previous in
            if previous?.regularFileContents == snapshot, let previous { return previous }
            return FileWrapper(regularFileWithContents: snapshot)
        }
    }

    func snapshot(contentType: UTType) async throws -> sending Data { Data(text.utf8) }
}

struct TextPatchExportModifier: ViewModifier {
    @Binding var isPresented: Bool
    let legacyDocument: TextPatchDocument
    let text: String
    let contentType: UTType
    let defaultFilename: String
    let onCompletion: (Result<URL, any Error>) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 27.0, *) {
            content.fileExporter(isPresented: $isPresented,
                                 document: AsyncTextPatchDocument(text: text),
                                 contentType: contentType,
                                 defaultFilename: defaultFilename,
                                 onCompletion: onCompletion)
        } else {
            content.fileExporter(isPresented: $isPresented,
                                 document: legacyDocument,
                                 contentType: contentType,
                                 defaultFilename: defaultFilename,
                                 onCompletion: onCompletion)
        }
    }
}

extension UTType {
    static let diff = UTType(filenameExtension: "diff", conformingTo: .plainText) ?? .plainText
}
