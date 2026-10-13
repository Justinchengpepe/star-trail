import AppKit
import Photos
import SwiftUI
import Vision

struct ThemeEvidence {
    let identifier: String
    let confidence: Float
}

struct PhotoLibraryAlbum: Identifiable {
    let id: String
    let title: String
    let assetIDs: [String]
}

enum MemoryTheme: String, CaseIterable, Identifiable {
    case concert = "演出现场"
    case food = "美食"
    case portrait = "人物"
    case landscape = "风景"
    case pet = "宠物"
    case city = "城市"
    case travel = "旅行"
    case document = "文档"
    case other = "其他"
    case uncertain = "待确认"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .concert: return "music.mic"
        case .food: return "fork.knife"
        case .portrait: return "person.crop.rectangle"
        case .landscape: return "mountain.2"
        case .pet: return "pawprint"
        case .city: return "building.2"
        case .travel: return "airplane"
        case .document: return "doc.text.viewfinder"
        case .other: return "sparkles"
        case .uncertain: return "questionmark.circle"
        }
    }

    static func bestMatch(
        from observations: [VNClassificationObservation],
        faceCount: Int = 0,
        recognizedText: String = ""
    ) -> (MemoryTheme, Float) {
        bestMatch(evidence: observations.map { ThemeEvidence(identifier: $0.identifier, confidence: $0.confidence) }, faceCount: faceCount, recognizedText: recognizedText)
    }

    static func bestMatch(
        evidence observations: [ThemeEvidence],
        faceCount: Int = 0,
        recognizedText: String = ""
    ) -> (MemoryTheme, Float) {
        // Vision exposes exact identifiers (e.g. musical_instrument, cityscape).
        // Strong evidence must lead clearly; a long list of weak labels is not confidence.
        let identifiers: [MemoryTheme: Set<String>] = [
            .concert: ["concert", "singer", "performance", "orchestra", "deejay", "karaoke"],
            .food: ["food", "dessert", "bread", "baked_goods", "cake", "birthday_cake", "seafood",
                    "fruit", "vegetable", "coffee", "drink", "pasta", "pizza", "sushi", "ramen",
                    "noodle", "soup", "salad", "hamburger", "sandwich", "steak", "meat", "rice",
                    "dumpling", "cookie", "ice_cream", "tea_drink", "bubble_tea", "pastry", "poultry",
                    "fried_chicken", "grilled_chicken", "stir_fry", "curry", "yogurt"],
            .pet: ["dog", "cat", "adult_cat", "canine", "feline", "kitten", "rabbit", "hamster",
                   "retriever", "husky", "poodle", "corgi", "bulldog", "terrier", "spaniel"],
            .landscape: ["mountain", "beach", "ocean", "forest", "lake", "waterfall", "canyon",
                         "glacier", "island", "sunset_sunrise", "desert", "river", "wetland"],
            .city: ["cityscape", "skyscraper", "street", "building", "bridge", "storefront",
                    "crosswalk", "apartment", "tower"],
            .travel: ["airplane", "airport", "train_real", "train_station", "railroad", "luggage",
                      "suitcase", "passport", "cruise_ship", "camping", "hiking"],
            .document: ["document", "screenshot", "handwriting", "receipt", "printed_page",
                        "diagram", "chart", "whiteboard", "chalkboard"],
            .portrait: ["people", "adult", "child", "baby", "teen", "bride", "groom"]
        ]
        var scores: [MemoryTheme: Float] = [:]
        for (theme, labels) in identifiers {
            let matches = observations.filter { labels.contains($0.identifier.lowercased()) }
                .map(\.confidence).sorted(by: >)
            if let strongest = matches.first {
                scores[theme] = min(1, strongest + matches.dropFirst().prefix(2).reduce(0, +) * 0.08)
            }
        }

        let concertEvidence = observations.filter {
            ["microphone", "musical_instrument", "spotlight", "crowd", "music", "stadium"].contains($0.identifier)
        }.map(\.confidence).sorted(by: >)
        // A crowd, instrument or microphone alone is not a concert.
        if (scores[.concert] ?? 0) >= 0.22, concertEvidence.first ?? 0 >= 0.20 {
            scores[.concert, default: 0] += min(0.12, concertEvidence.prefix(2).reduce(0, +) * 0.10)
        }
        let text = recognizedText.lowercased()
        let hasConcertText = ["演唱会", "音乐节", "巡演", "concert", "music festival"].contains(where: text.contains)
        if hasConcertText, (scores[.concert] ?? 0) >= 0.25 {
            scores[.concert, default: 0] += 0.08
        }
        if faceCount > 0, (scores[.portrait] ?? 0) >= 0.30 {
            scores[.portrait, default: 0] += 0.05
        }
        // Text-heavy pictures must have document evidence, not merely contain text.
        if recognizedText.count > 100, (scores[.document] ?? 0) >= 0.32 {
            scores[.document, default: 0] += 0.08
        }

        let ranked = scores.sorted { $0.value > $1.value }
        guard let best = ranked.first else { return (.uncertain, 0) }
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        guard best.value >= 0.50, best.value - runnerUp >= 0.12 else {
            return (.uncertain, min(1, best.value))
        }
        return (best.key, min(1, best.value))
    }
}

