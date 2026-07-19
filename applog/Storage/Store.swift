import Foundation
import SQLite3

private nonisolated let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Owns the single SQLite connection. All reads/writes go through this actor,
/// so `TrackingEngine` (writing every sample) and the UI (reading for display)
/// never race on the same handle.
actor Store {
    private var db: OpaquePointer?
    nonisolated let databaseURL: URL

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &handle) == SQLITE_OK else {
            throw StoreError.openFailed
        }
        self.db = handle
        try Self.exec(handle, "PRAGMA journal_mode=WAL;")
        try Self.exec(handle, "PRAGMA foreign_keys=ON;")
        try Self.createTables(handle)
    }

    deinit {
        sqlite3_close(db)
    }

    enum StoreError: Error { case openFailed, sqlError(String) }

    // MARK: - Schema

    private static func createTables(_ db: OpaquePointer?) throws {
        try exec(db, """
        CREATE TABLE IF NOT EXISTS node (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parent_id INTEGER REFERENCES node(id),
            kind TEXT NOT NULL,
            name TEXT NOT NULL,
            bundle_id TEXT,
            tag_id INTEGER REFERENCES tag(id),
            hidden INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            UNIQUE(parent_id, kind, name)
        );
        """)
        try exec(db, """
        CREATE TABLE IF NOT EXISTS usage_bucket (
            node_id INTEGER NOT NULL REFERENCES node(id),
            day TEXT NOT NULL,
            active_seconds INTEGER NOT NULL DEFAULT 0,
            semi_idle_seconds INTEGER NOT NULL DEFAULT 0,
            key_clicks INTEGER NOT NULL DEFAULT 0,
            mouse_clicks INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (node_id, day)
        );
        """)
        try exec(db, """
        CREATE TABLE IF NOT EXISTS session (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            node_id INTEGER NOT NULL REFERENCES node(id),
            started_at TEXT NOT NULL,
            ended_at TEXT NOT NULL
        );
        """)
        try exec(db, """
        CREATE TABLE IF NOT EXISTS tag (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            color TEXT NOT NULL
        );
        """)
        try exec(db, """
        CREATE TABLE IF NOT EXISTS setting (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)
        try exec(db, """
        CREATE TABLE IF NOT EXISTS exclusion (
            kind TEXT NOT NULL,
            value TEXT NOT NULL,
            PRIMARY KEY (kind, value)
        );
        """)
    }

    private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw StoreError.sqlError(msg)
        }
    }

    /// Prepares `sql` against the connection, surfacing sqlite's own error
    /// message on failure instead of silently handing back a null statement
    /// for the caller's `sqlite3_step` to fail on with no diagnostic.
    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }

    // MARK: - Node graph

    /// Finds or creates the node for one level of a hierarchy chain (e.g. the
    /// "github.com" domain node under the "Safari" app node).
    @discardableResult
    func findOrCreateNode(parentID: Int64?, kind: NodeKind, name: String, bundleID: String? = nil) throws -> Int64 {
        let selectSQL: String
        if parentID == nil {
            selectSQL = "SELECT id FROM node WHERE parent_id IS NULL AND kind = ? AND name = ?;"
        } else {
            selectSQL = "SELECT id FROM node WHERE parent_id = ? AND kind = ? AND name = ?;"
        }
        let stmt = try prepare(selectSQL)
        defer { sqlite3_finalize(stmt) }
        var bindIndex: Int32 = 1
        if let parentID {
            sqlite3_bind_int64(stmt, bindIndex, parentID); bindIndex += 1
        }
        sqlite3_bind_text(stmt, bindIndex, kind.rawValue, -1, SQLITE_TRANSIENT); bindIndex += 1
        sqlite3_bind_text(stmt, bindIndex, name, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }

        let insert = try prepare("""
            INSERT INTO node (parent_id, kind, name, bundle_id, created_at)
            VALUES (?, ?, ?, ?, ?);
        """)
        defer { sqlite3_finalize(insert) }
        if let parentID {
            sqlite3_bind_int64(insert, 1, parentID)
        } else {
            sqlite3_bind_null(insert, 1)
        }
        sqlite3_bind_text(insert, 2, kind.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(insert, 3, name, -1, SQLITE_TRANSIENT)
        if let bundleID {
            sqlite3_bind_text(insert, 4, bundleID, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(insert, 4)
        }
        sqlite3_bind_text(insert, 5, ISO8601DateFormatter().string(from: Date()), -1, SQLITE_TRANSIENT)
        guard sqlite3_step(insert) == SQLITE_DONE else {
            throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        return sqlite3_last_insert_rowid(db)
    }

    /// The "Away" node lives at the tree root and is created lazily the first
    /// time idle time needs somewhere to go (FR-7).
    func awayNodeID() throws -> Int64 {
        try findOrCreateNode(parentID: nil, kind: .away, name: "Away")
    }

    func allNodes() throws -> [Int64: Node] {
        let stmt = try prepare("SELECT id, parent_id, kind, name, bundle_id, tag_id, hidden, created_at FROM node;")
        defer { sqlite3_finalize(stmt) }
        var result: [Int64: Node] = [:]
        let iso = ISO8601DateFormatter()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let parentID: Int64? = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 1)
            let kind = NodeKind(rawValue: String(cString: sqlite3_column_text(stmt, 2))) ?? .app
            let name = String(cString: sqlite3_column_text(stmt, 3))
            let bundleID: String? = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 4))
            let tagID: Int64? = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 5)
            let hidden = sqlite3_column_int(stmt, 6) != 0
            let createdAt = iso.date(from: String(cString: sqlite3_column_text(stmt, 7))) ?? Date()
            result[id] = Node(id: id, parentID: parentID, kind: kind, name: name, bundleID: bundleID, tagID: tagID, hidden: hidden, createdAt: createdAt)
        }
        return result
    }

    // MARK: - Recording

    /// Adds one sample's worth of time to a node's bucket for `day`, and
    /// (for semi-idle bookkeeping / click counts) updates the same row.
    func addActiveSeconds(_ seconds: Int, isSemiIdle: Bool, keyClicks: Int, mouseClicks: Int, toNode nodeID: Int64, day: Date) throws {
        let dayString = Self.dayFormatter.string(from: day)
        let stmt = try prepare("""
            INSERT INTO usage_bucket (node_id, day, active_seconds, semi_idle_seconds, key_clicks, mouse_clicks)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(node_id, day) DO UPDATE SET
                active_seconds = active_seconds + excluded.active_seconds,
                semi_idle_seconds = semi_idle_seconds + excluded.semi_idle_seconds,
                key_clicks = key_clicks + excluded.key_clicks,
                mouse_clicks = mouse_clicks + excluded.mouse_clicks;
        """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, nodeID)
        sqlite3_bind_text(stmt, 2, dayString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, isSemiIdle ? 0 : Int64(seconds))
        sqlite3_bind_int64(stmt, 4, isSemiIdle ? Int64(seconds) : 0)
        sqlite3_bind_int64(stmt, 5, Int64(keyClicks))
        sqlite3_bind_int64(stmt, 6, Int64(mouseClicks))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }

    func recordSession(nodeID: Int64, startedAt: Date, endedAt: Date) throws {
        let stmt = try prepare("INSERT INTO session (node_id, started_at, ended_at) VALUES (?, ?, ?);")
        defer { sqlite3_finalize(stmt) }
        let iso = ISO8601DateFormatter()
        sqlite3_bind_int64(stmt, 1, nodeID)
        sqlite3_bind_text(stmt, 2, iso.string(from: startedAt), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, iso.string(from: endedAt), -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Sessions whose span overlaps the given day, used to draw the daily timeline panel.
    func sessions(onDay day: Date) throws -> [TrackedSession] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let iso = ISO8601DateFormatter()
        let stmt = try prepare("""
            SELECT node_id, started_at, ended_at FROM session
            WHERE started_at < ? AND ended_at > ?
            ORDER BY started_at ASC;
        """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, iso.string(from: end), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, iso.string(from: start), -1, SQLITE_TRANSIENT)
        var results: [TrackedSession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let nodeID = sqlite3_column_int64(stmt, 0)
            let startedAt = iso.date(from: String(cString: sqlite3_column_text(stmt, 1))) ?? start
            let endedAt = iso.date(from: String(cString: sqlite3_column_text(stmt, 2))) ?? start
            results.append(TrackedSession(nodeID: nodeID, startedAt: startedAt, endedAt: endedAt))
        }
        return results
    }

    /// Own (non-descendant-inclusive) active seconds per node, summed over a day range.
    func ownActiveSeconds(from: Date, to: Date) throws -> [Int64: Int] {
        let fromString = Self.dayFormatter.string(from: from)
        let toString = Self.dayFormatter.string(from: to)
        let stmt = try prepare("""
            SELECT node_id, SUM(active_seconds) FROM usage_bucket
            WHERE day BETWEEN ? AND ?
            GROUP BY node_id;
        """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, fromString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, toString, -1, SQLITE_TRANSIENT)
        var result: [Int64: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            result[sqlite3_column_int64(stmt, 0)] = Int(sqlite3_column_int64(stmt, 1))
        }
        return result
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    // MARK: - Tags

    func allTags() throws -> [Tag] {
        let stmt = try prepare("SELECT id, name, color FROM tag ORDER BY name;")
        defer { sqlite3_finalize(stmt) }
        var tags: [Tag] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            tags.append(Tag(
                id: sqlite3_column_int64(stmt, 0),
                name: String(cString: sqlite3_column_text(stmt, 1)),
                colorHex: String(cString: sqlite3_column_text(stmt, 2))
            ))
        }
        return tags
    }

    @discardableResult
    func createTag(name: String, colorHex: String) throws -> Int64 {
        let stmt = try prepare("INSERT INTO tag (name, color) VALUES (?, ?);")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, colorHex, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
        return sqlite3_last_insert_rowid(db)
    }

    func renameTag(id: Int64, to name: String) throws {
        let stmt = try prepare("UPDATE tag SET name = ? WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, id)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }

    func updateTagColor(id: Int64, to colorHex: String) throws {
        let stmt = try prepare("UPDATE tag SET color = ? WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, colorHex, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, id)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }

    func applyTag(_ tagID: Int64?, toNode nodeID: Int64) throws {
        let stmt = try prepare("UPDATE node SET tag_id = ? WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        if let tagID {
            sqlite3_bind_int64(stmt, 1, tagID)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_int64(stmt, 2, nodeID)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Settings (key/value, so they travel with the database — see design.md §6)

    func setting(_ key: String) throws -> String? {
        let stmt = try prepare("SELECT value FROM setting WHERE key = ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    func setSetting(_ key: String, _ value: String) throws {
        let stmt = try prepare("INSERT INTO setting (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Exclusions

    func exclusions(kind: ExclusionKind) throws -> [String] {
        let stmt = try prepare("SELECT value FROM exclusion WHERE kind = ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, kind.rawValue, -1, SQLITE_TRANSIENT)
        var values: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            values.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return values
    }

    func addExclusion(kind: ExclusionKind, value: String) throws {
        let stmt = try prepare("INSERT OR IGNORE INTO exclusion (kind, value) VALUES (?, ?);")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, kind.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }

    func removeExclusion(kind: ExclusionKind, value: String) throws {
        let stmt = try prepare("DELETE FROM exclusion WHERE kind = ? AND value = ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, kind.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.sqlError(String(cString: sqlite3_errmsg(db)))
        }
    }
}
