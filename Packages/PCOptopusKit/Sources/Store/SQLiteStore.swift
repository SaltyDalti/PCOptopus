import Foundation
import Model
import SQLite3

public enum StoreError: Error, Sendable {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case notFound
}

/// Thin SQLite wrapper for samples, findings, contract, journal, and settings.
public final class SQLiteStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let path: URL

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.path = directory.appendingPathComponent("pcoctopus.sqlite")
        var handle: OpaquePointer?
        if sqlite3_open(path.path, &handle) != SQLITE_OK {
            throw StoreError.openFailed(String(cString: sqlite3_errmsg(handle)))
        }
        db = handle
        try migrate()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public var databasePath: URL { path }

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS samples (
            id TEXT PRIMARY KEY,
            domain TEXT NOT NULL,
            timestamp REAL NOT NULL,
            metrics_json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_samples_time ON samples(timestamp);
        CREATE INDEX IF NOT EXISTS idx_samples_domain ON samples(domain, timestamp);
        CREATE TABLE IF NOT EXISTS findings (
            id TEXT PRIMARY KEY,
            payload_json TEXT NOT NULL,
            last_seen REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS journal (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            payload_json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_journal_time ON journal(timestamp);
        CREATE TABLE IF NOT EXISTS kv (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)
        try exec("INSERT OR IGNORE INTO meta(key, value) VALUES('schema_version', '1');")
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw StoreError.execFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard let stmt else { throw StoreError.prepareFailed("nil statement") }
        return stmt
    }

    // MARK: - Samples

    public func insertSample(_ sample: Sample) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(sample.metrics)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let stmt = try prepare("INSERT OR REPLACE INTO samples(id, domain, timestamp, metrics_json) VALUES(?,?,?,?);")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sample.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sample.domain.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, sample.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 4, json, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func samples(since: Date, domain: Domain? = nil, limit: Int = 500) throws -> [Sample] {
        let sql: String
        if domain != nil {
            sql = "SELECT id, domain, timestamp, metrics_json FROM samples WHERE timestamp >= ? AND domain = ? ORDER BY timestamp DESC LIMIT ?;"
        } else {
            sql = "SELECT id, domain, timestamp, metrics_json FROM samples WHERE timestamp >= ? ORDER BY timestamp DESC LIMIT ?;"
        }
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, since.timeIntervalSince1970)
        if let domain {
            sqlite3_bind_text(stmt, 2, domain.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(limit))
        } else {
            sqlite3_bind_int(stmt, 2, Int32(limit))
        }
        var results: [Sample] = []
        let decoder = JSONDecoder()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) ?? UUID()
            let domainRaw = String(cString: sqlite3_column_text(stmt, 1))
            let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
            let json = String(cString: sqlite3_column_text(stmt, 3))
            let metrics = (try? decoder.decode([String: String].self, from: Data(json.utf8))) ?? [:]
            let domain = Domain(rawValue: domainRaw) ?? .compute
            results.append(Sample(id: id, domain: domain, timestamp: ts, metrics: metrics))
        }
        return results
    }

    public func pruneSamples(olderThan date: Date) throws {
        let stmt = try prepare("DELETE FROM samples WHERE timestamp < ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
        _ = sqlite3_step(stmt)
    }

    // MARK: - Findings

    public func upsertFinding(_ finding: Finding) throws {
        let data = try JSONEncoder().encode(finding)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let stmt = try prepare("INSERT OR REPLACE INTO findings(id, payload_json, last_seen) VALUES(?,?,?);")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, finding.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, json, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, finding.lastSeen.timeIntervalSince1970)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func allFindings() throws -> [Finding] {
        let stmt = try prepare("SELECT payload_json FROM findings ORDER BY last_seen DESC;")
        defer { sqlite3_finalize(stmt) }
        var results: [Finding] = []
        let decoder = JSONDecoder()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let json = String(cString: sqlite3_column_text(stmt, 0))
            if let finding = try? decoder.decode(Finding.self, from: Data(json.utf8)) {
                results.append(finding)
            }
        }
        return results
    }

    public func clearFindingsNotIn(_ ids: Set<String>) throws {
        let existing = try allFindings()
        for finding in existing where !ids.contains(finding.id) {
            let stmt = try prepare("DELETE FROM findings WHERE id = ?;")
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, finding.id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
    }

    // MARK: - Journal

    public func insertJournal(_ entry: JournalEntry) throws {
        let data = try JSONEncoder().encode(entry)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let stmt = try prepare("INSERT OR REPLACE INTO journal(id, timestamp, payload_json) VALUES(?,?,?);")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, entry.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, json, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func updateJournal(_ entry: JournalEntry) throws {
        try insertJournal(entry)
    }

    public func journalEntries(limit: Int = 200) throws -> [JournalEntry] {
        let stmt = try prepare("SELECT payload_json FROM journal ORDER BY timestamp DESC LIMIT ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        var results: [JournalEntry] = []
        let decoder = JSONDecoder()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let json = String(cString: sqlite3_column_text(stmt, 0))
            if let entry = try? decoder.decode(JournalEntry.self, from: Data(json.utf8)) {
                results.append(entry)
            }
        }
        return results
    }

    public func journalEntry(id: UUID) throws -> JournalEntry {
        let stmt = try prepare("SELECT payload_json FROM journal WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_ROW {
            let json = String(cString: sqlite3_column_text(stmt, 0))
            if let entry = try? JSONDecoder().decode(JournalEntry.self, from: Data(json.utf8)) {
                return entry
            }
        }
        throw StoreError.notFound
    }

    // MARK: - KV (contract, settings, practices)

    public func setJSON<T: Encodable>(_ key: String, value: T) throws {
        let data = try JSONEncoder().encode(value)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let stmt = try prepare("INSERT OR REPLACE INTO kv(key, value) VALUES(?,?);")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, json, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw StoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func getJSON<T: Decodable>(_ key: String, as type: T.Type) throws -> T? {
        let stmt = try prepare("SELECT value FROM kv WHERE key = ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_ROW {
            let json = String(cString: sqlite3_column_text(stmt, 0))
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        }
        return nil
    }

    public func loadContract() throws -> Contract {
        try getJSON("contract", as: Contract.self) ?? .emptyDefault()
    }

    public func saveContract(_ contract: Contract) throws {
        try setJSON("contract", value: contract)
    }

    public func loadSettings() throws -> AppSettings {
        try getJSON("settings", as: AppSettings.self) ?? AppSettings()
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try setJSON("settings", value: settings)
    }

    public func loadPractices() throws -> [Practice] {
        try getJSON("practices", as: [Practice].self) ?? Practice.catalog
    }

    public func savePractices(_ practices: [Practice]) throws {
        try setJSON("practices", value: practices)
    }
}

/// SQLite requires a transient destructor pointer for binding Swift strings.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
