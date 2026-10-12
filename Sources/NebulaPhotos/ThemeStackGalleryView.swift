import SwiftUI

struct ThemePhotoStack: Identifiable, @unchecked Sendable {
    let id: String
    let title: String
    let photos: [MemoryPhoto]

    /// 纯函数版本：不依赖 PhotoOrganization 实例，可安全地放到后台线程构建。
    static func eventStacks(_ events: [PhotoEvent], names: [String: String], photos: [MemoryPhoto]) -> [ThemePhotoStack] {
        guard !events.isEmpty, !photos.isEmpty else { return [] }
        let available = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        return events.compactMap { event in
            let items = event.ids.compactMap { available[$0] }
            guard !items.isEmpty else { return nil }
            return ThemePhotoStack(id: event.id, title: names[event.id] ?? event.title, photos: items)
        }
    }

    static func albums(_ albums: [PhotoLibraryAlbum], photos: [MemoryPhoto]) -> [ThemePhotoStack] {
        let byID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        var groups = albums.compactMap { album -> ThemePhotoStack? in
            let items = album.assetIDs.compactMap { byID[$0] }
            guard !items.isEmpty else { return nil }
            return ThemePhotoStack(id: "album:\(album.id)", title: album.title, photos: items)
        }
        let covered = Set(groups.flatMap { $0.photos.map(\.id) })
        let remaining = photos.filter { !covered.contains($0.id) }
        if !remaining.isEmpty {
            groups.append(ThemePhotoStack(id: "album:unfiled", title: "未归入相册", photos: remaining))
        }
        return groups
    }

    static func grouped(_ photos: [MemoryPhoto]) -> [ThemePhotoStack] {
        let buckets = Dictionary(grouping: photos) { $0.theme?.rawValue ?? "待识别" }
        let order = MemoryTheme.allCases.map(\.rawValue) + ["待识别"]
        return order.compactMap { title in
            guard let items = buckets[title], !items.isEmpty else { return nil }
            return ThemePhotoStack(id: title, title: title, photos: items)
        }
    }
}

struct ThemeStackGalleryView: View {
    @Environment(BrowsingState.self) private var browsing
    @EnvironmentObject private var organization: PhotoOrganization
    let groups: [ThemePhotoStack]
    let appleGroups: [ThemePhotoStack]
    let eventGroups: [ThemePhotoStack]
    let isLoading: Bool
    @Binding var selectedPhoto: MemoryPhoto?
    private var activeGroupID: String? {
        get { browsing.activeStackID }
        nonmutating set { browsing.activeStackID = newValue }
    }
    @State private var focusedDate = ""
    @State private var hoveredDate: String?
    @AppStorage("NebulaPhotos.StackSource") private var source = "苹果相册"
    @State private var renamingID: String?
    @State private var nameDraft = ""
    @Namespace private var expansion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayedGroups: [ThemePhotoStack] { source == "事件" ? eventGroups : source == "苹果相册" ? appleGroups : groups }

    var body: some View {
        VStack(spacing: 0) {
            if activeGroupID == nil {
                HStack {
                    Picker("分组来源", selection: $source) {
                        Text("苹果相册").tag("苹果相册")
                        Text("事件").tag("事件")
                        Text("自动主题").tag("自动主题")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 290)
                    .help("苹果相册沿用现有相册和系统媒体分类；自动主题由本机识别")
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
            }
            ZStack {
            if let group = displayedGroups.first(where: { $0.id == activeGroupID }) {
                ThemeStackBrowser(group: group, namespace: expansion, selectedPhoto: $selectedPhoto) {
                    withAnimation(animation) { activeGroupID = nil }
                }
                .id(group.id)
                .transition(.opacity)
            } else if displayedGroups.isEmpty {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    NoMatchesView()
                }
            } else {
                overview
                    .transition(.opacity)
            }
            }
        }
        .clipped()
        .onAppear {
            if let focusedID = browsing.focusedID,
               let group = displayedGroups.first(where: { $0.photos.contains(where: { $0.id == focusedID }) }) {
                activeGroupID = group.id
            }
        }
        .onChange(of: displayedGroups.map(\.id)) { _, ids in
            if let activeGroupID, !ids.contains(activeGroupID) { self.activeGroupID = nil }
        }
        .alert("事件名称", isPresented: Binding(get: { renamingID != nil }, set: { if !$0 { renamingID = nil } })) {
            TextField("名称", text: $nameDraft)
            Button("保存") { if let renamingID { organization.renameEvent(renamingID, title: nameDraft) }; renamingID = nil }
            Button("取消", role: .cancel) { renamingID = nil }
        }
    }

