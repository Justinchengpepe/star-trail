import AppKit
import Photos
import SwiftUI

@MainActor
final class AssetThumbnailLoader: ObservableObject {
    @Published var image: NSImage?

    private static let manager = PHCachingImageManager()
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    private var requestID: PHImageRequestID?
    private var loadedKey: String?
    private var loadedPixelSize = CGSize.zero

    func load(asset: PHAsset, targetSize: CGSize) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelWidth = min(1600, max(384, Int(ceil(targetSize.width * scale / 128)) * 128))
        let pixelHeight = min(1600, max(384, Int(ceil(targetSize.height * scale / 128)) * 128))
        let requestKey = "\(asset.localIdentifier)-\(pixelWidth)x\(pixelHeight)"
        guard loadedKey != requestKey else { return }
        if loadedKey?.hasPrefix(asset.localIdentifier) == true,
           loadedPixelSize.width >= CGFloat(pixelWidth), loadedPixelSize.height >= CGFloat(pixelHeight) { return }
        if let requestID { Self.manager.cancelImageRequest(requestID) }
        requestID = nil
        // Preserve the previous image during a resolution upgrade.
        if loadedKey?.hasPrefix(asset.localIdentifier) != true { image = nil }
        loadedKey = requestKey
        loadedPixelSize = CGSize(width: pixelWidth, height: pixelHeight)
        let key = requestKey as NSString
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }

        let pixelSize = CGSize(width: pixelWidth, height: pixelHeight)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true

        requestID = Self.manager.requestImage(
            for: asset,
            targetSize: pixelSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            guard let image else { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            Task { @MainActor in
                guard let self, self.loadedKey == requestKey else { return }
                self.image = image
                if !degraded { Self.cache.setObject(image, forKey: key, cost: pixelWidth * pixelHeight * 4) }
            }
        }
    }

    func cancel() {
        if let requestID { Self.manager.cancelImageRequest(requestID) }
        requestID = nil
        loadedKey = nil
        loadedPixelSize = .zero
        image = nil
    }

}

struct AssetThumbnailView: View {
    let asset: PHAsset
    let size: CGSize
    var resolutionScale: CGFloat = 1
    @StateObject private var loader = AssetThumbnailLoader()

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
            do { try await Task.sleep(nanoseconds: 90_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            loader.load(asset: asset, targetSize: CGSize(width: size.width * resolutionScale, height: size.height * resolutionScale))
        }
        .onDisappear { loader.cancel() }
    }
}
