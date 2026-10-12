import Foundation
import CoreLocation
import CryptoKit
import SwiftUI

struct PhotoMetadata: Codable, Sendable {
    let id: String
    let date: Date?
    let modified: Date?
    let latitude: Double?
    let longitude: Double?
    var stamp: String { "\(modified?.timeIntervalSince1970 ?? 0):\(date?.timeIntervalSince1970 ?? 0):\(latitude ?? 0):\(longitude ?? 0)" }
    init(_ photo: MemoryPhoto) {
        id = photo.id; date = photo.createdAt; modified = photo.asset.modificationDate
        latitude = photo.asset.location?.coordinate.latitude
        longitude = photo.asset.location?.coordinate.longitude
    }
    init(id: String, date: Date?, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = id; self.date = date; modified = nil; self.latitude = latitude; self.longitude = longitude
    }
}

struct PhotoEvent: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let ids: [String]
}

enum EventBuilder {
    static func build(_ records: [PhotoMetadata], calendar: Calendar = .current) -> [PhotoEvent] {
        let dated = records.filter { $0.date != nil }.sorted { $0.date! == $1.date! ? $0.id < $1.id : $0.date! < $1.date! }
        var sessions: [[PhotoMetadata]] = []
        for record in dated {
            if let previous = sessions.last?.last, let date = record.date, let previousDate = previous.date {
                var farAway = false
                if let lat = record.latitude, let lon = record.longitude, let previousLat = previous.latitude, let previousLon = previous.longitude {
                    farAway = CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: previousLat, longitude: previousLon)) > 5_000
                }
                if calendar.isDate(date, inSameDayAs: previousDate) && date.timeIntervalSince(previousDate) <= 7_200 && !farAway {
                    sessions[sessions.count - 1].append(record); continue
                }
            }
            sessions.append([record])
        }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy年M月d日"
        var events = sessions.reversed().map { session in
            PhotoEvent(id: "event:\(session[0].id)", title: formatter.string(from: session[0].date!), ids: session.reversed().map(\.id))
        }
        let unknown = records.filter { $0.date == nil }.map(\.id)
        if !unknown.isEmpty { events.append(PhotoEvent(id: "event:undated", title: "日期未知", ids: unknown)) }
        return events
    }
}

@MainActor
final class PhotoOrganization: ObservableObject {
    @Published var events: [PhotoEvent] = []
    /// 只读暴露，供后台线程构建事件卡组时读取。
    private(set) var names: [String: String]
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let store = PhotoIndexStore.shared

    init() {
        names = PhotoIndexStore.shared.load([String: String].self, kind: "settings", id: "eventNames") ?? [:]
    }

    func load(_ photos: [MemoryPhoto]) {
        task?.cancel()
        let run = UUID(); generation = run
        let records = photos.map(PhotoMetadata.init)
        let store = store
        task = Task {
            let built = await Task.detached(priority: .utility) {
                let rawStamp = records.map { "\($0.id):\($0.stamp)" }.joined(separator: "|")
                let stamp = SHA256.hash(data: Data(rawStamp.utf8)).map { String(format: "%02x", $0) }.joined()
                if let cached = store.load([PhotoEvent].self, kind: "events", id: "library", stamp: stamp, version: "events-1") { return cached }
                let built = EventBuilder.build(records)
                store.save(built, kind: "events", id: "library", stamp: stamp, version: "events-1")
                return built
            }.value
            guard !Task.isCancelled, generation == run else { return }
            events = built
        }
    }

    func renameEvent(_ id: String, title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { names.removeValue(forKey: id) } else { names[id] = clean }
        store.save(names, kind: "settings", id: "eventNames")
        objectWillChange.send()
    }

    func eventStacks(_ photos: [MemoryPhoto]) -> [ThemePhotoStack] {
        ThemePhotoStack.eventStacks(events, names: names, photos: photos)
    }

    /// 供后台线程使用：不捕获 self，只传值。
    func eventStacksSnapshot() -> (events: [PhotoEvent], names: [String: String]) {
        (events, names)
    }
}
