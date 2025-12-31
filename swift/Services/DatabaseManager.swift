import Foundation
import SQLite3

// SQLite destructor type for transient strings
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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
                    pk: pk,
                    summaryMode: nil
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
                    pk: pk,
                    summaryMode: nil
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
            sqlite3_bind_text(statement, 1, bindValue, -1, SQLITE_TRANSIENT)

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
            sqlite3_bind_text(statement, 1, bindValue, -1, SQLITE_TRANSIENT)

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

    // MARK: - Summary Mode

    func getSummaryMode(sessionId: String) -> String? {
        guard openDatabase() else { return nil }
        defer { closeDatabase() }

        let query: String
        let bindValue: String

        if sessionId.hasPrefix("pending_") {
            let pendingId = String(sessionId.dropFirst(8))
            query = """
                SELECT snap.summary_json
                FROM snapshots snap
                JOIN sessions s ON snap.session_pk = s.id
                WHERE s.pending_id = ?
                ORDER BY snap.created_at DESC
                LIMIT 1
                """
            bindValue = pendingId
        } else {
            query = """
                SELECT snap.summary_json
                FROM snapshots snap
                JOIN sessions s ON snap.session_pk = s.id
                WHERE s.session_id = ?
                ORDER BY snap.created_at DESC
                LIMIT 1
                """
            bindValue = sessionId
        }

        var statement: OpaquePointer?
        var result: String?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, bindValue, -1, SQLITE_TRANSIENT)

            if sqlite3_step(statement) == SQLITE_ROW {
                if let jsonPtr = sqlite3_column_text(statement, 0) {
                    let jsonStr = String(cString: jsonPtr)
                    // Parse JSON to extract "mode" field
                    if let data = jsonStr.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let mode = dict["mode"] as? String {
                        result = mode
                    }
                }
            }
        }
        sqlite3_finalize(statement)

        return result
    }

    // MARK: - Prompt History

    func getPrompts(sessionId: String) -> [PromptRecord] {
        guard openDatabase() else { return [] }
        defer { closeDatabase() }

        let query: String
        let bindValue: String

        if sessionId.hasPrefix("pending_") {
            let pendingId = String(sessionId.dropFirst(8))
            query = """
                SELECT p.id, p.session_pk, p.round_number, p.content,
                       p.char_count, p.word_count, p.estimated_tokens, p.created_at
                FROM prompts p
                JOIN sessions s ON p.session_pk = s.id
                WHERE s.pending_id = ?
                ORDER BY p.round_number ASC
                """
            bindValue = pendingId
        } else {
            query = """
                SELECT p.id, p.session_pk, p.round_number, p.content,
                       p.char_count, p.word_count, p.estimated_tokens, p.created_at
                FROM prompts p
                JOIN sessions s ON p.session_pk = s.id
                WHERE s.session_id = ?
                ORDER BY p.round_number ASC
                """
            bindValue = sessionId
        }

        var prompts: [PromptRecord] = []
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, bindValue, -1, SQLITE_TRANSIENT)

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                let sessionPk = Int(sqlite3_column_int(statement, 1))
                let roundNumber = Int(sqlite3_column_int(statement, 2))
                let content = safeString(from: sqlite3_column_text(statement, 3))
                let charCount = Int(sqlite3_column_int(statement, 4))
                let wordCount = Int(sqlite3_column_int(statement, 5))
                let estimatedTokens = Int(sqlite3_column_int(statement, 6))
                let createdAtStr = safeString(from: sqlite3_column_text(statement, 7))
                let createdAt = dateFormatter.date(from: String(createdAtStr.prefix(19))) ?? Date()

                prompts.append(PromptRecord(
                    id: id,
                    sessionPk: sessionPk,
                    roundNumber: roundNumber,
                    content: content,
                    charCount: charCount,
                    wordCount: wordCount,
                    estimatedTokens: estimatedTokens,
                    createdAt: createdAt
                ))
            }
        }
        sqlite3_finalize(statement)

        return prompts
    }

    // MARK: - Session Usage

    func getSessionUsage(sessionId: String) -> SessionUsage? {
        guard openDatabase() else { return nil }
        defer { closeDatabase() }

        let query: String
        let bindValue: String

        if sessionId.hasPrefix("pending_") {
            let pendingId = String(sessionId.dropFirst(8))
            query = """
                SELECT su.session_pk, su.total_input_chars, su.total_output_chars,
                       su.total_input_words, su.total_output_words,
                       su.estimated_input_tokens, su.estimated_output_tokens, su.updated_at
                FROM session_usage su
                JOIN sessions s ON su.session_pk = s.id
                WHERE s.pending_id = ?
                """
            bindValue = pendingId
        } else {
            query = """
                SELECT su.session_pk, su.total_input_chars, su.total_output_chars,
                       su.total_input_words, su.total_output_words,
                       su.estimated_input_tokens, su.estimated_output_tokens, su.updated_at
                FROM session_usage su
                JOIN sessions s ON su.session_pk = s.id
                WHERE s.session_id = ?
                """
            bindValue = sessionId
        }

        var statement: OpaquePointer?
        var result: SessionUsage?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, bindValue, -1, SQLITE_TRANSIENT)

            if sqlite3_step(statement) == SQLITE_ROW {
                let sessionPk = Int(sqlite3_column_int(statement, 0))
                let totalInputChars = Int(sqlite3_column_int(statement, 1))
                let totalOutputChars = Int(sqlite3_column_int(statement, 2))
                let totalInputWords = Int(sqlite3_column_int(statement, 3))
                let totalOutputWords = Int(sqlite3_column_int(statement, 4))
                let estimatedInputTokens = Int(sqlite3_column_int(statement, 5))
                let estimatedOutputTokens = Int(sqlite3_column_int(statement, 6))
                let updatedAtStr = safeString(from: sqlite3_column_text(statement, 7))
                let updatedAt = dateFormatter.date(from: String(updatedAtStr.prefix(19))) ?? Date()

                result = SessionUsage(
                    sessionPk: sessionPk,
                    totalInputChars: totalInputChars,
                    totalOutputChars: totalOutputChars,
                    totalInputWords: totalInputWords,
                    totalOutputWords: totalOutputWords,
                    estimatedInputTokens: estimatedInputTokens,
                    estimatedOutputTokens: estimatedOutputTokens,
                    updatedAt: updatedAt
                )
            }
        }
        sqlite3_finalize(statement)

        return result
    }

    // MARK: - Session Resume Links

    func getResumedFrom(sessionId: String) -> String? {
        guard openDatabase() else { return nil }
        defer { closeDatabase() }

        // Don't check pending sessions for resume links
        if sessionId.hasPrefix("pending_") {
            return nil
        }

        let query = """
            SELECT original_session_id
            FROM session_links
            WHERE resumed_session_id = ?
            ORDER BY created_at DESC
            LIMIT 1
            """

        var statement: OpaquePointer?
        var result: String?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, sessionId, -1, SQLITE_TRANSIENT)

            if sqlite3_step(statement) == SQLITE_ROW {
                if let originalIdPtr = sqlite3_column_text(statement, 0) {
                    result = String(cString: originalIdPtr)
                }
            }
        }
        sqlite3_finalize(statement)

        return result
    }

    func getResumeChain(sessionId: String) -> [String] {
        guard openDatabase() else { return [sessionId] }
        defer { closeDatabase() }

        var chain = [sessionId]
        var current = sessionId

        // Walk backwards to find all ancestors
        while true {
            let query = """
                SELECT original_session_id
                FROM session_links
                WHERE resumed_session_id = ?
                """

            var statement: OpaquePointer?
            var foundOriginal: String?

            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, current, -1, SQLITE_TRANSIENT)

                if sqlite3_step(statement) == SQLITE_ROW {
                    if let originalIdPtr = sqlite3_column_text(statement, 0) {
                        foundOriginal = String(cString: originalIdPtr)
                    }
                }
            }
            sqlite3_finalize(statement)

            guard let original = foundOriginal else {
                break
            }

            chain.insert(original, at: 0)
            current = original
        }

        return chain
    }

    // MARK: - Relative Time

    func relativeTime(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return L(.time_just_now)
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)" + L(.time_minutes_ago)
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)" + L(.time_hours_ago)
        } else {
            let days = Int(interval / 86400)
            return "\(days)" + L(.time_days_ago)
        }
    }

    // MARK: - Project Queries

    func getUniqueProjects(limit: Int = 20) -> [String] {
        guard openDatabase() else { return [] }
        defer { closeDatabase() }

        var projects: [String] = []
        let query = """
            SELECT DISTINCT project FROM sessions
            WHERE project IS NOT NULL AND project != ''
            ORDER BY last_activity DESC
            LIMIT ?
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(limit))

            while sqlite3_step(statement) == SQLITE_ROW {
                if let projectPtr = sqlite3_column_text(statement, 0) {
                    let project = String(cString: projectPtr)
                    projects.append(project)
                }
            }
        }
        sqlite3_finalize(statement)

        return projects
    }
}