    private var animation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private var overview: some View {
        GeometryReader { viewport in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    ForEach(displayedGroups) { group in
                        GeometryReader { item in
                            let distance = (item.frame(in: .named("themeStacks")).midX - viewport.size.width / 2) / 240
                            let retreat = min(abs(distance), 3)
                            VStack(spacing: 18) {
                                ZStack {
                                    ForEach(Array(group.photos.prefix(3).enumerated()).reversed(), id: \.element.id) { layer, photo in
                                        PhotoCard(photo: photo, width: 168, height: 212, castsShadow: false, resolutionScale: 1.8) {
                                            withAnimation(animation) { activeGroupID = group.id }
                                        }
                                        .matchedGeometryEffect(id: "\(group.id):\(photo.id)", in: expansion)
                                        .rotationEffect(.degrees(Double(layer) * 3))
                                        .scaleEffect(1 - CGFloat(layer) * 0.035)
                                        .offset(x: CGFloat(layer) * 9, y: -CGFloat(layer) * 6)
                                        .zIndex(Double(3 - layer))
                                    }
                                }
                                .frame(height: 228)
                                VStack(spacing: 4) {
                                    Text(group.title).font(.system(size: 14, weight: .medium))
                                    Text("\(group.photos.count) 张")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 196)
                            .scaleEffect(reduceMotion ? 1 : 1 - retreat * 0.045)
                            .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(-distance * 7)), axis: (x: 0, y: 1, z: 0))
                            .offset(y: reduceMotion ? 0 : retreat * retreat * 7)
                            .contextMenu {
                                if group.id.hasPrefix("event:") {
                                    Button("重命名事件") { nameDraft = group.title; renamingID = group.id }
                                }
                            }
                            .preference(key: PhotoDateFocusKey.self, value: PhotoDateFocus(date: group.photos.first?.dateLabel ?? "", distance: abs(distance)))
                        }
                        .frame(width: 196, height: 300)
                    }
                }
                .padding(.horizontal, max(36, (viewport.size.width - 196) / 2))
                .frame(minHeight: viewport.size.height)
            }
            .coordinateSpace(name: "themeStacks")
            .onPreferenceChange(PhotoDateFocusKey.self) { value in
                if let value { focusedDate = value.date }
            }
        }
        .overlay(alignment: .bottomLeading) {
            PhotoDateCaption(date: hoveredDate ?? focusedDate).padding(24)
        }
        .environment(\.photoFocusChanged, { hoveredDate = $0 })
        .help("横向滚动浏览主题，点击卡组展开")
    }
}

private struct ThemeStackBrowser: View {
    @Environment(BrowsingState.self) private var browsing
    @EnvironmentObject private var organization: PhotoOrganization
    let group: ThemePhotoStack
    let namespace: Namespace.ID
    @Binding var selectedPhoto: MemoryPhoto?
    let close: () -> Void
    @State private var cursor: CGFloat = 0
    @State private var hoveredDate: String?
    @GestureState private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var photos: [MemoryPhoto] { group.photos }
    private var currentIndex: Int { max(0, min(photos.count - 1, Int(cursor.rounded()))) }
    private var visibleIndices: [Int] {
        Array(max(0, currentIndex - 2)...min(photos.count - 1, currentIndex + 2))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) { Label("返回", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(group.title).font(.system(size: 16, weight: .medium))
                Spacer()
                Text("\(currentIndex + 1) / \(photos.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)

            GeometryReader { proxy in
                ZStack {
                    ForEach(visibleIndices, id: \.self) { index in
                        browserCard(index: index, size: proxy.size)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture()
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        if abs(value.predictedEndTranslation.width) > 45 {
                            move(value.predictedEndTranslation.width < 0 ? 1 : -1)
                        }
                    })
                .background(MouseEventMonitor(onScroll: { delta in
                    guard abs(delta) > 0.1 else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        cursor = max(0, min(CGFloat(photos.count - 1), cursor - delta * 0.025))
                    }
                }))
            }
            GalleryNavigation(count: photos.count, cursor: $cursor)
                .padding(.bottom, 18)
        }
        .overlay(alignment: .bottomLeading) {
            PhotoDateCaption(date: hoveredDate ?? photos[currentIndex].dateLabel).padding(24)
        }
        .environment(\.photoFocusChanged, { hoveredDate = $0 })
        .onAppear { cursor = CGFloat(browsing.index(in: photos)) }
        .onChange(of: photos.map(\.id)) { _, _ in cursor = CGFloat(browsing.index(in: photos)) }
        .onChange(of: browsing.focusedID) { _, id in
            guard !photos.isEmpty else { return }
            let current = photos[currentIndex]
            if current.id != id { cursor = CGFloat(browsing.index(in: photos)) }
        }
        .onChange(of: currentIndex) { _, _ in browsing.focus(photos[currentIndex]) }
    }

    private func browserCard(index: Int, size: CGSize) -> some View {
        let relative = CGFloat(index - currentIndex)
        let width = min(320, size.width * 0.32)
        let height = min(390, size.height * 0.84)
        let photo = photos[index]
        return PhotoCard(photo: photo, width: width, height: height, castsShadow: false, resolutionScale: 1.5) {
            if index == currentIndex { selectedPhoto = photo }
            else { move(CGFloat(index - currentIndex)) }
        }
        .matchedGeometryEffect(id: "\(group.id):\(photo.id)", in: namespace)
        .scaleEffect(index == currentIndex ? 1 : 0.82)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(-relative * 16)), axis: (x: 0, y: 1, z: 0))
        .opacity(index == currentIndex ? 1 : 0.55)
        .offset(x: relative * width * 0.8 + drag.width * 0.3, y: abs(relative) * 8)
        .zIndex(Double(10 - abs(relative)))
        .transition(.opacity)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.88), value: currentIndex)
    }

    private func move(_ amount: CGFloat) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.88)) {
            cursor = max(0, min(CGFloat(photos.count - 1), CGFloat(currentIndex) + amount))
        }
    }
}
