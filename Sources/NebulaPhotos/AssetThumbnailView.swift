import AppKit
import Photos
import SwiftUI

/// Images are immutable after handoff; the decoder never mutates a published image.
struct DecodedThumbnail: @unchecked Sendable {
    let image: NSImage
    let cost: Int
}

// PhotoKit callbacks may already be queued when a tile changes resolution or
// disappears. Cancel obsolete CPU decoding too, not just the PhotoKit request.
final class ThumbnailDecodeTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

enum ThumbnailDecode {
    static func prepare(_ image: NSImage) -> DecodedThumbnail? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: source.width, height: source.height,
                                      bitsPerComponent: 8, bytesPerRow: source.width * 4,
                                      space: source.colorSpace?.model == .rgb ? source.colorSpace! : CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let decoded = context.makeImage() else { return nil }
        return DecodedThumbnail(image: NSImage(cgImage: decoded, size: image.size), cost: source.width * source.height * 4)
    }
}

@MainActor
final class AssetThumbnailLoader: ObservableObject {
    @Published var image: NSImage?
    private static let loaders = NSHashTable<AssetThumbnailLoader>.weakObjects()
    private static var cacheGeneration = UUID()

    init() { Self.loaders.add(self) }

    static func clearMemoryCache() {
        cacheGeneration = UUID()
        for loader in loaders.allObjects { loader.cancel() }
        manager.stopCachingImagesForAllAssets()
        cache.removeAllObjects(); previewKeys.removeAll()
        pendingPublications.removeAll(); publicationTask?.cancel(); publicationTask = nil
    }

