import Foundation
import SQLite3

/// The index contains only derived local data; PhotoKit assets are never mutated.
final class PhotoIndexStore: @unchecked Sendable {
    static let shared = PhotoIndexStore()
    let directory: URL
    private var database: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NebulaPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        if sqlite3_open(self.directory.appendingPathComponent("photo-index.sqlite").path, &database) == SQLITE_OK {
            sqlite3_exec(database, "PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS records(kind TEXT,id TEXT,stamp TEXT,version TEXT,payload BLOB,PRIMARY KEY(kind,id));", nil, nil, nil)
        }
    }

    deinit { sqlite3_close(database) }

    func read(kind: String, id: String, stamp: String? = nil, version: String? = nil) -> Data? {
        lock.lock(); defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT stamp,version,payload FROM records WHERE kind=? AND id=?", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, kind, -1, transient)
        sqlite3_bind_text(statement, 2, id, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        if let stamp, String(cString: sqlite3_column_text(statement, 0)) != stamp { return nil }
        if let version, String(cString: sqlite3_column_text(statement, 1)) != version { return nil }
        let length = Int(sqlite3_column_bytes(statement, 2))
        guard let bytes = sqlite3_column_blob(statement, 2) else { return length == 0 ? Data() : nil }
        return Data(bytes: bytes, count: length)
    }

    func write(kind: String, id: String, stamp: String = "", version: String = "1", data: Data) {
        lock.lock(); defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO records VALUES(?,?,?,?,?)", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, kind, -1, transient)
        sqlite3_bind_text(statement, 2, id, -1, transient)
        sqlite3_bind_text(statement, 3, stamp, -1, transient)
        sqlite3_bind_text(statement, 4, version, -1, transient)
        data.withUnsafeBytes { bytes in
            _ = sqlite3_bind_blob(statement, 5, bytes.baseAddress, Int32(data.count), transient)
        }
        _ = sqlite3_step(statement)
    }

    func save<T: Encodable>(_ value: T, kind: String, id: String, stamp: String = "", version: String = "1") {
        guard let data = try? JSONEncoder().encode(value) else { return }
        write(kind: kind, id: id, stamp: stamp, version: version, data: data)
    }

    func transaction(_ operation: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil)
        operation()
        sqlite3_exec(database, "COMMIT", nil, nil, nil)
    }

    func load<T: Decodable>(_ type: T.Type, kind: String, id: String, stamp: String? = nil, version: String? = nil) -> T? {
        guard let data = read(kind: kind, id: id, stamp: stamp, version: version) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
