import AppKit
import Photos
import Foundation

@main
struct PhotoWorkflowChecks {
    @MainActor static func main() async throws {
        var gate = GalleryPointerGate()
        precondition(gate.permitsPointerUpdates)
        gate.press(); precondition(!gate.permitsPointerUpdates)
        gate.release(); precondition(gate.permitsPointerUpdates)
        gate.release(); precondition(gate.permitsPointerUpdates)
        gate.press()
        gate.reconcile(leftButtonPressed: true)
        precondition(!gate.permitsPointerUpdates)
        // Slider tracking swallowed mouseUp: recover on the next wheel/move.
        gate.reconcile(leftButtonPressed: false)
        precondition(gate.permitsPointerUpdates)
        gate.press(); gate.release()
        gate.reconcile(leftButtonPressed: false)
        precondition(gate.permitsPointerUpdates)
        precondition(GalleryInputPolicy.dragDistance == 16)
        precondition(!GalleryInputPolicy.acceptsPhotoHit(opacity: 0))
        precondition(!GalleryInputPolicy.acceptsPhotoHit(opacity: 0.05))
        precondition(GalleryInputPolicy.acceptsPhotoHit(opacity: 0.051))
        let ticket = ThumbnailDecodeTicket()
        precondition(ticket.isActive)
        ticket.cancel(); precondition(!ticket.isActive)
        let privacySuite = "local.nebula.privacy-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: privacySuite)!
        defer { defaults.removePersistentDomain(forName: privacySuite) }
        defaults.set(["a": ["theme": "人物", "confidence": NSNumber(value: 0.8), "labels": ["秘密电话 123456789", "people"]]], forKey: "NebulaPhotos.StoredThemes.v3")
        defaults.set(["b": "美食"], forKey: "NebulaPhotos.StoredThemes.v2")
        defaults.set(["a", "b"], forKey: AnalysisPrivacy.manualKey)
        let safe = AnalysisPrivacy.migrate(defaults)
        precondition(safe["a"]?["labels"] == nil && safe["b"]?["theme"] as? String == "美食")
        precondition(defaults.object(forKey: "NebulaPhotos.StoredThemes.v3") == nil)
        precondition(defaults.object(forKey: "NebulaPhotos.StoredThemes.v2") == nil)
        precondition(defaults.stringArray(forKey: AnalysisPrivacy.manualKey) == ["a", "b"])
        precondition(!String(describing: defaults.dictionaryRepresentation()).contains("123456789"))
        precondition(AnalysisPrivacy.migrate(defaults).count == 2)
        AnalysisPrivacy.clear(defaults)
        precondition(defaults.object(forKey: AnalysisPrivacy.themesKey) == nil && defaults.object(forKey: AnalysisPrivacy.manualKey) == nil)
        ticket.cancel(); precondition(!ticket.isActive)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = ISO8601DateFormatter().date(from: "2026-10-12T08:00:00Z")!
        func record(_ id: String, _ seconds: Double, lat: Double? = nil) -> PhotoMetadata {
            PhotoMetadata(id: id, date: date.addingTimeInterval(seconds), latitude: lat, longitude: lat == nil ? nil : 0)
        }
        precondition(EventBuilder.build([record("a", 0), record("b", 7200)], calendar: calendar).count == 1)
        precondition(EventBuilder.build([record("a", 0), record("b", 7201)], calendar: calendar).count == 2)
        precondition(EventBuilder.build([record("a", 0), record("b", 86400)], calendar: calendar).count == 2)
        precondition(EventBuilder.build([record("a", 0, lat: 0), record("b", 20, lat: 0.1)], calendar: calendar).count == 2)
        precondition(EventBuilder.build([record("a", 0, lat: 0), record("b", 20)], calendar: calendar).count == 1)
        precondition(EventBuilder.build([record("a", 0, lat: 0), record("b", 20, lat: 0.01)], calendar: calendar).count == 1)
        precondition(EventBuilder.build([PhotoMetadata(id: "undated", date: nil)], calendar: calendar).first?.title == "日期未知")
        let grouped = EventBuilder.build([record("b", 20), record("a", 0)], calendar: calendar)
        precondition(grouped.first?.id == "event:a" && grouped.first?.ids == ["b", "a"])

        func photo(_ id: String, _ seconds: Double) -> MemoryPhoto {
            MemoryPhoto(id: id, asset: PHAsset(), createdAt: date.addingTimeInterval(seconds), width: 100, height: 100)
        }
        let photos = [photo("a", 0), photo("b", 20), photo("c", 40)]
        let isolatedModel = PhotoLibraryModel(defaults: defaults, observesLibrary: false, authorizationStatus: .authorized)
        var sensitivePhoto = photos[0]; sensitivePhoto.visionLabels = ["秘密电话 987654321"]
        isolatedModel.photos = [sensitivePhoto]
        isolatedModel.setTheme(.concert, for: sensitivePhoto.id)
        precondition(!String(describing: defaults.dictionaryRepresentation()).contains("987654321"))
        let privacyRevision = isolatedModel.privacyRevision
        isolatedModel.clearAnalysisData()
        precondition(isolatedModel.photos.count == 1 && isolatedModel.photos[0].theme == nil)
        precondition(isolatedModel.photos[0].visionLabels.isEmpty && !isolatedModel.photos[0].isThemeManual)
        precondition(isolatedModel.privacyRevision != privacyRevision)
        isolatedModel.authorizationStatus = .denied
        isolatedModel.clearAnalysisData()
        precondition(isolatedModel.photos.isEmpty && isolatedModel.albums.isEmpty && isolatedModel.totalCount == 0)
        precondition(NebulaPreheatWindow.indices(total: 0, center: 0, offsets: -15...44).isEmpty)
        let warmed = NebulaPreheatWindow.indices(total: 1000, center: 0, offsets: -15...44)
        precondition(warmed.count == 60 && warmed.first == 985 && warmed.last == 44)
        precondition(Set(NebulaPreheatWindow.indices(total: 4, center: 0, offsets: -15...44)) == Set(0..<4))
        let edge = NebulaPreheatWindow.indices(total: 1000, center: 999, offsets: -3...8)
        precondition(edge.count == 12 && edge.contains(0) && edge.allSatisfy { (0..<1000).contains($0) })
        let card = NebulaCard(photo: photos[0], resolutionScale: 2.6, selectedPhoto: .constant(nil))
        precondition(card == NebulaCard(photo: photos[0], resolutionScale: 2.6, selectedPhoto: .constant(nil)))
        precondition(card != NebulaCard(photo: photos[0], resolutionScale: 0.85, selectedPhoto: .constant(nil)))
        var changed = photos[0]; changed.theme = .concert
        precondition(card != NebulaCard(photo: changed, resolutionScale: 2.6, selectedPhoto: .constant(nil)))
        let gridCard = GridPhotoCard(photo: photos[0], width: 142, selectedPhoto: .constant(nil))
        let covers = StackCoverInputs(ThemePhotoStack(id: "album:a", title: "相册 A", photos: photos))
        precondition(covers == StackCoverInputs(ThemePhotoStack(id: "album:a", title: "相册 A", photos: photos)))
        precondition(covers != StackCoverInputs(ThemePhotoStack(id: "album:b", title: "相册 A", photos: photos)))
        precondition(covers != StackCoverInputs(ThemePhotoStack(id: "album:a", title: "新名称", photos: photos)))
        precondition(covers != StackCoverInputs(ThemePhotoStack(id: "album:a", title: "相册 A", photos: [changed, photos[1], photos[2]])))
        let largeStack = photos + (0..<1000).map { photo("extra:\($0)", Double($0)) }
        let largeCovers = StackCoverInputs(ThemePhotoStack(id: "album:a", title: "相册 A", photos: largeStack))
        precondition(largeCovers.photos.count == 3 && largeCovers.count == 1003)
        var changedInterior = largeStack
        changedInterior[500].theme = .concert
        precondition(largeCovers == StackCoverInputs(ThemePhotoStack(id: "album:a", title: "相册 A", photos: changedInterior)))
        precondition(largeCovers != StackCoverInputs(ThemePhotoStack(id: "album:a", title: "相册 A", photos: largeStack + [photo("new", 0)])))
        precondition(gridCard == GridPhotoCard(photo: photos[0], width: 142, selectedPhoto: .constant(nil)))
        precondition(gridCard != GridPhotoCard(photo: photos[0], width: 180, selectedPhoto: .constant(nil)))
        precondition(gridCard != GridPhotoCard(photo: changed, width: 142, selectedPhoto: .constant(nil)))
        let galleryDates = GalleryDateState()
        galleryDates.focus("2026年10月12日")
        galleryDates.hover("2026年10月13日")
        precondition(galleryDates.focusedDate == "2026年10月12日" && galleryDates.hoveredDate == "2026年10月13日")
        galleryDates.hoverHandler(nil)
        precondition(galleryDates.hoveredDate == nil && galleryDates.focusedDate == "2026年10月12日")
        let browsing = BrowsingState(); browsing.focus(photos[1])
        precondition(browsing.index(in: photos) == 1)
        precondition(browsing.index(in: photos.reversed()) == 1)
        browsing.reconcile([photos[0], photos[2]])
        precondition(browsing.focusedID == "a" || browsing.focusedID == "c")
        browsing.focus(photos[0]); browsing.reconcile([photos[2]])
        precondition(browsing.focusedID == "c" && browsing.index(in: []) == 0)
        browsing.nebulaZoom = 1.5; browsing.orbitZoom = 0.8; browsing.gridWidth = 190
        browsing.rememberStackOverview("event:old", source: "事件")
        browsing.rememberStackOverview("album:old", source: "苹果相册")
        browsing.rememberStackOverview(nil, source: "事件")
        precondition(browsing.stackOverviewID(for: "事件") == "event:old")
        precondition(browsing.stackOverviewID(for: "苹果相册") == "album:old")
        browsing.reconcileStackOverview(source: "事件", availableIDs: ["event:old", "event:new"])
        precondition(browsing.stackOverviewID(for: "事件") == "event:old")
        browsing.reconcileStackOverview(source: "事件", availableIDs: ["event:new"])
        precondition(browsing.stackOverviewID(for: "事件") == nil)
        precondition(browsing.stackOverviewID(for: "苹果相册") == "album:old")
        browsing.focus(photos[1])
        precondition(browsing.nebulaZoom == 1.5 && browsing.orbitZoom == 0.8 && browsing.gridWidth == 190)
        let catalog = PhotoCatalog.build(photos, year: nil, theme: nil, query: "")
        precondition(catalog.photos.map(\.id) == ["a", "b", "c"] && catalog.years == [2026])
        precondition(PhotoCatalog.build(photos, year: 2025, theme: nil, query: "").photos.isEmpty)
        precondition(PhotoCatalog.build(photos, year: nil, theme: nil, query: "2026年10月12日").photos.count == 3)
        precondition(PhotoCatalog.build(photos, year: nil, theme: nil, query: "不存在的主题").photos.isEmpty)
        let events = EventBuilder.build(photos.map(PhotoMetadata.init), calendar: calendar)
        let stacks = StackGroups.build(photos: photos, albums: [], events: events, names: [:])
        precondition(stacks.byEvent.flatMap(\.photos).count == 3 && stacks.byAlbum.first?.photos.count == 3)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 50, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 160, bitsPerPixel: 32)!
        let image = NSImage(size: CGSize(width: 40, height: 50)); image.addRepresentation(bitmap)
        let decoded = ThumbnailDecode.prepare(image)!
        precondition(decoded.cost == 40 * 50 * 4 && decoded.image.size == image.size)
        let displaySpace = CGColorSpace(name: CGColorSpace.displayP3)!
        let displayDecoded = ThumbnailDecode.prepare(image, displayColorSpace: displaySpace)!
        let displayCGImage = displayDecoded.image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        precondition(displayCGImage.width == 40 && displayCGImage.height == 50)
        precondition(displayCGImage.colorSpace == displaySpace)
        precondition(displayCGImage.alphaInfo == .premultipliedFirst)
        precondition(displayCGImage.bitmapInfo.contains(.byteOrder32Little))
        // Format conversion must preserve wide-gamut channel values and alpha,
        // not merely attach a different color-space label to the old pixels.
        let colorSource = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                    space: displaySpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        colorSource.setFillColor(CGColor(colorSpace: displaySpace, components: [0.98, 0.2, 0.05, 0.65])!)
        colorSource.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let colorCGImage = colorSource.makeImage()!
        let colorImage = NSImage(cgImage: colorCGImage, size: CGSize(width: 2, height: 2))
        let converted = ThumbnailDecode.prepare(colorImage, displayColorSpace: displaySpace)!
            .image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let rgba = colorCGImage.dataProvider!.data! as Data
        let bgra = converted.dataProvider!.data! as Data
        for pixel in stride(from: 0, to: 16, by: 4) {
            for (original, destination) in [(0, 2), (1, 1), (2, 0), (3, 3)] {
                precondition(abs(Int(rgba[pixel + original]) - Int(bgra[pixel + destination])) <= 1)
            }
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nebula-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PhotoIndexStore(directory: directory)
        store.save(grouped, kind: "events", id: "test", stamp: "v1", version: "1")
        precondition(store.load([PhotoEvent].self, kind: "events", id: "test", stamp: "v1", version: "1")?.first?.ids == ["b", "a"])
        precondition(store.load([PhotoEvent].self, kind: "events", id: "test", stamp: "v2") == nil)
        precondition(store.load([PhotoEvent].self, kind: "events", id: "test", version: "2") == nil)
        let reopened = PhotoIndexStore(directory: directory)
        precondition(reopened.load([PhotoEvent].self, kind: "events", id: "test")?.count == 1)
        store.save(["event:a": "本机事件"], kind: "settings", id: "eventNames")
        precondition(reopened.load([String: String].self, kind: "settings", id: "eventNames")?["event:a"] == "本机事件")
        let epoch = store.currentGeneration
        try store.clearAll()
        precondition(reopened.read(kind: "events", id: "test") == nil)
        precondition(reopened.read(kind: "settings", id: "eventNames") == nil)
        store.save(grouped, kind: "events", id: "late", expectedGeneration: epoch)
        precondition(store.read(kind: "events", id: "late") == nil)
        store.save(grouped, kind: "events", id: "new", expectedGeneration: store.currentGeneration)
        precondition(store.read(kind: "events", id: "new") != nil)
        let playback = LivePhotoPlayback()
        playback.press(photos[0], translation: .zero)
        precondition(playback.playingID == nil)
        playback.stop()
        print("Workflow checks passed: events, browsing, static click, privacy migration, OCR non-persistence, cache reset, denied-access reset, SQLite clearing and stale-write rejection")
    }
}
