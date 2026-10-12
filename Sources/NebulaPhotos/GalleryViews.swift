import AppKit
import SwiftUI

private struct DepthOfFieldKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var depthOfFieldEnabled: Bool {
        get { self[DepthOfFieldKey.self] }
        set { self[DepthOfFieldKey.self] = newValue }
    }
}

struct PhotoCard: View {
    @Environment(BrowsingState.self) private var browsing
    @EnvironmentObject private var playback: LivePhotoPlayback
    @Environment(\.photoFocusChanged) private var focusChanged
    let photo: MemoryPhoto
    var width: CGFloat = 112
    var height: CGFloat = 142
    var showDate = false
    var castsShadow = true
    var resolutionScale: CGFloat = 1
    let action: () -> Void
    @State private var isHovered = false
    @State private var hoverPoint = CGPoint(x: 0.5, y: 0.5)

    var body: some View {
        Button {
            guard !playback.consumeLongPress(photo.id) else { return }
            browsing.focus(photo)
            action()
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.045))
                AssetThumbnailView(asset: photo.asset, size: CGSize(width: width, height: height), resolutionScale: resolutionScale)
                if playback.playingID == photo.id, let livePhoto = playback.livePhoto {
                    NativeLivePhotoView(photo: livePhoto).allowsHitTesting(false)
                }
                if showDate {
                    LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                    Text(photo.dateLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(9)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.18), lineWidth: 0.7))
            .shadow(color: castsShadow ? .black.opacity(0.32) : .clear, radius: castsShadow ? 12 : 0, y: castsShadow ? 7 : 0)
        }
        .buttonStyle(PhotoPressStyle())
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { value in playback.press(photo, translation: value.translation) }
            .onEnded { _ in playback.stop() })
        .overlay(alignment: .topLeading) {
            if photo.isLivePhoto {
                Image(systemName: playback.failedID == photo.id ? "exclamationmark.circle" : "livephoto")
                    .font(.system(size: 11)).padding(6)
                    .background(.regularMaterial, in: Circle()).padding(6)
                    .help(playback.failedID == photo.id ? "读取失败，长按重试" : "长按播放实况，松开停止")
                    .allowsHitTesting(false)
            }
        }
        .onDisappear { playback.stopIfPressing(photo.id) }
        .scaleEffect(isHovered ? 1.045 : 1)
        .offset(y: isHovered ? -3 : 0)
        .rotation3DEffect(.degrees(isHovered ? Double((0.5 - hoverPoint.y) * 7) : 0), axis: (x: 1, y: 0, z: 0))
        .rotation3DEffect(.degrees(isHovered ? Double((hoverPoint.x - 0.5) * 7) : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.easeOut(duration: 0.18), value: isHovered)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                if !isHovered { focusChanged?(photo.dateLabel) }
                isHovered = true
                hoverPoint = CGPoint(
                    x: max(0, min(1, location.x / max(width, 1))),
                    y: max(0, min(1, location.y / max(height, 1)))
                )
            case .ended:
                playback.stopIfPressing(photo.id)
                focusChanged?(nil)
                isHovered = false
                hoverPoint = CGPoint(x: 0.5, y: 0.5)
            }
        }
        .accessibilityLabel("照片，\(photo.dateLabel)")
        .help(photo.dateLabel)
    }
}

struct PhotoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct NebulaView: View {
    @Environment(BrowsingState.self) private var browsing
    @State private var hoveredDate: String?
    @Environment(\.depthOfFieldEnabled) private var depthOfField
    let photos: [MemoryPhoto]
    let revision: UUID
    @Binding var selectedPhoto: MemoryPhoto?
    @GestureState private var drag: CGSize = .zero
    @GestureState private var liveMagnification: CGFloat = 1
    @State private var timeCursor: CGFloat = 0
    @State private var pointer = CGPoint(x: 0.5, y: 0.5)
    private var cameraZoom: CGFloat { browsing.nebulaZoom }

    private var visiblePhotos: [(photo: MemoryPhoto, travel: CGFloat, assetIndex: Int)] {
        guard !photos.isEmpty else { return [] }
        let count = min(36, photos.count)
        let base = Int(floor(timeCursor))
        let fraction = timeCursor - CGFloat(base)
        return (0..<count).map { offset in
            let travelOffset = offset - (count > 8 ? 3 : 0)
            let assetIndex = ((base + travelOffset) % photos.count + photos.count) % photos.count
            return (photos[assetIndex], CGFloat(travelOffset) - fraction, assetIndex)
        }
    }

