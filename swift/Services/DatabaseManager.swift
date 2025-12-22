import Foundation
import SQLite3

// MARK: - Data Models

struct SessionInfo {
    let sessionId: String
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
        guard openDatabase() else { return [] }
        defer { closeDatabase() }

        var sessions: [SessionInfo] = []
        let query = """
            SELECT session_id, project, original_goal, current_status, last_activity, created_at,
                   account_alias, bundle_id, terminal_pid, window_id
            FROM sessions
            WHERE current_status != 'completed'
            ORDER BY last_activity DESC
            LIMIT 20
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let sessionId = safeString(from: sqlite3_column_text(statement, 0))
                let project = safeString(from: sqlite3_column_text(statement, 1))
                let originalGoal = safeString(from: sqlite3_column_text(statement, 2))
                let currentStatus = safeString(from: sqlite3_column_text(statement, 3))

                let lastActivityStr = safeString(from: sqlite3_column_text(statement, 4))
                let createdAtStr = safeString(from: sqlite3_column_text(statement, 5))

                let lastActivity = dateFormatter.date(from: String(lastActivityStr.prefix(19))) ?? Date()
                let createdAt = dateFormatter.date(from: String(createdAtStr.prefix(19))) ?? Date()

                // Window info for terminal jumping
                let accountAlias = safeString(from: sqlite3_column_text(statement, 6))
                let bundleId = sqlite3_column_text(statement, 7).map { String(cString: $0) }
                let terminalPid = sqlite3_column_type(statement, 8) != SQLITE_NULL ? Int32(sqlite3_column_int(statement, 8)) : nil
                let windowId = sqlite3_column_type(statement, 9) != SQLITE_NULL ? UInt32(sqlite3_column_int(statement, 9)) : nil

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
                    windowId: windowId
                ))
            }
        }
        sqlite3_finalize(statement)

        return sessions
    }

    func getAllSessions(includeCompleted: Bool = false) -> [SessionInfo] {
        guard openDatabase() else { return [] }
        defer { closeDatabase() }

        var sessions: [SessionInfo] = []
        var query = """
            SELECT session_id, project, original_goal, current_status, last_activity, created_at,
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
                let sessionId = safeString(from: sqlite3_column_text(statement, 0))
                let project = safeString(from: sqlite3_column_text(statement, 1))
                let originalGoal = safeString(from: sqlite3_column_text(statement, 2))
                let currentStatus = safeString(from: sqlite3_column_text(statement, 3))

                let lastActivityStr = safeString(from: sqlite3_column_text(statement, 4))
                let createdAtStr = safeString(from: sqlite3_column_text(statement, 5))

                let lastActivity = dateFormatter.date(from: String(lastActivityStr.prefix(19))) ?? Date()
                let createdAt = dateFormatter.date(from: String(createdAtStr.prefix(19))) ?? Date()

                // Window info for terminal jumping
                let accountAlias = safeString(from: sqlite3_column_text(statement, 6))
                let bundleId = sqlite3_column_text(statement, 7).map { String(cString: $0) }
                let terminalPid = sqlite3_column_type(statement, 8) != SQLITE_NULL ? Int32(sqlite3_column_int(statement, 8)) : nil
                let windowId = sqlite3_column_type(statement, 9) != SQLITE_NULL ? UInt32(sqlite3_column_int(statement, 9)) : nil

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
                    windowId: windowId
                ))
            }
        }
        sqlite3_finalize(statement)

        return sessions
    }

    func getProgress(sessionId: String) -> ProgressInfo? {
        guard openDatabase() else { return nil }
        defer { closeDatabase() }

        let query = """
            SELECT todos_json, completed_count, total_count
            FROM progress
            WHERE session_id = ?
            """

        var statement: OpaquePointer?
        var result: ProgressInfo?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, sessionId, -1, nil)

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

        let query = """
            SELECT question
            FROM pending_decisions
            WHERE session_id = ? AND resolved = 0
            ORDER BY created_at DESC
            LIMIT 1
            """

        var statement: OpaquePointer?
        var result: String?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, sessionId, -1, nil)

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

        let query = """
            SELECT event_type, content, metadata_json, timestamp
            FROM timeline
            WHERE session_id = ?
            ORDER BY timestamp ASC
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, sessionId, -1, nil)

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

        let query = """
            SELECT session_id, project, original_goal, current_status, last_activity, created_at,
                   account_alias, bundle_id, terminal_pid, window_id
            FROM sessions
            WHERE session_id = ?
            """

        var statement: OpaquePointer?
        var result: SessionInfo?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, sessionId, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW {
                let project = safeString(from: sqlite3_column_text(statement, 1))
                let originalGoal = safeString(from: sqlite3_column_text(statement, 2))
                let currentStatus = safeString(from: sqlite3_column_text(statement, 3))

                let lastActivityStr = safeString(from: sqlite3_column_text(statement, 4))
                let createdAtStr = safeString(from: sqlite3_column_text(statement, 5))

                let lastActivity = dateFormatter.date(from: String(lastActivityStr.prefix(19))) ?? Date()
                let createdAt = dateFormatter.date(from: String(createdAtStr.prefix(19))) ?? Date()

                // Window info for terminal jumping
                let accountAlias = safeString(from: sqlite3_column_text(statement, 6))
                let bundleId = sqlite3_column_text(statement, 7).map { String(cString: $0) }
                let terminalPid = sqlite3_column_type(statement, 8) != SQLITE_NULL ? Int32(sqlite3_column_int(statement, 8)) : nil
                let windowId = sqlite3_column_type(statement, 9) != SQLITE_NULL ? UInt32(sqlite3_column_int(statement, 9)) : nil

                result = SessionInfo(
                    sessionId: sessionId,
                    project: project,
                    originalGoal: originalGoal,
                    currentStatus: currentStatus,
                    lastActivity: lastActivity,
                    createdAt: createdAt,
                    accountAlias: accountAlias.isEmpty ? "default" : accountAlias,
                    bundleId: bundleId,
                    terminalPid: terminalPid,
                    windowId: windowId
                )
            }
        }
        sqlite3_finalize(statement)

        return result
    }

    func getRoundCount(sessionId: String) -> Int {
        guard openDatabase() else { return 0 }
        defer { closeDatabase() }

        let query = """
            SELECT COUNT(*) FROM timeline
            WHERE session_id = ?
            AND event_type IN ('goal_set', 'user_input')
            """

        var statement: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, sessionId, -1, nil)

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
