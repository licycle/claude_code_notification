import Foundation
import SQLite3

// MARK: - Data Models

struct SessionInfo {
    let sessionId: String       // For pending sessions, this will be "pending_{pending_id}"
    let project: String
    let originalGoal: String
    let currentStatus: String
    let lastActivity: Date
    let createdAt: Date
    // Window info for terminal jumping
    let accountAlias: String
    let bundleId: String?
    let terminalPid: Int32?
    let windowId: UInt32?
    // Internal primary key for database operations
    let pk: Int?
}

struct ProgressInfo {
    let completed: Int
    let total: Int
    let todos: [TodoItem]
}

struct TodoItem {
    let content: String
    let status: String
    let activeForm: String
}

struct TimelineNode {
    let time: String
    let type: String      // start/milestone/waiting/permission/complete
    let title: String
    let description: String
    let status: String    // completed/current/pending
}

struct SessionSummary {
    let session: SessionInfo
    let progress: ProgressInfo?
    let pendingQuestion: String?
    let timeline: [TimelineNode]
}

// MARK: - Status Type

enum SessionStatusType {
    case needsDecision  // Red - waiting for user decision
    case idle           // Yellow - idle
    case working        // Green - actively working
    case completed      // Gray - completed
    case none           // No sessions

    var emoji: String {
        switch self {
        case .needsDecision: return "🔴"
        case .idle: return "🟡"
        case .working: return "🟢"
        case .completed: return "✅"
        case .none: return "⚪"
        }
    }
}

// MARK: - Database Manager

class DatabaseManager {
    static let shared = DatabaseManager()

    private let dbPath: String
    private var db: OpaquePointer?

    private let dateFormatter: DateFormatter = {
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

    private func openDatabase() -> Bool {
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            return true
        } else {
            log("DATABASE: Failed to open database at \(dbPath)")
            return false
        }
    }

