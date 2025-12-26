import Foundation
import SQLite3

// SQLite destructor type for transient strings (also defined in DatabaseManager.swift)
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Timeline & Summary Extension

extension DatabaseManager {

    // MARK: - Timeline Methods

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
            sqlite3_bind_text(statement, 1, bindValue, -1, SQLITE_TRANSIENT)

            var lastEventTime: Date?
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

                // Skip if too close to last event (< 10 seconds) for status_change
                if let lastTime = lastEventTime, eventType == "status_change" {
                    if eventTime.timeIntervalSince(lastTime) < 10 {
                        continue
                    }
                }

                var node: TimelineNode?

                switch eventType {
                case "goal_set":
                    let timeStr = formatTime(eventTime)
                    let desc = String(content.prefix(50))
                    let fullDesc = content.isEmpty ? "任务开始" : content
                    node = TimelineNode(
                        time: timeStr,
                        type: "start",
                        title: "开始任务",
                        description: desc.isEmpty ? "任务开始" : desc,
                        fullDescription: fullDesc,
                        status: "completed"
                    )

                case "status_change":
                    if content == lastStatus {
                        continue
                    }
                    lastStatus = content

                    let timeStr = formatTime(eventTime)
                    switch content {
                    case "idle":
                        node = TimelineNode(
                            time: timeStr,
                            type: "idle",
                            title: "空闲",
                            description: "等待新任务",
                            fullDescription: "等待新任务",
                            status: "completed"
                        )
                    case "working":
                        node = TimelineNode(
                            time: timeStr,
                            type: "working",
                            title: "工作中",
                            description: "正在执行任务",
                            fullDescription: "正在执行任务",
                            status: "completed"
                        )
                    case "waiting_for_user":
                        node = TimelineNode(
                            time: timeStr,
                            type: "waiting",
                            title: "等待决策",
                            description: "需要用户输入",
                            fullDescription: "需要用户输入",
                            status: "current"
                        )
                    case "waiting_permission":
                        node = TimelineNode(
                            time: timeStr,
                            type: "permission",
                            title: "等待权限",
                            description: "需要权限确认",
                            fullDescription: "需要权限确认",
                            status: "current"
                        )
                    case "completed":
                        node = TimelineNode(
                            time: timeStr,
                            type: "complete",
                            title: "任务完成",
                            description: "已完成全部步骤",
                            fullDescription: "已完成全部步骤",
                            status: "completed"
                        )
                    case "rate_limited":
                        node = TimelineNode(
                            time: timeStr,
                            type: "rate_limited",
                            title: "限流",
                            description: "API 请求受限",
                            fullDescription: "API 请求受限",
                            status: "current"
                        )
                    default:
                        break
                    }

                case "progress_update":
                    let completed = metadata["completed"] as? Int ?? 0
                    let total = metadata["total"] as? Int ?? 0
                    let timeStr = formatTime(eventTime)

                    // 每次进度更新都显示
                    if completed > lastCompletedCount {
                        let desc = "已完成 \(completed)/\(total) 项"
                        node = TimelineNode(
                            time: timeStr,
                            type: "progress",
                            title: "进度更新",
                            description: desc,
                            fullDescription: desc,
                            status: completed == total && total > 0 ? "completed" : "current"
                        )
                    }
                    lastCompletedCount = completed

                case "user_input":
                    let timeStr = formatTime(eventTime)
                    let desc = String(content.prefix(50))
                    let fullDesc = content.isEmpty ? "继续对话" : content
                    node = TimelineNode(
                        time: timeStr,
                        type: "input",
                        title: "用户输入",
                        description: desc.isEmpty ? "继续对话" : desc,
                        fullDescription: fullDesc,
                        status: "completed"
                    )

                case "ai_summary":
                    let timeStr = formatTime(eventTime)
                    let currentTask = content.isEmpty ? (metadata["current_task"] as? String ?? "AI 分析") : content

                    // 构建完整描述（用于 hover popover）
                    var fullParts: [String] = []
                    fullParts.append("当前任务: \(currentTask)")

                    if let progress = metadata["progress_summary"] as? String, !progress.isEmpty {
                        fullParts.append("进度: \(progress)")
                    }
                    if let nextStep = metadata["next_step"] as? String, !nextStep.isEmpty {
                        fullParts.append("下一步: \(nextStep)")
                    }
                    if let pending = metadata["pending_decision"] as? String, !pending.isEmpty {
                        fullParts.append("待决策: \(pending)")
                    }

                    let fullDesc = fullParts.joined(separator: "\n")

                    node = TimelineNode(
                        time: timeStr,
                        type: "ai_summary",
                        title: "AI 总结",
                        description: currentTask,
                        fullDescription: fullDesc,
                        status: "completed"
                    )

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
                fullDescription: last.fullDescription,
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
                       account_alias, bundle_id, terminal_pid, shell_pid, window_id
                FROM sessions
                WHERE pending_id = ?
                """
            bindValue = pendingId
        } else {
            query = """
                SELECT id, session_id, project, original_goal, current_status, last_activity, created_at,
                       account_alias, bundle_id, terminal_pid, shell_pid, window_id
                FROM sessions
                WHERE session_id = ?
                """
            bindValue = sessionId
        }

        var statement: OpaquePointer?
        var result: SessionInfo?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, bindValue, -1, SQLITE_TRANSIENT)

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
                let shellPid = sqlite3_column_type(statement, 10) != SQLITE_NULL ? Int32(sqlite3_column_int(statement, 10)) : nil
                let windowId = sqlite3_column_type(statement, 11) != SQLITE_NULL ? UInt32(sqlite3_column_int(statement, 11)) : nil

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
                    shellPid: shellPid,
                    windowId: windowId,
                    pk: pk,
                    summaryMode: nil
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
            sqlite3_bind_text(statement, 1, bindValue, -1, SQLITE_TRANSIENT)

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
            case "working", "executing_tool", "subagent_working":
                working += 1
            default:
                break
            }
        }

        // Priority: needsDecision > working > idle > none
        if needsDecision > 0 {
            return (.needsDecision, needsDecision)
        } else if working > 0 {
            return (.working, working)
        } else if idle > 0 {
            return (.idle, idle)
        } else {
            return (.none, sessions.count)
        }
    }

    // MARK: - Cleanup Methods

    /// Clean up sessions with dead processes
    /// Check if shell_pid is alive, mark session as completed if process doesn't exist
    /// - Returns: Number of sessions cleaned up
    @discardableResult
    func cleanupDeadSessions() -> Int {
        log("CLEANUP: cleanupDeadSessions() called")
        guard openDatabase() else {
            log("CLEANUP: Failed to open database")
            return 0
        }
        defer { closeDatabase() }

        // Query all active sessions with shell_pid
        // New schema: use id (primary key) for updates
        let query = """
            SELECT id, shell_pid
            FROM sessions
            WHERE current_status != 'completed'
            AND shell_pid IS NOT NULL
            """

        var deadSessions: [Int] = []  // Store primary keys
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let pk = Int(sqlite3_column_int(statement, 0))
                let pid = sqlite3_column_int(statement, 1)

                // Check if process is alive (kill with signal 0 only checks, doesn't send signal)
                let killResult = kill(pid, 0)
                let currentErrno = errno
                log("CLEANUP: Checking pk=\(pk) pid=\(pid) kill_result=\(killResult) errno=\(currentErrno)")

                if killResult != 0 {
                    // Process doesn't exist (errno == ESRCH) or no permission (errno == EPERM)
                    // EPERM means process exists but belongs to another user, don't clean up
                    if currentErrno == ESRCH {
                        deadSessions.append(pk)
                        log("CLEANUP: Session pk=\(pk) has dead shell PID \(pid)")
                    }
                }
            }
        } else {
            log("CLEANUP: SQL prepare failed")
        }
        sqlite3_finalize(statement)

        // Mark dead sessions as completed
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
}