struct MemoryPhoto: Identifiable, @unchecked Sendable {
    let id: String
    let asset: PHAsset
    let createdAt: Date?
    let width: Int
    let height: Int
    var theme: MemoryTheme?
    var themeConfidence: Float = 0
    var visionLabels: [String] = []
    var isThemeManual = false

    /// 展示字段改为预计算存储属性。
    /// 原来 year / dateLabel 是计算属性，画廊滚动时每个可见卡片每帧都会触发一次
    /// Calendar 查询和 DateFormatter 格式化；现在每张照片只在构造时算一次。
    let year: Int
    let dateLabel: String

    init(
        id: String,
        asset: PHAsset,
        createdAt: Date?,
        width: Int,
        height: Int,
        theme: MemoryTheme? = nil,
        themeConfidence: Float = 0,
        visionLabels: [String] = [],
        isThemeManual: Bool = false
    ) {
        self.id = id
        self.asset = asset
        self.createdAt = createdAt
        self.width = width
        self.height = height
        self.theme = theme
        self.themeConfidence = themeConfidence
        self.visionLabels = visionLabels
        self.isThemeManual = isThemeManual
        self.year = Self.calendar.component(.year, from: createdAt ?? .distantPast)
        self.dateLabel = createdAt.map { Self.dateFormatter.string(from: $0) } ?? "日期未知"
    }

    var isLivePhoto: Bool {
        asset.mediaSubtypes.contains(.photoLive)
    }

    /// DateFormatter 非线程安全，仅在主线程构造 MemoryPhoto 时使用（refresh / 测试）。
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    private static let calendar = Calendar.current
}

