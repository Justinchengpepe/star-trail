import AppKit
import SwiftUI

// Accessed only by the main-queue input monitor and main-actor analysis scheduler.
enum PhotoInteractionActivity {
    static var lastEvent = Date.distantPast
    private static var inputMonitor: Any?

    static func install() {
        guard inputMonitor == nil else { return }
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .mouseMoved, .scrollWheel, .keyDown, .magnify, .rotate]) { event in
            lastEvent = Date()
            return event
        }
    }
}

struct MouseEventMonitor: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void = { _ in }
    var onMove: (CGPoint, CGSize) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll, onMove: onMove)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.install(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.onMove = onMove
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitors()
    }

    final class Coordinator {
        var onScroll: (CGFloat) -> Void
        var onMove: (CGPoint, CGSize) -> Void
        weak var view: NSView?
        private var scrollMonitor: Any?
        private var moveMonitor: Any?
        private var pendingScroll: CGFloat = 0
        private var pendingPointer: (CGPoint, CGSize)?
        private var delivery: DispatchWorkItem?

        init(onScroll: @escaping (CGFloat) -> Void, onMove: @escaping (CGPoint, CGSize) -> Void) {
            self.onScroll = onScroll
            self.onMove = onMove
        }

        func install(for view: NSView) {
            self.view = view
            view.window?.acceptsMouseMovedEvents = true

            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.contains(event) else { return event }
                PhotoInteractionActivity.lastEvent = Date()
                self.pendingScroll += abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
                self.scheduleDelivery()
                return nil
            }
            moveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                guard let self, let view = self.view, self.contains(event) else { return event }
                PhotoInteractionActivity.lastEvent = Date()
                self.pendingPointer = (view.convert(event.locationInWindow, from: nil), view.bounds.size)
                self.scheduleDelivery()
                return event
            }
        }

        private func scheduleDelivery() {
            guard delivery == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.delivery = nil
                let delta = self.pendingScroll
                self.pendingScroll = 0
                if delta != 0 { self.onScroll(delta) }
                if let pointer = self.pendingPointer {
                    self.pendingPointer = nil
                    self.onMove(pointer.0, pointer.1)
                }
            }
            delivery = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0, execute: work)
        }

        private func contains(_ event: NSEvent) -> Bool {
            guard let view, event.window === view.window else { return false }
            return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }

        func removeMonitors() {
            delivery?.cancel()
            delivery = nil
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            if let moveMonitor { NSEvent.removeMonitor(moveMonitor) }
            scrollMonitor = nil
            moveMonitor = nil
        }

        deinit {
            removeMonitors()
        }
    }
}
