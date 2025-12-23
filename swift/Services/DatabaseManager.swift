import Foundation
import SQLite3

// MARK: - Database Manager

class DatabaseManager {
    static let shared = DatabaseManager()

    private let dbPath: String
    var db: OpaquePointer?

    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        dbPath = "\(homeDir)/.claude-task-tracker/tasks.db"
    }

    // MARK: - Connection Management

    func openDatabase() -> Bool {
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            return true
        } else {
            log("DATABASE: Failed to open database at \(dbPath)")
            return false
        }
    }

    func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    // MARK: - Query Methods

    func getActiveSessions() -> [SessionInfo] {
        log("DATABASE: getActiveSessions() called")
        guard openDatabase() else {
            log("DATABASE: Failed to open database")
            return []
        }
        defer { closeDatabase() }

        var sessions: [SessionInfo] = []
        // New schema: session_id can be NULL for pending sessions
        // Use COALESCE to create display ID: real session_id or 'pending_' + pending_id
        let query = """
            SELECT id, COALESCE(session_id, 'pending_' || pending_id) as display_id,
                   project, original_goal, current_status, last_activity, created_at,
                   account_alias, bundle_id, terminal_pid, shell_pid, window_id
            FROM sessions
            WHERE current_status != 'completed'
            ORDER BY last_activity DESC
            LIMIT 20
            """

        log("DATABASE: Executing query for active sessions")
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let pk = Int(sqlite3_column_int(statement, 0))
                let sessionId = safeString(from: sqlite3_column_text(statement, 1))
                let project = safeString(from: sqlite3_column_text(statement, 2))
                let originalGoal = safeString(from: sqlite3_column_text(statement, 3))
                let currentStatus = safeString(from: sqlite3_column_text(statement, 4))

                let lastActivityStr = safeString(from: sqlite3_column_text(statement, 5))
                let createdAtStr = safeString(from: sqlite3_column_text(statement, 6))

                let lastActivity = dateFormatter.date(from: String(lastActivityStr.prefix(19))) ?? Date()
                let createdAt = dateFormatter.date(from: String(createdAtStr.prefix(19))) ?? Date()

                // Window info for terminal jumping
                let accountAlias = safeString(from: sqlite3_column_text(statement, 7))
                let bundleId = sqlite3_column_text(statement, 8).map { String(cString: $0) }
                let terminalPid = sqlite3_column_type(statement, 9) != SQLITE_NULL ? Int32(sqlite3_column_int(statement, 9)) : nil
                let shellPid = sqlite3_column_type(statement, 10) != SQLITE_NULL ? Int32(sqlite3_column_int(statement, 10)) : nil
                let windowId = sqlite3_column_type(statement, 11) != SQLITE_NULL ? UInt32(sqlite3_column_int(statement, 11)) : nil

                log("DATABASE: Found session id=\(sessionId.prefix(8)) status=\(currentStatus) goal=\(originalGoal.prefix(30))")
                sessions.append(SessionInfo(
                    sessionId: sessionId,
                    project: project,
                    originalGoal: originalGoal,
                    currentStatus: currentStatus,
                    lastActivity: lastActivity,
                    createdAt: createdAt,
                    accountAlias: accountAlias.isEmpty ? "default" : accountAlias,
                    bundleId: bundleId,
                    terminalPid: terminalPid,
                    shellPid: shellPid,
                    windowId: windowId,
                    pk: pk
                ))
            }
        }
        sqlite3_finalize(statement)

        log("DATABASE: getActiveSessions() returning \(sessions.count) sessions")
        return sessions
    }

    func getAllSessions(includeCompleted: Bool = false) -> [SessionInfo] {
        guard openDatabase() else { return [] }
        defer { closeDatabase() }

        var sessions: [SessionInfo] = []
        var query = """
            SELECT id, COALESCE(session_id, 'pending_' || pending_id) as display_id,
                   project, original_goal, current_status, last_activity, created_at,
                   account_alias, bundle_id, terminal_pid, shell_pid, window_id
            FROM sessions
            """
        if !includeCompleted {
            query += " WHERE current_status != 'completed'"
        }
        query += " ORDER BY last_activity DESC LIMIT 50"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let pk = Int(sqlite3_column_int(statement, 0))
                let sessionId = safeString(from: sqlite3_column_text(statement, 1))
                let project = safeString(from: sqlite3_column_text(statement, 2))
                let originalGoal = safeString(from: sqlite3_column_text(statement, 3))
                let currentStatus = safeString(from: sqlite3_column_text(statement, 4))

                let lastActivityStr = safeString(from: sqlite3_column_text(statement, 5))
                let createdAtStr = safeString(from: sqlite3_column_text(statement, 6))

                let lastActivity = dateFormatter.date(from: String(lastActivityStr.prefix(19))) ?? Date()
                let createdAt = dateFormatter.date(from: String(createdAtStr.prefix(19))) ?? Date()

                // Window info for terminal jumping
                let accountAlias = safeString(from: sqlite3_column_text(statement, 7))
                let bundleId = sqlite3_column_text(statement, 8).map { String(cString: $0) }
                let terminalPid = sqlite3_column_type(statement, 9) != SQLITE_NULL ? Int32(sqlite3_column_int(statement, 9)) : nil
                let shellPid = sqlite3_column_type(statement, 10) != SQLITE_NULL ? Int32(sqlite3_column_int(statement, 10)) : nil
                let windowId = sqlite3_column_type(statement, 11) != SQLITE_NULL ? UInt32(sqlite3_column_int(statement, 11)) : nil

                sessions.append(SessionInfo(
                    sessionId: sessionId,
                    project: project,
                    originalGoal: originalGoal,
                    currentStatus: currentStatus,
                    lastActivity: lastActivity,
                    createdAt: createdAt,
                    accountAlias: accountAlias.isEmpty ? "default" : accountAlias,
                    bundleId: bundleId,
                    terminalPid: terminalPid,
                    shellPid: shellPid,
                    windowId: windowId,
                    pk: pk
                ))
            }
        }
        sqlite3_finalize(statement)

        return sessions
    }

    func getProgress(sessionId: String) -> ProgressInfo? {
        guard openDatabase() else { return nil }
        defer { closeDatabase() }

        // New schema: progress uses session_pk, need to join with sessions
        // Handle both real session_id and pending_xxx format
        let query: String
        let bindValue: String

        if sessionId.hasPrefix("pending_") {
            // Pending session - lookup by pending_id
            let pendingId = String(sessionId.dropFirst(8))
            query = """
                SELECT p.todos_json, p.completed_count, p.total_count
                FROM progress p
                JOIN sessions s ON p.session_pk = s.id
                WHERE s.pending_id = ?
                """
            bindValue = pendingId
        } else {
            // Real session - lookup by session_id
            query = """
                SELECT p.todos_json, p.completed_count, p.total_count
                FROM progress p
                JOIN sessions s ON p.session_pk = s.id
                WHERE s.session_id = ?
                """
            bindValue = sessionId
        }

        var statement: OpaquePointer?
        var result: ProgressInfo?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, bindValue, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW {
                let completed = Int(sqlite3_column_int(statement, 1))
                let total = Int(sqlite3_column_int(statement, 2))

                var todos: [TodoItem] = []
                if let todosJsonPtr = sqlite3_column_text(statement, 0) {
                    let todosJson = String(cString: todosJsonPtr)
                    todos = parseTodosJson(todosJson)
                }

                result = ProgressInfo(completed: completed, total: total, todos: todos)
            }
        }
        sqlite3_finalize(statement)

        return result
    }

    func getPendingQuestion(sessionId: String) -> String? {
        guard openDatabase() else { return nil }
        defer { closeDatabase() }

        // New schema: pending_decisions uses session_pk
        let query: String
        let bindValue: String

        if sessionId.hasPrefix("pending_") {
            let pendingId = String(sessionId.dropFirst(8))
            query = """
                SELECT pd.question
                FROM pending_decisions pd
                JOIN sessions s ON pd.session_pk = s.id
                WHERE s.pending_id = ? AND pd.resolved = 0
                ORDER BY pd.created_at DESC
                LIMIT 1
                """
            bindValue = pendingId
        } else {
            query = """
                SELECT pd.question
                FROM pending_decisions pd
                JOIN sessions s ON pd.session_pk = s.id
                WHERE s.session_id = ? AND pd.resolved = 0
                ORDER BY pd.created_at DESC
                LIMIT 1
                """
            bindValue = sessionId
        }

        var statement: OpaquePointer?
        var result: String?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, bindValue, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW {
                if let questionPtr = sqlite3_column_text(statement, 0) {
                    result = String(cString: questionPtr)
                }
            }
        }
        sqlite3_finalize(statement)

        return result
    }

    // MARK: - Helper Methods

    func safeString(from pointer: UnsafePointer<UInt8>?) -> String {
        guard let pointer = pointer else { return "" }
        return String(cString: pointer)
    }

    func parseTodosJson(_ json: String) -> [TodoItem] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { dict in
            guard let content = dict["content"] as? String,
                  let status = dict["status"] as? String else {
                return nil
            }
            let activeForm = dict["activeForm"] as? String ?? content
            return TodoItem(content: content, status: status, activeForm: activeForm)
        }
    }

    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Relative Time

    func relativeTime(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)分钟前"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)小时前"
        } else {
            let days = Int(interval / 86400)
            return "\(days)天前"
        }
    }
}
