import Foundation

enum DemoData {
    static func makeFilePair() throws -> (left: URL, right: URL) {
        let root = try freshDirectory(named: "FileComparison")
        let left = root.appending(path: "SyncEngine-Before.swift")
        let right = root.appending(path: "SyncEngine-After.swift")

        try beforeFile.write(to: left, atomically: true, encoding: .utf8)
        try afterFile.write(to: right, atomically: true, encoding: .utf8)
        return (left, right)
    }

    static func makeFolderPair() throws -> (left: URL, right: URL) {
        let root = try freshDirectory(named: "ProjectComparison")
        let before = root.appending(path: "OrchardSync-Before")
        let after = root.appending(path: "OrchardSync-After")

        let shared: [String: String] = [
            "LICENSE": "MIT License\n",
            "Sources/Models/User.swift": "struct User: Codable, Identifiable { let id: UUID; let name: String }\n",
            "Sources/Views/AppIconView.swift": "import SwiftUI\nstruct AppIconView: View { var body: some View { Image(systemName: \"arrow.triangle.2.circlepath\") } }\n"
        ]
        for (path, content) in shared {
            try write(content, at: path, below: before)
            try write(content, at: path, below: after)
        }

        let beforeFiles: [String: String] = [
            "Package.swift": packageBefore,
            "README.md": "# OrchardSync\nA small macOS synchronization client.\n",
            "Sources/Core/APIClient.swift": apiBefore,
            "Sources/Core/SyncEngine.swift": engineBefore,
            "Sources/Core/LegacyScanner.swift": "import Foundation\nstruct LegacyScanner { func scan(_ root: URL) -> [URL] { [] } }\n",
            "Sources/Models/SyncJob.swift": jobBefore,
            "Sources/Models/SyncState.swift": "enum SyncState { case idle, running, completed, failed }\n",
            "Sources/Views/DashboardView.swift": dashboardBefore,
            "Sources/Views/SettingsView.swift": settingsBefore,
            "Resources/defaults.json": "{\"maxConcurrentJobs\":2,\"retryCount\":1,\"telemetry\":false}\n",
            "Tests/APIClientTests.swift": "import Testing\n@Test func sendsPostRequest() async throws { #expect(true) }\n",
            "Tests/SyncEngineTests.swift": "import Testing\n@Test func enqueuesJobs() async throws { #expect(true) }\n"
        ]
        let afterFiles: [String: String] = [
            "Package.swift": packageAfter,
            "README.md": "# OrchardSync\nA fast concurrent macOS sync client with checksum validation.\n",
            "Sources/Core/APIClient.swift": apiAfter,
            "Sources/Core/SyncEngine.swift": engineAfter,
            "Sources/Core/ChecksumCache.swift": "import CryptoKit\nimport Foundation\nactor ChecksumCache { private var values: [URL: SHA256.Digest] = [:] }\n",
            "Sources/Models/SyncJob.swift": jobAfter,
            "Sources/Models/SyncState.swift": "enum SyncState: Sendable { case idle, scanning, uploading, completed, failed(String) }\n",
            "Sources/Views/DashboardView.swift": dashboardAfter,
            "Sources/Views/SettingsView.swift": settingsAfter,
            "Resources/defaults.json": "{\"maxConcurrentJobs\":4,\"retryCount\":3,\"telemetry\":false,\"checksum\":\"sha256\"}\n",
            "Tests/APIClientTests.swift": "import Testing\n@Test func sendsVersionedPutRequest() async throws { #expect(true) }\n",
            "Tests/SyncEngineTests.swift": "import Testing\n@Test func uploadsConcurrently() async throws { #expect(true) }\n@Test func reportsRejectedJobs() async throws { #expect(true) }\n"
        ]
        for (path, content) in beforeFiles { try write(content, at: path, below: before) }
        for (path, content) in afterFiles { try write(content, at: path, below: after) }
        return (before, after)
    }