    private var currentPhoto: MemoryPhoto? {
        guard !photos.isEmpty else { return nil }
        return photos[min(Int(timeCursor.rounded(.down)), photos.count - 1)]
    }

    var body: some View {
        GeometryReader { proxy in
            // visiblePhotos 是 O(卡片数) 的构造，原来在 ForEach 闭包里被访问 253 次/帧
            // （行内 `visiblePhotos.count` 每张卡片各求值 7 次）。这里只算一次。
            let items = visiblePhotos
            let count = items.count
            let layered = count > 8
            let span = layered ? CGFloat(count - 7) : CGFloat(max(count - 1, 1))
            let arrivalSpan = CGFloat(count - 3)
            ZStack {
                    ForEach(Array(items.enumerated()), id: \.element.photo.id) { _, item in
                        let depth = max(0.02, 1 - item.travel / span)
                        let point = tunnelPoint(photoIndex: item.assetIndex, depth: depth, size: proxy.size)
                        let scale = (0.18 + pow(depth, 2.15) * 1.62) * cameraZoom * liveMagnification
                        let blur = depthOfField ? max(0, 0.38 - depth) * 3 + max(0, depth - 1.08) * 8 : 0
                        let arrival = layered ? min(1, max(0, (arrivalSpan - item.travel) / 5)) : 1
                        let departure = layered ? min(1, max(0, (item.travel + 3) / 2.5)) : 1
                        PhotoCard(
                            photo: item.photo,
                            width: 112,
                            height: 142,
                            castsShadow: false,
                            resolutionScale: depth >= 0.85 ? 2.6 : depth >= 0.5 ? 1.6 : 0.85,
                            action: { selectedPhoto = item.photo }
                        )
                        .scaleEffect(scale)
                        .blur(radius: blur)
                        .opacity(arrival * departure * min(1, 0.35 + depth * 0.8))
                        .offset(
                            x: point.x + drag.width * (0.035 + depth * 0.12) + (pointer.x - 0.5) * -62 * depth,
                            y: point.y + drag.height * (0.035 + depth * 0.12) + (pointer.y - 0.5) * -42 * depth
                        )
                        .zIndex(depth)
                        .transition(.opacity)
                    }
                    if photos.isEmpty { NoMatchesView() }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                // 所有卡片的旋转角度相同，提到容器上只做一次 3D 变换，
                // 避免 36 个图层各自离屏渲染。
                .rotation3DEffect(.degrees(Double(drag.width / 28)), axis: (x: 0, y: 1, z: 0))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .updating($drag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            moveCursor(by: -value.predictedEndTranslation.height * 0.018)
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .updating($liveMagnification) { value, state, _ in state = value }
                        .onEnded { value in browsing.nebulaZoom = max(0.62, min(1.5, cameraZoom * value)) }
                )
                .background(
                    MouseEventMonitor(
                        onScroll: { delta in
                            moveCursor(by: -delta * 0.065)
                        },
                        onMove: { location, size in
                            guard size.width > 0, size.height > 0 else { return }
                            let next = CGPoint(x: location.x / size.width, y: location.y / size.height)
                            // 指针视差每变化一次都会重算全部 36 张卡片的 offset，
                            // 加上量化阈值，避免亚像素抖动触发整屏重绘。
                            guard abs(next.x - pointer.x) > 0.003 || abs(next.y - pointer.y) > 0.003 else { return }
                            pointer = next
                        }
                    )
                )
        }
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            GalleryNavigation(count: photos.count, cursor: $timeCursor)
                .padding(.trailing, 54)
                .padding(.bottom, 22)
        }
        .overlay(alignment: .bottomLeading) {
            PhotoDateCaption(date: hoveredDate ?? currentPhoto?.dateLabel ?? "").padding(24)
        }
        .environment(\.photoFocusChanged, { newValue in
            // 悬停时每张卡片都会回调，去重后只有日期真正变化才触发 body 重算。
            if hoveredDate != newValue { hoveredDate = newValue }
        })
        .onAppear { timeCursor = CGFloat(browsing.index(in: photos)); if let currentPhoto { browsing.focus(currentPhoto) } }
        .onChange(of: timeCursor) { _, _ in if let currentPhoto { browsing.focus(currentPhoto) } }
        .onChange(of: revision) { _, _ in timeCursor = CGFloat(browsing.index(in: photos)) }
        .onChange(of: browsing.focusedID) { _, id in
            guard currentPhoto?.id != id else { return }
            timeCursor = CGFloat(browsing.index(in: photos))
        }
    }

