import Foundation

enum AnalysisPrivacy {
    static let themesKey = "NebulaPhotos.StoredThemes.v4"
    static let manualKey = "NebulaPhotos.ManualThemes.v2"
    static let legacyKeys = ["NebulaPhotos.StoredThemes.v2", "NebulaPhotos.StoredThemes.v3"]

    /// Only theme and confidence may leave memory. Legacy OCR cannot be safely
    /// distinguished from arbitrary labels, so no labels are migrated at all.
    static func sanitized(_ records: [String: [String: Any]]) -> [String: [String: Any]] {
        records.reduce(into: [:]) { result, entry in
            guard let theme = entry.value["theme"] as? String else { return }
            result[entry.key] = ["theme": theme, "confidence": entry.value["confidence"] as? NSNumber ?? NSNumber(value: 0)]
        }
    }

    static func migrate(_ defaults: UserDefaults) -> [String: [String: Any]] {
        let source = defaults.dictionary(forKey: themesKey) as? [String: [String: Any]]
            ?? defaults.dictionary(forKey: legacyKeys[1]) as? [String: [String: Any]] ?? [:]
        var records = sanitized(source)
        let legacy = defaults.dictionary(forKey: legacyKeys[0]) as? [String: String] ?? [:]
        for id in defaults.stringArray(forKey: manualKey) ?? [] where records[id] == nil {
            if let theme = legacy[id] { records[id] = ["theme": theme, "confidence": NSNumber(value: 1)] }
        }
        // Commit the safe replacement before retiring legacy sensitive records.
        defaults.set(records, forKey: themesKey)
        for key in legacyKeys { defaults.removeObject(forKey: key) }
        return records
    }

    static func clear(_ defaults: UserDefaults) {
        for key in legacyKeys + [themesKey, manualKey] { defaults.removeObject(forKey: key) }
    }
}
