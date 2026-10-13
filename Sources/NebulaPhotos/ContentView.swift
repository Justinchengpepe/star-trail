import AppKit
import Photos
import SwiftUI

enum GalleryMode: String, CaseIterable, Identifiable {
    case nebula = "星云"
    case stack = "层叠"
    case orbit = "轨道"
    case gallery = "画廊"

    var id: String { rawValue }
    var shortcut: KeyEquivalent {
        switch self {
        case .nebula: return "1"
        case .stack: return "2"
        case .orbit: return "3"
        case .gallery: return "4"
        }
    }
    var shortcutHint: String {
        switch self {
        case .nebula: return "⌘1"
        case .stack: return "⌘2"
        case .orbit: return "⌘3"
        case .gallery: return "⌘4"
        }
    }
    var icon: String {
        switch self {
        case .nebula: return "sparkles"
        case .stack: return "rectangle.stack"
        case .orbit: return "circle.dotted"
        case .gallery: return "square.grid.2x2"
        }
    }
}

/// 层叠模式的三套分组结果。
///
/// 构建成本是 O(照片数)：`grouped` 要分桶，`albums` 要建 id→photo 字典再建覆盖集合，
/// `eventStacks` 也要建一次字典。原实现把这三个调用直接写在视图初始化参数里，
/// 于是 `ContentView.body` 每次求值（搜索输入、筛选、识别进度更新……）都会全量重算。
/// 现在改为按输入签名缓存 + 后台线程构建。
struct StackGroups: @unchecked Sendable {
    let byTheme: [ThemePhotoStack]
    let byAlbum: [ThemePhotoStack]
    let byEvent: [ThemePhotoStack]

    static let empty = StackGroups(byTheme: [], byAlbum: [], byEvent: [])

    static func build(photos: [MemoryPhoto],
                      albums: [PhotoLibraryAlbum],
                      events: [PhotoEvent],
                      names: [String: String]) -> StackGroups {
        StackGroups(
            byTheme: ThemePhotoStack.grouped(photos),
            byAlbum: ThemePhotoStack.albums(albums, photos: photos),
            byEvent: ThemePhotoStack.eventStacks(events, names: names, photos: photos)
        )
    }
}

/// 决定分组结果是否需要重建的输入签名。
private struct GroupBuildKey: Equatable {
    let photosRevision: UUID
    let albumsRevision: UUID
    let eventsRevision: UUID
    let eventNames: [String: String]
    let year: Int?
    let theme: MemoryTheme?
    let query: String
}

struct PhotoCatalog: @unchecked Sendable {
    let photos: [MemoryPhoto]
    let years: [Int]
    let themes: [MemoryTheme]

    static func build(_ photos: [MemoryPhoto], year: Int?, theme: MemoryTheme?, query: String) -> PhotoCatalog {
        let years = Array(Set(photos.map(\.year).filter { $0 > 1900 })).sorted(by: >)
        let present = Set(photos.compactMap(\.theme))
        let themes = MemoryTheme.allCases.filter { present.contains($0) }
        let filtered = year == nil && theme == nil && query.isEmpty ? photos : photos.filter { photo in
            guard year == nil || photo.year == year, theme == nil || photo.theme == theme else { return false }
            return query.isEmpty || ([photo.dateLabel, photo.theme?.rawValue ?? ""] + photo.visionLabels).contains { $0.localizedCaseInsensitiveContains(query) }
        }
        return PhotoCatalog(photos: filtered, years: years, themes: themes)
    }
}

struct ContentView: View {
    @EnvironmentObject private var library: PhotoLibraryModel
    @Environment(BrowsingState.self) private var browsing
    @EnvironmentObject private var organization: PhotoOrganization
    @EnvironmentObject private var playback: LivePhotoPlayback
    @State private var mode: GalleryMode = .nebula
    @State private var query = ""
    @State private var photoListRevision = UUID()
    @State private var albumsRevision = UUID()
    @State private var eventsRevision = UUID()
    @State private var displayedRevision = UUID()
    @State private var catalog = PhotoCatalog(photos: [], years: [], themes: [])
    @State private var selectedYear: Int?
    @State private var selectedTheme: MemoryTheme?
    @State private var selectedPhoto: MemoryPhoto?
    @State private var lightBackground = false
    @AppStorage("NebulaPhotos.DepthOfField") private var depthOfField = false
    @State private var stackGroups: StackGroups = .empty
    @State private var stackGroupsReady = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var cleanupResult: String?