    private func moveCursor(by amount: CGFloat) {
        guard photos.count > 1 else { return }
        // 滚动不再包 withAnimation：连续滚动时每个事件都会新建一个 0.12s 动画事务，
        // 事务互相打断，36 张卡片每帧都要做属性插值。滚动本身是连续输入，直接赋值更跟手。
        timeCursor = max(0, min(CGFloat(photos.count - 1), timeCursor + amount))
    }

    private func tunnelPoint(photoIndex: Int, depth: CGFloat, size: CGSize) -> CGPoint {
        let angle = Double(photoIndex) * 2.39996 + Double(pseudo(photoIndex * 47 + 19)) * 0.8
        let spread = 0.06 + pow(depth, 1.3) * 0.94
        let x = cos(angle) * Double(spread * size.width * 0.46)
        let y = sin(angle) * Double(spread * size.height * 0.42)
        return CGPoint(x: x, y: y)
    }
}

struct OrbitView: View {
    @Environment(BrowsingState.self) private var browsing
    @State private var hoveredDate: String?
    @Environment(\.depthOfFieldEnabled) private var depthOfField
    let photos: [MemoryPhoto]
    let revision: UUID
    @Binding var selectedPhoto: MemoryPhoto?
    @State private var orbitCursor: CGFloat = 0
    @GestureState private var orbitDrag: CGSize = .zero
    @GestureState private var liveMagnification: CGFloat = 1
    @State private var pointerY: CGFloat = 0.5
    private var ringScale: CGFloat { browsing.orbitZoom }

    private var visiblePhotos: [MemoryPhoto] {
        guard !photos.isEmpty else { return [] }
        let count = min(20, photos.count)
        let base = Int(floor(orbitCursor))
        return (0..<count).map { photos[(base + $0) % photos.count] }
    }

    var body: some View {
        GeometryReader { proxy in
                ZStack {
                    ForEach(Array(visiblePhotos.enumerated()), id: \.element.id) { index, photo in
                        // 同星云：选中的那张退出视图树，交给详情图补间。
                        if selectedPhoto?.id != photo.id {
                            orbitCard(photo: photo, index: index, size: proxy.size)
                        }
                    }
                    if photos.isEmpty { NoMatchesView() }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .updating($orbitDrag) { value, state, _ in state = value.translation }
                        .onEnded { value in moveOrbit(by: -value.predictedEndTranslation.width / 52) }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .updating($liveMagnification) { value, state, _ in state = value }
                        .onEnded { value in browsing.orbitZoom = max(0.62, min(1.35, ringScale * value)) }
                )
                .background(
                    MouseEventMonitor(
                        onScroll: { delta in moveOrbit(by: -delta * 0.055) },
                        onMove: { location, size in
                            guard size.height > 0 else { return }
                            pointerY = max(0, min(1, location.y / size.height))
                        }
                    )
                )
        }
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            GalleryNavigation(count: photos.count, cursor: $orbitCursor)
                .padding(22)
        }
        .overlay(alignment: .bottomLeading) {
            PhotoDateCaption(date: hoveredDate ?? (photos.isEmpty ? "" : photos[min(Int(orbitCursor), photos.count - 1)].dateLabel))
                .padding(24)
        }
        .environment(\.photoFocusChanged, { hoveredDate = $0 })
        .onAppear { orbitCursor = CGFloat(browsing.index(in: photos)) }
        .onChange(of: revision) { _, _ in orbitCursor = CGFloat(browsing.index(in: photos)) }
        .onChange(of: orbitCursor) { _, _ in
            if !photos.isEmpty { browsing.focus(photos[min(Int(orbitCursor), photos.count - 1)]) }
        }
        .onChange(of: browsing.focusedID) { _, id in
            guard !photos.isEmpty else { return }
            let photo = photos[min(Int(orbitCursor), photos.count - 1)]
            if photo.id != id { orbitCursor = CGFloat(browsing.index(in: photos)) }
        }
    }

    private func moveOrbit(by amount: CGFloat) {
        guard photos.count > 1 else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            orbitCursor += amount
            while orbitCursor < 0 { orbitCursor += CGFloat(photos.count) }
            while orbitCursor >= CGFloat(photos.count) { orbitCursor -= CGFloat(photos.count) }
        }
    }

    private func orbitCard(photo: MemoryPhoto, index: Int, size: CGSize) -> some View {
        let count = max(min(20, photos.count), 1)
        let fraction = orbitCursor - floor(orbitCursor)
        let angle = (Double(index) - Double(fraction)) / Double(count) * .pi * 2 + Double(orbitDrag.width) * 0.008
        let effectiveScale = ringScale * liveMagnification
        let xRadius = min(size.width * 0.37, 390) * effectiveScale
        let yRadius = min(size.height * (0.18 + pointerY * 0.1), 205) * effectiveScale
        let depth = CGFloat((sin(angle) + 1) / 2)
        return PhotoCard(
            photo: photo,
            width: 112,
            height: 142,
            castsShadow: false,
            resolutionScale: 1.8,
            action: { selectedPhoto = photo }
        )
        .scaleEffect((0.66 + depth * 0.48) * effectiveScale)
        .blur(radius: depthOfField ? max(0, 0.3 - depth) * 2 : 0)
        .opacity(0.48 + depth * 0.52)
        .offset(x: cos(angle) * xRadius, y: sin(angle) * yRadius)
        .zIndex(depth)
    }
}


