import Foundation

// MARK: - Language Enum
enum Language: String, CaseIterable {
    case english = "en"
    case chinese = "zh"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }
}

// MARK: - String Keys
enum StringKey: String, CaseIterable {
    // ========== App General ==========
    case app_title
    case app_name

    // ========== Status Bar & Session List ==========
    case session_list_title
    case session_list_empty
    case session_list_cleanup
    case session_list_management
    case session_list_refresh

    // ========== Session Card ==========
    case status_waiting_decision
    case status_waiting_permission
    case status_idle
    case status_working
    case status_executing_tool
    case status_subagent
    case status_completed
    case session_card_detail

    // ========== Session Detail ==========
    case detail_back
    case detail_back_list
    case detail_jump_terminal
    case detail_copy_summary
    case detail_original_goal
    case detail_timeline
    case detail_timeline_empty
    case detail_todo
    case detail_todo_pending
    case detail_todo_completed
    case detail_todo_none
    case detail_session_info
    case detail_status
    case detail_project
    case detail_work_duration
    case detail_token_usage

    // ========== Settings Window ==========
    case settings_title
    case settings_permission_status
    case settings_notification
    case settings_accessibility
    case settings_authorized
    case settings_not_authorized
    case settings_open_settings
    case settings_checking
    case settings_summary_ai
    case settings_enable_ai_summary
    case settings_ai_hint
    case settings_base_url
    case settings_api_key
    case settings_model
    case settings_save
    case settings_test_api
    case settings_testing
    case settings_show
    case settings_hide
    case settings_send_test
    case settings_sending
    case settings_refresh_status
    case settings_language
    case settings_language_hint

    // Settings Messages
    case settings_saved_success
    case settings_url_required
    case settings_key_required
    case settings_test_success
    case settings_test_invalid_url
    case settings_test_invalid_key
    case settings_test_not_found
    case settings_test_rate_limited
    case settings_test_timeout
    case settings_test_connection_failed
    case settings_notification_success
    case settings_notification_error
    case settings_permission_denied

    // Alert
    case alert_success
    case alert_error
    case alert_ok

    // ========== Management Window ==========
    case management_title

    // Navigation
    case nav_task_center
    case nav_reports
    case nav_mcp
    case nav_settings

    // ========== MCP Server ==========
    case mcp_status_running
    case mcp_status_stopped
    case mcp_start
    case mcp_stop
    case mcp_restart
    case mcp_log_title
    case mcp_refresh_log

    // Task Center Table
    case table_account
    case table_session_id
    case table_goal
    case table_status
    case table_project
    case table_updated
    case table_action

    // Task Center Status
    case task_status_working
    case task_status_idle
    case task_status_waiting
    case task_status_permission
    case task_status_completed

    // Task Center Filter
    case filter_search_placeholder
    case filter_all_status
    case filter_working
    case filter_idle
    case filter_waiting
    case filter_completed
    case filter_all_accounts

    // Context Menu
    case context_view_details
    case context_jump_terminal
    case context_mark_completed
    case context_delete

    // Delete Confirmation
    case delete_confirm_title
    case delete_confirm_message
    case delete_button
    case cancel_button

    // Time Relative
    case time_just_now
    case time_minutes_ago
    case time_hours_ago
    case time_days_ago

    // ========== Reports ==========
    case report_daily
    case report_weekly
    case report_monthly
    case report_today
    case report_total_sessions
    case report_completed
    case report_working
    case report_waiting
    case report_coming_soon

    // ========== Copy Summary Text ==========
    case copy_task
    case copy_status
    case copy_project
    case copy_progress
    case copy_timeline

    // ========== Notification Actions ==========
    case notification_jump
    case notification_dismiss
    case notification_view_details

    // ========== Timeline Events ==========
    case timeline_start_task
    case timeline_task_started
    case timeline_idle
    case timeline_waiting_new_task
    case timeline_working
    case timeline_executing_task
    case timeline_waiting_decision
    case timeline_needs_user_input
    case timeline_waiting_permission
    case timeline_needs_permission
    case timeline_task_complete
    case timeline_all_steps_done
    case timeline_rate_limited
    case timeline_api_limited
    case timeline_progress_update
    case timeline_progress_done
    case timeline_user_input
    case timeline_continue_chat
    case timeline_ai_summary
    case timeline_current_task
    case timeline_progress
    case timeline_next_step
    case timeline_pending_decision