    private var groupBuildKey: GroupBuildKey {
        GroupBuildKey(
            photosRevision: photoListRevision,
            albumsRevision: albumsRevision,
            eventsRevision: eventsRevision,
            eventNames: organization.names,
            year: selectedYear,
            theme: selectedTheme,
            query: query
        )
    }

    private var filteredPhotos: [MemoryPhoto] {
        catalog.photos
    }

    private var years: [Int] {
        catalog.years
    }

    private var themes: [MemoryTheme] {
        catalog.themes
    }

    private var displayedPhotos: [MemoryPhoto] { filteredPhotos }

    private var canvas: some View {
        ZStack {
            CosmicBackground(isLight: lightBackground)
            VStack(spacing: 0) {
                HeaderBar(query: $query, lightBackground: $lightBackground, depthOfField: $depthOfField)
                Group {
                    if !library.canReadLibrary {
                        PermissionView()
                    } else if library.photos.isEmpty && !library.isLoading {
                        EmptyLibraryView()
                    } else {
                        galleryContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                BottomControlBar(
                    mode: $mode,
                    selectedYear: $selectedYear,
                    selectedTheme: $selectedTheme,
                    years: years,
                    themes: themes,
                    visibleCount: filteredPhotos.count
                )
            }
        }
    }

    var body: some View {
        canvas
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo, lightBackground: lightBackground)
                .environmentObject(library)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.revalidateAccess() }
        }
        .onAppear {
            if library.authorizationStatus == .denied || library.authorizationStatus == .restricted {
                library.clearAnalysisData()
            }
        }
        .onChange(of: library.privacyRevision) { _, _ in
            selectedPhoto = nil; playback.stop()
            query = ""; catalog = PhotoCatalog(photos: [], years: [], themes: [])
            stackGroups = .empty; stackGroupsReady = false
            Task {
                do {
                    try await organization.clearAnalysisData()
                    if library.canReadLibrary {
                        cleanupResult = "已清除本机分析数据，苹果相册原图未修改。可重新识别主题或通过星迹菜单重建事件索引。"
                    }
                } catch { cleanupResult = "分析索引未完全清除，请重试。" }
            }
        }
        .alert("分析数据清理", isPresented: Binding(get: { cleanupResult != nil }, set: { if !$0 { cleanupResult = nil } })) {
            Button("好") { cleanupResult = nil }
        } message: { Text(cleanupResult ?? "") }
        .task(id: library.metadataRevision) {
            organization.load(library.photos); browsing.reconcile(library.photos)
        }
        .task(id: groupBuildKey) {
            let key = groupBuildKey
            let photos = library.photos
            let albums = library.albums
            let snapshot = organization.eventStacksSnapshot()
            let built = await Task.detached(priority: .userInitiated) {
                let catalog = PhotoCatalog.build(photos, year: key.year, theme: key.theme, query: key.query)
                let groups = StackGroups.build(photos: catalog.photos, albums: albums, events: snapshot.events, names: snapshot.names)
                return (catalog, groups)
            }.value
            guard !Task.isCancelled, groupBuildKey == key else { return }
            catalog = built.0
            stackGroups = built.1
            displayedRevision = UUID()
            browsing.reconcile(built.0.photos)
            stackGroupsReady = true
        }
        .onChange(of: mode) { _, _ in playback.stop() }
        .onReceive(library.$photos) { _ in photoListRevision = UUID() }
        .onReceive(library.$albums) { _ in albumsRevision = UUID() }
        .onReceive(organization.$events) { _ in eventsRevision = UUID() }
        .onChange(of: query) { _, _ in playback.stop() }
        .onChange(of: selectedYear) { _, _ in playback.stop() }
        .onChange(of: selectedTheme) { _, _ in playback.stop() }
        .onAppear {
            if library.canReadLibrary && library.photos.isEmpty {
                library.refresh()
            }
        }
        .preferredColorScheme(lightBackground ? .light : .dark)
        .environment(\.depthOfFieldEnabled, depthOfField)
        .focusedSceneValue(\.photoBrowserMode, selectedPhoto == nil ? $mode : nil)
    }

    @ViewBuilder
    private var galleryContent: some View {
        Group {
            switch mode {
            case .nebula:
                NebulaView(photos: displayedPhotos, revision: displayedRevision, selectedPhoto: $selectedPhoto)
            case .orbit:
                OrbitView(photos: displayedPhotos, revision: displayedRevision, selectedPhoto: $selectedPhoto)
            case .stack:
                ThemeStackGalleryView(
                    groups: stackGroups.byTheme,
                    appleGroups: stackGroups.byAlbum,
                    eventGroups: stackGroups.byEvent,
                    isLoading: !stackGroupsReady,
                    revision: displayedRevision,
                    selectedPhoto: $selectedPhoto
                )
            case .gallery:
                GridGalleryView(photos: displayedPhotos, revision: displayedRevision, selectedPhoto: $selectedPhoto)
            }
        }
    }
}

