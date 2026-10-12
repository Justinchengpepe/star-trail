import AppKit
import Photos
import PhotosUI
import SwiftUI

@MainActor
final class LivePhotoPlayback: ObservableObject {
    @Published var playingID: String?
    @Published var livePhoto: PHLivePhoto?
    @Published var failedID: String?
    private var pressingID: String?
    private var suppressedID: String?
    private var timer: Task<Void, Never>?
    private var requestID: PHImageRequestID?
    private var generation = UUID()
    private var observer: NSObjectProtocol?
    private var releaseObserver: Any?

    init() {
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        releaseObserver = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDragged]) { [weak self] event in
            if event.type == .leftMouseUp { self?.stop() }
            return event
        }
    }

    func press(_ photo: MemoryPhoto, translation: CGSize) {
        guard photo.isLivePhoto else { return }
        if hypot(translation.width, translation.height) > 8 { stop(); return }
        guard pressingID != photo.id else { return }
        stop(); pressingID = photo.id; suppressedID = nil
        timer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            guard let self, self.pressingID == photo.id else { return }
            self.suppressedID = photo.id; self.start(photo)
        }
    }

    func consumeLongPress(_ id: String) -> Bool {
        guard suppressedID == id else { return false }
        suppressedID = nil; return true
    }

    func stopIfPressing(_ id: String) {
        if pressingID == id || playingID == id { stop() }
    }

    private func start(_ photo: MemoryPhoto) {
        let run = UUID(); generation = run; failedID = nil
        let options = PHLivePhotoRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .highQualityFormat
        requestID = PHImageManager.default().requestLivePhoto(for: photo.asset, targetSize: CGSize(width: 1000, height: 1000), contentMode: .aspectFit, options: options) { [weak self] livePhoto, info in
            if info?[PHImageResultIsDegradedKey] as? Bool == true { return }
            Task { @MainActor in
                guard let self, self.generation == run, self.pressingID == photo.id else { return }
                if let livePhoto { self.livePhoto = livePhoto; self.playingID = photo.id }
                else { self.failedID = photo.id }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, self.generation == run, self.playingID == nil else { return }
            self.failedID = photo.id; self.stop()
        }
    }

    func stop() {
        timer?.cancel(); timer = nil; generation = UUID(); pressingID = nil
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
        requestID = nil; playingID = nil; livePhoto = nil
    }
}

struct NativeLivePhotoView: NSViewRepresentable {
    let photo: PHLivePhoto
    func makeNSView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView(); view.isMuted = true; return view
    }
    func updateNSView(_ view: PHLivePhotoView, context: Context) {
        guard view.livePhoto !== photo else { return }
        view.livePhoto = photo; view.isMuted = true; view.startPlayback(with: .full)
    }
    static func dismantleNSView(_ view: PHLivePhotoView, coordinator: ()) { view.stopPlayback(); view.livePhoto = nil }
}
