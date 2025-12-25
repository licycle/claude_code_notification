import Foundation

// MARK: - Notification Names

extension Notification.Name {
    static let showManagementWindow = Notification.Name("showManagementWindow")
}

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
    let shellPid: Int32?
    let windowId: UInt32?
    // Internal primary key for database operations
    let pk: Int?
    // Summary mode from latest snapshot (ai/raw/nil)
    let summaryMode: String?
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
    let description: String       // 列表显示用（简短）
    let fullDescription: String   // hover popover 显示用（完整）
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
