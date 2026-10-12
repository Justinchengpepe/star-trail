import SwiftUI
import Observation

@MainActor
@Observable
final class BrowsingState {
    var focusedID: String?
    var nebulaZoom: CGFloat = 1
    var orbitZoom: CGFloat = 1
    var gridWidth: CGFloat = 142
    var activeStackID: String?
    private var focusedDate: Date?

    init() { PhotoInteractionActivity.install() }

    func focus(_ photo: MemoryPhoto) {
        guard focusedID != photo.id else { return }
        focusedID = photo.id; focusedDate = photo.createdAt
    }

    func index(in photos: [MemoryPhoto]) -> Int {
        guard !photos.isEmpty else { return 0 }
        if let focusedID, let index = photos.firstIndex(where: { $0.id == focusedID }) { return index }
        if let focusedDate {
            return photos.indices.min { abs((photos[$0].createdAt ?? .distantPast).timeIntervalSince(focusedDate)) < abs((photos[$1].createdAt ?? .distantPast).timeIntervalSince(focusedDate)) } ?? 0
        }
        return 0
    }

    func reconcile(_ photos: [MemoryPhoto]) {
        guard !photos.isEmpty else { return }
        if let focusedID, photos.contains(where: { $0.id == focusedID }) { return }
        focus(photos[index(in: photos)])
    }
}