    // ========== Detail Tabs (New) ==========
    case detail_tab_timeline
    case detail_tab_prompts
    case detail_tab_usage

    // ========== Prompt History (New) ==========
    case prompt_round_label
    case prompt_chars
    case prompt_tokens_estimated
    case prompt_empty

    // ========== Usage Stats (New) ==========
    case usage_input_tokens
    case usage_output_tokens
    case usage_total_estimated
    case usage_empty
    case usage_chars
    case usage_words

    // ========== Resume Link (New) ==========
    case detail_resumed_from

    // ========== Todo Management ==========
    case todo_edit
    case todo_delete
    case todo_mark_complete
    case todo_mark_pending
    case todo_delete_confirm_title
    case todo_delete_confirm_message
    case todo_title_placeholder
    case todo_description
    case todo_status
    case todo_status_pending
    case todo_status_in_progress
    case todo_status_blocked
    case todo_status_completed
    case todo_status_cancelled
    case todo_priority
    case todo_priority_normal
    case todo_priority_high
    case todo_priority_urgent
    case todo_estimated_time
    case todo_minutes
    case todo_project

    // ========== Create Task/Todo ==========
    case create_mode_task
    case create_mode_todo
    case create_task_title
    case create_todo_title
    case create_task_button
    case create_todo_button
    case create_task_projects
    case create_todo_project
    case create_task_decompose
    case create_task_api_profile
    case create_task_api_none
    case create_task_api_no_profiles
    case create_error_title_required
    case create_error_project_required
    case create_error_failed

    // ========== Common ==========
    case cancel
    case save
}

