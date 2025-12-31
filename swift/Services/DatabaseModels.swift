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

// MARK: - Global Task & Todo System Models

/// Global Task - high-level cross-project objective
struct GlobalTaskInfo {
    let id: Int
    let title: String
    let description: String?
    let status: String  // active, completed, archived
    let priority: Int   // 0=normal, 1=high, 2=urgent
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
    let metadata: [String: Any]?
    // Aggregated fields
    let todoCount: Int
    let completedTodoCount: Int

    var completionPercentage: Double {
        guard todoCount > 0 else { return 0 }
        return Double(completedTodoCount) / Double(todoCount) * 100
    }

    var priorityIcon: String {
        switch priority {
        case 2: return "◉"  // urgent
        case 1: return "●"  // high
        default: return "○" // normal
        }
    }

    var statusIcon: String {
        switch status {
        case "active": return "▶"
        case "completed": return "✓"
        case "archived": return "⌫"
        default: return "○"
        }
    }
}

/// Project-level Todo with hierarchy support
struct ProjectTodoItem {
    let id: Int
    let globalTaskId: Int?
    let parentTodoId: Int?
    let projectPath: String
    let title: String
    let description: String?
    let status: String  // pending, in_progress, blocked, completed, cancelled
    let priority: Int
    let estimatedMinutes: Int?
    let actualMinutes: Int?
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
    let completionSummary: String?
    let metadata: [String: Any]?
    // Related data
    var children: [ProjectTodoItem]?
    var linkedSessions: [Int]?

    var isCompleted: Bool { status == "completed" }
    var isBlocked: Bool { status == "blocked" }
    var isInProgress: Bool { status == "in_progress" }
    var isPending: Bool { status == "pending" }

    var statusIcon: String {
        switch status {
        case "pending": return "○"
        case "in_progress": return "→"
        case "blocked": return "!"
        case "completed": return "✓"
        case "cancelled": return "×"
        default: return "○"
        }
    }

    var priorityIcon: String {
        switch priority {
        case 2: return "◉"
        case 1: return "●"
        default: return "○"
        }
    }

    var projectName: String {
        return (projectPath as NSString).lastPathComponent
    }

    var estimatedTimeFormatted: String? {
        guard let minutes = estimatedMinutes else { return nil }
        if minutes >= 60 {
            return String(format: "%.1fh", Double(minutes) / 60.0)
        }
        return "\(minutes)m"
    }
}

/// Todo execution record
struct TodoExecutionRecord {
    let id: Int
    let todoId: Int
    let sessionPk: Int?
    let action: String  // created, started, completed, split, etc.
    let actor: String   // user, claude_code, system, ai
    let details: [String: Any]?
    let createdAt: Date

    var actionIcon: String {
        switch action {
        case "created": return "+"
        case "started": return "▶"
        case "completed": return "✓"
        case "split": return "⋮"
        case "blocked": return "!"
        case "cancelled": return "×"
        default: return "·"
        }
    }
}

/// Workflow run record
struct WorkflowRunInfo {
    let id: Int
    let workflowName: String
    let taskId: Int?
    let status: String  // pending, running, completed, failed, cancelled
    let currentStep: String?
    let context: [String: Any]?
    let startedAt: Date?
    let completedAt: Date?
    let createdAt: Date

    var statusIcon: String {
        switch status {
        case "pending": return "○"
        case "running": return "▶"
        case "completed": return "✓"
        case "failed": return "✗"
        case "cancelled": return "×"
        default: return "○"
        }
    }

    var isRunning: Bool { status == "running" }
    var isCompleted: Bool { status == "completed" }
    var hasFailed: Bool { status == "failed" }
}

/// Workflow step log
struct WorkflowStepLogInfo {
    let id: Int
    let runId: Int
    let stepId: String
    let status: String  // pending, running, completed, failed, skipped
    let output: [String: Any]?
    let error: String?
    let startedAt: Date?
    let completedAt: Date?

    var statusIcon: String {
        switch status {
        case "pending": return "○"
        case "running": return "▶"
        case "completed": return "✓"
        case "failed": return "✗"
        case "skipped": return "⊘"
        default: return "○"
        }
    }
}

/// Todo statistics for a project
struct ProjectTodoStats {
    let total: Int
    let pending: Int
    let inProgress: Int
    let blocked: Int
    let completed: Int
    let cancelled: Int

    var activeCount: Int {
        return pending + inProgress + blocked
    }

    var completionPercentage: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total) * 100
    }
}
