import AppKit
import Photos
import Foundation

@main
struct PhotoWorkflowChecks {
    @MainActor static func main() async throws {
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
        let browsing = BrowsingState(); browsing.focus(photos[1])
        precondition(browsing.index(in: photos) == 1)
        precondition(browsing.index(in: photos.reversed()) == 1)
        browsing.reconcile([photos[0], photos[2]])
        precondition(browsing.focusedID == "a" || browsing.focusedID == "c")
        browsing.focus(photos[0]); browsing.reconcile([photos[2]])
        precondition(browsing.focusedID == "c" && browsing.index(in: []) == 0)
        browsing.nebulaZoom = 1.5; browsing.orbitZoom = 0.8; browsing.gridWidth = 190
        browsing.focus(photos[1])
        precondition(browsing.nebulaZoom == 1.5 && browsing.orbitZoom == 0.8 && browsing.gridWidth == 190)

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
        let playback = LivePhotoPlayback()
        playback.press(photos[0], translation: .zero)
        precondition(playback.playingID == nil && !playback.consumeLongPress("a"))
        playback.stop()
        print("Workflow checks passed: event boundaries, missing date/location, focused ID, nearest filter result, independent zoom, SQLite persistence, static click safety")
    }
}
