import AppKit
import SwiftUI

enum GalleryInputPolicy {
    // Allow small mouse/trackpad slips without stealing the native button click.
    static let dragDistance: CGFloat = 16
    static func acceptsPhotoHit(opacity: CGFloat) -> Bool { opacity > 0.05 }
}

struct GalleryPointerGate {
    private(set) var isPressed = false
    mutating func press() { isPressed = true }
    mutating func release() { isPressed = false }
    mutating func reconcile(leftButtonPressed: Bool) {
        // Native control tracking can consume mouseUp before local monitors see
        // it. The next real input must recover instead of staying locked forever.
        if !leftButtonPressed { release() }
    }
    var permitsPointerUpdates: Bool { !isPressed }
}

// Accessed only by the main-queue input monitor and main-actor analysis scheduler.
enum PhotoInteractionActivity {
    static let pointerDidEnd = Notification.Name("local.nebula.pointer-did-end")
    static var lastEvent = Date.distantPast
    private static var inputMonitor: Any?

    static func finishPointerInteraction() {
        lastEvent = Date()
        NotificationCenter.default.post(name: pointerDidEnd, object: nil)
    }

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
        private var pointerGate = GalleryPointerGate()
        private var pendingScroll: CGFloat = 0
        private var pendingPointer: (CGPoint, CGSize)?
        private var delivery: DispatchWorkItem?
        private var resetObservers: [NSObjectProtocol] = []

        init(onScroll: @escaping (CGFloat) -> Void, onMove: @escaping (CGPoint, CGSize) -> Void) {
            self.onScroll = onScroll
            self.onMove = onMove
        }

        func install(for view: NSView) {
            removeMonitors()
            self.view = view
            view.window?.acceptsMouseMovedEvents = true

            for name in [PhotoInteractionActivity.pointerDidEnd, NSApplication.didResignActiveNotification] {
                resetObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.resetInput()
                })
            }
            resetObservers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self, let window = notification.object as? NSWindow, window === self.view?.window else { return }
                self.resetInput()
            })

            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.contains(event) else { return event }
                self.pointerGate.reconcile(leftButtonPressed: NSEvent.pressedMouseButtons & 1 != 0)
                guard self.pointerGate.permitsPointerUpdates else { return event }
                PhotoInteractionActivity.lastEvent = Date()
                self.pendingScroll += abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
                self.scheduleDelivery()
                return nil
            }
            moveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]) { [weak self] event in
                guard let self, let view = self.view else { return event }
                self.pointerGate.reconcile(leftButtonPressed: NSEvent.pressedMouseButtons & 1 != 0)
                if event.type == .leftMouseUp {
                    self.pointerGate.release()
                    return event
                }
                guard self.contains(event) else { return event }
                if event.type == .leftMouseDown {
                    self.pointerGate.press()
                    self.pendingPointer = nil
                    self.pendingScroll = 0
                    return event
                }
                // Keep the photo under the pointer during a press. Real drags
                // still reach SwiftUI; only camera parallax is held steady.
                guard self.pointerGate.permitsPointerUpdates else { return event }
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
                self.pointerGate.reconcile(leftButtonPressed: NSEvent.pressedMouseButtons & 1 != 0)
                let delta = self.pendingScroll
                self.pendingScroll = 0
                if delta != 0 { self.onScroll(delta) }
                if let pointer = self.pendingPointer, self.pointerGate.permitsPointerUpdates {
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

        private func resetInput() {
            delivery?.cancel()
            delivery = nil
            pointerGate.release()
            pendingPointer = nil
            pendingScroll = 0
        }

        func removeMonitors() {
            resetInput()
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            if let moveMonitor { NSEvent.removeMonitor(moveMonitor) }
            scrollMonitor = nil
            moveMonitor = nil
            for observer in resetObservers { NotificationCenter.default.removeObserver(observer) }
            resetObservers.removeAll()
        }

        deinit {
            removeMonitors()
        }
    }
}