struct GridGalleryView: View {
    @Environment(BrowsingState.self) private var browsing
    @State private var hoveredDate: String?
    let photos: [MemoryPhoto]
    let revision: UUID
    @Binding var selectedPhoto: MemoryPhoto?
    private var cardWidth: CGFloat { browsing.gridWidth }
    @GestureState private var liveMagnification: CGFloat = 1
    @State private var focusedDate = ""
    @State private var restoringPosition = true
    /// id → 下标映射。原实现在滚动时对每个 preference 回调做一次
    /// `photos.first(where:)`，图库上万张时是每帧 O(n) 的线性查找。
    @State private var indexByID: [String: Int] = [:]

    private func rebuildIndex() {
        var map: [String: Int] = [:]
        map.reserveCapacity(photos.count)
        for (offset, photo) in photos.enumerated() { map[photo.id] = offset }
        indexByID = map
    }

    var body: some View {
        if photos.isEmpty {
            NoMatchesView()
        } else {
            ScrollViewReader { reader in
            ScrollView {
                let width = max(96, min(230, cardWidth * liveMagnification))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: width, maximum: width * 1.22), spacing: 12)], spacing: 12) {
                    ForEach(photos) { photo in
                        GeometryReader { proxy in
                            PhotoCard(photo: photo, width: proxy.size.width, height: proxy.size.width * 1.18, showDate: true) {
                                selectedPhoto = photo
                            }
                            .preference(key: PhotoDateFocusKey.self, value: PhotoDateFocus(date: photo.dateLabel, distance: abs(proxy.frame(in: .named("photoGrid")).minY - 20), id: photo.id))
                        }
                        .id(photo.id)
                        .aspectRatio(0.85, contentMode: .fit)
                    }
                }
                .padding(28)
            }
            .coordinateSpace(name: "photoGrid")
            .onPreferenceChange(PhotoDateFocusKey.self) { value in
                if let value, !restoringPosition {
                    focusedDate = value.date
                    if let id = value.id, let index = indexByID[id], photos.indices.contains(index) {
                        browsing.focus(photos[index])
                    } else if let photo = photos.first(where: { $0.id == value.id }) {
                        browsing.focus(photo)
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                PhotoDateCaption(date: hoveredDate ?? focusedDate).padding(24)
            }
            .environment(\.photoFocusChanged, { hoveredDate = $0 })
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($liveMagnification) { value, state, _ in state = value }
                    .onEnded { value in
                        withAnimation(.easeOut(duration: 0.2)) {
                            browsing.gridWidth = max(96, min(230, cardWidth * value))
                        }
                    }
            )
            .onAppear {
                rebuildIndex()
                if !photos.isEmpty {
                    let photo = photos[browsing.index(in: photos)]
                    focusedDate = photo.dateLabel
                    reader.scrollTo(photo.id, anchor: .top)
                }
                Task { try? await Task.sleep(nanoseconds: 150_000_000); restoringPosition = false }
            }
            .onChange(of: revision) { _, _ in
                rebuildIndex()
                guard !photos.isEmpty else { return }
                restoringPosition = true
                let photo = photos[browsing.index(in: photos)]
                focusedDate = photo.dateLabel
                reader.scrollTo(photo.id, anchor: .top)
                Task { try? await Task.sleep(nanoseconds: 150_000_000); restoringPosition = false }
            }
            }
        }
    }
}

