import SwiftUI

private struct PhotoFocusChangedKey: EnvironmentKey {
    static let defaultValue: ((String?) -> Void)? = nil
}

extension EnvironmentValues {
    var photoFocusChanged: ((String?) -> Void)? {
        get { self[PhotoFocusChangedKey.self] }
        set { self[PhotoFocusChangedKey.self] = newValue }
    }
}

struct PhotoDateFocus: Equatable {
    let date: String
    let distance: CGFloat
    var id: String? = nil
}

struct PhotoDateFocusKey: PreferenceKey {
    static var defaultValue: PhotoDateFocus? = nil
    static func reduce(value: inout PhotoDateFocus?, nextValue: () -> PhotoDateFocus?) {
        guard let next = nextValue() else { return }
        if value == nil || next.distance < value!.distance { value = next }
    }
}

struct PhotoDateCaption: View {
    let date: String
    var body: some View {
        if !date.isEmpty {
            Text(date)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
                .accessibilityLabel("当前照片日期，\(date)")
        }
    }
}
