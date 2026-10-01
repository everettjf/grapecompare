import AppKit
import SwiftUI

/// Restore only after layout; persist actual clamped offsets, including independent horizontal positions.
struct ReadingScrollAnchor: NSViewRepresentable {
    let initial: ReadingOffset
    let changed: (ReadingOffset) -> Void

    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.initial = initial
        view.changed = changed
        return view
    }
    func updateNSView(_ view: Anchor, context: Context) { view.changed = changed; view.attach() }

    final class Anchor: NSView {
        var initial = ReadingOffset()
        var changed: ((ReadingOffset) -> Void)?
        private weak var clip: NSClipView?
        private var observer: NSObjectProtocol?
        private var restored = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); attach() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); attach() }
        override func layout() { super.layout(); attach() }
        func attach() {
            guard window != nil, let scroll = enclosingScrollView, clip !== scroll.contentView else { return }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            clip = scroll.contentView
            restored = false
            scroll.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.restored, let clip = self.clip else { return }
                        self.changed?(ReadingOffset(x: clip.bounds.origin.x, y: clip.bounds.origin.y))
                    }
                }
            DispatchQueue.main.async { [weak self, weak scroll] in
                guard let self, let scroll, self.window != nil else { return }
                scroll.layoutSubtreeIfNeeded()
                let bounds = scroll.documentView?.bounds ?? .zero
                let x = min(max(0, self.initial.x), max(0, bounds.width - scroll.contentSize.width))
                let y = min(max(0, self.initial.y), max(0, bounds.height - scroll.contentSize.height))
                scroll.contentView.scroll(to: NSPoint(x: x, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
                self.restored = true
            }
        }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
