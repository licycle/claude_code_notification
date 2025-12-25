import Foundation
import SQLite3

// SQLite destructor type for transient strings
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Session Stats Model

struct SessionStats {
    let totalCount: Int
    let completedCount: Int
    let workingCount: Int
    let idleCount: Int
    let waitingCount: Int
    let rawModeCount: Int
    let aiModeCount: Int
}

// MARK: - Database Manager Reports Extension

extension DatabaseManager {

    // MARK: - Get All Sessions (including completed)

    func getAllSessions(limit: Int = 100) -> [SessionInfo] {
        guard openDatabase() else { return [] }
        defer { closeDatabase() }

        var sessions: [SessionInfo] = []
        let query = """
            SELECT id, COALESCE(session_id, 'pending_' || pending_id) as display_id,
                   project, original_goal, current_status, last_activity, created_at,
                   account_alias, bundle_id, terminal_pid, shell_pid, window_id
            FROM sessions
            ORDER BY last_activity DESC
            LIMIT ?
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(limit))

            while sqlite3_step(statement) == SQLITE_ROW {
                if let session = parseSessionRow(statement) {
                    sessions.append(session)
                }
            }
        }
        sqlite3_finalize(statement)
        return sessions
    }

    // MARK: - Get Sessions by Status

    func getSessionsByStatus(_ status: String, limit: Int = 100) -> [SessionInfo] {
        guard openDatabase() else { return [] }
        defer { closeDatabase() }

        var sessions: [SessionInfo] = []
        let query = """
            SELECT id, COALESCE(session_id, 'pending_' || pending_id) as display_id,
                   project, original_goal, current_status, last_activity, created_at,
                   account_alias, bundle_id, terminal_pid, shell_pid, window_id
            FROM sessions
            WHERE current_status = ?
            ORDER BY last_activity DESC
            LIMIT ?
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, status, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 2, Int32(limit))

