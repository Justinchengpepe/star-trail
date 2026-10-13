import SwiftUI
import Observation

/// Only the caption observes these values; pointer movement does not invalidate
/// the grid's body or recreate its environment closure for every photo.
@MainActor @Observable
final class GalleryDateState {
    private(set) var focusedDate = ""
    private(set) var hoveredDate: String?
    @ObservationIgnored lazy var hoverHandler: (String?) -> Void = { [weak self] in self?.hover($0) }

    func focus(_ date: String) {
        if focusedDate != date { focusedDate = date }
    }

    func hover(_ date: String?) {
        if hoveredDate != date { hoveredDate = date }
    }
}

struct GalleryDateOverlay: View {
    let state: GalleryDateState
    var body: some View {
        PhotoDateCaption(date: state.hoveredDate ?? state.focusedDate).padding(24)
    }
}

/// Geometry preferences still track each cell's scroll position, but unchanged
/// image/press/hover content skips rebuilding while the cell moves on screen.
struct GridPhotoCard: View, Equatable {
    let photo: MemoryPhoto
    let width: CGFloat
    @Binding var selectedPhoto: MemoryPhoto?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.width == rhs.width && PhotoCardInputs.matches(lhs.photo, rhs.photo)
    }

    var body: some View {
        PhotoCard(photo: photo, width: width, height: width * 1.18,
                  showDate: true, usesFlatLiveBadge: true) {
            selectedPhoto = photo
        }
    }
}