    private static let manager = PHCachingImageManager()
    private static let preheatOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat; options.resizeMode = .exact
        options.isNetworkAccessAllowed = false
        return options
    }()

    static func preheat(added: [PHAsset], removed: [PHAsset], targetSize: CGSize) {
        if !removed.isEmpty { manager.stopCachingImages(for: removed, targetSize: targetSize, contentMode: .aspectFill, options: preheatOptions) }
        if !added.isEmpty { manager.startCachingImages(for: added, targetSize: targetSize, contentMode: .aspectFill, options: preheatOptions) }
    }
    private static let decodeQueue = DispatchQueue(label: "local.nebula.thumbnail-decode", qos: .userInitiated)
    private static var pendingPublications: [ObjectIdentifier: () -> Void] = [:]
    private static var publicationTask: Task<Void, Never>?

    private static func publishTogether(for loader: AssetThumbnailLoader, _ update: @escaping () -> Void) {
        pendingPublications[ObjectIdentifier(loader)] = update
        guard publicationTask == nil else { return }
        let generation = cacheGeneration
        publicationTask = Task { @MainActor in
            // One display interval, not a debounce: continuous loading cannot
            // postpone visible photos indefinitely. SwiftUI gets one batch.
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled, cacheGeneration == generation else { return }
            let updates = Array(pendingPublications.values)
            pendingPublications.removeAll(keepingCapacity: true)
            publicationTask = nil
            for update in updates { update() }
        }
    }
    private static var previewKeys: [String: String] = [:]
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    private var requestID: PHImageRequestID?
    private var decodeTicket: ThumbnailDecodeTicket?
    private var loadedKey: String?
    private var loadedPixelSize = CGSize.zero

    static func cachedPreview(for asset: PHAsset) -> NSImage? {
        guard let key = previewKeys[asset.localIdentifier] else { return nil }
        let prefix = "\(asset.localIdentifier):\(asset.modificationDate?.timeIntervalSince1970 ?? 0)-"
        guard key.hasPrefix(prefix), let image = cache.object(forKey: key as NSString) else {
            previewKeys.removeValue(forKey: asset.localIdentifier); return nil
        }
        return image
    }

    private func request(asset: PHAsset, targetSize: CGSize) -> (key: String, width: Int, height: Int) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let width = min(1600, max(384, Int(ceil(targetSize.width * scale / 128)) * 128))
        let height = min(1600, max(384, Int(ceil(targetSize.height * scale / 128)) * 128))
        return ("\(asset.localIdentifier):\(asset.modificationDate?.timeIntervalSince1970 ?? 0)-\(width)x\(height)", width, height)
    }

    func restoreCached(asset: PHAsset, targetSize: CGSize) -> Bool {
        let request = request(asset: asset, targetSize: targetSize)
        if loadedKey == request.key { return true }
        let prefix = "\(asset.localIdentifier):\(asset.modificationDate?.timeIntervalSince1970 ?? 0)-"
        // Never replace an already sharper image with a lower-resolution cache
        // entry as the same tile moves between depth bands.
        if loadedKey?.hasPrefix(prefix) == true, image != nil,
           loadedPixelSize.width >= CGFloat(request.width), loadedPixelSize.height >= CGFloat(request.height) { return true }
        guard let cached = Self.cache.object(forKey: request.key as NSString) else { return false }
        decodeTicket?.cancel(); decodeTicket = nil
        if let requestID { Self.manager.cancelImageRequest(requestID) }
        requestID = nil; loadedKey = request.key
        loadedPixelSize = CGSize(width: request.width, height: request.height)
        image = cached
        return true
    }

    func load(asset: PHAsset, targetSize: CGSize) {
        let request = request(asset: asset, targetSize: targetSize)
        let pixelWidth = request.width, pixelHeight = request.height, requestKey = request.key
        let assetPrefix = "\(asset.localIdentifier):\(asset.modificationDate?.timeIntervalSince1970 ?? 0)-"
        guard loadedKey != requestKey else { return }
        if loadedKey?.hasPrefix(assetPrefix) == true,
           loadedPixelSize.width >= CGFloat(pixelWidth), loadedPixelSize.height >= CGFloat(pixelHeight) { return }
        if let requestID { Self.manager.cancelImageRequest(requestID) }
        requestID = nil
        decodeTicket?.cancel(); decodeTicket = nil
        // Preserve the previous image during a resolution upgrade.
        if loadedKey?.hasPrefix(assetPrefix) != true { image = nil }
        loadedKey = requestKey
        loadedPixelSize = CGSize(width: pixelWidth, height: pixelHeight)
        let key = requestKey as NSString
        let assetID = asset.localIdentifier
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }

        let pixelSize = CGSize(width: pixelWidth, height: pixelHeight)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        let ticket = ThumbnailDecodeTicket()
        decodeTicket = ticket

        requestID = Self.manager.requestImage(
            for: asset,
            targetSize: pixelSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            guard ticket.isActive, let image else { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let source = DecodedThumbnail(image: image, cost: pixelWidth * pixelHeight * 4)
            // Decode before publishing: SwiftUI's first draw must not decode JPEG/HEIF.
            Self.decodeQueue.async {
                autoreleasepool {
                    guard ticket.isActive else { return }
                    let prepared = ThumbnailDecode.prepare(source.image) ?? source
                    Task { @MainActor in
                        guard ticket.isActive, let self, self.loadedKey == requestKey else { return }
                        if !degraded {
                            Self.cache.setObject(prepared.image, forKey: requestKey as NSString, cost: prepared.cost)
                            Self.previewKeys[assetID] = requestKey
                        }
                        Self.publishTogether(for: self) { [weak self] in
                            guard ticket.isActive, let self, self.loadedKey == requestKey else { return }
                            self.image = prepared.image
                        }
                    }
                }
            }
        }
    }

    func cancel() {
        Self.pendingPublications.removeValue(forKey: ObjectIdentifier(self))
        decodeTicket?.cancel(); decodeTicket = nil
        if let requestID { Self.manager.cancelImageRequest(requestID) }
        requestID = nil
        loadedKey = nil
        loadedPixelSize = .zero
        image = nil
    }

}

struct AssetThumbnailView: View, Equatable {
    let asset: PHAsset
    let size: CGSize
    var resolutionScale: CGFloat = 1
    @StateObject private var loader = AssetThumbnailLoader()

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.asset.localIdentifier == rhs.asset.localIdentifier && lhs.asset.modificationDate == rhs.asset.modificationDate && lhs.size == rhs.size && lhs.resolutionScale == rhs.resolutionScale
    }

    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Color.primary.opacity(0.025)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .animation(.easeOut(duration: 0.22), value: loader.image != nil)
        .task(id: "\(asset.localIdentifier)-\(Int(size.width * resolutionScale / 64))-\(Int(size.height * resolutionScale / 64))") {
            let targetSize = CGSize(width: size.width * resolutionScale, height: size.height * resolutionScale)
            if loader.restoreCached(asset: asset, targetSize: targetSize) { return }
            do { try await Task.sleep(nanoseconds: 90_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            loader.load(asset: asset, targetSize: targetSize)
        }
        .onDisappear { loader.cancel() }
    }
}
