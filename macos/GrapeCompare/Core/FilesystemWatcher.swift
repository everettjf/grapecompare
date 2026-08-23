import CoreServices
import Foundation

/// Recursive, coalesced filesystem observation backed by FSEvents.
/// The stream reports paths only; callers must revalidate all inputs before acting.
nonisolated final class FilesystemWatcher: @unchecked Sendable {
    typealias Handler = @Sendable ([URL]) -> Void

    private let queue = DispatchQueue(label: "com.xnu.compare.filesystem-watcher", qos: .utility)
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var rootSources: [DispatchSourceFileSystemObject] = []
    private var rootPollTimer: DispatchSourceTimer?
    private var rootFingerprints: [String: String] = [:]
    private var handler: Handler?
    private var pendingPaths: Set<String> = []
    private var deliveryGeneration: UInt = 0
    private var coalescingDelay: TimeInterval = 0.05

    deinit { stop() }

    func start(watching roots: [URL], latency: TimeInterval = 0.2, handler: @escaping Handler) {
        stop()
        let paths = Array(Set(roots.map {
            $0.standardizedFileURL.path(percentEncoded: false)
        })).filter { !$0.isEmpty }
        guard !paths.isEmpty else { return }

        // Capture a concrete checkpoint before creating the stream. Using the
        // special `SinceNow` value leaves a small registration window in which
        // an immediate save can be missed.
        let sinceEventID = FSEventsGetCurrentEventId()
        lock.withLock {
            self.handler = handler
            coalescingDelay = min(max(latency, 0.02), 0.5)
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, rawPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FilesystemWatcher>.fromOpaque(info).takeUnretainedValue()
            let pathArray: CFArray = Unmanaged.fromOpaque(rawPaths).takeUnretainedValue()
            let paths = (pathArray as NSArray).compactMap { $0 as? String }
            let urls = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
            watcher.deliver(urls)
        }
        guard let created = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths as CFArray,
            sinceEventID,
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagWatchRoot |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagNoDefer)) else {
            installRootSources(paths)
            return
        }
        lock.withLock { stream = created }
        FSEventStreamSetDispatchQueue(created, queue)
        if !FSEventStreamStart(created) {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            lock.withLock { stream = nil }
        } else {
            // Make start() a real observation boundary so an immediate atomic
            // save cannot race stream registration.
            FSEventStreamFlushSync(created)
        }
        installRootSources(paths)
    }

    func stop() {
        let (existing, sources, timer) = lock.withLock {
            () -> (FSEventStreamRef?, [DispatchSourceFileSystemObject], DispatchSourceTimer?) in
            defer {
                stream = nil
                rootSources = []
                rootPollTimer = nil
                rootFingerprints = [:]
                pendingPaths = []
                deliveryGeneration &+= 1
                handler = nil
            }
            return (stream, rootSources, rootPollTimer)
        }
        timer?.cancel()
        sources.forEach { $0.cancel() }
        if let existing {
            FSEventStreamStop(existing)
            FSEventStreamInvalidate(existing)
            FSEventStreamRelease(existing)
        }
    }

    private func deliver(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let (generation, delay) = lock.withLock {
            pendingPaths.formUnion(urls.map { $0.standardizedFileURL.path(percentEncoded: false) })
            deliveryGeneration &+= 1
            return (deliveryGeneration, coalescingDelay)
        }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.flushDelivery(generation: generation)
        }
    }

    private func flushDelivery(generation: UInt) {
        let delivery: (Handler?, [URL]) = lock.withLock {
            guard generation == deliveryGeneration else { return (nil, []) }
            let urls = pendingPaths.sorted().map(URL.init(fileURLWithPath:))
            pendingPaths.removeAll(keepingCapacity: true)
            return (handler, urls)
        }
        guard !delivery.1.isEmpty else { return }
        delivery.0?(delivery.1)
    }

    /// A vnode source closes the small FSEvents delivery gap for immediate
    /// writes, root replacement, and filesystems whose event journal is not
    /// available. FSEvents remains responsible for recursive child paths.
    private func installRootSources(_ paths: [String]) {
        let sources = paths.compactMap { path -> DispatchSourceFileSystemObject? in
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .attrib, .extend],
                queue: queue)
            let root = URL(fileURLWithPath: path).standardizedFileURL
            source.setEventHandler { [weak self] in self?.deliver([root]) }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            return source
        }
        lock.withLock { rootSources = sources }
        installRootPoller(paths)
    }

    private func installRootPoller(_ paths: [String]) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        lock.withLock {
            rootFingerprints = Dictionary(uniqueKeysWithValues: paths.map { ($0, rootFingerprint($0)) })
            rootPollTimer = timer
        }
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.pollRoots(paths) }
        timer.resume()
    }

    private func pollRoots(_ paths: [String]) {
        var changed: [URL] = []
        lock.withLock {
            for path in paths {
                let current = rootFingerprint(path)
                if rootFingerprints[path] != current {
                    rootFingerprints[path] = current
                    changed.append(URL(fileURLWithPath: path).standardizedFileURL)
                }
            }
        }
        deliver(changed)
    }

    private func rootFingerprint(_ path: String) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return "missing"
        }
        let date = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? -1
        let identifier = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        return "\(identifier):\(date):\(size)"
    }
}
