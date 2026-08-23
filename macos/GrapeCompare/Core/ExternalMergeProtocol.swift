import Foundation

/// Command-line handoff used by Git mergetool. Completion is represented by an
/// atomically-created sentinel so the invoking shell only reports success after save.
nonisolated struct ExternalMergeRequest: Equatable, Sendable {
    let baseURL: URL
    let oursURL: URL
    let theirsURL: URL
    let destinationURL: URL
    let sentinelURL: URL

    init?(commandLineArguments arguments: [String]) {
        guard arguments.count == 7, arguments[1] == "--merge" else { return nil }
        baseURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        oursURL = URL(fileURLWithPath: arguments[3]).standardizedFileURL
        theirsURL = URL(fileURLWithPath: arguments[4]).standardizedFileURL
        destinationURL = URL(fileURLWithPath: arguments[5]).standardizedFileURL
        sentinelURL = URL(fileURLWithPath: arguments[6]).standardizedFileURL
    }

    func complete(with snapshot: TextSnapshot) throws {
        try complete(with: snapshot.encodedData())
    }

    func complete(with data: Data) throws {
        try data.write(to: destinationURL, options: .atomic)
        try Data().write(to: sentinelURL, options: .atomic)
    }
}