            while sqlite3_step(statement) == SQLITE_ROW {
                if let session = parseSessionRow(statement) {
                    sessions.append(session)
                }
            }
        }
        sqlite3_finalize(statement)
        return sessions
    }

    // MARK: - Get Sessions by Date Range

    func getSessionsByDateRange(startDate: Date, endDate: Date) -> [SessionInfo] {
        guard openDatabase() else { return [] }
        defer { closeDatabase() }

        var sessions: [SessionInfo] = []
        let startStr = dateFormatter.string(from: startDate)
        let endStr = dateFormatter.string(from: endDate)

        let query = """
            SELECT id, COALESCE(session_id, 'pending_' || pending_id) as display_id,
                   project, original_goal, current_status, last_activity, created_at,
                   account_alias, bundle_id, terminal_pid, shell_pid, window_id
            FROM sessions
            WHERE created_at >= ? AND created_at <= ?
            ORDER BY last_activity DESC
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, startStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, endStr, -1, SQLITE_TRANSIENT)

            while sqlite3_step(statement) == SQLITE_ROW {
                if let session = parseSessionRow(statement) {
                    sessions.append(session)
                }
            }
        }
        sqlite3_finalize(statement)
        return sessions
    }

    // MARK: - Search Sessions

    func searchSessions(keyword: String, limit: Int = 100) -> [SessionInfo] {
        guard openDatabase() else { return [] }
        defer { closeDatabase() }

        var sessions: [SessionInfo] = []
        let searchPattern = "%\(keyword)%"

        let query = """
            SELECT id, COALESCE(session_id, 'pending_' || pending_id) as display_id,
                   project, original_goal, current_status, last_activity, created_at,
                   account_alias, bundle_id, terminal_pid, shell_pid, window_id
            FROM sessions
            WHERE session_id LIKE ? OR original_goal LIKE ? OR project LIKE ?
            ORDER BY last_activity DESC
            LIMIT ?
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, searchPattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, searchPattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, searchPattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 4, Int32(limit))

            while sqlite3_step(statement) == SQLITE_ROW {
                if let session = parseSessionRow(statement) {
                    sessions.append(session)
                }
            }
        }
        sqlite3_finalize(statement)
        return sessions
    }

    // MARK: - Get Session Stats

    func getSessionStats(startDate: Date? = nil, endDate: Date? = nil) -> SessionStats {
        guard openDatabase() else {
            return SessionStats(totalCount: 0, completedCount: 0, workingCount: 0,
                              idleCount: 0, waitingCount: 0, rawModeCount: 0, aiModeCount: 0)
        }
        defer { closeDatabase() }

        var whereClause = ""
        if let start = startDate, let end = endDate {
            let startStr = dateFormatter.string(from: start)
            let endStr = dateFormatter.string(from: end)
            whereClause = "WHERE created_at >= '\(startStr)' AND created_at <= '\(endStr)'"
        }

        // Count by status
        let statusQuery = """
            SELECT current_status, COUNT(*) as cnt
            FROM sessions
            \(whereClause)
            GROUP BY current_status
            """

        var totalCount = 0
        var completedCount = 0
        var workingCount = 0
        var idleCount = 0
        var waitingCount = 0

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, statusQuery, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let status = safeString(from: sqlite3_column_text(statement, 0))
                let count = Int(sqlite3_column_int(statement, 1))
                totalCount += count

                switch status {
                case "completed":
                    completedCount = count
                case "working", "executing_tool", "subagent_working":
                    workingCount += count
                case "idle":
                    idleCount = count
                case "waiting_for_user", "waiting_permission":
                    waitingCount += count
                default:
                    break
                }
            }
        }
        sqlite3_finalize(statement)

        // Count by mode (from snapshots)
        let modeQuery = """
            SELECT
                SUM(CASE WHEN summary_json LIKE '%"mode": "ai"%' OR summary_json LIKE '%"mode":"ai"%' THEN 1 ELSE 0 END) as ai_count,
                SUM(CASE WHEN summary_json NOT LIKE '%"mode": "ai"%' AND summary_json NOT LIKE '%"mode":"ai"%' THEN 1 ELSE 0 END) as raw_count
            FROM (
                SELECT DISTINCT session_pk, summary_json
                FROM snapshots
                WHERE summary_json IS NOT NULL
            )
            """

        var rawModeCount = 0
        var aiModeCount = 0

        if sqlite3_prepare_v2(db, modeQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                aiModeCount = Int(sqlite3_column_int(statement, 0))
                rawModeCount = Int(sqlite3_column_int(statement, 1))
            }
        }
        sqlite3_finalize(statement)

        return SessionStats(
            totalCount: totalCount,
            completedCount: completedCount,
            workingCount: workingCount,
            idleCount: idleCount,
            waitingCount: waitingCount,
            rawModeCount: rawModeCount,
            aiModeCount: aiModeCount
        )
    }

    // MARK: - Get Today's Sessions

    func getTodaySessions() -> [SessionInfo] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
        return getSessionsByDateRange(startDate: startOfDay, endDate: endOfDay)
    }

    // MARK: - Update Session Status

    func updateSessionStatus(sessionId: String, newStatus: String) -> Bool {
        guard openDatabase() else { return false }
        defer { closeDatabase() }

        let query = """
            UPDATE sessions
            SET current_status = ?, last_activity = ?
            WHERE session_id = ? OR pending_id = ?
            """

        let now = dateFormatter.string(from: Date())
        let cleanId = sessionId.hasPrefix("pending_") ? String(sessionId.dropFirst(8)) : sessionId

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, newStatus, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, now, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, cleanId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, cleanId, -1, SQLITE_TRANSIENT)

            let result = sqlite3_step(statement)
            sqlite3_finalize(statement)
            return result == SQLITE_DONE
        }
        return false
    }

    // MARK: - Delete Session

    func deleteSession(sessionId: String) -> Bool {
        guard openDatabase() else { return false }
        defer { closeDatabase() }

        let cleanId = sessionId.hasPrefix("pending_") ? String(sessionId.dropFirst(8)) : sessionId

        let query = """
            DELETE FROM sessions
            WHERE session_id = ? OR pending_id = ?
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, cleanId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, cleanId, -1, SQLITE_TRANSIENT)

            let result = sqlite3_step(statement)
            sqlite3_finalize(statement)
            return result == SQLITE_DONE
        }
        return false
    }

    // MARK: - Get Unique Accounts

    func getUniqueAccounts() -> [String] {
        guard openDatabase() else { return [] }
        defer { closeDatabase() }

        var accounts: [String] = []
        let query = "SELECT DISTINCT account_alias FROM sessions WHERE account_alias IS NOT NULL ORDER BY account_alias"

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let account = safeString(from: sqlite3_column_text(statement, 0))
                if !account.isEmpty {
                    accounts.append(account)
                }
            }
        }
        sqlite3_finalize(statement)
        return accounts
    }

    // MARK: - Helper: Parse Session Row

    private func parseSessionRow(_ statement: OpaquePointer?) -> SessionInfo? {
        guard let stmt = statement else { return nil }

        let pk = Int(sqlite3_column_int(stmt, 0))
        let sessionId = safeString(from: sqlite3_column_text(stmt, 1))
        let project = safeString(from: sqlite3_column_text(stmt, 2))
        let originalGoal = safeString(from: sqlite3_column_text(stmt, 3))
        let currentStatus = safeString(from: sqlite3_column_text(stmt, 4))

        let lastActivityStr = safeString(from: sqlite3_column_text(stmt, 5))
        let createdAtStr = safeString(from: sqlite3_column_text(stmt, 6))

        let lastActivity = dateFormatter.date(from: String(lastActivityStr.prefix(19))) ?? Date()
        let createdAt = dateFormatter.date(from: String(createdAtStr.prefix(19))) ?? Date()

        let accountAlias = safeString(from: sqlite3_column_text(stmt, 7))
        let bundleId = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
        let terminalPid = sqlite3_column_type(stmt, 9) != SQLITE_NULL ? Int32(sqlite3_column_int(stmt, 9)) : nil
        let shellPid = sqlite3_column_type(stmt, 10) != SQLITE_NULL ? Int32(sqlite3_column_int(stmt, 10)) : nil
        let windowId = sqlite3_column_type(stmt, 11) != SQLITE_NULL ? UInt32(sqlite3_column_int(stmt, 11)) : nil

        return SessionInfo(
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
            pk: pk,
            summaryMode: nil
        )
    }
}