    private static func freshDirectory(named name: String) throws -> URL {
        let fm = FileManager.default
        let cache = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = cache.appending(path: "GrapeCompare/DemoData/\(name)")
        if fm.fileExists(atPath: root.path(percentEncoded: false)) {
            try fm.removeItem(at: root)
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func write(_ content: String, at path: String, below root: URL) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let beforeFile = """
    import Foundation

    actor SyncEngine {
        private let client: APIClient
        private var pending: [SyncJob] = []

        init(client: APIClient) {
            self.client = client
        }

        func enqueue(_ job: SyncJob) {
            pending.append(job)
        }

        func run() async throws {
            for job in pending {
                try await client.upload(job)
            }
            pending.removeAll()
        }

        func cancelAll() {
            pending.removeAll()
        }
    }
    """

    private static let afterFile = """
    import Foundation
    import OSLog

    actor SyncEngine {
        private let client: APIClient
        private let logger = Logger(subsystem: "com.example.orchard", category: "sync")
        private var pending: [SyncJob] = []

        init(client: APIClient) {
            self.client = client
        }

        func enqueue(_ job: SyncJob, priority: TaskPriority = .medium) {
            pending.append(job.with(priority: priority))
            logger.debug("Queued job \\(job.id)")
        }

        func run(maxConcurrentJobs: Int = 4) async throws {
            logger.info("Starting sync for \\(self.pending.count) jobs")
            try await withThrowingTaskGroup(of: Void.self) { group in
                for job in pending.prefix(maxConcurrentJobs) {
                    group.addTask { try await self.client.upload(job) }
                }
                try await group.waitForAll()
            }
            pending.removeAll(keepingCapacity: true)
        }
    }
    """

    private static let packageBefore = "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"OrchardSync\", platforms: [.macOS(.v14)], targets: [.executableTarget(name: \"OrchardSync\")])\n"
    private static let packageAfter = "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"OrchardSync\", platforms: [.macOS(.v15)], targets: [.executableTarget(name: \"OrchardSync\", resources: [.process(\"Resources\")])])\n"
    private static let apiBefore = "import Foundation\nstruct APIClient { let endpoint: URL; func upload(_ job: SyncJob) async throws { var request = URLRequest(url: endpoint); request.httpMethod = \"POST\"; _ = try await URLSession.shared.data(for: request) } }\n"
    private static let apiAfter = "import Foundation\nstruct APIClient: Sendable { let endpoint: URL; let session: URLSession; func upload(_ job: SyncJob) async throws { var request = URLRequest(url: endpoint.appending(path: \"v2/jobs\")); request.httpMethod = \"PUT\"; request.setValue(\"application/json\", forHTTPHeaderField: \"Content-Type\"); _ = try await session.data(for: request) } }\n"
    private static let engineBefore = "import Foundation\nactor SyncEngine { private let client: APIClient; private var pending: [SyncJob] = []; func run() async throws { for job in pending { try await client.upload(job) }; pending.removeAll() } }\n"
    private static let engineAfter = "import Foundation\nimport OSLog\nactor SyncEngine { private let client: APIClient; private let logger = Logger(); private var pending: [SyncJob] = []; func run() async throws { try await withThrowingTaskGroup(of: Void.self) { group in for job in pending { group.addTask { try await self.client.upload(job) } }; try await group.waitForAll() }; pending.removeAll() } }\n"
    private static let jobBefore = "import Foundation\nstruct SyncJob: Codable, Identifiable { let id: UUID; let path: String; let createdAt: Date }\n"
    private static let jobAfter = "import Foundation\nstruct SyncJob: Codable, Identifiable, Sendable { let id: UUID; let relativePath: String; let checksum: String; let createdAt: Date; var priority: Priority = .normal; enum Priority: String, Codable, Sendable { case low, normal, high } }\n"
    private static let dashboardBefore = "import SwiftUI\nstruct DashboardView: View { var body: some View { VStack { Text(\"Orchard Sync\"); Button(\"Start\") {} }.padding() } }\n"
    private static let dashboardAfter = "import SwiftUI\nstruct DashboardView: View { @State private var syncing = false; var body: some View { VStack(spacing: 18) { Label(\"Orchard Sync\", systemImage: \"arrow.triangle.2.circlepath\").font(.title.bold()); ProgressView().opacity(syncing ? 1 : 0); Button(syncing ? \"Syncing…\" : \"Start Sync\") { syncing = true }.buttonStyle(.borderedProminent) }.padding(32) } }\n"
    private static let settingsBefore = "import SwiftUI\nstruct SettingsView: View { @AppStorage(\"endpoint\") private var endpoint = \"https://api.example.com\"; var body: some View { Form { TextField(\"Endpoint\", text: $endpoint) } } }\n"
    private static let settingsAfter = "import SwiftUI\nstruct SettingsView: View { @AppStorage(\"endpoint\") private var endpoint = \"https://api.example.com\"; @AppStorage(\"launchAtLogin\") private var launchAtLogin = false; var body: some View { Form { TextField(\"Endpoint\", text: $endpoint); Toggle(\"Launch at login\", isOn: $launchAtLogin) }.formStyle(.grouped) } }\n"
}