    private func closeDatabase() {
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
                   account_alias, bundle_id, terminal_pid, window_id
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
                let windowId = sqlite3_column_type(statement, 10) != SQLITE_NULL ? UInt32(sqlite3_column_int(statement, 10)) : nil

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
                   account_alias, bundle_id, terminal_pid, window_id
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
                let windowId = sqlite3_column_type(statement, 10) != SQLITE_NULL ? UInt32(sqlite3_column_int(statement, 10)) : nil

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

    func getTimelineNodes(sessionId: String, maxNodes: Int = 10) -> [TimelineNode] {
        guard openDatabase() else { return [] }
        defer { closeDatabase() }

        var nodes: [TimelineNode] = []

        // New schema: timeline uses session_pk
        let query: String
        let bindValue: String

        if sessionId.hasPrefix("pending_") {
            let pendingId = String(sessionId.dropFirst(8))
            query = """
                SELECT t.event_type, t.content, t.metadata_json, t.timestamp
                FROM timeline t
                JOIN sessions s ON t.session_pk = s.id
                WHERE s.pending_id = ?
                ORDER BY t.timestamp ASC
                """
            bindValue = pendingId
        } else {
            query = """
                SELECT t.event_type, t.content, t.metadata_json, t.timestamp
                FROM timeline t
                JOIN sessions s ON t.session_pk = s.id
                WHERE s.session_id = ?
                ORDER BY t.timestamp ASC
                """
            bindValue = sessionId
        }

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, bindValue, -1, nil)

            var lastEventTime: Date?
            var consecutiveProgress = 0
            var lastCompletedCount = 0
            var lastStatus: String?

            while sqlite3_step(statement) == SQLITE_ROW {
                let eventType = safeString(from: sqlite3_column_text(statement, 0))

                let content = safeString(from: sqlite3_column_text(statement, 1))

                var metadata: [String: Any] = [:]
                let metadataJson = safeString(from: sqlite3_column_text(statement, 2))
                if !metadataJson.isEmpty,
                   let data = metadataJson.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    metadata = json
                }

                let timestampStr = safeString(from: sqlite3_column_text(statement, 3))
                guard let eventTime = dateFormatter.date(from: String(timestampStr.prefix(19))) else {
                    continue
                }

                // Skip if too close to last event (< 30 seconds) for status_change
                if let lastTime = lastEventTime, eventType == "status_change" {
                    if eventTime.timeIntervalSince(lastTime) < 30 {
                        continue
                    }
                }

                var node: TimelineNode?

                switch eventType {
                case "goal_set":
                    let timeStr = formatTime(eventTime)
                    let desc = String(content.prefix(50))
                    node = TimelineNode(
                        time: timeStr,
                        type: "start",
                        title: "开始任务",
                        description: desc.isEmpty ? "任务开始" : desc,
                        status: "completed"
                    )

                case "status_change":
                    if content == lastStatus {
                        continue
                    }
                    lastStatus = content

                    let timeStr = formatTime(eventTime)
                    switch content {
                    case "waiting_for_user":
                        node = TimelineNode(
                            time: timeStr,
                            type: "waiting",
                            title: "等待决策",
                            description: "需要用户输入",
                            status: "current"
                        )
                    case "waiting_permission":
                        node = TimelineNode(
                            time: timeStr,
                            type: "permission",
                            title: "等待权限",
                            description: "需要权限确认",
                            status: "current"
                        )
                    case "completed":
                        node = TimelineNode(
                            time: timeStr,
                            type: "complete",
                            title: "任务完成",
                            description: "已完成全部步骤",
                            status: "completed"
                        )
                    default:
                        break
                    }

                case "progress_update":
                    let completed = metadata["completed"] as? Int ?? 0
                    let total = metadata["total"] as? Int ?? 0

                    if completed > lastCompletedCount {
                        consecutiveProgress += (completed - lastCompletedCount)
                    }
                    lastCompletedCount = completed

                    // Create milestone for 3+ consecutive completions
                    if consecutiveProgress >= 3 {
                        let timeStr = formatTime(eventTime)
                        node = TimelineNode(
                            time: timeStr,
                            type: "milestone",
                            title: "阶段完成",
                            description: "已完成 \(completed)/\(total) 项",
                            status: "completed"
                        )
                        consecutiveProgress = 0
                    }

                    // All todos completed
                    if completed == total && total > 0 {
                        let timeStr = formatTime(eventTime)
                        node = TimelineNode(
                            time: timeStr,
                            type: "complete",
                            title: "全部完成",
                            description: "已完成全部 \(total) 项任务",
                            status: "completed"
                        )
                    }

                default:
                    break
                }

                if let n = node {
                    nodes.append(n)
                    lastEventTime = eventTime
                }
            }
        }
        sqlite3_finalize(statement)

        // Mark last node as current if not completed
        if !nodes.isEmpty && nodes[nodes.count - 1].type != "complete" {
            let last = nodes[nodes.count - 1]
            nodes[nodes.count - 1] = TimelineNode(
                time: last.time,
                type: last.type,
                title: last.title,
                description: last.description,
                status: "current"
            )
        }

        // Return last maxNodes
        if nodes.count > maxNodes {
            return Array(nodes.suffix(maxNodes))
        }
        return nodes
    }

    // MARK: - Summary Methods

    func getSessionSummary(sessionId: String) -> SessionSummary? {
        guard let session = getSession(sessionId: sessionId) else {
            return nil
        }

        let progress = getProgress(sessionId: sessionId)
        let pendingQuestion = getPendingQuestion(sessionId: sessionId)
        let timeline = getTimelineNodes(sessionId: sessionId)

        return SessionSummary(
            session: session,
            progress: progress,
            pendingQuestion: pendingQuestion,
            timeline: timeline
        )
    }

    func getSession(sessionId: String) -> SessionInfo? {
        guard openDatabase() else { return nil }
        defer { closeDatabase() }

        // Handle both real session_id and pending_xxx format
        let query: String
        let bindValue: String

        if sessionId.hasPrefix("pending_") {
            let pendingId = String(sessionId.dropFirst(8))
            query = """
                SELECT id, COALESCE(session_id, 'pending_' || pending_id) as display_id,
                       project, original_goal, current_status, last_activity, created_at,
                       account_alias, bundle_id, terminal_pid, window_id
                FROM sessions
                WHERE pending_id = ?
                """
            bindValue = pendingId
        } else {
            query = """
                SELECT id, session_id, project, original_goal, current_status, last_activity, created_at,
                       account_alias, bundle_id, terminal_pid, window_id
                FROM sessions
                WHERE session_id = ?
                """
            bindValue = sessionId
        }

        var statement: OpaquePointer?
        var result: SessionInfo?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, bindValue, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW {
                let pk = Int(sqlite3_column_int(statement, 0))
                let displayId = safeString(from: sqlite3_column_text(statement, 1))
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
                let windowId = sqlite3_column_type(statement, 10) != SQLITE_NULL ? UInt32(sqlite3_column_int(statement, 10)) : nil

                result = SessionInfo(
                    sessionId: displayId.isEmpty ? sessionId : displayId,
                    project: project,
                    originalGoal: originalGoal,
                    currentStatus: currentStatus,
                    lastActivity: lastActivity,
                    createdAt: createdAt,
                    accountAlias: accountAlias.isEmpty ? "default" : accountAlias,
                    bundleId: bundleId,
                    terminalPid: terminalPid,
                    windowId: windowId,
                    pk: pk
                )
            }
        }
        sqlite3_finalize(statement)

        return result
    }

    func getRoundCount(sessionId: String) -> Int {
        guard openDatabase() else { return 0 }
        defer { closeDatabase() }

        // New schema: timeline uses session_pk
        let query: String
        let bindValue: String

        if sessionId.hasPrefix("pending_") {
            let pendingId = String(sessionId.dropFirst(8))
            query = """
                SELECT COUNT(*) FROM timeline t
                JOIN sessions s ON t.session_pk = s.id
                WHERE s.pending_id = ?
                AND t.event_type IN ('goal_set', 'user_input')
                """
            bindValue = pendingId
        } else {
            query = """
                SELECT COUNT(*) FROM timeline t
                JOIN sessions s ON t.session_pk = s.id
                WHERE s.session_id = ?
                AND t.event_type IN ('goal_set', 'user_input')
                """
            bindValue = sessionId
        }

        var statement: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, bindValue, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)

        return count
    }

    func getOverallStatus() -> (status: SessionStatusType, count: Int) {
        let sessions = getActiveSessions()
        if sessions.isEmpty {
            return (.none, 0)
        }

        var needsDecision = 0
        var idle = 0
        var working = 0

        for session in sessions {
            switch session.currentStatus {
            case "waiting_for_user", "waiting_permission":
                needsDecision += 1
            case "idle":
                idle += 1
            case "working":
                working += 1
            default:
                break
            }
        }

        if needsDecision > 0 {
            return (.needsDecision, needsDecision)
        } else if idle > 0 {
            return (.idle, idle)
        } else if working > 0 {
            return (.working, working)
        } else {
            return (.none, sessions.count)
        }
    }

    // MARK: - Helper Methods

    private func safeString(from pointer: UnsafePointer<UInt8>?) -> String {
        guard let pointer = pointer else { return "" }
        return String(cString: pointer)
    }

    private func parseTodosJson(_ json: String) -> [TodoItem] {
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

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Cleanup Methods

    /// 清理已死亡进程的会话
    /// 检查 terminal_pid 是否存活，如果进程不存在则标记会话为 completed
    /// - Returns: 清理的会话数量
    @discardableResult
    func cleanupDeadSessions() -> Int {
        guard openDatabase() else { return 0 }
        defer { closeDatabase() }

        // 查询所有有 terminal_pid 的活跃会话
        // New schema: use id (primary key) for updates
        let query = """
            SELECT id, terminal_pid
            FROM sessions
            WHERE current_status != 'completed'
            AND terminal_pid IS NOT NULL
            """

        var deadSessions: [Int] = []  // Store primary keys
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let pk = Int(sqlite3_column_int(statement, 0))
                let pid = sqlite3_column_int(statement, 1)

                // 检查进程是否存活 (kill with signal 0 只检查不发送信号)
                if kill(pid, 0) != 0 {
                    // 进程不存在 (errno == ESRCH) 或无权限 (errno == EPERM)
                    // EPERM 说明进程存在但属于其他用户，这种情况不清理
                    if errno == ESRCH {
                        deadSessions.append(pk)
                        log("CLEANUP: Session pk=\(pk) has dead PID \(pid)")
                    }
                }
            }
        }
        sqlite3_finalize(statement)

        // 标记死亡会话为 completed
        if !deadSessions.isEmpty {
            for pk in deadSessions {
                let updateQuery = """
                    UPDATE sessions
                    SET current_status = 'completed', last_activity = datetime('now')
                    WHERE id = ?
                    """
                var updateStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, updateQuery, -1, &updateStmt, nil) == SQLITE_OK {
                    sqlite3_bind_int(updateStmt, 1, Int32(pk))
                    sqlite3_step(updateStmt)
                }
                sqlite3_finalize(updateStmt)
            }
            log("CLEANUP: Marked \(deadSessions.count) dead sessions as completed")
        }

        return deadSessions.count
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