@MainActor
final class PhotoLibraryModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var photos: [MemoryPhoto] = []
    @Published var albums: [PhotoLibraryAlbum] = []
    @Published var metadataRevision = UUID()
    @Published var isLoading = false
    @Published var loadedCount = 0
    @Published var totalCount = 0
    @Published var errorMessage: String?
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var privacyRevision = UUID()

    private let imageManager = PHCachingImageManager()
    private var fetchResult: PHFetchResult<PHAsset>?
    private var themeCache: [String: (MemoryTheme, Float, [String])] = [:]
    private var manualThemeIDs: Set<String> = []
    private var analysisRunID = UUID()
    private var pendingThemes: [String: (MemoryTheme, Float, [String])] = [:]
    private let storedThemesKey = AnalysisPrivacy.themesKey
    private let manualThemesKey = AnalysisPrivacy.manualKey
    private var analysisRequestID: PHImageRequestID?
    private var fullRequests: Set<PHImageRequestID> = []
    private let defaults: UserDefaults
    private let observesLibrary: Bool

    override convenience init() {
        self.init(defaults: .standard, observesLibrary: true,
                  authorizationStatus: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    /// An isolated preferences domain and disabled observer allow lifecycle
    /// tests without reading a real Photos library or requesting permission.
    init(defaults: UserDefaults, observesLibrary: Bool, authorizationStatus: PHAuthorizationStatus) {
        self.defaults = defaults; self.observesLibrary = observesLibrary
        super.init()
        self.authorizationStatus = authorizationStatus
        loadSavedThemes()
        if observesLibrary {
            PHPhotoLibrary.shared().register(self)
            if canReadLibrary { refresh() }
        }
    }

    deinit {
        if observesLibrary { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    }

    var canReadLibrary: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    var statusText: String {
        switch authorizationStatus {
        case .authorized: return "已连接 iCloud 照片"
        case .limited: return "已连接部分照片"
        case .denied: return "照片访问已关闭"
        case .restricted: return "照片访问受系统限制"
        case .notDetermined: return "等待连接 iCloud 照片"
        @unknown default: return "照片权限状态未知"
        }
    }

    func requestAccess() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            authorizationStatus = status
            if canReadLibrary {
                refresh()
            } else {
                clearAnalysisData()
            }
        }
    }

    func refresh() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard canReadLibrary else { clearAnalysisData(); return }
        isLoading = true
        loadedCount = 0
        errorMessage = nil

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        fetchResult = result
        totalCount = result.count

        var items: [MemoryPhoto] = []
        let count = result.count
        if count > 0 {
            for index in 0..<count {
                let asset = result.object(at: index)
                items.append(
                    MemoryPhoto(
                        id: asset.localIdentifier,
                        asset: asset,
                        createdAt: asset.creationDate,
                        width: asset.pixelWidth,
                        height: asset.pixelHeight,
                        theme: themeCache[asset.localIdentifier]?.0,
                        themeConfidence: themeCache[asset.localIdentifier]?.1 ?? 0,
                        visionLabels: themeCache[asset.localIdentifier]?.2 ?? [],
                        isThemeManual: manualThemeIDs.contains(asset.localIdentifier)
                    )
                )
            }
        }
        let allowedIDs = Set(items.map(\.id))
        let removedPhotos = Set(photos.map(\.id)).subtracting(allowedIDs)
        let previousThemeCount = themeCache.count
        let previousManualCount = manualThemeIDs.count
        themeCache = themeCache.filter { allowedIDs.contains($0.key) }
        manualThemeIDs.formIntersection(allowedIDs)
        pendingThemes = pendingThemes.filter { allowedIDs.contains($0.key) }
        // A running analysis must not repopulate IDs removed from permission.
        if isAnalyzing && !removedPhotos.isEmpty { cancelAnalysis() }
        if themeCache.count != previousThemeCount || manualThemeIDs.count != previousManualCount { persistThemes() }
        photos = items
        loadAlbums(options: options)
        loadedCount = count
        isLoading = false
        metadataRevision = UUID()
    }

    private func loadAlbums(options: PHFetchOptions) {
        var indexed: [PhotoLibraryAlbum] = []
        var seen: Set<String> = []
        func append(_ collection: PHAssetCollection, title: String? = nil) {
            guard seen.insert(collection.localIdentifier).inserted else { return }
            let assets = PHAsset.fetchAssets(in: collection, options: options)
            guard assets.count > 0 else { return }
            var ids: [String] = []
            assets.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
            indexed.append(PhotoLibraryAlbum(id: collection.localIdentifier, title: title ?? collection.localizedTitle ?? "未命名相册", assetIDs: ids))
        }
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in append(collection) }
        let systemAlbums: [(PHAssetCollectionSubtype, String)] = [
            (.smartAlbumFavorites, "收藏"), (.smartAlbumSelfPortraits, "自拍"),
            (.smartAlbumDepthEffect, "人像模式"), (.smartAlbumLivePhotos, "实况照片"),
            (.smartAlbumPanoramas, "全景"), (.smartAlbumScreenshots, "截图"),
            (.smartAlbumLongExposures, "长曝光"), (.smartAlbumRAW, "RAW")
        ]
        for (subtype, title) in systemAlbums {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
                .enumerateObjects { collection, _, _ in append(collection, title: title) }
        }
        albums = indexed
    }

    func analyzeThemes() {
        guard canReadLibrary, !isAnalyzing else { return }
        let candidates = photos.filter { !$0.isThemeManual }
        guard !candidates.isEmpty else { return }

        let runID = UUID()
        analysisRunID = runID
        isAnalyzing = true
        analysisProgress = 0
        analyzeNext(candidates, index: 0, runID: runID)
    }

    func cancelAnalysis() {
        analysisRunID = UUID()
        if let analysisRequestID { imageManager.cancelImageRequest(analysisRequestID) }
        analysisRequestID = nil
        publishPendingThemes()
        persistThemes()
        isAnalyzing = false
    }

    private func analyzeNext(_ candidates: [MemoryPhoto], index: Int, runID: UUID) {
        guard analysisRunID == runID, canReadLibrary else { return }
        guard analysisRunID == runID, index < candidates.count else {
            if analysisRunID == runID {
                isAnalyzing = false
                analysisProgress = 1
                publishPendingThemes()
                persistThemes()
            }
            return
        }

        if Date().timeIntervalSince(PhotoInteractionActivity.lastEvent) < 1.2 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                self?.analyzeNext(candidates, index: index, runID: runID)
            }
            return
        }

        let photo = candidates[index]
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true

        analysisRequestID = imageManager.requestImage(
            for: photo.asset,
            targetSize: CGSize(width: 768, height: 768),
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            guard let self else { return }
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            guard !cancelled,
                  let image,
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                Task { @MainActor in self.analyzeNext(candidates, index: index + 1, runID: runID) }
                return
            }

            DispatchQueue.global(qos: .utility).async {
                let result = classifyMemoryImage(cgImage, isScreenshot: photo.asset.mediaSubtypes.contains(.photoScreenshot))
                Task { @MainActor in
                    guard self.analysisRunID == runID, self.canReadLibrary else { return }
                    self.pendingThemes[photo.id] = (result.theme, result.confidence, result.labels)
                    self.themeCache[photo.id] = (result.theme, result.confidence, result.labels)
                    if (index + 1).isMultiple(of: 8) {
                        self.publishPendingThemes()
                        self.analysisProgress = Double(index + 1) / Double(candidates.count)
                    }
                    if index.isMultiple(of: 25) { self.persistThemes() }
                    self.analyzeNext(candidates, index: index + 1, runID: runID)
                }
            }
        }
    }

    private func publishPendingThemes() {
        guard !pendingThemes.isEmpty else { return }
        var updated = photos
        for index in updated.indices where !updated[index].isThemeManual {
            guard let result = pendingThemes[updated[index].id] else { continue }
            updated[index].theme = result.0
            updated[index].themeConfidence = result.1
            updated[index].visionLabels = result.2
        }
        pendingThemes.removeAll(keepingCapacity: true)
        photos = updated
    }

    func setTheme(_ theme: MemoryTheme, for photoID: String) {
        guard let index = photos.firstIndex(where: { $0.id == photoID }) else { return }
        photos[index].theme = theme
        photos[index].themeConfidence = 1
        photos[index].isThemeManual = true
        manualThemeIDs.insert(photoID)
        themeCache[photoID] = (theme, 1, photos[index].visionLabels)
        persistThemes()
    }


    private func loadSavedThemes() {
        manualThemeIDs = Set(defaults.stringArray(forKey: manualThemesKey) ?? [])
        let saved = AnalysisPrivacy.migrate(defaults)
        for (id, item) in saved {
            guard let rawValue = item["theme"] as? String, let theme = MemoryTheme(rawValue: rawValue) else { continue }
            themeCache[id] = (theme, (item["confidence"] as? NSNumber)?.floatValue ?? 0, [])
        }
    }

    private func persistThemes() {
        let saved: [String: [String: Any]] = themeCache.mapValues {
            ["theme": $0.0.rawValue, "confidence": NSNumber(value: $0.1)]
        }
        defaults.set(saved, forKey: storedThemesKey)
        defaults.set(Array(manualThemeIDs), forKey: manualThemesKey)
    }

    @discardableResult
    func requestFullImage(for photo: MemoryPhoto, completion: @escaping (NSImage?) -> Void) -> PHImageRequestID {
        let revision = privacyRevision
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        let requestID = imageManager.requestImage(
            for: photo.asset,
            targetSize: CGSize(width: 2400, height: 2400),
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            guard info?[PHImageResultIsDegradedKey] as? Bool != true else { return }
            guard let image else { Task { @MainActor in
                guard let self, self.privacyRevision == revision, self.canReadLibrary else { return }
                completion(nil)
            }; return }
            let source = DecodedThumbnail(image: image, cost: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                let decoded = autoreleasepool { ThumbnailDecode.prepare(source.image) ?? source }
                Task { @MainActor in
                    guard let self, self.privacyRevision == revision, self.canReadLibrary else { return }
                    completion(decoded.image)
                }
            }
        }
        fullRequests.insert(requestID)
        return requestID
    }

    func cancelFullImageRequest(_ id: PHImageRequestID) {
        imageManager.cancelImageRequest(id)
        fullRequests.remove(id)
    }

    func revalidateAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status != authorizationStatus || status == .limited { refresh() }
    }

    /// Removes only this application's derived data; never mutates PhotoKit.
    func clearAnalysisData() {
        analysisRunID = UUID()
        if let analysisRequestID { imageManager.cancelImageRequest(analysisRequestID) }
        analysisRequestID = nil
        for id in fullRequests { imageManager.cancelImageRequest(id) }
        fullRequests.removeAll()
        imageManager.stopCachingImagesForAllAssets()
        themeCache.removeAll(); manualThemeIDs.removeAll(); pendingThemes.removeAll()
        isAnalyzing = false; analysisProgress = 0
        AnalysisPrivacy.clear(defaults)
        AssetThumbnailLoader.clearMemoryCache()
        if canReadLibrary {
            photos = photos.map { item in
                var photo = item; photo.theme = nil; photo.themeConfidence = 0
                photo.visionLabels = []; photo.isThemeManual = false; return photo
            }
        } else {
            photos = []; albums = []; fetchResult = nil
            loadedCount = 0; totalCount = 0; isLoading = false
        }
        metadataRevision = UUID(); privacyRevision = UUID()
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.refresh()
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") else { return }
        NSWorkspace.shared.open(url)
    }
}

private func classifyMemoryImage(_ cgImage: CGImage, isScreenshot: Bool) -> (theme: MemoryTheme, confidence: Float, labels: [String]) {
    autoreleasepool {
        let request = VNClassifyImageRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request, faceRequest])
        let observations = Array((request.results ?? []).prefix(30))
        let initial = MemoryTheme.bestMatch(from: observations, faceCount: faceRequest.results?.count ?? 0)

        var recognizedText = ""
        if isScreenshot || initial.0 == .concert || initial.0 == .document || initial.0 == .other || initial.0 == .uncertain {
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            textRequest.recognitionLanguages = ["zh-Hans", "en-US"]
            try? handler.perform([textRequest])
            recognizedText = (textRequest.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
        }

        let match = MemoryTheme.bestMatch(
            from: observations,
            faceCount: faceRequest.results?.count ?? 0,
            recognizedText: recognizedText
        )
        var labels = observations.prefix(6).map(\.identifier)
        if !recognizedText.isEmpty { labels.append(recognizedText) }
        return isScreenshot ? (.document, 1, labels) : (match.0, match.1, labels)
    }
}