struct HeaderBar: View {
    @EnvironmentObject private var library: PhotoLibraryModel
    @Binding var query: String
    @Binding var lightBackground: Bool
    @Binding var depthOfField: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text("星迹")
                .font(.system(size: 17, weight: .medium))

            Spacer()

            HStack(spacing: 8) {
                Button { searchFocused = true } label: {
                    Image(systemName: "magnifyingglass")
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("搜索照片（⌘F）")
                    .accessibilityLabel("搜索照片")
                TextField("搜索日期、主题、文字", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onExitCommand {
                        if query.isEmpty { searchFocused = false }
                        else { query = "" }
                    }
                    .frame(width: 150)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.09)))

            if library.canReadLibrary {
                Menu {
                    Button { library.refresh() } label: { Label("刷新照片", systemImage: "arrow.clockwise") }
                        .disabled(library.isLoading)
                    Button { library.isAnalyzing ? library.cancelAnalysis() : library.analyzeThemes() } label: {
                        Label(library.isAnalyzing ? "停止识别照片主题" : "识别全部照片主题", systemImage: library.isAnalyzing ? "stop.fill" : "wand.and.stars")
                    }
                    .disabled(library.photos.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 38, height: 38)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("图库操作：刷新、主题识别")
                .accessibilityLabel("图库操作")
                if library.isAnalyzing {
                    Button { library.cancelAnalysis() } label: {
                        Image(systemName: "stop.circle").frame(width: 38, height: 38)
                    }
                    .buttonStyle(GlassButtonStyle())
                    .help("停止识别 · 已完成 \(Int(library.analysisProgress * 100))%")
                    .accessibilityLabel("停止识别照片主题")
                }
            } else {
                Button { library.requestAccess() } label: {
                    Image(systemName: "photo.on.rectangle.angled").frame(width: 38, height: 38)
                }
                .buttonStyle(GlassButtonStyle())
                .help("连接 iCloud 照片")
                .accessibilityLabel("连接 iCloud 照片")
            }

            Button {
                depthOfField.toggle()
            } label: {
                Image(systemName: "camera.aperture")
                    .foregroundStyle(depthOfField ? Color.cyan : Color.secondary)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(GlassButtonStyle())
            .help(depthOfField ? "关闭景深 · 所有照片清晰" : "开启轻微景深 · 焦点照片保持清晰")
            .accessibilityLabel(depthOfField ? "关闭景深虚化" : "开启景深虚化")

            Button {
                withAnimation(.easeOut(duration: 0.28)) {
                    lightBackground.toggle()
                }
            } label: {
                Image(systemName: lightBackground ? "moon.fill" : "sun.max.fill")
                    .frame(width: 38, height: 38)
                    .foregroundStyle(lightBackground ? Color.primary : Color.secondary)
            }
            .buttonStyle(GlassButtonStyle())
            .help(lightBackground ? "切换黑色背景" : "切换白色背景")
            .accessibilityLabel(lightBackground ? "切换黑色背景" : "切换白色背景")

        }
        .padding(.horizontal, 24)
        .focusedSceneValue(\.focusPhotoSearch, { searchFocused = true })
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

struct PermissionView: View {
    @EnvironmentObject private var library: PhotoLibraryModel

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.08))
                    .frame(width: 124, height: 124)
                Circle()
                    .stroke(Color.cyan.opacity(0.18), lineWidth: 1)
                    .frame(width: 92, height: 92)
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.white, .cyan)
            }

            VStack(spacing: 9) {
                Text("连接你的 iCloud 照片")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("通过 macOS 照片图库读取已同步的照片。\n照片只在这台 Mac 上处理，不会上传。")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            if library.authorizationStatus == .denied || library.authorizationStatus == .restricted {
                Button("打开系统设置") { library.openPrivacySettings() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("允许访问照片") { library.requestAccess() }
                    .buttonStyle(PrimaryButtonStyle())
            }

            Label("需要在“照片”中启用 iCloud 照片同步", systemImage: "lock.shield")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }
}

struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text("照片图库为空")
                .font(.title2.weight(.semibold))
            Text("请确认这台 Mac 已开启 iCloud 照片同步。")
                .foregroundStyle(.secondary)
        }
    }
}

struct BottomControlBar: View {
    @Binding var mode: GalleryMode
    @Binding var selectedYear: Int?
    @Binding var selectedTheme: MemoryTheme?
    let years: [Int]
    let themes: [MemoryTheme]
    let visibleCount: Int

    var body: some View {
        HStack(spacing: 16) {
            Text("\(visibleCount) 张")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            Menu {
                Button { selectedYear = nil } label: {
                    FilterMenuLabel(title: "全部年份", selected: selectedYear == nil)
                }
                ForEach(years, id: \.self) { year in
                    Button { selectedYear = year } label: {
                        FilterMenuLabel(title: String(year), selected: selectedYear == year)
                    }
                }
            } label: {
                Text(selectedYear.map(String.init) ?? "年份")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Button { selectedTheme = nil } label: {
                    FilterMenuLabel(title: "全部主题", selected: selectedTheme == nil)
                }
                ForEach(themes) { theme in
                    Button { selectedTheme = theme } label: {
                        FilterMenuLabel(title: theme.rawValue, selected: selectedTheme == theme)
                    }
                }
            } label: {
                Text(selectedTheme?.rawValue ?? "主题")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 12)

            HStack(spacing: 4) {
                ForEach(GalleryMode.allCases) { item in
                    Button { withAnimation(.easeOut(duration: 0.24)) { mode = item } } label: {
                        HStack(spacing: 7) {
                            Image(systemName: item.icon)
                            Text(item.rawValue)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(mode == item ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(mode == item ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("切换到\(item.rawValue)模式")
                    .accessibilityAddTraits(mode == item ? .isSelected : [])
                    .help("\(item.rawValue)（\(item.shortcutHint)）")
                }
            }
            .padding(4)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.primary.opacity(0.08)))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1) }
    }
}

private struct FilterMenuLabel: View {
    let title: String
    let selected: Bool
    var body: some View {
        if selected { Label(title, systemImage: "checkmark") }
        else { Text(title) }
    }
}

struct YearChip: View {
    let label: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(label)
            }
                .font(.system(size: 11, weight: .medium, design: icon == nil ? .monospaced : .default))
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(isSelected ? Color.cyan.opacity(0.16) : Color.primary.opacity(0.045), in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.cyan.opacity(0.32) : Color.primary.opacity(0.06)))
                .foregroundStyle(isSelected ? Color.cyan : .secondary)
        }
        .buttonStyle(.plain)
    }
}

struct CosmicBackground: View {
    let isLight: Bool

    var body: some View {
        (isLight ? Color(white: 0.97) : Color(white: 0.035))
            .ignoresSafeArea()
    }
}

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.09)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 22)
            .frame(height: 44)
            .background(Color.cyan.opacity(configuration.isPressed ? 0.72 : 0.9), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Color(red: 0.02, green: 0.08, blue: 0.1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