struct GalleryNavigation: View {
    let count: Int
    @Binding var cursor: CGFloat

    var body: some View {
        if count > 1 {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button { step(-1) } label: {
                        Image(systemName: "chevron.left").frame(width: 28, height: 28)
                    }
                    .help("上一张")
                    .accessibilityLabel("上一张")
                    Slider(value: $cursor, in: 0...CGFloat(count - 1))
                        .tint(.cyan)
                        .accessibilityLabel("跳转照片位置")
                    Button { step(1) } label: {
                        Image(systemName: "chevron.right").frame(width: 28, height: 28)
                    }
                    .help("下一张")
                    .accessibilityLabel("下一张")
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .frame(width: 210)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func step(_ direction: CGFloat) {
        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88)) {
            cursor = max(0, min(CGFloat(count - 1), cursor.rounded() + direction))
        }
    }
}

struct InteractionBadge: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.07)))
            .allowsHitTesting(false)
    }
}

struct NoMatchesView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("没有匹配的照片")
                .font(.headline)
            Text("试试其他年份或搜索词")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct PhotoDetailView: View {
    @EnvironmentObject private var library: PhotoLibraryModel
    @EnvironmentObject private var playback: LivePhotoPlayback
    @Environment(\.dismiss) private var dismiss
    let photo: MemoryPhoto
    let lightBackground: Bool
    @State private var image: NSImage?
    @State private var chosenTheme: MemoryTheme?

    var body: some View {
        ZStack {
            (lightBackground ? Color(red: 0.97, green: 0.975, blue: 0.98) : Color(red: 0.02, green: 0.026, blue: 0.04))
                .ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(photo.dateLabel)
                            .font(.title3.weight(.semibold))
                        Text("\(photo.width) × \(photo.height)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Menu {
                            ForEach(MemoryTheme.allCases) { theme in
                                Button {
                                    chosenTheme = theme
                                    library.setTheme(theme, for: photo.id)
                                } label: {
                                    Label(theme.rawValue, systemImage: theme.icon)
                                }
                            }
                        } label: {
                            Label(chosenTheme?.rawValue ?? photo.theme?.rawValue ?? "选择主题", systemImage: chosenTheme?.icon ?? photo.theme?.icon ?? "tag")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.cyan)
                        }
                        .menuStyle(.borderlessButton)
                        .help("手动修正后会在本机保存，并覆盖自动识别结果")
                        if !photo.visionLabels.isEmpty {
                            Text(photo.visionLabels.prefix(3).joined(separator: " · "))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(GlassButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("关闭")
                }
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        ProgressView("正在从 iCloud 读取…")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    if playback.playingID == photo.id, let livePhoto = playback.livePhoto {
                        NativeLivePhotoView(photo: livePhoto).allowsHitTesting(false)
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in playback.press(photo, translation: value.translation) }
                    .onEnded { _ in playback.stop() })
                .help(photo.isLivePhoto ? "长按播放实况，松开停止" : photo.dateLabel)
            }
            .padding(24)
        }
        .frame(minWidth: 760, minHeight: 580)
        .preferredColorScheme(lightBackground ? .light : .dark)
        .onDisappear { playback.stop() }
        .onAppear {
            chosenTheme = photo.theme
            library.requestFullImage(for: photo) { image = $0 }
        }
    }
}

private func pseudo(_ value: Int) -> CGFloat {
    let x = sin(Double(value) * 12.9898) * 43758.5453
    return CGFloat(x - floor(x))
}
