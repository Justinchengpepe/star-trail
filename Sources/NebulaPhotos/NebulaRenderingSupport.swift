import SwiftUI
import Observation
import Photos

enum PhotoCardInputs {
    static func matches(_ lhs: MemoryPhoto, _ rhs: MemoryPhoto) -> Bool {
        lhs.id == rhs.id && lhs.asset.modificationDate == rhs.asset.modificationDate &&
        lhs.createdAt == rhs.createdAt && lhs.width == rhs.width && lhs.height == rhs.height &&
        lhs.theme == rhs.theme && lhs.themeConfidence == rhs.themeConfidence &&
        lhs.visionLabels == rhs.visionLabels && lhs.isThemeManual == rhs.isThemeManual
    }
}

/// Static card inputs are independent of the camera pose. The original PhotoCard
/// still owns its press/hover animations; the caller applies the unchanged motion.
struct NebulaCard: View, Equatable {
    let photo: MemoryPhoto
    let resolutionScale: CGFloat
    @Binding var selectedPhoto: MemoryPhoto?

    static func == (lhs: Self, rhs: Self) -> Bool {
        PhotoCardInputs.matches(lhs.photo, rhs.photo) &&
        lhs.resolutionScale == rhs.resolutionScale
    }

    var body: some View {
        // No badge in the tunnel; full-size Live Photo playback is unchanged.
        PhotoCard(photo: photo, width: 112, height: 142, castsShadow: false, resolutionScale: resolutionScale, showsLiveBadge: false) {
            selectedPhoto = photo
        }
    }
}

@MainActor @Observable
final class NebulaHoverState {
    var date: String?
    @ObservationIgnored lazy var handler: (String?) -> Void = { [weak self] in self?.update($0) }
    func update(_ date: String?) { if self.date != date { self.date = date } }
}

struct NebulaDateCaption: View {
    let hover: NebulaHoverState
    let currentDate: String
    var body: some View { PhotoDateCaption(date: hover.date ?? currentDate).padding(24) }
}

enum NebulaPreheatWindow {
    static func indices(total: Int, center: Int, offsets: ClosedRange<Int>) -> [Int] {
        guard total > 0 else { return [] }
        var seen: Set<Int> = []
        return offsets.compactMap { offset in
            let index = ((center + offset) % total + total) % total
            return seen.insert(index).inserted ? index : nil
        }
    }
}

/// Bounded, local-only PhotoKit warming. No extra views or model inference.
@MainActor
final class NebulaImagePreheater {
    private var previousCenter: Int?
    private var bands: [[String: PHAsset]] = [[:], [:], [:]]
    private let sizes = [CGSize(width: 384, height: 384), CGSize(width: 384, height: 512), CGSize(width: 640, height: 768)]

    func update(_ photos: [MemoryPhoto], center: Int, force: Bool = false) {
        guard force || previousCenter == nil || abs(center - previousCenter!) >= 4 else { return }
        previousCenter = center
        let ranges = [-15...44, -2...18, -3...8]
        for band in sizes.indices {
            let indices = NebulaPreheatWindow.indices(total: photos.count, center: center, offsets: ranges[band])
            let next = Dictionary(uniqueKeysWithValues: indices.map { (photos[$0].id, photos[$0].asset) })
            let added = next.filter { bands[band][$0.key] == nil }.map(\.value)
            let removed = bands[band].filter { next[$0.key] == nil }.map(\.value)
            AssetThumbnailLoader.preheat(added: added, removed: removed, targetSize: sizes[band])
            bands[band] = next
        }
    }

    func stop() {
        for band in sizes.indices {
            AssetThumbnailLoader.preheat(added: [], removed: Array(bands[band].values), targetSize: sizes[band])
            bands[band].removeAll()
        }
        previousCenter = nil
    }
}