// MARK: - String Translations
struct Strings {
    private static let translations: [StringKey: [Language: String]] = [
        // ========== App General ==========
        .app_title: [.english: "Claude Monitor", .chinese: "Claude Monitor"],
        .app_name: [.english: "ClaudeMonitor", .chinese: "ClaudeMonitor"],

        // ========== Status Bar & Session List ==========
        .session_list_title: [.english: "Claude Monitor", .chinese: "Claude Monitor"],
        .session_list_empty: [.english: "No active tasks", .chinese: "暂无活跃任务"],
        .session_list_cleanup: [.english: "Cleanup", .chinese: "清理无效"],
        .session_list_management: [.english: "Management", .chinese: "管理中心"],
        .session_list_refresh: [.english: "Refresh", .chinese: "刷新"],

        // ========== Session Card ==========
        .status_waiting_decision: [.english: "Waiting for decision", .chinese: "等待决策"],
        .status_waiting_permission: [.english: "Waiting for permission", .chinese: "等待权限"],
        .status_idle: [.english: "Idle", .chinese: "空闲中"],
        .status_working: [.english: "Working", .chinese: "运行中"],
        .status_executing_tool: [.english: "Executing tool", .chinese: "执行工具"],
        .status_subagent: [.english: "Sub-agent", .chinese: "子代理"],
        .status_completed: [.english: "Completed", .chinese: "已完成"],
        .session_card_detail: [.english: "Detail", .chinese: "详情"],

        // ========== Session Detail ==========
        .detail_back: [.english: "<- Back", .chinese: "<- 返回"],
        .detail_jump_terminal: [.english: "Jump to Terminal", .chinese: "跳转终端"],
        .detail_copy_summary: [.english: "Copy Summary", .chinese: "复制摘要"],
        .detail_original_goal: [.english: "Original Goal", .chinese: "原始目标"],
        .detail_timeline: [.english: "Progress Timeline", .chinese: "进度时间线"],
        .detail_timeline_empty: [.english: "No timeline data", .chinese: "暂无时间线数据"],
        .detail_todo: [.english: "Todo", .chinese: "Todo"],
        .detail_todo_pending: [.english: "Pending", .chinese: "待完成"],
        .detail_todo_completed: [.english: "Completed", .chinese: "已完成"],
        .detail_todo_none: [.english: "None", .chinese: "暂无"],
        .detail_back_list: [.english: "← Back to List", .chinese: "← 返回列表"],
        .detail_session_info: [.english: "Session Info", .chinese: "会话信息"],
        .detail_status: [.english: "Status:", .chinese: "状态:"],
        .detail_project: [.english: "Project:", .chinese: "项目:"],
        .detail_work_duration: [.english: "Duration:", .chinese: "时长:"],
        .detail_token_usage: [.english: "Token:", .chinese: "Token:"],

        // ========== Settings Window ==========
        .settings_title: [.english: "ClaudeMonitor Settings", .chinese: "ClaudeMonitor 设置"],
        .settings_permission_status: [.english: "Permission Status", .chinese: "权限状态"],
        .settings_notification: [.english: "Notification:", .chinese: "通知权限:"],
        .settings_accessibility: [.english: "Accessibility:", .chinese: "辅助功能:"],
        .settings_authorized: [.english: "Authorized", .chinese: "已授权"],
        .settings_not_authorized: [.english: "Not Authorized", .chinese: "未授权"],
        .settings_open_settings: [.english: "Open Settings", .chinese: "打开设置"],
        .settings_checking: [.english: "Checking...", .chinese: "检查中..."],
        .settings_summary_ai: [.english: "Summary AI Settings", .chinese: "AI 总结设置"],
        .settings_enable_ai_summary: [.english: "Enable AI Summary (uses API to summarize notifications)", .chinese: "启用 AI 总结（使用 API 总结通知）"],
        .settings_ai_hint: [.english: "When disabled, notifications show raw user prompt and AI assistance requests", .chinese: "禁用时，通知显示原始用户 prompt 和 AI 协助请求"],
        .settings_base_url: [.english: "Base URL:", .chinese: "Base URL:"],
        .settings_api_key: [.english: "API Key:", .chinese: "API Key:"],
        .settings_model: [.english: "Model:", .chinese: "模型:"],
        .settings_save: [.english: "Save", .chinese: "保存"],
        .settings_test_api: [.english: "Test API", .chinese: "测试 API"],
        .settings_testing: [.english: "Testing...", .chinese: "测试中..."],
        .settings_show: [.english: "Show", .chinese: "显示"],
        .settings_hide: [.english: "Hide", .chinese: "隐藏"],
        .settings_send_test: [.english: "Send Test Notification", .chinese: "发送测试通知"],
        .settings_sending: [.english: "Sending...", .chinese: "发送中..."],
        .settings_refresh_status: [.english: "Refresh Status", .chinese: "刷新状态"],
        .settings_language: [.english: "Language", .chinese: "语言"],
        .settings_language_hint: [.english: "App language (changes take effect immediately)", .chinese: "应用语言（立即生效）"],

        // Settings Messages
        .settings_saved_success: [.english: "Saved to config.json", .chinese: "已保存到 config.json"],
        .settings_url_required: [.english: "Base URL is required", .chinese: "请输入 Base URL"],
        .settings_key_required: [.english: "API Key is required", .chinese: "请输入 API Key"],
        .settings_test_success: [.english: "API connection successful!", .chinese: "API 连接成功！"],
        .settings_test_invalid_url: [.english: "Invalid URL format", .chinese: "无效的 URL 格式"],
        .settings_test_invalid_key: [.english: "Invalid API Key (401)", .chinese: "无效的 API Key (401)"],
        .settings_test_not_found: [.english: "Endpoint not found (404) - check Base URL", .chinese: "接口未找到 (404) - 请检查 Base URL"],
        .settings_test_rate_limited: [.english: "Rate limited (429) - but API key is valid", .chinese: "请求限流 (429) - 但 API key 有效"],
        .settings_test_timeout: [.english: "Connection timeout", .chinese: "连接超时"],
        .settings_test_connection_failed: [.english: "Cannot connect to server", .chinese: "无法连接服务器"],
        .settings_notification_success: [.english: "Test notification sent!", .chinese: "测试通知已发送！"],
        .settings_notification_error: [.english: "Failed to send notification", .chinese: "发送通知失败"],
        .settings_permission_denied: [.english: "Please grant notification permission first", .chinese: "请先授予通知权限"],

        // Alert
        .alert_success: [.english: "Success", .chinese: "成功"],
        .alert_error: [.english: "Error", .chinese: "错误"],
        .alert_ok: [.english: "OK", .chinese: "确定"],

        // ========== Management Window ==========
        .management_title: [.english: "Claude Monitor - Management Center", .chinese: "Claude Monitor - 管理中心"],

        // Navigation
        .nav_task_center: [.english: "Task Center", .chinese: "任务中心"],
        .nav_reports: [.english: "Reports", .chinese: "报告分析"],
        .nav_mcp: [.english: "MCP Server", .chinese: "MCP 服务"],
        .nav_settings: [.english: "Settings", .chinese: "设置"],

        // MCP Server
        .mcp_status_running: [.english: "Running", .chinese: "运行中"],
        .mcp_status_stopped: [.english: "Stopped", .chinese: "已停止"],
        .mcp_start: [.english: "Start", .chinese: "启动"],
        .mcp_stop: [.english: "Stop", .chinese: "停止"],
        .mcp_restart: [.english: "Restart", .chinese: "重启"],
        .mcp_log_title: [.english: "Server Log", .chinese: "服务日志"],
        .mcp_refresh_log: [.english: "Refresh", .chinese: "刷新"],

        // Task Center Table
        .table_account: [.english: "Account", .chinese: "账户"],
        .table_session_id: [.english: "Session ID", .chinese: "会话 ID"],
        .table_goal: [.english: "Goal", .chinese: "目标"],
        .table_status: [.english: "Status", .chinese: "状态"],
        .table_project: [.english: "Project", .chinese: "项目"],
        .table_updated: [.english: "Updated", .chinese: "更新时间"],
        .table_action: [.english: "Action", .chinese: "操作"],

        // Task Center Status
        .task_status_working: [.english: "Working", .chinese: "工作中"],
        .task_status_idle: [.english: "Idle", .chinese: "空闲"],
        .task_status_waiting: [.english: "Waiting", .chinese: "等待中"],
        .task_status_permission: [.english: "Permission", .chinese: "权限"],
        .task_status_completed: [.english: "Completed", .chinese: "已完成"],

        // Task Center Filter
        .filter_search_placeholder: [.english: "Search sessions...", .chinese: "搜索会话..."],
        .filter_all_status: [.english: "All Status", .chinese: "全部状态"],
        .filter_working: [.english: "Working", .chinese: "工作中"],
        .filter_idle: [.english: "Idle", .chinese: "空闲"],
        .filter_waiting: [.english: "Waiting", .chinese: "等待决策"],
        .filter_completed: [.english: "Completed", .chinese: "已完成"],
        .filter_all_accounts: [.english: "All Accounts", .chinese: "全部账户"],

        // Context Menu
        .context_view_details: [.english: "View Details", .chinese: "查看详情"],
        .context_jump_terminal: [.english: "Jump to Terminal", .chinese: "跳转终端"],
        .context_mark_completed: [.english: "Mark Completed", .chinese: "标记完成"],
        .context_delete: [.english: "Delete", .chinese: "删除"],

        // Delete Confirmation
        .delete_confirm_title: [.english: "Confirm Delete", .chinese: "确认删除"],
        .delete_confirm_message: [.english: "Are you sure you want to delete the selected session(s)? This action cannot be undone.", .chinese: "确定要删除选中的会话吗？此操作无法撤销。"],
        .delete_button: [.english: "Delete", .chinese: "删除"],
        .cancel_button: [.english: "Cancel", .chinese: "取消"],

        // Time Relative
        .time_just_now: [.english: "Just now", .chinese: "刚刚"],
        .time_minutes_ago: [.english: "m ago", .chinese: "分钟前"],
        .time_hours_ago: [.english: "h ago", .chinese: "小时前"],
        .time_days_ago: [.english: "d ago", .chinese: "天前"],

        // ========== Reports ==========
        .report_daily: [.english: "Daily", .chinese: "日报"],
        .report_weekly: [.english: "Weekly", .chinese: "周报"],
        .report_monthly: [.english: "Monthly", .chinese: "月报"],
        .report_today: [.english: "Today's Report", .chinese: "今日报告"],
        .report_total_sessions: [.english: "Total Sessions", .chinese: "总会话"],
        .report_completed: [.english: "Completed", .chinese: "已完成"],
        .report_working: [.english: "Working", .chinese: "工作中"],
        .report_waiting: [.english: "Waiting", .chinese: "等待中"],
        .report_coming_soon: [.english: "Coming soon...", .chinese: "功能即将推出..."],

        // ========== Copy Summary Text ==========
        .copy_task: [.english: "Task:", .chinese: "任务:"],
        .copy_status: [.english: "Status:", .chinese: "状态:"],
        .copy_project: [.english: "Project:", .chinese: "项目:"],
        .copy_progress: [.english: "Progress:", .chinese: "进度:"],
        .copy_timeline: [.english: "Timeline:", .chinese: "时间线:"],

        // ========== Notification Actions ==========
        .notification_jump: [.english: "Jump to Terminal", .chinese: "跳转到终端"],
        .notification_dismiss: [.english: "Dismiss", .chinese: "稍后处理"],
        .notification_view_details: [.english: "View Details", .chinese: "查看详情"],

        // ========== Timeline Events ==========
        .timeline_start_task: [.english: "Start Task", .chinese: "开始任务"],
        .timeline_task_started: [.english: "Task started", .chinese: "任务开始"],
        .timeline_idle: [.english: "Idle", .chinese: "空闲"],
        .timeline_waiting_new_task: [.english: "Waiting for new task", .chinese: "等待新任务"],
        .timeline_working: [.english: "Working", .chinese: "工作中"],
        .timeline_executing_task: [.english: "Executing task", .chinese: "正在执行任务"],
        .timeline_waiting_decision: [.english: "Waiting for Decision", .chinese: "等待决策"],
        .timeline_needs_user_input: [.english: "Needs user input", .chinese: "需要用户输入"],
        .timeline_waiting_permission: [.english: "Waiting for Permission", .chinese: "等待权限"],
        .timeline_needs_permission: [.english: "Needs permission confirmation", .chinese: "需要权限确认"],
        .timeline_task_complete: [.english: "Task Complete", .chinese: "任务完成"],
        .timeline_all_steps_done: [.english: "All steps completed", .chinese: "已完成全部步骤"],
        .timeline_rate_limited: [.english: "Rate Limited", .chinese: "限流"],
        .timeline_api_limited: [.english: "API request limited", .chinese: "API 请求受限"],
        .timeline_progress_update: [.english: "Progress Update", .chinese: "进度更新"],
        .timeline_progress_done: [.english: "Completed", .chinese: "已完成"],
        .timeline_user_input: [.english: "User Input", .chinese: "用户输入"],
        .timeline_continue_chat: [.english: "Continue conversation", .chinese: "继续对话"],
        .timeline_ai_summary: [.english: "AI Summary", .chinese: "AI 总结"],
        .timeline_current_task: [.english: "Current task:", .chinese: "当前任务:"],
        .timeline_progress: [.english: "Progress:", .chinese: "进度:"],
        .timeline_next_step: [.english: "Next step:", .chinese: "下一步:"],
        .timeline_pending_decision: [.english: "Pending decision:", .chinese: "待决策:"],

        // ========== Detail Tabs (New) ==========
        .detail_tab_timeline: [.english: "Timeline", .chinese: "时间线"],
        .detail_tab_prompts: [.english: "Prompts", .chinese: "提示词"],
        .detail_tab_usage: [.english: "Usage", .chinese: "用量"],

        // ========== Prompt History (New) ==========
        .prompt_round_label: [.english: "Round", .chinese: "第"],
        .prompt_chars: [.english: "chars", .chinese: "字符"],
        .prompt_tokens_estimated: [.english: "tokens (est.)", .chinese: "token (估算)"],
        .prompt_empty: [.english: "No prompts recorded", .chinese: "暂无提示词记录"],

        // ========== Usage Stats (New) ==========
        .usage_input_tokens: [.english: "Input Tokens", .chinese: "输入 Token"],
        .usage_output_tokens: [.english: "Output Tokens", .chinese: "输出 Token"],
        .usage_total_estimated: [.english: "Total (Estimated)", .chinese: "总计 (估算)"],
        .usage_empty: [.english: "No usage data", .chinese: "暂无用量数据"],
        .usage_chars: [.english: "characters", .chinese: "字符"],
        .usage_words: [.english: "words", .chinese: "单词"],

        // ========== Resume Link (New) ==========
        .detail_resumed_from: [.english: "Resumed from:", .chinese: "恢复自:"],

        // ========== Todo Management ==========
        .todo_edit: [.english: "Edit", .chinese: "编辑"],
        .todo_delete: [.english: "Delete", .chinese: "删除"],
        .todo_mark_complete: [.english: "Mark Complete", .chinese: "标记完成"],
        .todo_mark_pending: [.english: "Mark Pending", .chinese: "标记待处理"],
        .todo_delete_confirm_title: [.english: "Delete Todo", .chinese: "删除任务"],
        .todo_delete_confirm_message: [.english: "Are you sure you want to delete this todo? Child todos will become independent.", .chinese: "确定要删除此任务吗？子任务将变为独立任务。"],
        .todo_title_placeholder: [.english: "Todo title", .chinese: "任务标题"],
        .todo_description: [.english: "Description:", .chinese: "描述:"],
        .todo_status: [.english: "Status:", .chinese: "状态:"],
        .todo_status_pending: [.english: "Pending", .chinese: "待处理"],
        .todo_status_in_progress: [.english: "In Progress", .chinese: "进行中"],
        .todo_status_blocked: [.english: "Blocked", .chinese: "阻塞"],
        .todo_status_completed: [.english: "Completed", .chinese: "已完成"],
        .todo_status_cancelled: [.english: "Cancelled", .chinese: "已取消"],
        .todo_priority: [.english: "Priority:", .chinese: "优先级:"],
        .todo_priority_normal: [.english: "Normal", .chinese: "普通"],
        .todo_priority_high: [.english: "High", .chinese: "高"],
        .todo_priority_urgent: [.english: "Urgent", .chinese: "紧急"],
        .todo_estimated_time: [.english: "Estimated:", .chinese: "预估时间:"],
        .todo_minutes: [.english: "minutes", .chinese: "分钟"],
        .todo_project: [.english: "Project:", .chinese: "项目:"],

        // ========== Create Task/Todo ==========
        .create_mode_task: [.english: "Global Task", .chinese: "全局任务"],
        .create_mode_todo: [.english: "Single Todo", .chinese: "单独 Todo"],
        .create_task_title: [.english: "Create Global Task", .chinese: "创建全局任务"],
        .create_todo_title: [.english: "Add Todo", .chinese: "添加 Todo"],
        .create_task_button: [.english: "Create Task", .chinese: "创建任务"],
        .create_todo_button: [.english: "Add Todo", .chinese: "添加 Todo"],
        .create_task_projects: [.english: "Target Projects (one per line):", .chinese: "目标项目（每行一个）:"],
        .create_todo_project: [.english: "Project Path:", .chinese: "项目路径:"],
        .create_task_decompose: [.english: "Auto-decompose into Todos (uses AI)", .chinese: "自动分解为 Todos（使用 AI）"],
        .create_task_api_profile: [.english: "API Profile:", .chinese: "API Profile:"],
        .create_task_api_none: [.english: "None (use Claude CLI)", .chinese: "无（使用 Claude CLI）"],
        .create_task_api_no_profiles: [.english: "No profiles configured", .chinese: "未配置 profile"],
        .create_error_title_required: [.english: "Title is required", .chinese: "请输入标题"],
        .create_error_project_required: [.english: "Project path is required", .chinese: "请选择项目"],
        .create_error_failed: [.english: "Failed to create", .chinese: "创建失败"],

        // ========== Common ==========
        .cancel: [.english: "Cancel", .chinese: "取消"],
        .save: [.english: "Save", .chinese: "保存"]
    ]

    // MARK: - Lookup

    static func get(_ key: StringKey, language: Language) -> String {
        guard let langDict = translations[key],
              let value = langDict[language] else {
            // Fallback to English
            if let langDict = translations[key],
               let value = langDict[.english] {
                return value
            }
            // Last fallback: return key name for debugging
            log("Localization: Missing translation for \(key.rawValue) in \(language.rawValue)")
            return key.rawValue
        }
        return value
    }
}
