import SwiftUI

/// Only the three visible covers and caption participate in rendering equality.
/// A group can contain thousands of photos; don't compare all members per frame.
struct StackCoverInputs: Equatable {
    let id: String
    let title: String
    let count: Int
    let photos: [MemoryPhoto]

    init(_ group: ThemePhotoStack) {
        id = group.id; title = group.title; count = group.photos.count
        photos = Array(group.photos.prefix(3))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.count == rhs.count &&
        lhs.photos.count == rhs.photos.count &&
        zip(lhs.photos, rhs.photos).allSatisfy { PhotoCardInputs.matches($0, $1) }
    }
}

/// Scroll-position transforms stay outside this boundary. Static cover content
/// is reused, while internal hover/press state and matched geometry still work.
struct StackCoverContent: View, Equatable {
    let inputs: StackCoverInputs
    let namespace: Namespace.ID
    let source: String
    let open: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.inputs == rhs.inputs && lhs.namespace == rhs.namespace && lhs.source == rhs.source
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                ForEach(Array(inputs.photos.enumerated()).reversed(), id: \.element.id) { layer, photo in
                    PhotoCard(photo: photo, width: 168, height: 212, castsShadow: false, resolutionScale: 1.8, action: open)
                        .matchedGeometryEffect(id: "\(inputs.id):\(photo.id)", in: namespace)
                        .rotationEffect(.degrees(Double(layer) * 3))
                        .scaleEffect(1 - CGFloat(layer) * 0.035)
                        .offset(x: CGFloat(layer) * 9, y: -CGFloat(layer) * 6)
                        .zIndex(Double(3 - layer))
                }
            }
            .frame(height: 228)
            VStack(spacing: 4) {
                Text(inputs.title).font(.system(size: 14, weight: .medium))
                Text("\(inputs.count) 张")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 196)
    }
}
