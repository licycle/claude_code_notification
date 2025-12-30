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

// MARK: - Prompt Record (for prompt history display)

struct PromptRecord {
    let id: Int
    let sessionPk: Int
    let roundNumber: Int
    let content: String
    let charCount: Int
    let wordCount: Int
    let estimatedTokens: Int
    let createdAt: Date
}

// MARK: - Session Usage (for token estimation)

struct SessionUsage {
    let sessionPk: Int
    let totalInputChars: Int
    let totalOutputChars: Int
    let totalInputWords: Int
    let totalOutputWords: Int
    let estimatedInputTokens: Int
    let estimatedOutputTokens: Int
    let updatedAt: Date

    var totalEstimatedTokens: Int {
        return estimatedInputTokens + estimatedOutputTokens
    }

    var formattedInputTokens: String {
        return formatTokenCount(estimatedInputTokens)
    }

    var formattedOutputTokens: String {
        return formatTokenCount(estimatedOutputTokens)
    }

    var formattedTotalTokens: String {
        return formatTokenCount(totalEstimatedTokens)
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Session Link (for resume tracking)

struct SessionLink {
    let id: Int
    let originalSessionId: String
    let resumedSessionId: String
    let createdAt: Date
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
